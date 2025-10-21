// lib/services/ai_service.dart (Logique de Contexte C5+ Corrigée et avec débogage)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:japanese_story_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'local_context_service.dart';
import 'ai_prompts.dart';
import '../config.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';


Future<String> _preparePromptIsolate(Map<String, dynamic> data) async {
  final novel = Novel.fromJson(jsonDecode(data['novel_json']));
  final isFirstChapter = data['isFirstChapter'] as bool;
  final isFinalChapter = data['isFinalChapter'] as bool;
  final backendUrl = data['backendUrl'] as String;

  // Utiliser une nouvelle instance avec l'URL passée
  final localContextService = LocalContextService.withUrl(backendUrl);

  final LanguagePrompts currentLanguagePrompts = AIPrompts.getPromptsFor(novel.language);
  final int currentChapterCount = novel.chapters.length;

  String? lastChapterContent;
  String? lastSentence;
  List<String> relevantContextChapters = [];

  if (!isFirstChapter && novel.chapters.isNotEmpty) {
    lastChapterContent = novel.chapters.last.content;
    if (lastChapterContent.isNotEmpty) {

      final sentences = lastChapterContent.trim().split(RegExp(r'(?<=[.?!。？！…])\s*'));

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
                relevantContextChapters = similarChapters.sublist(1).take(topK).toList();
            } else if (similarChapters.length == 1 && chaptersInIndex > 1) {
              // Rien à faire pour l'instant
            }
        }
      } catch (e) {
        debugPrint("Erreur (dans l'isolate) lors de la récupération du contexte pertinent : $e");
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

  /// Prépare le prompt pour l'IA en exécutant la logique de contexte dans un isolate séparé.
  static Future<String> preparePrompt({
    required Novel novel,
    required bool isFirstChapter,
    bool isFinalChapter = false,
  }) async {
    final Map<String, dynamic> data = {
      'novel_json': jsonEncode(novel.toJsonForIsolate()),
      'isFirstChapter': isFirstChapter,
      'isFinalChapter': isFinalChapter,
      'backendUrl': _backendUrl,
    };
    return await compute(_preparePromptIsolate, data);
  }

  /// Établit une connexion de streaming avec le backend pour recevoir la génération de chapitre.
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

        streamedResponse.stream
          .transform(utf8.decoder)
          .listen(
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
                      debugPrint("Ping reçu du backend");
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
                     debugPrint("Erreur parsing JSON stream chunk: $e - Chunk: $jsonString");
                  }
                }
              }
            }
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
            debugPrint("Stream terminé (onDone).");
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
            debugPrint("Erreur sur le stream: $e");
          },
          cancelOnError: true,
        );

      } catch (e) {
        debugPrint("Erreur dans streamChapterFromPrompt: $e");
        if (!controller.isClosed) {
          controller.addError(e is TimeoutException
            ? ApiConnectionException("Le délai de la requête a expiré (3 minutes).")
            : ApiException(e.toString()));
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  static Future<void> generateNextChapter(
    Novel novel,
    BuildContext context,
    WidgetRef ref,
  ) async {
    debugPrint(">>> Début de generateNextChapter pour chap ${novel.chapters.length + 1}");

    final bool isFirstChapter = novel.chapters.isEmpty;

    debugPrint(">>> Appel de preparePrompt (isFirstChapter: $isFirstChapter)...");

    String prompt = "";
    try {
      prompt = await preparePrompt(
        novel: novel,
        isFirstChapter: isFirstChapter,
        isFinalChapter: false,
      );
      debugPrint(">>> preparePrompt terminé avec succès.");

    } catch (e, stackTrace) {
      debugPrint("❌ ERREUR DANS preparePrompt LORS DE LA GÉNÉRATION DU CHAPITRE ${novel.chapters.length + 1} ❌");
      debugPrint("Erreur: $e");
      debugPrint("StackTrace: $stackTrace");
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la préparation du contexte: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }


    debugPrint("=========================================================");
    debugPrint("           PROMPT FINAL ENVOYÉ À L'IA                   ");
    debugPrint("           (Généré par l'isolate)                     ");
    debugPrint("=========================================================");
    debugPrint(prompt);
    debugPrint("---------------------------------------------------------");
    debugPrint("Taille du prompt : ${prompt.length} caractères");
    debugPrint("=========================================================");

    if (!context.mounted) {
       debugPrint(">>> Contexte non monté APRÈS preparePrompt. Arrêt.");
       return;
    }
    debugPrint(">>> Contexte est monté. Appel de streamChapterFromPrompt...");


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

      await ref.read(roadmapServiceProvider).triggerRoadmapUpdateIfNeeded(novel, context);

      final syncTask = SyncTask(
        action: 'add',
        novelId: novel.id,
        content: newChapter.content,
        chapterIndex: novel.chapters.length - 1,
      );
      await ref.read(syncServiceProvider).addTask(syncTask);

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
        final cleanedContent = cleanAIResponse(rawContent);

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
      throw ApiException("Erreur lors de la génération du plan: ${e.toString()}");
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
          Uri.parse('$_backendUrl/translate'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'word': word,
            'target_lang': 'FR',
            }),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          return {
            'reading': null,
            'translation': data['translation'],
            'readingError': null,
            'translationError': null,
          };
        } else {
          final errorMsg = _extractApiError(response);
          debugPrint("Erreur API (${response.statusCode}) lors de la traduction: $errorMsg");
          return {
            'reading': null,
            'translation': null,
            'readingError': null,
            'translationError': "Erreur $errorMsg (${response.statusCode})",
          };
        }
     } catch (e) {
        debugPrint("Erreur de connexion lors de la traduction: $e");
        String errorDetail = (e is TimeoutException) ? "Timeout" : "Erreur réseau";
        return {
          'reading': null,
          'translation': null,
          'readingError': null,
          'translationError': 'Impossible de joindre le service de traduction ($errorDetail).',
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
    } catch (_) {
      // Ignorer
    }
    return response.reasonPhrase ?? 'Erreur inconnue du serveur';
  }

  /// ✅ Renommée en 'cleanAIResponse' et rendue publique
  static String cleanAIResponse(String rawText) {
    final regex = RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false);
    return rawText.replaceAll(regex, '').trim();
  }

  static Chapter extractTitleAndContent(
    String rawContent,
    int currentChapterCount,
    bool isFirstChapter,
    bool isFinalChapter,
    LanguagePrompts languagePrompts
  ) {

    final String cleanedRawContent = cleanAIResponse(rawContent);

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
            debugPrint("La dernière phrase du chapitre généré est incomplète. Nettoyage...");

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
                debugPrint("Aucune phrase terminée trouvée dans le chapitre généré. Le contenu a été vidé.");
            }
        }
    }

    return Chapter(
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

      if (futureOutline != null && futureOutline.isNotEmpty) {
        buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
        buffer.writeln(languagePrompts.futureOutlineHeader);
        buffer.writeln(futureOutline);
        buffer.writeln(languagePrompts.futureOutlinePriorityRule);
      }

      buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
      buffer.writeln(commonInstructions);
      buffer.writeln("\n--- FORMAT DE SORTIE ---");
      buffer.writeln(languagePrompts.outputFormatFirst);
      return buffer.toString();
    }

    final String intro = isFinalChapter
        ? languagePrompts.finalChapterIntro
        : languagePrompts.nextChapterIntro.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());

    final String outputFormat = isFinalChapter
        ? languagePrompts.outputFormatFinal
        : languagePrompts.outputFormatNext.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());

    final String finalChapterInstructions = isFinalChapter ? languagePrompts.finalChapterSpecificInstructions : "";

    final buffer = StringBuffer();

    buffer.writeln("--- TÂCHE ---");
    buffer.writeln(intro);

    if (lastSentence != null && lastSentence.isNotEmpty) {
        buffer.writeln("\n--- ANCRAGE IMMÉDIAT (PRIORITÉ ABSOLUE) ---");
        buffer.writeln(languagePrompts.contextLastSentenceHeader);
        buffer.writeln(lastSentence);
        buffer.writeln(languagePrompts.contextFollowInstruction.replaceAll("[LAST_SENTENCE]", lastSentence));
    } else {
      buffer.writeln("\n[AVERTISSEMENT: La dernière phrase du chapitre précédent est manquante. Continuez logiquement.]");
    }

    buffer.writeln("\n--- CONTEXTE PASSÉ (MÉMOIRE IMMÉDIATE) ---");
    if (lastChapterContent != null && lastChapterContent.isNotEmpty) {
      final header = languagePrompts.contextLastChapterHeader.replaceAll('[CHAPTER_NUMBER]', currentChapterCount.toString());
      buffer.writeln(header);
      buffer.writeln(lastChapterContent);
    } else {
      buffer.writeln("[AVERTISSEMENT: Le contexte du chapitre précédent (N-1) est manquant.]");
    }

    if (roadMap != null && roadMap.isNotEmpty && currentChapterCount >= 4) {
      buffer.writeln("\n--- CONTEXTE PASSÉ (RÉSUMÉ GLOBAL) ---");
      buffer.writeln(languagePrompts.roadmapHeader);
      buffer.writeln(roadMap);
    }

    if (futureOutline != null && futureOutline.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
      buffer.writeln(languagePrompts.futureOutlineHeader);
      buffer.writeln(futureOutline);
      buffer.writeln(languagePrompts.futureOutlinePriorityRule);
    }

    if (similarChapters != null && similarChapters.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE PERTINENT (EXTRAITS DE LA MÉMOIRE) ---");
      buffer.writeln(languagePrompts.contextSimilarSectionHeader);
      for (int i = 0; i < similarChapters.length; i++) {
        final excerptHeader = languagePrompts.similarExcerptHeader.replaceAll("[NUMBER]", (i + 1).toString());
        buffer.writeln("$excerptHeader\n${similarChapters[i]}\n${languagePrompts.similarExcerptFooter}");
      }
    }

    buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
    buffer.writeln(commonInstructions);
    buffer.writeln(finalChapterInstructions);

    buffer.writeln("\n--- FORMAT DE SORTIE ---");
    buffer.writeln(outputFormat);

    return buffer.toString();
  }
}
