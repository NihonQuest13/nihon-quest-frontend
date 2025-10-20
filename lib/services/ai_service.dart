// lib/services/ai_service.dart (CORRIGÉ)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'local_context_service.dart';
import 'ai_prompts.dart';
import '../config.dart';

// --- AJOUTS NÉCESSAIRES ---
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
// --- FIN DES AJOUTS ---


Future<String> _preparePromptIsolate(Map<String, dynamic> data) async {
  final novel = Novel.fromJson(jsonDecode(data['novel_json']));
  final isFirstChapter = data['isFirstChapter'] as bool;
  final isFinalChapter = data['isFinalChapter'] as bool;
  final backendUrl = data['backendUrl'] as String;

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
        
        const int topK = 2;
        
        if (chaptersInIndex > 1) {
            final similarChapters = await localContextService.getContext(
                novelId: novel.id, 
                query: lastChapterContent, 
                topK: (chaptersInIndex < topK + 1) ? chaptersInIndex : topK + 1 
            );

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
    futureOutline: novel.futureOutline,
  );
  
  debugPrint("----- PROMPT PRÉPARÉ DANS L'ISOLATE -----");
  localContextService.dispose();
  return prompt;
}

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
  static String get _backendUrl => LocalContextService().baseUrl;
  static const String _defaultChapterModel = kDefaultModelId;
  static const String _defaultPlannerModel = kDefaultModelId;

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
          'Accept': 'text/event-stream'
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
            final lines = data.split('\n');
            for (final line in lines) {
              if (line.startsWith('data: ')) {
                final jsonString = line.substring(6);
                if (jsonString.trim() == '[DONE]') {
                    // Ne rien faire
                } else {
                  try {
                    final jsonData = jsonDecode(jsonString);

                    if (jsonData['type'] == 'ping') {
                      continue;
                    }

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
                    // Ignorer les erreurs
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

  /// Génère le prochain chapitre (ou le premier) et le sauvegarde dans l'état de l'application.
  static Future<void> generateNextChapter(
    Novel novel,
    BuildContext context,
    WidgetRef ref, // On a besoin du 'ref' pour mettre à jour le provider
  ) async {
    debugPrint("Demande de génération de chapitre ${novel.chapters.length + 1} for '${novel.title}'");

    final bool isFirstChapter = novel.chapters.isEmpty;
    
    // 1. Préparer le prompt
    final String prompt = await preparePrompt(
      novel: novel,
      isFirstChapter: isFirstChapter,
      isFinalChapter: false,
    );

    if (!context.mounted) return;

    // 2. Préparer le stream de données depuis le backend
    final stream = streamChapterFromPrompt(
      prompt: prompt,
      modelId: novel.modelId,
      language: novel.language,
    );

    final StringBuffer contentBuffer = StringBuffer();
    
    try {
      // 3. Écouter le stream et assembler le texte complet du chapitre
      await for (final chunk in stream) {
        contentBuffer.write(chunk);
      }

      // 4. Vérifier si le widget est toujours monté
      if (!context.mounted) return;

      // 5. Le stream est terminé, on extrait le titre et le contenu propre
      final LanguagePrompts prompts = AIPrompts.getPromptsFor(novel.language);
      final Chapter newChapter = extractTitleAndContent(
        contentBuffer.toString(),
        novel.chapters.length,
        isFirstChapter,
        false, // isFinalChapter
        prompts,
      );

      // 6. Ajouter le nouveau chapitre au roman
      novel.chapters.add(newChapter);
      novel.updatedAt = DateTime.now();
      
      // 7. Sauvegarder le roman mis à jour via le provider
      await ref.read(novelsProvider.notifier).updateNovel(novel);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Chapitre ${novel.chapters.length} généré avec succès !"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }

    } catch (e) {
      debugPrint("Erreur critique lors de la génération du chapitre : $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de la génération du chapitre: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      throw ApiException("Échec de la génération du chapitre: $e");
    }
  }

  /// Génère un plan de 10 chapitres ("sommaire") pour le futur du roman.
  static Future<String> generateFutureOutline(Novel novel) async {
    debugPrint("Génération du plan directeur futur pour le roman ${novel.title}...");
    final languagePrompts = AIPrompts.getPromptsFor(novel.language);
    
    final String prompt = languagePrompts.futureOutlinePrompt
        .replaceAll('[NOVEL_TITLE]', novel.title)
        .replaceAll('[NOVEL_GENRE]', novel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications)
        .replaceAll('[CURRENT_ROADMAP]', novel.roadMap ?? languagePrompts.firstChapterContext);

    try {
      final response = await _client.post(
        Uri.parse('$_backendUrl/generate_completion'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'prompt': prompt,
          'model_id': novel.modelId ?? _defaultPlannerModel,
          'language': novel.language,
        }),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        
        final rawContent = data['content'] as String? ?? '';
        final cleanedContent = _cleanAIResponse(rawContent);

        debugPrint("Plan directeur généré : \n$cleanedContent");
        return cleanedContent;
      } else {
        final errorMsg = _extractApiError(response);
        debugPrint("Erreur API (${response.statusCode}) lors de la génération du plan: $errorMsg");
        throw ApiException(errorMsg, statusCode: response.statusCode);
      }
    } catch (e) {
      debugPrint("Erreur de connexion lors de la génération du plan: $e");
      if (e is TimeoutException) {
        throw ApiConnectionException("Le délai de la génération du plan a expiré (2 minutes).");
      }
      throw ApiException(e.toString());
    }
  }


  static Future<String> updateRoadMap(Novel novel) async {
    debugPrint("Appel à updateRoadMap (résumé du PASSÉ)...");
    return novel.roadMap ?? "Le résumé du passé sera mis à jour par le backend.";
  }

  static Future<Map<String, String?>> getReadingAndTranslation(String word, SharedPreferences prefs) async {
     debugPrint("Appel du backend pour traduction de : $word");

     try {
        final response = await _client.post(
          Uri.parse('$_backendUrl/get_reading_translation'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'word': word}),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          return {
            'reading': data['reading'],
            'translation': data['translation'],
            'readingError': data['readingError'],
            'translationError': data['translationError'],
          };
        } else {
          final errorMsg = _extractApiError(response);
          debugPrint("Erreur API (${response.statusCode}) lors de la traduction: $errorMsg");
          return {
            'reading': null,
            'translation': null,
            'readingError': 'Erreur ${response.statusCode}',
            'translationError': errorMsg,
          };
        }
     } catch (e) {
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
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'];
      }
      if (decoded is Map && decoded['error']?['message'] is String) {
        return decoded['error']['message'];
      }
    } catch (_) { /* Ignorer */ }
    return response.reasonPhrase ?? 'Erreur inconnue';
  }

  static String _cleanAIResponse(String rawText) {
    final regex = RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false);
    return rawText.replaceAll(regex, '').trim();
  }

  static Chapter extractTitleAndContent(String rawContent, int currentChapterCount, bool isFirstChapter, bool isFinalChapter, LanguagePrompts languagePrompts) {
    
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
    String chapterContent = cleanedRawContent.trim();

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
    String? futureOutline,
  }) {
    String commonInstructions = languagePrompts.commonInstructions
        .replaceAll('[NOVEL_LEVEL]', novel.level)
        .replaceAll('[NOVEL_GENRE]', novel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications)
        .replaceAll('[NOVEL_LANGUAGE]', novel.language);

    if (isFirstChapter) {
      String prompt = languagePrompts.firstChapterIntro
          .replaceAll('[NOVEL_TITLE]', novel.title);
      
      final buffer = StringBuffer();
      buffer.writeln(prompt);
      buffer.writeln("- Titre du roman: ${novel.title}");
      buffer.writeln("- Niveau de langue: ${novel.level}");
      buffer.writeln("- Genre: ${novel.genre}");
      buffer.writeln("- Spécifications: ${novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications}");

      if (futureOutline != null && futureOutline.isNotEmpty) {
        buffer.writeln("\n${languagePrompts.futureOutlineHeader}");
        buffer.writeln(futureOutline);
        buffer.writeln(languagePrompts.futureOutlinePriorityRule);
      }
      
      buffer.writeln("\n$commonInstructions");
      buffer.writeln(languagePrompts.outputFormatFirst);
      return buffer.toString();

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
      
      if(lastSentence != null && lastSentence.isNotEmpty) {
          buffer.writeln("\n${languagePrompts.contextLastSentenceHeader}");
          buffer.writeln('"$lastSentence"');
      }

      if (lastChapterContent != null && lastChapterContent.isNotEmpty) {
        final header = languagePrompts.contextLastChapterHeader.replaceAll('[CHAPTER_NUMBER]', currentChapterCount.toString());
        buffer.writeln("\n$header");
        buffer.writeln(lastChapterContent);
      }
      
      if (similarChapters != null && similarChapters.isNotEmpty) {
        buffer.writeln("\n${languagePrompts.contextSimilarSectionHeader}");
        for (int i = 0; i < similarChapters.length; i++) {
          final excerptHeader = languagePrompts.similarExcerptHeader.replaceAll("[NUMBER]", (i + 1).toString());
          buffer.writeln("$excerptHeader\n${similarChapters[i]}\n${languagePrompts.similarExcerptFooter}");
        }
      }

      if (futureOutline != null && futureOutline.isNotEmpty) {
        buffer.writeln("\n${languagePrompts.futureOutlineHeader}");
        buffer.writeln(futureOutline);
        buffer.writeln(languagePrompts.futureOutlinePriorityRule);
      }
      
      if (roadMap != null && roadMap.isNotEmpty) {
        buffer.writeln("\n${languagePrompts.roadmapHeader}:");
        buffer.writeln(roadMap);
      }
      
      buffer.writeln(languagePrompts.contextFollowInstruction);
      final String contextSection = buffer.toString();

      // --- ⬇️ MODIFICATION PRINCIPALE ⬇️ ---
      // On sépare clairement la tâche finale du contexte.
      final String finalTaskInstruction = 
          "TA TÂCHE FINALE EST LA SUIVANTE :\n$intro\n$outputFormat";

      // On enlève la ligne qui causait l'erreur
      return '''- Niveau de langue: ${novel.level}
- Genre: ${novel.genre}
- Titre du roman: ${novel.title}

$contextSection

$commonInstructions

$finalChapterInstructions

---
$finalTaskInstruction
''';
      // --- ⬆️ FIN DE LA MODIFICATION ⬆️ ---
    }
  }
}

