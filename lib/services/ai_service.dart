// lib/services/ai_service.dart (RÉVISION APPROFONDIE DE LA LOGIQUE AI)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'local_context_service.dart';
import 'ai_prompts.dart';
import '../config.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';


// --- ⬇️ MODIFICATION 1 (Correction Bug n°3 : Regex) ⬇️ ---
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
      
      // ✅ CORRECTION BUG n°3 : Ajout des ponctuations japonaises/coréennes
      // et gestion des espaces optionnels (ou absents) après la ponctuation.
      final sentences = lastChapterContent.trim().split(RegExp(r'(?<=[.?!。？！…])\s*'));
      // --- FIN CORRECTION ---

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
  
  // Pour déboguer le prompt final :
  // debugPrint("----- PROMPT PRÉPARÉ (Taille: ${prompt.length}) -----");
  // debugPrint(prompt);
  
  localContextService.dispose();
  return prompt;
}
// --- ⬆️ FIN MODIFICATION 1 ⬆️ ---

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

  // --- [AUCUNE MODIFICATION] ---
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

  // --- [AUCUNE MODIFICATION] ---
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

  // --- [AUCUNE MODIFICATION] ---
  static Future<void> generateNextChapter(
    Novel novel,
    BuildContext context,
    WidgetRef ref,
  ) async {
    debugPrint("Demande de génération de chapitre ${novel.chapters.length + 1} for '${novel.title}'");

    final bool isFirstChapter = novel.chapters.isEmpty;
    
    final String prompt = await preparePrompt(
      novel: novel,
      isFirstChapter: isFirstChapter,
      isFinalChapter: false,
    );

    if (!context.mounted) return;

    final stream = streamChapterFromPrompt(
      prompt: prompt,
      modelId: novel.modelId,
      language: novel.language,
    );

    final StringBuffer contentBuffer = StringBuffer();
    
    try {
      await for (final chunk in stream) {
        contentBuffer.write(chunk);
      }

      if (!context.mounted) return;

      final LanguagePrompts prompts = AIPrompts.getPromptsFor(novel.language);
      final Chapter newChapter = extractTitleAndContent(
        contentBuffer.toString(),
        novel.chapters.length,
        isFirstChapter,
        false, // isFinalChapter
        prompts,
      );

      novel.chapters.add(newChapter);
      novel.updatedAt = DateTime.now();
      
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

  // --- [AUCUNE MODIFICATION] ---
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

  // --- [AUCUNE MODIFICATION] ---
  static Future<String> updateRoadMap(Novel novel) async {
    debugPrint("Appel à updateRoadMap (résumé du PASSÉ)...");
    return novel.roadMap ?? "Le résumé du passé sera mis à jour par le backend.";
  }

  // --- [AUCUNE MODIFICATION] ---
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
  
  // --- [AUCUNE MODIFICATION] ---
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

  // --- [AUCUNE MODIFICATION] ---
  static String _cleanAIResponse(String rawText) {
    final regex = RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false);
    return rawText.replaceAll(regex, '').trim();
  }

  // --- [AUCUNE MODIFICATION] ---
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

  // --- ⬇️ MODIFICATION 2 (Correction Bug n°1 et n°2 : Segmentation du Prompt) ⬇️ ---
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
    // === PARTIE 1 : Instructions communes ===
    // (Style, langue, niveau, genre, etc.)
    String commonInstructions = languagePrompts.commonInstructions
        .replaceAll('[NOVEL_LEVEL]', novel.level)
        .replaceAll('[NOVEL_GENRE]', novel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications)
        .replaceAll('[NOVEL_LANGUAGE]', novel.language);

    // === PARTIE 2 : Cas spécial du PREMIER chapitre ===
    // Ce cas est simple car il n'y a pas de contexte passé.
    if (isFirstChapter) {
      String intro = languagePrompts.firstChapterIntro
          .replaceAll('[NOVEL_TITLE]', novel.title);
      
      final buffer = StringBuffer();
      buffer.writeln("--- TÂCHE ---");
      buffer.writeln(intro);
      buffer.writeln("\n--- DÉTAILS DU ROMAN ---");
      buffer.writeln("- Titre: ${novel.title}");
      buffer.writeln("- Niveau: ${novel.level}");
      buffer.writeln("- Genre: ${novel.genre}");
      buffer.writeln("- Spécifications: ${novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications}");

      // Contexte futur (le seul contexte disponible)
      if (futureOutline != null && futureOutline.isNotEmpty) {
        buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
        buffer.writeln(languagePrompts.futureOutlineHeader);
        buffer.writeln(futureOutline);
        buffer.writeln(languagePrompts.futureOutlinePriorityRule); // Règle de priorité
      }
      
      // Règles et format
      buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
      buffer.writeln(commonInstructions);
      buffer.writeln("\n--- FORMAT DE SORTIE ---");
      buffer.writeln(languagePrompts.outputFormatFirst);
      return buffer.toString();
    }
    
    // === PARTIE 3 : Cas des chapitres SUIVANTS (Chap 2+) ===
    // C'est ici que la segmentation est cruciale.

    // 1. Définition de la TÂCHE
    final String intro = isFinalChapter
        ? languagePrompts.finalChapterIntro
        : languagePrompts.nextChapterIntro.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());
    
    final String outputFormat = isFinalChapter
        ? languagePrompts.outputFormatFinal
        : languagePrompts.outputFormatNext.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());

    final String finalChapterInstructions = isFinalChapter ? languagePrompts.finalChapterSpecificInstructions : "";

    final buffer = StringBuffer();
    
    // --- SEGMENT 1 : LA TÂCHE ---
    buffer.writeln("--- TÂCHE ---");
    buffer.writeln(intro);

    // --- SEGMENT 2 : ANCRAGE IMMÉDIAT (PRIORITÉ ABSOLUE) ---
    // C'est la boussole à très court terme.
    if (lastSentence != null && lastSentence.isNotEmpty) {
        buffer.writeln("\n--- ANCRAGE IMMÉDIAT (PRIORITÉ ABSOLUE) ---");
        buffer.writeln(languagePrompts.contextLastSentenceHeader);
        buffer.writeln(lastSentence);
        buffer.writeln(languagePrompts.contextFollowInstruction); 
    } else {
      buffer.writeln("\n[AVERTISSEMENT: La dernière phrase du chapitre précédent est manquante. Continuez logiquement.]");
    }

    // --- SEGMENT 3 : CONTEXTE PASSÉ (MÉMOIRE) ---
    // ✅ CORRECTION BUG n°1 : On ne fournit qu'UN SEUL type de contexte passé.
    // Le Roadmap (résumé) est prioritaire s'il existe (Chap 4+).
    // Sinon, on se rabat sur le chapitre précédent complet (Chap 2-3).
    buffer.writeln("\n--- CONTEXTE PASSÉ (MÉMOIRE) ---");
    if (roadMap != null && roadMap.isNotEmpty) {
      buffer.writeln(languagePrompts.roadmapHeader);
      buffer.writeln(roadMap);
    } else if (lastChapterContent != null && lastChapterContent.isNotEmpty) {
      final header = languagePrompts.contextLastChapterHeader.replaceAll('[CHAPTER_NUMBER]', currentChapterCount.toString());
      buffer.writeln(header);
      buffer.writeln(lastChapterContent);
    } else {
      buffer.writeln("[AVERTISSEMENT: Le contexte du chapitre précédent est manquant.]");
    }
    // --- FIN CORRECTION BUG n°1 ---

    // --- SEGMENT 4 : CONTEXTE FUTUR (GUIDE) ---
    // C'est la carte routière à long terme.
    if (futureOutline != null && futureOutline.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
      buffer.writeln(languagePrompts.futureOutlineHeader);
      buffer.writeln(futureOutline);
      
      // ✅ CORRECTION BUG n°2 : On ajoute la règle de priorité qui manquait ici.
      buffer.writeln(languagePrompts.futureOutlinePriorityRule);
      // --- FIN CORRECTION BUG n°2 ---
    }
    
    // --- SEGMENT 5 : CONTEXTE PERTINENT (FAISS) ---
    // Ce sont des "flashbacks" de chapitres pertinents.
    if (similarChapters != null && similarChapters.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE PERTINENT (EXTRAITS DE LA MÉMOIRE) ---");
      buffer.writeln(languagePrompts.contextSimilarSectionHeader);
      for (int i = 0; i < similarChapters.length; i++) {
        final excerptHeader = languagePrompts.similarExcerptHeader.replaceAll("[NUMBER]", (i + 1).toString());
        buffer.writeln("$excerptHeader\n${similarChapters[i]}\n${languagePrompts.similarExcerptFooter}");
      }
    }
      
    // --- SEGMENT 6 : RÈGLES ET FORMAT ---
    buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
    buffer.writeln(commonInstructions);
    buffer.writeln(finalChapterInstructions);
    
    buffer.writeln("\n--- FORMAT DE SORTIE ---");
    buffer.writeln(outputFormat);

    return buffer.toString();
  }
  // --- ⬆️ FIN MODIFICATION 2 ⬆️ ---
}