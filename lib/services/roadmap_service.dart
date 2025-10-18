import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'ai_service.dart';
import '../providers.dart';

class RoadmapService {
  final Ref _ref;

  RoadmapService(this._ref);

  Future<void> triggerRoadmapUpdateIfNeeded(Novel novel, BuildContext context) async {
    final int chapterCount = novel.chapters.length;

    final bool isFirstRoadmapTrigger = (chapterCount == 4);
    final bool isSubsequentRoadmapTrigger = (chapterCount > 4 && (chapterCount - 1) % 3 == 0);

    debugPrint("Vérification fiche de route pour $chapterCount chapitres. Déclenchement: ${isFirstRoadmapTrigger || isSubsequentRoadmapTrigger}");

    if (isFirstRoadmapTrigger || isSubsequentRoadmapTrigger) {
      
      await Future.delayed(const Duration(seconds: 2));

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mise à jour de la fiche de route en arrière-plan..."),
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
              content: Text("Le plan de l'histoire a été mis à jour !"),
              backgroundColor: Colors.green, 
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        debugPrint("Erreur lors de la mise à jour du plan de l'histoire : $e");
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de la mise à jour du plan de l'histoire: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }
}
