// lib/controllers/home_controller.dart (CORRIGÉ ET FINAL)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../services/ai_service.dart';
import '../services/ai_prompts.dart';
import '../services/sync_service.dart';

/// Controller qui gère la logique métier de la page d'accueil
/// Sépare la logique de l'UI pour une meilleure testabilité
class HomeController {
  final Ref _ref;
  final BuildContext _context;

  HomeController(this._ref, this._context);

  // ================== Backend Status ==================
  
  Future<void> checkBackendStatus() async {
    final statusNotifier = _ref.read(serverStatusProvider.notifier);
    statusNotifier.state = ServerStatus.connecting;
    
    // --- DÉBUT DE LA CORRECTION "NUAGE QUI TOURNE" ---
    // Version simple et robuste sans Future.any
    // Le 'isBackendRunning' a son propre timeout, on a juste
    // besoin de catcher les erreurs imprévues.
    try {
      final isRunning = await _ref.read(localContextServiceProvider).isBackendRunning();
      
      if (_context.mounted) {
        statusNotifier.state = isRunning ? ServerStatus.connected : ServerStatus.failed;
      }
    } catch (e) {
      debugPrint("Erreur inattendue lors de checkBackendStatus: $e");
      if (_context.mounted) {
        statusNotifier.state = ServerStatus.failed; // Forcer l'état d'échec
      }
    }
    // --- FIN DE LA CORRECTION ---
  }

  // ================== Synchronisation ==================
  
  Future<void> forceSyncWithServer() async {
    if (!_context.mounted) return;

    final status = _ref.read(serverStatusProvider);
    if (status != ServerStatus.connected) {
      _showFeedback('Le serveur doit être connecté pour la synchronisation.', isError: true);
      return;
    }

    _showFeedback('Synchronisation complète avec le serveur en cours...', color: Colors.blue);

    try {
      // --- DÉBUT CORRECTION ERREUR "getNovelsWithFullContent" ---
      // On utilise .build()
      // 'novelsToSync' contiendra maintenant les chapitres
      // grâce à notre correction dans lib/providers.dart
      final novelsToSync = await _ref.read(novelsProvider.notifier).build();
      // --- FIN CORRECTION ERREUR ---
      
      if (!_context.mounted) return;

      if (novelsToSync.isEmpty) {
        _showFeedback('Aucun roman à synchroniser.');
        return;
      }
      
      final localContextService = _ref.read(localContextServiceProvider);
      for (final novel in novelsToSync) {
        await localContextService.deleteNovelData(novel.id);
        for (final chapter in novel.chapters) {
          await localContextService.addChapter(
            novelId: novel.id,
            chapterText: chapter.content, // 'chapter.content' est maintenant disponible
          );
        }
      }
      
      if (_context.mounted) {
        _showFeedback('Synchronisation terminée avec succès !', color: Colors.green);
      }
    } catch (e) {
      if (_context.mounted) {
        _showFeedback('Erreur durant la synchronisation : ${e.toString()}', isError: true);
      }
    }
  }

  // ================== Création de roman ==================
  
  Future<void> handleNovelCreation(Novel newNovel, String chapterText) async {
    if (!_context.mounted) return;

    try {
      final firstChapter = AIService.extractTitleAndContent(
        chapterText,
        0,
        true,
        false,
        AIPrompts.getPromptsFor(newNovel.language),
      );
      newNovel.addChapter(firstChapter);
      
      await _ref.read(novelsProvider.notifier).addNovel(newNovel);
      if (_context.mounted) {
        _showFeedback('Roman "${newNovel.title}" créé avec succès !');
      }

      // Ajout à la file de synchronisation
      final syncTask = SyncTask(
        action: 'add',
        novelId: newNovel.id,
        content: firstChapter.content,
        chapterIndex: 0,
      );
      await _ref.read(syncServiceProvider).addTask(syncTask);
      
      if (_context.mounted) {
        _showFeedback(
          'Synchronisation du premier chapitre en cours...', 
          color: Colors.blue
        );
      }

    } catch (e) {
      if (_context.mounted) {
        _showFeedback(
          'Erreur lors de la création du roman : ${e.toString()}', 
          isError: true, 
          duration: 8
        );
      }
    }
  }

  // ================== Dialog de génération ==================
  
  // (Cette méthode est correctement déplacée dans home_page.dart, rien à changer ici)
  Future<String?> _showStreamingDialog(Novel novel) async {
    final prompt = await AIService.preparePrompt(
      novel: novel,
      isFirstChapter: true,
    );

    if (!_context.mounted || prompt.isEmpty) {
      throw Exception("La préparation du prompt a échoué.");
    }

    final stream = AIService.streamChapterFromPrompt(
      prompt: prompt,
      modelId: novel.modelId,
      language: novel.language,
    );
    
    return null; // La logique du dialog est dans home_page.dart
  }

  // ================== Helpers ==================
  
  void _showFeedback(
    String message, {
    bool isError = false,
    Color? color,
    int duration = 4,
  }) {
    if (!_context.mounted) return;
    
    ScaffoldMessenger.of(_context).hideCurrentSnackBar();
    ScaffoldMessenger.of(_context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : (color ?? Colors.green),
        duration: Duration(seconds: duration),
      ),
    );
  }

  String sortOptionToString(SortOption option) {
    switch (option) {
      case SortOption.updatedAt:
        return 'Date de consultation';
      case SortOption.createdAt:
        return 'Date de création';
      case SortOption.title:
        return 'Titre / alphabétique';
      case SortOption.genre:
        return 'Genre';
    }
  }
}