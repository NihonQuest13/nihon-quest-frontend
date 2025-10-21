// lib/services/roadmap_service.dart (AMÉLIORÉ AVEC LOGS ET GESTION DE CONTEXTE ROBUSTE)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'ai_service.dart';
import '../providers.dart';
import '../utils/app_logger.dart';
import 'ai_prompts.dart';

final roadmapServiceProvider = Provider<RoadmapService>((ref) {
  return RoadmapService(ref);
});

class RoadmapService {
  final Ref _ref;

  RoadmapService(this._ref);

  /// S'occupe de mettre à jour le RÉSUMÉ DU PASSÉ (le roadmap)
  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    // Déclenchement: Chapitre 4 (première fois), puis 7, 10, 13...
    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    AppLogger.info(
        "Vérification màj Roadmap (PASSÉ) pour ${novel.title} ($chapterCount chapitres). Conditions: isFirst=$isFirstRoadmapTrigger, isSubsequent=$isSubsequentRoadmapTrigger",
        tag: "RoadmapService"
    );

    if (isFirstRoadmapTrigger || isSubsequentRoadmapTrigger) {
       AppLogger.info(">>> Déclenchement de la mise à jour du Roadmap (Passé)...", tag: "RoadmapService");
      await Future.delayed(const Duration(seconds: 1)); // Petit délai

      final currentContext = context;
      if (!currentContext.mounted) {
          AppLogger.warning("Contexte non monté AVANT l'appel IA pour màj Roadmap (Passé). Annulation.", tag: "RoadmapService");
          return;
      }

      ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
      ScaffoldMessenger.of(currentContext).showSnackBar(
        const SnackBar(
          content: Text("🤖 L'écrivain met à jour le résumé de l'histoire (passé)..."),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 10), 
        ),
      );

      try {
        final String newRoadMap = await AIService.updateRoadMap(novel);
        AppLogger.success("Nouveau Roadmap (Passé) généré par le backend. Longueur: ${newRoadMap.length}", tag: "RoadmapService");

        if (!currentContext.mounted) {
           AppLogger.warning("Contexte non monté APRÈS l'appel IA pour màj Roadmap (Passé). Mise à jour Novel annulée.", tag: "RoadmapService");
           return;
        }

        final updatedNovel = novel.copyWith(
            roadMap: newRoadMap,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Roadmap (Passé) via provider.", tag: "RoadmapService");

        ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(
            content: Text("✅ Résumé de l'histoire (passé) mis à jour !"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      } catch (e, stackTrace) {
        AppLogger.error("Erreur lors de la mise à jour du Roadmap (Passé)", error: e, stackTrace: stackTrace, tag: "RoadmapService");
        if (!currentContext.mounted) {
           AppLogger.warning("Contexte non monté lors de la gestion d'erreur Roadmap (Passé).", tag: "RoadmapService");
           return;
        }

        String errorMessage = "Échec de la mise à jour du résumé passé.";
        if (e is ApiException) {
          errorMessage += " Erreur: ${e.message}";
          if (e.statusCode != null) {
              errorMessage += " (Code: ${e.statusCode})";
          }
        } else {
            errorMessage += " Erreur: ${e.toString()}";
        }

        ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } else {
        AppLogger.info("Aucun déclenchement nécessaire pour le Roadmap (Passé).", tag: "RoadmapService");
    }
  }

  /// S'occupe de générer ou régénérer le PLAN FUTUR (le "future outline")
  Future<void> triggerFutureOutlineUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;
    final bool isMilestoneChapter = (chapterCount > 0 && chapterCount % 10 == 0);

    AppLogger.info(
      "Vérification màj Plan Directeur (FUTUR) pour ${novel.title} ($chapterCount chapitres). Condition: isMilestone=$isMilestoneChapter",
      tag: "RoadmapService"
    );

    if (isMilestoneChapter) {
        AppLogger.info(">>> Déclenchement de la mise à jour du Plan Directeur (Futur)...", tag: "RoadmapService");
        await Future.delayed(const Duration(seconds: 3));

      final currentContext = context;
      if (!currentContext.mounted) {
         AppLogger.warning("Contexte non monté après délai pour màj Plan Directeur (Futur). Annulation.", tag: "RoadmapService");
         return;
      }

      ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(
          content: Text("Mise à jour de la trame future (chapitres ${chapterCount + 1}-${chapterCount + 10})..."),
          backgroundColor: Colors.deepPurpleAccent,
          duration: const Duration(seconds: 4),
        ),
      );

      try {
        final String newOutline = await AIService.generateFutureOutline(novel);
        AppLogger.success("Nouveau Plan Directeur (Futur) généré.", tag: "RoadmapService");

        if (!currentContext.mounted) return;

        final updatedNovel = novel.copyWith(
            futureOutline: newOutline,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Plan Directeur (Futur) via provider.", tag: "RoadmapService");


        ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(
            content: Text("Trame future de l'histoire mise à jour !"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      } catch (e, stackTrace) {
        AppLogger.error("Erreur lors de la mise à jour du Plan Directeur (Futur)", error: e, stackTrace: stackTrace, tag: "RoadmapService");
        if (!currentContext.mounted) return;
        ScaffoldMessenger.of(currentContext).hideCurrentSnackBar();
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text("Échec de la mise à jour de la trame future: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } else {
        AppLogger.info("Aucun déclenchement nécessaire pour le Plan Directeur (Futur).", tag: "RoadmapService");
    }
  }

  String getPlanPrompt({
    required String title,
    required String userPreferences,
    required String language,
    required String level,
    required String genre,
    required String modelId,
    required String userId,
  }) {
    AppLogger.info("Construction du prompt pour le plan directeur (futur)...", tag: "RoadmapService");

    final tempNovel = Novel(
      id: '',
      user_id: userId,
      title: title,
      level: level,
      genre: genre,
      specifications: userPreferences,
      language: language,
      modelId: modelId,
      createdAt: DateTime.now(),
      roadMap: null,
      futureOutline: null,
    );

    final languagePrompts = AIPrompts.getPromptsFor(tempNovel.language);
    final String prompt = languagePrompts.futureOutlinePrompt
        .replaceAll('[NOVEL_TITLE]', tempNovel.title)
        .replaceAll('[NOVEL_GENRE]', tempNovel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', tempNovel.specifications.isEmpty ? languagePrompts.contextNotAvailable : tempNovel.specifications)
        .replaceAll('[CURRENT_ROADMAP]', tempNovel.roadMap ?? languagePrompts.firstChapterContext);

    AppLogger.info("Prompt pour le plan directeur construit (longueur: ${prompt.length})", tag: "RoadmapService");
    return prompt;
  }

  Future<Novel> createNovelFromPlan({
    required String userId,
    required String title,
    required String specifications,
    required String language,
    required String level,
    required String genre,
    required String modelId,
    required String generatedPlan,
  }) async {
    AppLogger.info("Création du Novel à partir du plan généré...", tag: "RoadmapService");

    final newNovel = Novel(
      user_id: userId,
      title: title,
      level: level,
      genre: genre,
      specifications: specifications,
      language: language,
      modelId: modelId,
      createdAt: DateTime.now(),
      futureOutline: generatedPlan,
      roadMap: "Le roman vient de commencer.",
    );

    try {
      await _ref.read(novelsProvider.notifier).addNovel(newNovel);
      AppLogger.success("Nouveau roman ${newNovel.id} créé et envoyé pour sauvegarde.", tag: "RoadmapService");
      return newNovel;
    } catch (e, stackTrace) {
      AppLogger.error("Échec de la sauvegarde initiale du roman", error: e, stackTrace: stackTrace, tag: "RoadmapService");
      throw Exception("Erreur lors de la sauvegarde du roman : ${e.toString()}");
    }
  }
}
