// lib/providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:collection/collection.dart'; // Pour firstWhereOrNull
import 'package:japanese_story_app/utils/app_logger.dart'; // ✅ AJOUT: Importer AppLogger

import 'models.dart';
import 'services/local_context_service.dart';
import 'services/roadmap_service.dart';
import 'services/sync_service.dart';
import 'services/vocabulary_service.dart';
// Importer le controller des amis pour les providers dépendants
import 'controllers/friends_controller.dart';

// --- État du mode écrivain ---
final writerModeProvider = StateProvider<bool>((ref) => false);

// --- État du serveur backend ---
enum ServerStatus { connecting, connected, failed }
final serverStatusProvider = StateProvider<ServerStatus>((ref) => ServerStatus.connecting);

// --- État de la file de synchronisation ---
enum SyncQueueStatus { idle, processing, hasPendingTasks }
final syncQueueStatusProvider = StateProvider<SyncQueueStatus>((ref) => SyncQueueStatus.idle);

// --- Accès aux SharedPreferences (initialisé dans main.dart) ---
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences non initialisé. Assurez-vous de l\'override dans ProviderScope.');
});

// --- Service de synchronisation ---
final syncServiceProvider = Provider<SyncService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SyncService(ref, prefs);
});

// --- Service de contexte local (backend Python) ---
final localContextServiceProvider = Provider<LocalContextService>((ref) {
  final service = LocalContextService();
  // Ferme le client HTTP quand le provider est détruit
  ref.onDispose(() => service.dispose());
  return service;
});

// --- Service de gestion de la roadmap ---
final roadmapServiceProvider = Provider<RoadmapService>((ref) {
  return RoadmapService(ref);
});

// --- Service de vocabulaire ---
final vocabularyServiceProvider = Provider<VocabularyService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VocabularyService(prefs: prefs);
});


// --- Gestion du Thème ---
final themeService = ThemeService(ThemeMode.system); // Initialisation (sera chargé depuis prefs)

class ThemeService extends ValueNotifier<ThemeMode> {
  ThemeService(super.value);
  static const _themePrefKey = 'theme_mode_pref_v2'; // Clé de préférence

  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themePrefKey);
      if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
         value = ThemeMode.values[themeIndex];
      } else {
         value = ThemeMode.system; // Défaut si rien n'est sauvegardé ou invalide
      }
    } catch (e) {
      AppLogger.error("Erreur chargement thème", error: e, tag:"ThemeService");
      value = ThemeMode.system;
    }
  }

  void updateTheme(ThemeMode newThemeMode) {
    if (value == newThemeMode) return;
    value = newThemeMode;
    _saveTheme(newThemeMode);
  }

  Future<void> _saveTheme(ThemeMode themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themePrefKey, themeMode.index);
    } catch (e) {
      AppLogger.error("Erreur sauvegarde thème", error: e, tag:"ThemeService");
    }
  }
}

// Provider Riverpod pour le thème (StateNotifier)
final themeServiceProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  // Charge l'état initial depuis le service
  ThemeNotifier() : super(themeService.value) {
    // Écoute les changements externes (par exemple, si loadTheme est appelé après coup)
    themeService.addListener(_onServiceThemeChanged);
  }

  void _onServiceThemeChanged() {
    if (state != themeService.value) {
      state = themeService.value;
    }
  }

  void updateTheme(ThemeMode newThemeMode) {
    // Met à jour l'état local ET appelle le service pour sauvegarder
    if (state != newThemeMode) {
      state = newThemeMode;
      themeService.updateTheme(newThemeMode); // Le service sauvegarde
    }
  }

  @override
  void dispose() {
    themeService.removeListener(_onServiceThemeChanged);
    super.dispose();
  }
}

// --- Option de tri pour la liste des romans ---
enum SortOption { updatedAt, createdAt, title, genre }
final sortOptionProvider = StateProvider<SortOption>((ref) => SortOption.updatedAt);

// --- Accès au client Supabase ---
final supabaseProvider = Provider((ref) => Supabase.instance.client);

// --- Suivi de l'état d'authentification ---
final authStateProvider = StreamProvider<AuthState>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.auth.onAuthStateChange;
});

// --- Provider principal pour la liste des romans ---
final novelsProvider = AsyncNotifierProvider<NovelsNotifier, List<Novel>>(NovelsNotifier.new);

class NovelsNotifier extends AsyncNotifier<List<Novel>> {

  // Récupère l'instance Supabase une seule fois
  SupabaseClient get _supabase => ref.read(supabaseProvider);
  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  Future<List<Novel>> build() async {
    // S'abonne aux changements d'état d'authentification pour reconstruire si nécessaire
    ref.watch(authStateProvider);
    // S'abonne aux changements d'option de tri
    final sortOption = ref.watch(sortOptionProvider);

    final currentUserId = _userId;
    if (currentUserId == null) {
      AppLogger.info("Aucun utilisateur connecté, retour liste vide.", tag: "NovelsProvider");
      return [];
    }

    AppLogger.info("Récupération romans depuis Supabase (User: $currentUserId, Tri: $sortOption)...", tag: "NovelsProvider");

    try {
      // La requête ne filtre plus par user_id ici, RLS s'en charge
      final novelsData = await _supabase
          .from('novels')
          .select('*, chapters(*)') // Récupère les romans ET leurs chapitres associés
          // RLS filtre automatiquement les romans auxquels l'utilisateur a accès
          .order('updated_at', ascending: false) // Tri principal par défaut
          // Tri secondaire pour les chapitres par Supabase (important)
          .order('created_at', referencedTable: 'chapters', ascending: true);

      // Mapper les données JSON en objets Novel
      final novels = novelsData.map((novelRow) {
        try {
          // Novel.fromJson trie déjà les chapitres lors du parsing
          return Novel.fromJson(novelRow);
        } catch (e, stacktrace) {
          AppLogger.error("Erreur parsing Novel ID ${novelRow['id']}", error: e, stackTrace: stacktrace, tag: "NovelsProvider");
          return null; // Ignore les romans qui ne peuvent pas être parsés
        }
      }).whereType<Novel>().toList(); // Filtrer les nulls

      AppLogger.info("${novels.length} romans récupérés et parsés.", tag: "NovelsProvider");

      // Appliquer le tri des ROMANS côté client
      return _sortNovels(novels, sortOption);

    } catch (e, stacktrace) {
       AppLogger.error("Erreur lors de la récupération des romans", error: e, stackTrace: stacktrace, tag: "NovelsProvider");
       // Retourne l'erreur pour que l'UI puisse l'afficher
       throw Exception("Impossible de charger les romans: $e");
    }
  }

  // --- Fonctions de tri (côté client) ---
  List<Novel> _sortNovels(List<Novel> novels, SortOption sortOption) {
    // Crée une copie modifiable pour le tri
    final sortedList = List<Novel>.from(novels);
    switch (sortOption) {
      case SortOption.createdAt:
        sortedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.title:
        sortedList.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortOption.genre:
        sortedList.sort((a, b) {
          final genreComparison = a.genre.toLowerCase().compareTo(b.genre.toLowerCase());
          if (genreComparison != 0) return genreComparison;
          // Tri secondaire par titre si même genre
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case SortOption.updatedAt:
        // Le tri par défaut de Supabase est déjà par updatedAt descendant
        sortedList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Assurer le tri même si Supabase change
        break;
    }
    return sortedList;
  }

  // --- Fonctions de modification (ajout, màj, suppression) ---

  // Helper pour convertir Novel en JSON pour Supabase (table 'novels')
  Map<String, dynamic> _novelToSupabaseJson(Novel novel, String userId) {
    final data = novel.toJson();
    // Assure que user_id est présent, retire 'chapters' et 'summaries'
    data['user_id'] = userId;
    data.remove('chapters');
    data.remove('summaries'); // Summaries non stockés dans la table novels
    return data;
  }

  // Ajouter un nouveau roman
  Future<void> addNovel(Novel novel) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // Préparer les données pour Supabase
    final novelData = _novelToSupabaseJson(novel, currentUserId);
    final chaptersData = novel.chapters.map((chapter) {
      // ✅ Assurer le tri avant de préparer les données chapitre (fait par Novel.fromJson)
      // novel.chapters.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // ❌ DÉSORMAIS FAIT VIA LE CONSTRUCTEUR/novelWithAddedChapter
      final chapterJson = chapter.toJson();
      chapterJson['novel_id'] = novel.id; // Lier le chapitre au roman
      return chapterJson;
    }).toList();

    // Mettre à jour l'état local immédiatement (optimiste)
    state = await AsyncValue.guard(() async {
      final currentNovels = state.value ?? [];
      // Ajoute au début et re-trie les romans selon l'option actuelle
      return _sortNovels([novel, ...currentNovels], ref.read(sortOptionProvider));
    });

    // Envoyer à Supabase
    try {
      await _supabase.from('novels').insert(novelData);
      if (chaptersData.isNotEmpty) {
        await _supabase.from('chapters').insert(chaptersData);
      }
      AppLogger.info("Roman ${novel.id} ajouté avec succès.", tag: "NovelsProvider");
      // Pas besoin d'invalider ici, la mise à jour optimiste a fonctionné
    } catch (e) {
      AppLogger.error("Erreur lors de l'ajout du roman ${novel.id}", error: e, tag: "NovelsProvider");
      // En cas d'erreur, invalider pour récupérer l'état réel de la BDD
      ref.invalidateSelf();
      // Propager l'erreur pour que l'UI puisse la gérer
      throw Exception("Erreur Supabase lors de l'ajout: $e");
    }
  }

  // Mettre à jour un roman existant (métadonnées)
  Future<void> updateNovel(Novel updatedNovel) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    final novelData = _novelToSupabaseJson(updatedNovel, currentUserId);

    // Mise à jour optimiste de l'état local
    state = await AsyncValue.guard(() async {
       final currentNovels = state.value ?? [];
       final index = currentNovels.indexWhere((n) => n.id == updatedNovel.id);
       if (index != -1) {
         final newList = List<Novel>.from(currentNovels);
         newList[index] = updatedNovel; // Remplacer par le novel mis à jour (avec chapitres triés)
         // Re-trie les romans si nécessaire
         return _sortNovels(newList, ref.read(sortOptionProvider));
       }
       return currentNovels; // Retourne la liste inchangée si non trouvé
    });

    // Envoyer à Supabase
    try {
      await _supabase.from('novels').update(novelData).eq('id', updatedNovel.id);
      AppLogger.info("Roman ${updatedNovel.id} mis à jour avec succès.", tag: "NovelsProvider");
    } catch (e) {
      AppLogger.error("Erreur lors de la mise à jour du roman ${updatedNovel.id}", error: e, tag: "NovelsProvider");
      ref.invalidateSelf();
      throw Exception("Erreur Supabase lors de la mise à jour: $e");
    }
  }

  // Ajouter un chapitre à un roman existant
  Future<void> addChapter(String novelId, Chapter newChapter) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // Préparer les données du chapitre pour Supabase
    final chapterData = newChapter.toJson();
    chapterData['novel_id'] = novelId;

    // Mise à jour optimiste de l'état local
    Novel? updatedNovelState;
    state = await AsyncValue.guard(() async {
       final currentNovels = state.value ?? [];
       final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
       if (novelIndex != -1) {
         final originalNovel = currentNovels[novelIndex];
         // Utilise la méthode helper du modèle pour créer une nouvelle instance
         final updatedNovel = originalNovel.novelWithAddedChapter(newChapter);
         // ✅ Forcer le tri des chapitres DANS la nouvelle instance (déjà fait par novelWithAddedChapter)
         updatedNovelState = updatedNovel; // Sauvegarde pour la màj Supabase de updated_at

         final newList = List<Novel>.from(currentNovels);
         newList[novelIndex] = updatedNovel;
         return _sortNovels(newList, ref.read(sortOptionProvider)); // Re-trier les romans
       }
       return currentNovels;
    });

    // Envoyer à Supabase
    if (updatedNovelState != null) {
        try {
          await _supabase.from('chapters').insert(chapterData);
          // Mettre à jour 'updated_at' du roman parent
          await _supabase.from('novels')
              .update({'updated_at': updatedNovelState!.updatedAt.toIso8601String()})
              .eq('id', novelId);
          AppLogger.info("Chapitre ${newChapter.id} ajouté au roman ${novelId}.", tag: "NovelsProvider");
        } catch (e) {
           AppLogger.error("Erreur lors de l'ajout du chapitre ${newChapter.id}", error: e, tag: "NovelsProvider");
           ref.invalidateSelf();
           throw Exception("Erreur Supabase lors de l'ajout du chapitre: $e");
        }
    } else {
       AppLogger.error("Erreur addChapter: Roman $novelId non trouvé dans l'état local.", tag: "NovelsProvider");
       ref.invalidateSelf(); // Recharge au cas où
       throw Exception("Roman non trouvé pour ajouter le chapitre.");
    }
  }

  // Mettre à jour un chapitre existant
  Future<void> updateChapter(String novelId, Chapter updatedChapter) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // Mise à jour optimiste
    Novel? updatedNovelState;
    state = await AsyncValue.guard(() async {
      final currentNovels = state.value ?? [];
      final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
      if (novelIndex != -1) {
        final originalNovel = currentNovels[novelIndex];
        // Utilise la méthode helper du modèle
        final updatedNovel = originalNovel.novelWithUpdatedChapter(updatedChapter);
        // ✅ Forcer le tri des chapitres DANS la nouvelle instance (déjà fait par novelWithUpdatedChapter)
        updatedNovelState = updatedNovel;

        final newList = List<Novel>.from(currentNovels);
        newList[novelIndex] = updatedNovel;
        return _sortNovels(newList, ref.read(sortOptionProvider)); // Re-trier les romans
      }
      return currentNovels;
    });

    // Envoyer à Supabase
     if (updatedNovelState != null) {
        try {
          // Ne pas envoyer novel_id et created_at dans l'update du chapitre
          final updateData = updatedChapter.toJson()
            ..remove('novel_id')
            ..remove('created_at'); // Ne pas modifier la date de création originale

          await _supabase.from('chapters')
              .update(updateData)
              .eq('id', updatedChapter.id);
          // Mettre à jour 'updated_at' du roman
          await _supabase.from('novels')
              .update({'updated_at': updatedNovelState!.updatedAt.toIso8601String()})
              .eq('id', novelId);
          AppLogger.info("Chapitre ${updatedChapter.id} mis à jour.", tag: "NovelsProvider");
        } catch (e) {
           AppLogger.error("Erreur màj chapitre ${updatedChapter.id}", error: e, tag: "NovelsProvider");
           ref.invalidateSelf();
           throw Exception("Erreur Supabase màj chapitre: $e");
        }
     } else {
        AppLogger.error("Erreur updateChapter: Roman $novelId non trouvé.", tag: "NovelsProvider");
        ref.invalidateSelf();
        throw Exception("Roman non trouvé pour màj chapitre.");
     }
  }

  // Supprimer un chapitre
  Future<void> deleteChapter(String novelId, String chapterId) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // Mise à jour optimiste
    Novel? updatedNovelState;
    state = await AsyncValue.guard(() async {
      final currentNovels = state.value ?? [];
      final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
      if (novelIndex != -1) {
         final originalNovel = currentNovels[novelIndex];
         // Vérifie si le chapitre existe avant de tenter la suppression locale
         if (!originalNovel.chapters.any((c) => c.id == chapterId)) {
            AppLogger.warning("Chapitre $chapterId non trouvé dans ${novelId} pour suppression locale.", tag: "NovelsProvider");
            return currentNovels; // Retourne sans changement
         }
         final updatedNovel = originalNovel.novelWithRemovedChapter(chapterId);
         // ✅ Le tri n'est pas nécessaire ici car on supprime juste
         updatedNovelState = updatedNovel;

         final newList = List<Novel>.from(currentNovels);
         newList[novelIndex] = updatedNovel;
         return _sortNovels(newList, ref.read(sortOptionProvider)); // Re-trier les romans
      }
      return currentNovels;
    });

    // Envoyer à Supabase
    if (updatedNovelState != null) {
      try {
        await _supabase.from('chapters').delete().eq('id', chapterId);
        // Mettre à jour 'updated_at' du roman
        await _supabase.from('novels')
            .update({'updated_at': updatedNovelState!.updatedAt.toIso8601String()})
            .eq('id', novelId);
        AppLogger.info("Chapitre $chapterId supprimé du roman ${novelId}.", tag: "NovelsProvider");
      } catch (e) {
         AppLogger.error("Erreur suppression chapitre $chapterId", error: e, tag: "NovelsProvider");
         ref.invalidateSelf();
         throw Exception("Erreur Supabase suppression chapitre: $e");
      }
    } else {
      AppLogger.warning("Tentative suppression BDD chapitre $chapterId (non trouvé localement ou roman manquant).", tag: "NovelsProvider");
       try {
           await _supabase.from('chapters').delete().eq('id', chapterId);
           ref.invalidateSelf(); // Force un rechargement pour être sûr
       } catch (e) {
            AppLogger.error("Erreur suppression BDD chapitre $chapterId", error: e, tag: "NovelsProvider");
            ref.invalidateSelf();
            throw Exception("Erreur Supabase suppression chapitre: $e");
       }
    }
  }
  
  // ✅ NOUVELLE FONCTION: Réorganiser les chapitres
  Future<void> reorderChapters(String novelId, List<String> chapterIdsInNewOrder) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // 1. Récupérer l'état actuel du roman et les détails des chapitres
    final originalNovels = state.value;
    final originalNovel = originalNovels?.firstWhereOrNull((n) => n.id == novelId);
    if (originalNovel == null) throw Exception("Roman non trouvé pour réorganiser les chapitres.");

    final chaptersMap = {for (var c in originalNovel.chapters) c.id: c};
    
    Novel? updatedNovelState;

    // 2. Mise à jour optimiste de l'état local
    state = await AsyncValue.guard(() async {
      final currentNovels = state.value ?? [];
      final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
      
      if (novelIndex != -1) {
        // Le roman à cet index est l'originalNovel, mais on utilise le map local pour plus de clarté.
        
        // Crée une nouvelle liste de chapitres dans l'ordre spécifié
        final List<Chapter> reorderedChapters = chapterIdsInNewOrder
            .map((id) => chaptersMap[id])
            .whereType<Chapter>()
            .toList();

        // Crée un Novel mis à jour, en s'assurant que les métadonnées sont à jour
        final updatedNovel = originalNovel.copyWith(
          chapters: List.unmodifiable(reorderedChapters), // Nouvelle liste triée
          updatedAt: DateTime.now(),
        );

        updatedNovelState = updatedNovel; // Sauvegarde de l'état pour la BDD
        
        // Applique la mise à jour à la liste principale des romans
        final newList = List<Novel>.from(currentNovels);
        newList[novelIndex] = updatedNovel;
        return _sortNovels(newList, ref.read(sortOptionProvider));
      }
      return currentNovels;
    });

    // 3. Mise à jour de la base de données (mise à jour des created_at)
    if (updatedNovelState != null) {
      try {
        final List<Map<String, dynamic>> updates = [];
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Mettre à jour le created_at de chaque chapitre pour refléter le nouvel ordre
        for (int i = 0; i < chapterIdsInNewOrder.length; i++) {
          final chapterId = chapterIdsInNewOrder[i];
          final originalChapter = chaptersMap[chapterId]; 
          
          if (originalChapter == null) {
              AppLogger.warning("Chapitre ID $chapterId non trouvé pour la réorganisation. Ignoré.", tag: "NovelsProvider");
              continue;
          }

          updates.add({
            'id': chapterId,
            'novel_id': novelId, 
            // ✅ CORRECTION: Inclure les champs NOT NULL manquants (title et content)
            'title': originalChapter.title, 
            'content': originalChapter.content, 
            // La colonne "created_at" est mise à jour pour forcer le tri BDD
            'created_at': DateTime.fromMillisecondsSinceEpoch(now + (i * 1000)).toIso8601String(),
          });
        }
        
        // L'upsert mettra à jour les lignes existantes ou échouera si l'ID n'est pas trouvé
        await _supabase.from('chapters').upsert(updates);

        // Mettre à jour 'updated_at' du roman parent
        await _supabase.from('novels')
            .update({'updated_at': updatedNovelState!.updatedAt.toIso8601String()})
            .eq('id', novelId);
            
        AppLogger.info("Chapitres du roman $novelId réorganisés avec succès via created_at.", tag: "NovelsProvider");
      } catch (e) {
        AppLogger.error("Erreur lors de la réorganisation des chapitres Supabase.", error: e, tag: "NovelsProvider");
        ref.invalidateSelf(); // Reviens à l'état de la BDD
        throw Exception("Erreur Supabase lors de la réorganisation : $e");
      }
    } else {
        AppLogger.error("Erreur reorderChapters: Roman $novelId non trouvé.", tag: "NovelsProvider");
        ref.invalidateSelf();
        throw Exception("Roman non trouvé pour réorganiser les chapitres.");
    }
  }


  // Supprimer un roman entier
  Future<void> deleteNovel(String novelId) async {
    final currentUserId = _userId;
    if (currentUserId == null) throw Exception('Utilisateur non authentifié');

    // Mise à jour optimiste
    state = await AsyncValue.guard(() async {
       final currentNovels = state.value ?? [];
       // Retourne une nouvelle liste sans le roman supprimé
       return currentNovels.where((n) => n.id != novelId).toList();
    });

    // Envoyer à Supabase (la suppression cascade via FOREIGN KEY s'occupera des chapitres)
    try {
      await _supabase.from('novels').delete().eq('id', novelId);
      AppLogger.info("Roman $novelId supprimé.", tag: "NovelsProvider");
    } catch (e) {
      AppLogger.error("Erreur suppression roman $novelId", error: e, tag: "NovelsProvider");
      ref.invalidateSelf();
      throw Exception("Erreur Supabase suppression roman: $e");
    }
  }

  // Rafraîchir manuellement la liste
  Future<void> refresh() async {
    AppLogger.info("Rafraîchissement manuel demandé.", tag: "NovelsProvider");
    // Invalider le provider force la méthode build() à s'exécuter à nouveau
    ref.invalidateSelf();
  }
} // Fin NovelsNotifier


// --- Providers pour les amis (dépendent du controller) ---
// (Déplacés dans friends_controller.dart pour la clarté)