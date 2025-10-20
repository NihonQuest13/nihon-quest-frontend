// lib/services/roadmap_service.dart (CORRIGÉ)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'ai_service.dart';
import '../providers.dart';
import '../utils/app_logger.dart';
import 'ai_prompts.dart';

class RoadmapService {
  final Ref _ref;

  RoadmapService(this._ref);

  /// S'occupe de mettre à jour le RÉSUMÉ DU PASSÉ (le roadmap)
  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    AppLogger.info("Vérification fiche de route (PASSÉ) pour $chapterCount chapitres. Déclenchement: ${isFirstRoadmapTrigger || isSubsequentRoadmapTrigger}", tag: "RoadmapService");

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
        final newRoadMap = await AIService.updateRoadMap(novel);
        if (!context.mounted) return;

        novel.roadMap = newRoadMap;
        novel.updatedAt = DateTime.now();
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
        AppLogger.error("Erreur lors de la mise à jour du plan de l'histoire (résumé)", error: e, tag: "RoadmapService");
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

  /// S'occupe de générer le PLAN FUTUR (le "sommaire")
  Future<void> triggerFutureOutlineUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    final bool isFirstOutline = (chapterCount == 0);
    final bool isMilestoneChapter = (chapterCount > 0 && chapterCount % 10 == 0);

    AppLogger.info("Vérification plan directeur (FUTUR) pour $chapterCount chapitres. Déclenchement: ${isFirstOutline || isMilestoneChapter}", tag: "RoadmapService");

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
        final newOutline = await AIService.generateFutureOutline(novel);
        if (!context.mounted) return;

        novel.futureOutline = newOutline;
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
        AppLogger.error("Erreur lors de la génération du plan directeur", error: e, tag: "RoadmapService");
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
    // ✅ CORRIGÉ : logInfo -> info
    AppLogger.info("Construction du prompt pour le plan directeur...", tag: "RoadmapService");

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
    );

    // ✅ CORRIGÉ : Appel à une méthode inexistante remplacé par la logique de construction du prompt.
    final languagePrompts = AIPrompts.getPromptsFor(tempNovel.language);
    final String prompt = languagePrompts.futureOutlinePrompt
        .replaceAll('[NOVEL_TITLE]', tempNovel.title)
        .replaceAll('[NOVEL_GENRE]', tempNovel.genre)
        .replaceAll('[NOVEL_SPECIFICATIONS]', tempNovel.specifications.isEmpty ? languagePrompts.contextNotAvailable : tempNovel.specifications)
        .replaceAll('[CURRENT_ROADMAP]', tempNovel.roadMap ?? languagePrompts.firstChapterContext);

    return prompt;
  }

  /// 2. Crée et sauvegarde le roman à partir du plan généré
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
    // ✅ CORRIGÉ : logInfo -> info
    AppLogger.info("Analyse du plan généré et création du roman...", tag: "RoadmapService");

    final List<ChapterSummary> summaries = _parsePlanToSummaries(generatedPlan);

    if (summaries.isEmpty) {
      // ✅ CORRIGÉ : logError -> error
      AppLogger.error("Le plan généré n'a pas pu être analysé ou est vide.", error: generatedPlan, tag: "RoadmapService");
      throw Exception("Le plan généré par l'IA est invalide ou vide. Veuillez réessayer.");
    }

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
      summaries: summaries,
      roadMap: "Le roman vient de commencer.",
    );

    try {
      // ✅ CORRIGÉ : `addNovel` ne retourne rien, on attend simplement la fin de l'opération
      // et on retourne l'objet `newNovel` que nous avons créé.
      await _ref.read(novelsProvider.notifier).addNovel(newNovel);
      AppLogger.info("Nouveau roman ${newNovel.id} envoyé pour sauvegarde.", tag: "RoadmapService");
      return newNovel;
    } catch (e) {
      // ✅ CORRIGÉ : logError -> error
      AppLogger.error("Échec de la sauvegarde du roman dans Supabase", error: e, tag: "RoadmapService");
      throw Exception("Erreur lors de la sauvegarde du roman : ${e.toString()}");
    }
  }

  /// 3. Outil interne pour analyser le plan texte en objets ChapterSummary
  List<ChapterSummary> _parsePlanToSummaries(String planText) {
    final List<ChapterSummary> summaries = [];
    final lines = planText.split('\n');

    String currentTitle = '';
    String currentContent = '';
    int chapterIndex = 0;

    for (final line in lines) {
      final titleMatch = RegExp(r'^(?:Chapitre|Chapter|Capítulo|Capitolo|第[一二三四五六七八九十百千\d]+章|10?)\s*\.?\s*\d*\s*[:：-]?\s*(.*)', caseSensitive: false).firstMatch(line.trim());

      if (titleMatch != null) {
        if (currentTitle.isNotEmpty && currentContent.isNotEmpty) {
          // ✅ CORRIGÉ : Appel au constructeur de ChapterSummary avec les bons paramètres.
          summaries.add(ChapterSummary(
            endChapterIndex: chapterIndex, // Utilise l'index du chapitre précédent
            summaryText: '$currentTitle: ${currentContent.trim()}',
            createdAt: DateTime.now(),
          ));
          currentContent = '';
        }
        currentTitle = titleMatch.group(1)?.trim() ?? 'Titre inconnu';
        chapterIndex++;
      } else if (currentTitle.isNotEmpty && line.trim().isNotEmpty) {
        currentContent += '${line.trim()} ';
      }
    }

    if (currentTitle.isNotEmpty && currentContent.isNotEmpty) {
      // ✅ CORRIGÉ : Appel au constructeur de ChapterSummary avec les bons paramètres.
      summaries.add(ChapterSummary(
        endChapterIndex: chapterIndex,
        summaryText: '$currentTitle: ${currentContent.trim()}',
        createdAt: DateTime.now(),
      ));
    }

    return summaries;
  }
}
