// lib/services/ai_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'local_context_service.dart';
import 'ai_prompts.dart';

Future<String> _preparePromptIsolate(Map<String, dynamic> data) async {
  final novel = Novel.fromJson(jsonDecode(data['novel_json']));
  final isFirstChapter = data['isFirstChapter'] as bool;
  final isFinalChapter = data['isFinalChapter'] as bool;
  final backendUrl = data['backendUrl'] as String;

  // On utilise une instance de service dédiée pour l'isolate
  final localContextService = LocalContextService.withUrl(backendUrl);
  
  final LanguagePrompts currentLanguagePrompts = AIPrompts.getPromptsFor(novel.language);
  final int currentChapterCount = novel.chapters.length;

  String? lastChapterContent;
  String? lastSentence;
  List<String> relevantContextChapters = [];

  if (!isFirstChapter && novel.chapters.isNotEmpty) {
    lastChapterContent = novel.chapters.last.content;
    if (lastChapterContent.isNotEmpty) {
      final sentences = lastChapterContent.trim().split(RegExp(r'(?<=[.?!])\s+'));
      if (sentences.isNotEmpty) {
        lastSentence = sentences.last.trim();
      }
      
      try {
        final int chaptersInIndex = novel.chapters.length;
        
        // C'est bien la logique topK = 2 (dernier chapitre + 2 pertinents)
        const int topK = 2;
        
        if (chaptersInIndex > 1) {
            final similarChapters = await localContextService.getContext(
                novelId: novel.id, 
                query: lastChapterContent, 
                // On cherche topK + 1 (donc 3) pour exclure le dernier chapitre lui-même
                topK: (chaptersInIndex < topK + 1) ? chaptersInIndex : topK + 1 
            );

            // On retire le premier résultat (qui est le chapitre lui-même)
            if (similarChapters.length > 1) {
                relevantContextChapters = similarChapters.sublist(1);
            }
        }
      } catch (e) {
        debugPrint("Erreur (dans l'isolate) lors de la récupération du contexte : $e");
      }
    }
  }

  final String prompt = AIService._buildChapterPrompt(
    novel: novel,
    isFirstChapter: isFirstChapter,
    isFinalChapter: isFinalChapter,
    currentChapterCount: currentChapterCount,
    languagePrompts: currentLanguagePrompts,
    lastChapterContent: lastChapterContent,
    similarChapters: relevantContextChapters,
    lastSentence: lastSentence,
    roadMap: novel.roadMap,
  );
  
  debugPrint("----- PROMPT PRÉPARÉ DANS L'ISOLATE -----");
  localContextService.dispose();
  return prompt;
}

// NOTE IMPORTANTE : La logique de mise à jour de la roadmap et de traduction
// doit également être déplacée vers le backend pour la sécurité des clés API.
// Pour l'instant, ces fonctions sont marquées comme non implémentées.

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => "Erreur API${statusCode != null ? ' ($statusCode)' : ''}: $message";
}

class ApiServerException extends ApiException {
  ApiServerException(super.message, {required super.statusCode});
  @override
  String toString() => "Erreur du service de l'écrivain ($statusCode). Veuillez réessayer plus tard.";
}

class ApiConnectionException extends ApiException {
  ApiConnectionException(super.message) : super(statusCode: null);
   @override
  String toString() => "Erreur de connexion: $message";
}


class AIService {
  // Les clés API sont maintenant sécurisées sur le backend.
  static String get _backendUrl => LocalContextService().baseUrl;
  
  static const String _defaultChapterModel = 'deepseek/deepseek-r1-0528:free';

  static final http.Client _client = http.Client();

  static Future<String> preparePrompt({
    required Novel novel,
    required bool isFirstChapter,
    bool isFinalChapter = false,
  }) async {
    final Map<String, dynamic> data = {
      'novel_json': jsonEncode(novel.toJson()),
      'isFirstChapter': isFirstChapter,
      'isFinalChapter': isFinalChapter,
      'backendUrl': _backendUrl,
    };
    return await compute(_preparePromptIsolate, data);
  }

  static Stream<String> streamChapterFromPrompt({
    required String prompt,
    required String? modelId,
    required String language,
  }) {
    final controller = StreamController<String>();

    Future(() async {
      try {
        final modelToUse = modelId ?? _defaultChapterModel;
        
        final request = http.Request('POST', Uri.parse('$_backendUrl/generate_chapter_stream'));
        request.headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'text/event-stream' // Préciser qu'on attend un stream
        });
        request.body = jsonEncode({
          'prompt': prompt,
          'model_id': modelToUse,
          'language': language,
        });

        final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 180));

        if (streamedResponse.statusCode >= 400) {
            final body = await streamedResponse.stream.bytesToString();
            throw ApiException(_extractApiError(http.Response(body, streamedResponse.statusCode)), statusCode: streamedResponse.statusCode);
        }

        streamedResponse.stream.transform(utf8.decoder).listen(
          (data) {
            // Le backend renvoie directement le flux brut, on le traite ici
            final lines = data.split('\n');
            for (final line in lines) {
              if (line.startsWith('data: ')) {
                final jsonString = line.substring(6);
                if (jsonString.trim() == '[DONE]') {
                    // Ne rien faire, on attend le onDone
                } else {
                  try {
                    final jsonData = jsonDecode(jsonString);

                    // --- MODIFICATION HEARTBEAT ---
                    // On vérifie si c'est un message de ping du backend
                    if (jsonData['type'] == 'ping') {
                      // C'est un heartbeat, on l'ignore et on continue
                      continue;
                    }
                    // --- FIN DE LA MODIFICATION ---

                    // Gestion des erreurs venant du stream backend
                    if (jsonData['error'] != null) {
                      debugPrint("Erreur reçue du stream backend: ${jsonData['error']}");
                      controller.addError(ApiException(jsonData['error'], statusCode: jsonData['status_code']));
                      continue;
                    }

                    final content = jsonData['choices'][0]['delta']['content'];
                    if (content != null) {
                      controller.add(content);
                    }
                  } catch (e) { 
                    // Ignorer les erreurs de parsing JSON (chunks partiels, etc.)
                  }
                }
              }
            }
          },
          onDone: () { if (!controller.isClosed) controller.close(); },
          onError: (e) { if (!controller.isClosed) controller.addError(e); },
          cancelOnError: true,
        );

      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e is TimeoutException ? ApiConnectionException("Le délai de la requête a expiré (3 minutes).") : e);
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  static Future<String> updateRoadMap(Novel novel) async {
    // Cette fonction doit être migrée vers le backend pour la sécurité.
    // Le 'roadmap_service.dart' appelle cette fonction, mais la logique
    // de génération réelle doit être (et est) sur le backend.
    // Ce message est un avertissement de développement.
    debugPrint("AVERTISSEMENT: La mise à jour de la roadmap (logique IA) doit être sur le backend. L'appel est en cours...");
    
    // NOTE: Idéalement, cette fonction devrait appeler un endpoint backend
    // comme '/update_roadmap' qui fait le vrai travail.
    // Pour l'instant, le roadmap_service gère l'appel lui-même (ce qui est ok si le service appelle le backend).
    
    // On retourne le roadmap existant pour ne pas bloquer
    return novel.roadMap ?? "La mise à jour de la roadmap est gérée par le backend.";
  }

  static Future<Map<String, String?>> getReadingAndTranslation(String word, SharedPreferences prefs) async {
     // Cette fonction appelle maintenant le backend.
     // L'ancien avertissement est trompeur. La migration A EU LIEU.
     debugPrint("Appel du backend pour traduction de : $word");

     try {
        final response = await _client.post(
          Uri.parse('$_backendUrl/get_reading_translation'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'word': word}),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          // Le backend renvoie { 'reading': '...', 'translation': '...', 'readingError': '...', 'translationError': '...' }
          return {
            'reading': data['reading'],
            'translation': data['translation'],
            'readingError': data['readingError'],
            'translationError': data['translationError'],
          };
        } else {
          // Gérer les erreurs serveur (4xx, 5xx)
          final errorMsg = _extractApiError(response);
          // ✅ CORRECTION ICI : Espace supprimé
          debugPrint("Erreur API (${response.statusCode}) lors de la traduction: $errorMsg");
          return {
            'reading': null,
            'translation': null,
            'readingError': 'Erreur ${response.statusCode}',
            'translationError': errorMsg,
          };
        }
     } catch (e) {
        // Gérer les erreurs de connexion (timeout, pas de réseau)
        debugPrint("Erreur de connexion lors de la traduction: $e");
        return {
          'reading': null,
          'translation': null,
          'readingError': 'Erreur réseau',
          'translationError': 'Impossible de joindre le serveur.',
        };
     }
  }
  
  static String _extractApiError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) { // FastAPI utilise 'detail'
        return decoded['detail'];
      }
      if (decoded is Map && decoded['error']?['message'] is String) {
        return decoded['error']['message'];
      }
    } catch (_) { /* Ignorer l'erreur de parsing */ }
    return response.reasonPhrase ?? 'Erreur inconnue';
  }

  /// Nettoie la réponse brute de l'IA en supprimant les blocs <think>...</think>.
  static String _cleanAIResponse(String rawText) {
    // L'option 'dotAll: true' permet au '.' de correspondre aux sauts de ligne,
    // ce qui est crucial car le bloc <think> est sur plusieurs lignes.
    final regex = RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false);
    
    // Remplace toutes les occurrences trouvées par une chaîne vide et nettoie les espaces
    return rawText.replaceAll(regex, '').trim();
  }

  static Chapter extractTitleAndContent(String rawContent, int currentChapterCount, bool isFirstChapter, bool isFinalChapter, LanguagePrompts languagePrompts) {
    
    // On nettoie le contenu brut AVANT tout traitement
    final String cleanedRawContent = _cleanAIResponse(rawContent);

    String defaultTitle;
    if (isFirstChapter) {
      defaultTitle = languagePrompts.titleFirst;
    } else if (isFinalChapter) {
      defaultTitle = languagePrompts.titleFinal;
    } else {
      defaultTitle = "${languagePrompts.titleChapterPrefix}${currentChapterCount + 1}${languagePrompts.titleChapterSuffix}";
    }

    String chapterTitle = defaultTitle;
    // On utilise le contenu nettoyé ici
    String chapterContent = cleanedRawContent.trim();

    // Et ici
    final lines = cleanedRawContent.trim().split('\n');
    if (lines.isNotEmpty) {
        final firstLine = lines.first.trim();
        final titleRegex = RegExp(r"^(?:Chapitre|Chapter|Capítulo|Capitolo|第[一二三四五六七八九十百千\d]+章|第一章|最終章)\s*\d*\s*[:：-]?\s*(.*)", caseSensitive: false);
        final match = titleRegex.firstMatch(firstLine);

        if (match != null) {
            String extracted = match.group(1)!.trim();
            if (extracted.isNotEmpty) {
              chapterTitle = extracted;
            }
            chapterContent = lines.sublist(1).join('\n').trim();
        } else if (lines.length > 1 && lines[0].length < 80 && lines[1].trim().isEmpty) {
            chapterTitle = lines[0];
            chapterContent = lines.sublist(2).join('\n').trim();
        }
    }
    
    chapterTitle = chapterTitle.replaceAll(RegExp(r'["`*]'), '').trim();

    String finalContent = chapterContent;
    if (finalContent.isNotEmpty) {
        final trimmedContent = finalContent.trim();
        const terminalChars = ['.', '!', '?', '。', '！', '？', '…'];
        
        if (trimmedContent.isNotEmpty && !terminalChars.contains(trimmedContent[trimmedContent.length - 1])) {
            debugPrint("La dernière phrase du chapitre est incomplète. Nettoyage...");
            
            int lastPunctuationIndex = -1;
            for (final char in terminalChars) {
                int index = trimmedContent.lastIndexOf(char);
                if (index > lastPunctuationIndex) {
                    lastPunctuationIndex = index;
                }
            }

            if (lastPunctuationIndex != -1) {
                finalContent = trimmedContent.substring(0, lastPunctuationIndex + 1);
                debugPrint("Contenu du chapitre tronqué pour terminer sur une phrase complète.");
            } else {
                finalContent = ""; 
                debugPrint("Aucune phrase terminée trouvée dans le chapitre. Le contenu a été vidé.");
            }
        }
    }

    return Chapter(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: chapterTitle,
      content: finalContent.trim(),
      createdAt: DateTime.now(),
    );
  }

  static String _buildChapterPrompt({
    required Novel novel,
    required bool isFirstChapter,
    required bool isFinalChapter,
    required int currentChapterCount,
    required LanguagePrompts languagePrompts,
    String? lastChapterContent,
    List<String>? similarChapters,
    String? lastSentence,
    String? roadMap,
  }) {
    String commonInstructions = languagePrompts.commonInstructions
        .replaceAll('[NOVEL_LEVEL]', novel.level)
        .replaceAll('[NOVEL_GENRE]', novel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications)
        .replaceAll('[NOVEL_LANGUAGE]', novel.language);

    if (isFirstChapter) {
      String prompt = languagePrompts.firstChapterIntro
          .replaceAll('[NOVEL_TITLE]', novel.title);
      return '''$prompt
- Titre du roman: ${novel.title}
- Niveau de langue: ${novel.level}
- Genre: ${novel.genre}
- Spécifications: ${novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications}

$commonInstructions

${languagePrompts.outputFormatFirst}
''';
    } else {
      final String intro = isFinalChapter
          ? languagePrompts.finalChapterIntro
          : languagePrompts.nextChapterIntro.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());
      
      final String outputFormat = isFinalChapter
          ? languagePrompts.outputFormatFinal
          : languagePrompts.outputFormatNext.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());

      final String finalChapterInstructions = isFinalChapter ? languagePrompts.finalChapterSpecificInstructions : "";
      
      final buffer = StringBuffer();
      buffer.writeln(languagePrompts.contextSectionHeader);
      if (roadMap != null && roadMap.isNotEmpty) {
        // --- MODIFICATION : Utilisation de la variable de langue ---
        buffer.writeln("\n${languagePrompts.roadmapHeader}:");
        // --- FIN MODIFICATION ---
        buffer.writeln(roadMap);
      }
      if (lastChapterContent != null && lastChapterContent.isNotEmpty) {
        final header = languagePrompts.contextLastChapterHeader.replaceAll('[CHAPTER_NUMBER]', currentChapterCount.toString());
        buffer.writeln("\n$header");
        buffer.writeln(lastChapterContent);
      }
      if (similarChapters != null && similarChapters.isNotEmpty) {
        buffer.writeln("\n${languagePrompts.contextSimilarSectionHeader}");
        for (int i = 0; i < similarChapters.length; i++) {
          // --- MODIFICATION : Utilisation des variables de langue ---
          final excerptHeader = languagePrompts.similarExcerptHeader.replaceAll("[NUMBER]", (i + 1).toString());
          buffer.writeln("$excerptHeader\n${similarChapters[i]}\n${languagePrompts.similarExcerptFooter}");
          // --- FIN MODIFICATION ---
        }
      }
      if(lastSentence != null && lastSentence.isNotEmpty) {
          buffer.writeln("\n${languagePrompts.contextLastSentenceHeader}");
          buffer.writeln('"$lastSentence"');
      }
      buffer.writeln(languagePrompts.contextFollowInstruction);
      final String contextSection = buffer.toString();

      return '''${intro.replaceAll('[NOVEL_TITLE]', novel.title)}
- Niveau de langue: ${novel.level}
- Genre: ${novel.genre}

$contextSection

$commonInstructions

$finalChapterInstructions

$outputFormat
''';
    }
  }
}