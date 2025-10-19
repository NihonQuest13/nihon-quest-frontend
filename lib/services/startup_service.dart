// lib/services/startup_service.dart (CORRIGÉ)
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'local_context_service.dart';
import '../providers.dart';

final startupServiceProvider = Provider((ref) => StartupService(ref));

class StartupService {
  final Ref _ref;
  
  StartupService(this._ref);

  Future<void> synchronizeOnStartup() async {
    debugPrint("[StartupService] Début de la vérification de synchronisation au démarrage.");
    
    final serverStatus = _ref.read(serverStatusProvider);
    if (serverStatus != ServerStatus.connected) {
      debugPrint("[StartupService] Serveur déconnecté. Vérification reportée.");
      return;
    }

    try {
      final localContextService = _ref.read(localContextServiceProvider);
      
      // ✅ CORRECTION : Utiliser l'état actuel au lieu de .build()
      final asyncNovels = _ref.read(novelsProvider);
      final localNovels = asyncNovels.when(
        data: (novels) => novels,
        loading: () => <Novel>[],
        error: (_, __) => <Novel>[],
      );
      
      final backendNovelIds = (await localContextService.listIndexedNovels()).toSet();
      final localNovelIds = localNovels.map((n) => n.id).toSet();
      
      // Gérer les romans qui sont dans notre BDD mais pas sur le backend (nouveaux romans)
      final missingOnBackend = localNovelIds.difference(backendNovelIds);
      if (missingOnBackend.isNotEmpty) {
        debugPrint("[StartupService] ${missingOnBackend.length} roman(s) manquant(s) sur le backend détecté(s). Lancement de la synchronisation.");
        for (final novelId in missingOnBackend) {
          final novel = localNovels.firstWhere((n) => n.id == novelId);
          debugPrint("[StartupService] Synchronisation de '${novel.title}'...");
          await localContextService.deleteNovelData(novel.id); 
          for (final chapter in novel.chapters) {
            await localContextService.addChapter(novelId: novel.id, chapterText: chapter.content);
          }
        }
      }

      // Gérer les romans qui sont sur le backend mais plus dans notre BDD (romans supprimés)
      final missingLocally = backendNovelIds.difference(localNovelIds);
      if (missingLocally.isNotEmpty) {
        debugPrint("[StartupService] ${missingLocally.length} roman(s) supprimé(s) localement détecté(s). Nettoyage du backend.");
        for (final novelId in missingLocally) {
          debugPrint("[StartupService] Suppression du roman $novelId du backend...");
          await localContextService.deleteNovelData(novelId);
        }
      }
      
      debugPrint("[StartupService] Synchronisation de démarrage terminée.");

    } catch (e) {
      debugPrint("[StartupService] ERREUR CRITIQUE durant la synchronisation de démarrage : $e");
    }
  }
}