import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'ai_service.dart';
import '../providers.dart'; // Assurez-vous que ce provider existe et est correct
import 'ai_service.dart'; // Assurez-vous que AIService est importé

class RoadmapService {
  final Ref _ref;

  RoadmapService(this._ref);

  /// S'occupe de mettre à jour le RÉSUMÉ DU PASSÉ (le roadmap)
  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    // C'est votre logique existante pour le résumé du PASSÉ
    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    debugPrint("Vérification fiche de route (PASSÉ) pour $chapterCount chapitres. Déclenchement: ${isFirstRoadmapTrigger || isSubsequentRoadmapTrigger}");

    if (isFirstRoadmapTrigger || isSubsequentRoadmapTrigger) {
      
      await Future.delayed(const Duration(seconds: 2));

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mise à jour de la fiche de route (résumé) en arrière-plan..."),
          backgroundColor: Colors.blueAccent, 
          duration: Duration(seconds: 4),
        ),
      );

      try {
        // Cette fonction doit appeler votre backend pour générer le RÉSUMÉ
        final newRoadMap = await AIService.updateRoadMap(novel); 
        
        if (!context.mounted) return;

        novel.roadMap = newRoadMap;
        novel.updatedAt = DateTime.now();
        
        // Assurez-vous que novelsProvider est le bon nom pour votre provider
        await _ref.read(novelsProvider.notifier).updateNovel(novel);

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Le plan de l'histoire (résumé) a été mis à jour !"),
              backgroundColor: Colors.green, 
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        debugPrint("Erreur lors de la mise à jour du plan de l'histoire (résumé) : $e");
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de la mise à jour du résumé: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  // --- MODIFICATION : Ajout de la fonction pour le PLAN FUTUR (ton "sommaire") ---
  /// S'occupe de générer le PLAN FUTUR (le "sommaire")
  /// Doit être appelé à la création du roman (chapitre 0) et avant chaque 10ème chapitre.
  Future<void> triggerFutureOutlineUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    // Se déclenche à la création (0) ou tous les 10 chapitres (10, 20, 30...)
    final bool isFirstOutline = (chapterCount == 0);
    final bool isMilestoneChapter = (chapterCount > 0 && chapterCount % 10 == 0);

    debugPrint("Vérification plan directeur (FUTUR) pour $chapterCount chapitres. Déclenchement: ${isFirstOutline || isMilestoneChapter}");

    if (isFirstOutline || isMilestoneChapter) {
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFirstOutline 
              ? "Génération du plan directeur de l'histoire..." 
              : "Génération du plan pour les 10 prochains chapitres..."),
          backgroundColor: Colors.deepPurpleAccent, 
          duration: const Duration(seconds: 4),
        ),
      );

      try {
        // Appelle la nouvelle fonction dans AIService
        final newOutline = await AIService.generateFutureOutline(novel);
        
        if (!context.mounted) return;

        novel.futureOutline = newOutline; // On sauvegarde le nouveau plan
        novel.updatedAt = DateTime.now();
        await _ref.read(novelsProvider.notifier).updateNovel(novel);

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Plan directeur de l'histoire mis à jour !"),
              backgroundColor: Colors.green, 
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        debugPrint("Erreur lors de la génération du plan directeur : $e");
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de la génération du plan directeur: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }
  // --- FIN MODIFICATION ---
}