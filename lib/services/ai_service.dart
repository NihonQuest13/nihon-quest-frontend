// lib/services/ai_service.dart (Logique de Contexte C5+ Corrigée)

// --- LOGIQUE DE CONTEXTE VOULUE (POUR FUTURES IA) ---
//
// Le but est de fournir à l'IA une hiérarchie de contexte claire et non-contradictoire
// pour assurer la continuité narrative à chaque étape.
//
// Chapitre 1 (C1) : 
// Tâche : "Écris le C1"
// Contexte : 
//   - Spécifications du Roman (Genre, Niveau, Specs, etc.)
//   - Future Outline (Plan directeur futur, s'il existe)
//
// Chapitre 2 (C2) :
// Tâche : "Écris le C2"
// Contexte :
//   - Ancrage Immédiat (Dernière phrase du C1)
//   - Contexte Passé Immédiat (Contenu complet du C1)
//   - Future Outline (Plan directeur)
//   - Spécifications du Roman (Règles globales)
//
// Chapitre 3 (C3) :
// Tâche : "Écris le C3"
// Contexte :
//   - Ancrage Immédiat (Dernière phrase du C2)
//   - Contexte Passé Immédiat (Contenu complet du C2)
//   - Future Outline (Plan directeur)
//   - Contexte Pertinent (Contenu du C1, récupéré par Faiss)
//   - Spécifications du Roman (Règles globales)
//
// Chapitre 4 (C4) :
// Tâche : "Écris le C4"
// Contexte :
//   - Ancrage Immédiat (Dernière phrase du C3)
//   - Contexte Passé Immédiat (Contenu complet du C3)
//   - Future Outline (Plan directeur)
//   - Contexte Pertinent (Contenu du C1, C2, récupéré par Faiss)
//   - Spécifications du Roman (Règles globales)
//
// Chapitre 5 et suivants (C5+) :
// Tâche : "Écris le C(N)"
// Contexte :
//   - Ancrage Immédiat (Dernière phrase du C(N-1))
//   - Contexte Passé Immédiat (Contenu complet du C(N-1)) <-- CRUCIAL
//   - Contexte Passé Global (Le "Roadmap" / Résumé de C1 à C(N-2))
//   - Future Outline (Plan directeur)
//   - Contexte Pertinent (Extraits de C1, C2, C3... récupérés par Faiss)
//   - Spécifications du Roman (Règles globales)
//
// La correction (MODIFICATION 3) ci-dessous implémente cette logique, 
// en s'assurant que le "Contexte Passé Immédiat" (le dernier chapitre complet)
// n'est JAMAIS supprimé, même lorsque le "Roadmap" (résumé) est disponible.
// --- FIN DE LA LOGIQUE DE CONTEXTE ---

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
            // On cherche les chapitres similaires au dernier chapitre
            final similarChapters = await localContextService.getContext(
                novelId: novel.id, 
                query: lastChapterContent, 
                // On demande K+1 pour exclure le dernier chapitre lui-même (qui sera le plus similaire)
                topK: (chaptersInIndex < topK + 1) ? chaptersInIndex : topK + 1 
            );

            // On retire le résultat le plus similaire (qui est le chapitre lui-même)
            if (similarChapters.length > 1) {
                relevantContextChapters = similarChapters.sublist(1);
            }
        }
      } catch (e) {
        debugPrint("Erreur (dans l'isolate) lors de la récupération du contexte : $e");
      }
    }
  }

  // --- MODIFICATION 3 : Appel à la logique de prompt C5+ ---
  final String prompt = AIService._buildChapterPrompt(
    novel: novel,
    isFirstChapter: isFirstChapter,
    isFinalChapter: isFinalChapter,
    currentChapterCount: currentChapterCount,
    languagePrompts: currentLanguagePrompts,
    lastChapterContent: lastChapterContent,
    similarChapters: relevantContextChapters,
    lastSentence: lastSentence,
    roadMap: novel.roadMap, // Passé depuis C5+
    futureOutline: novel.futureOutline, // Passé à toutes les étapes
  );
  // --- FIN MODIFICATION 3 ---
  
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

  // --- ⬇️ MODIFICATION (AJOUT DU BLOC DE DÉBOGAGE) ⬇️ ---
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

    // --- ⬇️ AJOUT POUR LE DÉBOGAGE DU PROMPT ⬇️ ---
    // Cela affichera le prompt complet dans votre console de débogage.
    debugPrint("=========================================================");
    debugPrint("           PROMPT FINAL ENVOYÉ À L'IA                   ");
    debugPrint("           (Généré par l'isolate)                     ");
    debugPrint("=========================================================");
    debugPrint(prompt);
    debugPrint("---------------------------------------------------------");
    debugPrint("Taille du prompt : ${prompt.length} caractères");
    debugPrint("=========================================================");
    // --- ⬆️ FIN DE L'AJOUT ⬆️ ---

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

      // TODO: C'est ici qu'il faudrait appeler la mise à jour du Roadmap
      // par exemple : 
      // if (novel.chapters.length >= 3) {
      //   ref.read(novelsProvider.notifier).updateNovelRoadmap(novel);
      // }
      
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
  // --- ⬆️ FIN DE LA MODIFICATION (DÉBOGAGE) ⬆️ ---


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
  // Ceci est un "bouchon" (stub). Il doit être remplacé par un véritable appel au backend.
  static Future<String> updateRoadMap(Novel novel) async {
    debugPrint("Appel à updateRoadMap (résumé du PASSÉ)...");
    
    // !! ATTENTION !! : 
    // Ceci est un bouchon. Il ne contacte pas le backend.
    // Il renvoie simplement la valeur existante, ou un message par défaut.
    // C'est pourquoi votre roadmap n'est pas générée.
    return novel.roadMap ?? "Le résumé du passé sera mis à jour par le backend.";
  }

  // --- [AUCUNE MODIFICATION - MAIS CORRECTION ENDPOINT] ---
  static Future<Map<String, String?>> getReadingAndTranslation(String word, SharedPreferences prefs) async {
     debugPrint("Appel du backend pour traduction de : $word");

     try {
        final response = await _client.post(
          // Note: L'endpoint /get_reading_translation n'existe pas dans le router.py fourni
          // Il a été remplacé par /translate
          Uri.parse('$_backendUrl/translate'), 
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'word': word,
            'target_lang': 'FR', // Langue cible par défaut
            }),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          // Le backend /translate renvoie 'word' et 'translation'
          return {
            'reading': null, // La lecture n'est pas gérée par /translate
            'translation': data['translation'],
            'readingError': 'Service de lecture non disponible',
            'translationError': null,
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

  // --- ⬇️ MODIFICATION 3 (Logique de Contexte C5+) ⬇️ ---
  // Cette fonction remplace l'ancienne logique (Bug #1 et #2)
  // pour suivre la hiérarchie C1 -> C5+ demandée.
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
    // (Contient les 'spec du roman' via [NOVEL_SPECIFICATIONS])
    String commonInstructions = languagePrompts.commonInstructions
        .replaceAll('[NOVEL_LEVEL]', novel.level)
        .replaceAll('[NOVEL_GENRE]', novel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications)
        .replaceAll('[NOVEL_LANGUAGE]', novel.language);

    // === PARTIE 2 : Cas C1 (PREMIER chapitre) ===
    // Logique C1 : spec du roman + future outline
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
      // 'spec du roman'
      buffer.writeln("- Spécifications: ${novel.specifications.isEmpty ? languagePrompts.contextNotAvailable : novel.specifications}");

      // 'future outline'
      if (futureOutline != null && futureOutline.isNotEmpty) {
        buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
        buffer.writeln(languagePrompts.futureOutlineHeader);
        buffer.writeln(futureOutline);
        buffer.writeln(languagePrompts.futureOutlinePriorityRule);
      }
      
      buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
      buffer.writeln(commonInstructions); // Contient aussi les 'spec'
      buffer.writeln("\n--- FORMAT DE SORTIE ---");
      buffer.writeln(languagePrompts.outputFormatFirst);
      return buffer.toString();
    }
    
    // === PARTIE 3 : Cas C2 et suivants (Chap 2+) ===

    // 1. Définition de la TÂCHE (avec le bon numéro de chapitre)
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
    buffer.writeln(intro); // Ex: "Écrivez le chapitre suivant (Chapitre 2)"

    // --- SEGMENT 2 : ANCRAGE IMMÉDIAT (PRIORITÉ ABSOLUE) ---
    // Logique C2+ : 'Dernière phrase C(N-1)'
    if (lastSentence != null && lastSentence.isNotEmpty) {
        buffer.writeln("\n--- ANCRAGE IMMÉDIAT (PRIORITÉ ABSOLUE) ---");
        buffer.writeln(languagePrompts.contextLastSentenceHeader);
        buffer.writeln(lastSentence);
        buffer.writeln(languagePrompts.contextFollowInstruction); 
    } else {
      buffer.writeln("\n[AVERTISSEMENT: La dernière phrase du chapitre précédent est manquante. Continuez logiquement.]");
    }

    // --- SEGMENT 3 : CONTEXTE PASSÉ (MÉMOIRE) ---
    
    // Logique C2+ : 'Contenu C(N-1)'
    // On fournit TOUJOURS le chapitre précédent (contexte court terme)
    buffer.writeln("\n--- CONTEXTE PASSÉ (MÉMOIRE IMMÉDIATE) ---");
    if (lastChapterContent != null && lastChapterContent.isNotEmpty) {
      final header = languagePrompts.contextLastChapterHeader.replaceAll('[CHAPTER_NUMBER]', currentChapterCount.toString());
      buffer.writeln(header);
      buffer.writeln(lastChapterContent);
    } else {
      buffer.writeln("[AVERTISSEMENT: Le contexte du chapitre précédent est manquant.]");
    }

    // Logique C5+ : 'Roadmap'
    // ON AJOUTE le roadmap (contexte long terme) s'il existe.
    if (roadMap != null && roadMap.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE PASSÉ (RÉSUMÉ GLOBAL) ---"); // Titre distinct
      buffer.writeln(languagePrompts.roadmapHeader);
      buffer.writeln(roadMap);
    }
    
    // --- SEGMENT 4 : CONTEXTE FUTUR (GUIDE) ---
    // Logique C2+ : 'future outline'
    if (futureOutline != null && futureOutline.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE FUTUR (GUIDE) ---");
      buffer.writeln(languagePrompts.futureOutlineHeader);
      buffer.writeln(futureOutline);
      buffer.writeln(languagePrompts.futureOutlinePriorityRule);
    }
    
    // --- SEGMENT 5 : CONTEXTE PERTINENT (FAISS) ---
    // Logique C3+ : 'Chapitres pertinents (C1, C2, etc.)'
    if (similarChapters != null && similarChapters.isNotEmpty) {
      buffer.writeln("\n--- CONTEXTE PERTINENT (EXTRAITS DE LA MÉMOIRE) ---");
      buffer.writeln(languagePrompts.contextSimilarSectionHeader);
      for (int i = 0; i < similarChapters.length; i++) {
        final excerptHeader = languagePrompts.similarExcerptHeader.replaceAll("[NUMBER]", (i + 1).toString());
        buffer.writeln("$excerptHeader\n${similarChapters[i]}\n${languagePrompts.similarExcerptFooter}");
      }
    }
      
    // --- SEGMENT 6 : RÈGLES ET FORMAT ---
    // Logique C2+ : 'spec du roman' (via commonInstructions)
    buffer.writeln("\n--- RÈGLES DE GÉNÉRATION ---");
    buffer.writeln(commonInstructions);
    buffer.writeln(finalChapterInstructions);
    
    buffer.writeln("\n--- FORMAT DE SORTIE ---");
    buffer.writeln(outputFormat); // Ex: "Chapitre 2: [Titre]"

    return buffer.toString();
  }
  // --- ⬆️ FIN MODIFICATION 3 ⬆️ ---
}