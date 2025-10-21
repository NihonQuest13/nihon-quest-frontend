// lib/services/ai_service.dart (MODIFIÉ POUR APPELER LE BACKEND ROADMAP)

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
import '../utils/app_logger.dart';


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
  
  static Future<String> generateFutureOutline(Novel novel) async {
    AppLogger.info("Génération du plan directeur futur pour le roman ${novel.title}...", tag: "AIService");
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
        AppLogger.success("Plan directeur (futur) généré. Longueur: ${cleanedContent.length}", tag: "AIService");
        return cleanedContent;
      } else {
        final errorMsg = _extractApiError(response);
        AppLogger.error("Erreur API (${response.statusCode}) lors de la génération du plan: $errorMsg", tag: "AIService");
        throw ApiException(errorMsg, statusCode: response.statusCode);
      }
    } on TimeoutException catch (e) {
        AppLogger.error("Timeout lors de la génération du plan futur", error: e, tag: "AIService");
        throw ApiConnectionException("Le délai de la génération du plan a expiré (2 minutes).");
    } catch (e) {
      AppLogger.error("Erreur inattendue lors de la génération du plan futur", error: e, tag: "AIService");
      throw ApiException("Erreur lors de la génération du plan: ${e.toString()}");
    }
  }

  static Future<String> updateRoadMap(Novel novel) async {
    final int chapterCount = novel.chapters.length;
    AppLogger.info("Appel à updateRoadMap (génération du résumé PASSÉ) pour ${novel.title} ($chapterCount chapitres)...", tag: "AIService");

    List<Chapter> relevantChapters;
    if (chapterCount < 3) {
      AppLogger.warning("Moins de 3 chapitres, impossible de générer la roadmap.", tag: "AIService");
      return novel.roadMap ?? "Pas assez de chapitres pour générer un résumé.";
    } else if (chapterCount == 4 && novel.chapters.length >= 3) {
      // Cas de la toute première génération (au 4ème chapitre)
      relevantChapters = novel.chapters.sublist(0, 3);
      AppLogger.info("Utilisation des 3 premiers chapitres pour la création initiale de la roadmap.", tag: "AIService");
    } else {
      // Cas des mises à jour suivantes (prendre les 3 derniers)
      relevantChapters = novel.chapters.sublist(chapterCount - 3);
      AppLogger.info("Utilisation des 3 derniers chapitres (indices ${chapterCount - 3} à ${chapterCount - 1}) pour la mise à jour de la roadmap.", tag: "AIService");
    }

    final List<String> chaptersContent = relevantChapters.map((c) => "Chapitre ${novel.chapters.indexOf(c) + 1}: ${c.title}\n${c.content}").toList();

    final requestBody = {
      'novel_id': novel.id,
      'title': novel.title,
      'genre': novel.genre,
      'specifications': novel.specifications,
      'language': novel.language,
      'model_id': novel.modelId ?? _defaultPlannerModel,
      'chapters_content': chaptersContent,
      'current_roadmap': novel.roadMap,
    };

    AppLogger.info("Envoi de la requête au backend /generate_roadmap...", tag: "AIService");

    try {
      final response = await _client.post(
        Uri.parse('$_backendUrl/generate_roadmap'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 180));

      AppLogger.info("Réponse reçue du backend /generate_roadmap (Status: ${response.statusCode})", tag: "AIService");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final newRoadmap = data['new_roadmap'] as String? ?? '';

        if (newRoadmap.isEmpty) {
          AppLogger.error("Le backend a retourné une roadmap vide.", tag: "AIService");
          throw ApiException("Le service de résumé n'a retourné aucun contenu.", statusCode: 500);
        }
        AppLogger.success("Nouvelle roadmap (passé) reçue du backend. Longueur: ${newRoadmap.length}", tag: "AIService");
        return newRoadmap;
      } else {
        final errorMsg = _extractApiError(response);
        String detailError = errorMsg;
        try {
           final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
           if (errorBody['detail'] != null) { detailError = errorBody['detail'].toString(); }
        } catch (_) {}
        AppLogger.error("Erreur API backend (${response.statusCode}) lors de la génération de la roadmap: $detailError", tag: "AIService");
        throw ApiException("Erreur lors de la génération du résumé: $detailError", statusCode: response.statusCode);
      }
    } on TimeoutException catch (e) {
       AppLogger.error("Timeout lors de l'appel à /generate_roadmap", error: e, tag: "AIService");
       throw ApiConnectionException("Le délai pour générer le résumé a expiré (3 minutes).");
    } catch (e) {
       AppLogger.error("Erreur inattendue lors de l'appel à /generate_roadmap", error: e, tag: "AIService");
      if (e is ApiException) rethrow;
      throw ApiException("Erreur de communication lors de la génération du résumé: ${e.toString()}");
    }
  }


  static Future<Map<String, String?>> getReadingAndTranslation(String word, SharedPreferences prefs) async {
     AppLogger.info("Appel du backend pour traduction de : '$word'", tag: "AIService");
     try {
        final response = await _client.post(
          Uri.parse('$_backendUrl/translate'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'word': word, 'target_lang': 'FR'}),
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          return {'reading': null, 'translation': data['translation'], 'readingError': null, 'translationError': null};
        } else {
          final errorMsg = _extractApiError(response);
          AppLogger.error("Erreur API (${response.statusCode}) lors de la traduction: $errorMsg", tag: "AIService");
          return {'reading': null, 'translation': null, 'readingError': null, 'translationError': "Erreur $errorMsg (${response.statusCode})"};
        }
     } catch (e) {
        AppLogger.error("Erreur de connexion lors de la traduction", error: e, tag: "AIService");
        String errorDetail = (e is TimeoutException) ? "Timeout" : "Erreur réseau";
        return {'reading': null, 'translation': null, 'readingError': null, 'translationError': 'Impossible de joindre le service de traduction ($errorDetail).'};
     }
  }

  static String _extractApiError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) { return decoded['detail']; }
      if (decoded is Map && decoded['error']?['message'] is String) { return decoded['error']['message']; }
    } catch (_) {}
    return response.reasonPhrase ?? 'Erreur inconnue du serveur';
  }

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
            if (extracted.isNotEmpty) { chapterTitle = extracted; }
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
            AppLogger.warning("La dernière phrase du chapitre généré est incomplète. Nettoyage...", tag: "AIService");
            int lastPunctuationIndex = -1;
            for (final char in terminalChars) {
                int index = trimmedContent.lastIndexOf(char);
                if (index > lastPunctuationIndex) { lastPunctuationIndex = index; }
            }
            if (lastPunctuationIndex != -1) {
                finalContent = trimmedContent.substring(0, lastPunctuationIndex + 1);
                AppLogger.info("Contenu du chapitre tronqué pour terminer sur une phrase complète.", tag: "AIService");
            } else {
                finalContent = "";
                AppLogger.error("Aucune phrase terminée trouvée dans le chapitre généré. Le contenu a été vidé.", tag: "AIService");
            }
        }
    }
    return Chapter(title: chapterTitle, content: finalContent.trim(), createdAt: DateTime.now());
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
      String intro = languagePrompts.firstChapterIntro.replaceAll('[NOVEL_TITLE]', novel.title);
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
    final String intro = isFinalChapter ? languagePrompts.finalChapterIntro : languagePrompts.nextChapterIntro.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());
    final String outputFormat = isFinalChapter ? languagePrompts.outputFormatFinal : languagePrompts.outputFormatNext.replaceAll('[NEXT_CHAPTER_NUMBER]', (currentChapterCount + 1).toString());
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
