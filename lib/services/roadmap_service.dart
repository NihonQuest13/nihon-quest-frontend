// lib/services/roadmap_service.dart (MODIFIÉ POUR LA TRAME ÉVOLUTIVE)
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

  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    AppLogger.info(
        "Vérification màj Roadmap (PASSÉ) pour ${novel.title} ($chapterCount chapitres). Conditions: isFirst=$isFirstRoadmapTrigger, isSubsequent=$isSubsequentRoadmapTrigger",
        tag: "RoadmapService"
    );

    if (isFirstRoadmapTrigger || isSubsequentRoadmapTrigger) {
       AppLogger.info(">>> Déclenchement de la mise à jour du Roadmap (Passé)...", tag: "RoadmapService");
      await Future.delayed(const Duration(seconds: 2));

      if (!context.mounted) {
          AppLogger.warning("Contexte non monté après délai pour màj Roadmap (Passé). Annulation.", tag: "RoadmapService");
          return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mise à jour de la fiche de route (résumé passé) en arrière-plan..."),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 4),
        ),
      );

      try {
        final String newRoadMap = await AIService.updateRoadMap(novel);
        AppLogger.success("Nouveau Roadmap (Passé) généré.", tag: "RoadmapService");

        if (!context.mounted) return;

        final updatedNovel = novel.copyWith(
            roadMap: newRoadMap,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Roadmap (Passé) via provider.", tag: "RoadmapService");

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Le résumé de l'histoire (passé) a été mis à jour !"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e, stackTrace) {
        AppLogger.error("Erreur lors de la mise à jour du Roadmap (Passé)", error: e, stackTrace: stackTrace, tag: "RoadmapService");
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de la mise à jour du résumé passé: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } else {
        AppLogger.info("Aucun déclenchement nécessaire pour le Roadmap (Passé).", tag: "RoadmapService");
    }
  }

  // ✅ MODIFIÉ POUR IGNORER LA MISE À JOUR SI LA TRAME N'EST PAS ÉVOLUTIVE
  Future<void> triggerFutureOutlineUpdateIfNeeded(Novel novel, BuildContext context) async {
    // Si la trame n'est pas dynamique (gérée par l'utilisateur), on ne fait rien.
    if (!novel.isDynamicOutline) {
      AppLogger.info(
        "Mise à jour du Plan Directeur (FUTUR) ignorée car la trame est gérée par l'utilisateur.",
        tag: "RoadmapService"
      );
      return;
    }

    final int chapterCount = novel.chapters.length;
    final bool isMilestoneChapter = (chapterCount > 0 && chapterCount % 10 == 0);

    AppLogger.info(
      "Vérification màj Plan Directeur (FUTUR) pour ${novel.title} ($chapterCount chapitres). Condition: isMilestone=$isMilestoneChapter",
      tag: "RoadmapService"
    );

    if (isMilestoneChapter) {
        AppLogger.info(">>> Déclenchement de la mise à jour du Plan Directeur (Futur)...", tag: "RoadmapService");
        await Future.delayed(const Duration(seconds: 3));

      if (!context.mounted) {
         AppLogger.warning("Contexte non monté après délai pour màj Plan Directeur (Futur). Annulation.", tag: "RoadmapService");
         return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Mise à jour de la trame future (chapitres ${chapterCount + 1}-${chapterCount + 10})..."),
          backgroundColor: Colors.deepPurpleAccent,
          duration: const Duration(seconds: 4),
        ),
      );

      try {
        final String newOutline = await AIService.generateFutureOutline(novel);
         AppLogger.success("Nouveau Plan Directeur (Futur) généré.", tag: "RoadmapService");

        if (!context.mounted) return;

        final updatedNovel = novel.copyWith(
            futureOutline: newOutline,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Plan Directeur (Futur) via provider.", tag: "RoadmapService");


        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Trame future de l'histoire mise à jour !"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e, stackTrace) {
        AppLogger.error("Erreur lors de la mise à jour du Plan Directeur (Futur)", error: e, stackTrace: stackTrace, tag: "RoadmapService");
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
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
     if (kDebugMode) {
        // debugPrint("Prompt Plan Directeur:\n$prompt");
     }
    return prompt;
  }

  // ✅ MODIFIÉ POUR ACCEPTER LE NOUVEAU CHAMP
  Future<Novel> createNovelFromPlan({
    required String userId,
    required String title,
    required String specifications,
    required String language,
    required String level,
    required String genre,
    required String modelId,
    required String? generatedPlan,
    required bool isDynamicOutline,
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
      isDynamicOutline: isDynamicOutline,
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

