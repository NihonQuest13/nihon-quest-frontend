// lib/services/roadmap_service.dart (MODIFIÉ - Logique de déclenchement vérifiée + déplacement plan futur)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'ai_service.dart';
import '../providers.dart';
import '../utils/app_logger.dart';
import 'ai_prompts.dart';

// ✅ Provider pour le service (inchangé)
final roadmapServiceProvider = Provider<RoadmapService>((ref) {
  return RoadmapService(ref);
});

class RoadmapService {
  final Ref _ref;

  RoadmapService(this._ref);

  /// S'occupe de mettre à jour le RÉSUMÉ DU PASSÉ (le roadmap)
  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    // Déclenchement:
    // - La première fois exactement au chapitre 4.
    // - Ensuite, tous les 3 chapitres *après* le chapitre 4 (donc à 7, 10, 13...).
    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    // (chapterCount - 1) % 3 == 0  -> chapterCount = 4, 7, 10, 13...
    // On veut déclencher après 4, donc on exclut le cas chapterCount == 4 ici.
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    AppLogger.info(
        "Vérification màj Roadmap (PASSÉ) pour ${novel.title} ($chapterCount chapitres). Conditions: isFirst=$isFirstRoadmapTrigger, isSubsequent=$isSubsequentRoadmapTrigger",
        tag: "RoadmapService"
    );

    if (isFirstRoadmapTrigger || isSubsequentRoadmapTrigger) {
       AppLogger.info(">>> Déclenchement de la mise à jour du Roadmap (Passé)...", tag: "RoadmapService");
       // Ajout d'un délai pour éviter les doubles déclenchements potentiels et laisser l'UI se stabiliser
      await Future.delayed(const Duration(seconds: 2));

      // Re-vérifier si le contexte est toujours valide après le délai
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
         // Appeler l'AIService pour générer le nouveau résumé du passé
        final String newRoadMap = await AIService.updateRoadMap(novel);
        AppLogger.success("Nouveau Roadmap (Passé) généré.", tag: "RoadmapService");

        if (!context.mounted) return; // Vérifier après l'appel asynchrone

        // Mettre à jour l'objet Novel avec le nouveau roadmap et sauvegarder
        // ✅ Utiliser copyWith pour créer une nouvelle instance immutable
        final updatedNovel = novel.copyWith(
            roadMap: newRoadMap,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Roadmap (Passé) via provider.", tag: "RoadmapService");

        // Confirmer à l'utilisateur
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

  /// S'occupe de générer ou régénérer le PLAN FUTUR (le "future outline")
  /// Déclenché automatiquement à la création du roman (via createNovelFromPlan)
  /// et ensuite tous les 10 chapitres.
  Future<void> triggerFutureOutlineUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    // Déclencher la régénération tous les 10 chapitres (après le chapitre 0)
    // Ex: à la fin du chapitre 10, 20, 30...
    final bool isMilestoneChapter = (chapterCount > 0 && chapterCount % 10 == 0);
    // La génération initiale est gérée dans createNovelFromPlan

    AppLogger.info(
      "Vérification màj Plan Directeur (FUTUR) pour ${novel.title} ($chapterCount chapitres). Condition: isMilestone=$isMilestoneChapter",
      tag: "RoadmapService"
    );

    // Ne déclencher que sur les paliers de 10 chapitres
    if (isMilestoneChapter) {
        AppLogger.info(">>> Déclenchement de la mise à jour du Plan Directeur (Futur)...", tag: "RoadmapService");
        // Délai pour éviter conflits potentiels avec d'autres opérations
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
          duration: Duration(seconds: 4),
        ),
      );

      try {
         // Appeler l'AIService pour générer le nouveau plan futur
        final String newOutline = await AIService.generateFutureOutline(novel);
         AppLogger.success("Nouveau Plan Directeur (Futur) généré.", tag: "RoadmapService");

        if (!context.mounted) return; // Vérifier après l'appel asynchrone

        // Mettre à jour l'objet Novel et sauvegarder
        // ✅ Utiliser copyWith
        final updatedNovel = novel.copyWith(
            futureOutline: newOutline,
            updatedAt: DateTime.now()
        );
        await _ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
        AppLogger.info("Novel mis à jour avec le nouveau Plan Directeur (Futur) via provider.", tag: "RoadmapService");


        // Confirmer à l'utilisateur (discrètement)
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
            duration: Duration(seconds: 8),
          ),
        );
      }
    } else {
        AppLogger.info("Aucun déclenchement nécessaire pour le Plan Directeur (Futur).", tag: "RoadmapService");
    }
  }

  /// 1. Construit le prompt pour le plan directeur (sans appeler l'IA)
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

    // Créer un Novel temporaire juste pour le formatage du prompt
    final tempNovel = Novel(
      id: '', // Non pertinent pour le prompt
      user_id: userId, // Non pertinent pour le prompt
      title: title,
      level: level,
      genre: genre,
      specifications: userPreferences,
      language: language,
      modelId: modelId,
      createdAt: DateTime.now(), // Non pertinent pour le prompt
      // S'assurer que roadMap est null ou vide pour le premier plan
      roadMap: null,
      futureOutline: null,
    );

    final languagePrompts = AIPrompts.getPromptsFor(tempNovel.language);
    final String prompt = languagePrompts.futureOutlinePrompt
        .replaceAll('[NOVEL_TITLE]', tempNovel.title)
        .replaceAll('[NOVEL_GENRE]', tempNovel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', tempNovel.specifications.isEmpty ? languagePrompts.contextNotAvailable : tempNovel.specifications)
        // Utiliser le contexte spécifique pour le premier chapitre si roadMap est vide
        .replaceAll('[CURRENT_ROADMAP]', tempNovel.roadMap ?? languagePrompts.firstChapterContext);

    AppLogger.info("Prompt pour le plan directeur construit (longueur: ${prompt.length})", tag: "RoadmapService");
    // Optionnel: logger le prompt entier en mode debug
     if (kDebugMode) {
        // debugPrint("Prompt Plan Directeur:\n$prompt");
     }
    return prompt;
  }

  /// 2. Crée et sauvegarde le roman à partir du plan généré (qui est maintenant caché)
  Future<Novel> createNovelFromPlan({
    required String userId,
    required String title,
    required String specifications,
    required String language,
    required String level,
    required String genre,
    required String modelId,
    required String generatedPlan, // Le plan généré par l'IA
  }) async {
    AppLogger.info("Création du Novel à partir du plan généré (qui sera caché)...", tag: "RoadmapService");

    // Le parsing en summaries n'est plus utile si on ne les affiche pas.
    // final List<ChapterSummary> summaries = _parsePlanToSummaries(generatedPlan);
    // if (summaries.isEmpty) {
    //   AppLogger.error("Le plan généré n'a pas pu être analysé ou est vide.", error: generatedPlan, tag: "RoadmapService");
    //   throw Exception("Le plan généré par l'IA est invalide ou vide. Veuillez réessayer.");
    // }

    // Création de l'objet Novel
    final newNovel = Novel(
      user_id: userId,
      title: title,
      level: level,
      genre: genre,
      specifications: specifications,
      language: language,
      modelId: modelId,
      createdAt: DateTime.now(),
      // Stocker le plan brut pour l'IA, mais ne pas l'utiliser pour l'affichage
      futureOutline: generatedPlan,
      // summaries: summaries, // Ne plus stocker les summaries parsés
      // Initialiser le roadmap (passé)
      roadMap: "Le roman vient de commencer.",
    );

    try {
      // Sauvegarder le roman initial dans la base de données via le provider
      // addNovel gère l'ajout à l'état local et l'insertion dans Supabase
      await _ref.read(novelsProvider.notifier).addNovel(newNovel);
      AppLogger.success("Nouveau roman ${newNovel.id} créé et envoyé pour sauvegarde.", tag: "RoadmapService");
      return newNovel; // Retourner l'objet Novel créé
    } catch (e, stackTrace) {
      AppLogger.error("Échec de la sauvegarde initiale du roman", error: e, stackTrace: stackTrace, tag: "RoadmapService");
      // Retransmettre l'exception pour que l'UI puisse la gérer
      throw Exception("Erreur lors de la sauvegarde du roman : ${e.toString()}");
    }
  }

  // ✅ FONCTION SUPPRIMÉE : _parsePlanToSummaries (plus nécessaire)

} // Fin de la classe RoadmapService