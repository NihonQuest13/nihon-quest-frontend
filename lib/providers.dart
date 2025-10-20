// lib/providers.dart (CORRIGÉ - Requête unique)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'services/local_context_service.dart';
import 'services/roadmap_service.dart';
import 'services/sync_service.dart';
import 'services/vocabulary_service.dart';

// --- Providers inchangés ---
enum ServerStatus { connecting, connected, failed }
final serverStatusProvider = StateProvider<ServerStatus>((ref) => ServerStatus.connecting);

enum SyncQueueStatus { idle, processing, hasPendingTasks }
final syncQueueStatusProvider = StateProvider<SyncQueueStatus>((ref) => SyncQueueStatus.idle);

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SyncService(ref, prefs);
});

final localContextServiceProvider = Provider<LocalContextService>((ref) {
  final service = LocalContextService();
  ref.onDispose(() => service.dispose());
  return service;
});

// --- LOGIQUE DU THÈME ---
final themeService = ThemeService(ThemeMode.dark);

class ThemeService extends ValueNotifier<ThemeMode> {
  ThemeService(super.value);
  static const _themePrefKey = 'theme_mode_pref';

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themePrefKey) ?? ThemeMode.dark.index;
    value = ThemeMode.values[themeIndex];
  }

  void updateTheme(ThemeMode newThemeMode) {
    if (value == newThemeMode) return;
    value = newThemeMode;
    _saveTheme(newThemeMode);
  }

  Future<void> _saveTheme(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themePrefKey, themeMode.index);
  }
}

final themeServiceProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

final roadmapServiceProvider = Provider<RoadmapService>((ref) {
  return RoadmapService(ref);
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  void _loadTheme() {
    state = themeService.value;
  }

  void updateTheme(ThemeMode newThemeMode) {
    if (state != newThemeMode) {
      state = newThemeMode;
      themeService.updateTheme(newThemeMode);
    }
  }
}

enum SortOption { updatedAt, createdAt, title, genre }
final sortOptionProvider = StateProvider<SortOption>((ref) => SortOption.updatedAt);

final supabaseProvider = Provider((ref) => Supabase.instance.client);

final novelsProvider = AsyncNotifierProvider<NovelsNotifier, List<Novel>>(NovelsNotifier.new);

class NovelsNotifier extends AsyncNotifier<List<Novel>> {
  DateTime? _lastFetch;
  static const _cacheDuration = Duration(minutes: 5);
  String? _cachedUserId; // <-- ✅ AJOUT : Mémorise l'ID de l'utilisateur du cache

  @override
  Future<List<Novel>> build() async {
    final supabase = ref.watch(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;

    final now = DateTime.now();
    
    // --- ✅ MODIFICATION : Vérifie si le user ID du cache correspond au user ID actuel ---
    if (_lastFetch != null &&
        now.difference(_lastFetch!) < _cacheDuration &&
        state.hasValue &&
        _cachedUserId == userId) // <-- LA VÉRIFICATION CRITIQUE
    {
      debugPrint("[NovelsProvider] Utilisation du cache (user: $userId, ${state.value!.length} romans)");
      return state.value!;
    }
    // --- FIN MODIFICATION ---

    debugPrint("[NovelsProvider] Cache invalide (user: $userId). Récupération depuis Supabase...");

    if (userId == null) {
      _lastFetch = now;
      _cachedUserId = null; // <-- ✅ Vide l'ID du cache
      return [];
    }

    final novelsData = await supabase
        .from('novels')
        .select('*, chapters(*)')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .order('created_at', referencedTable: 'chapters', ascending: true);
    
    final novels = novelsData.map((novelRow) {
      return Novel.fromJson(novelRow);
    }).toList();
    
    _lastFetch = now;
    _cachedUserId = userId; // <-- ✅ Stocke l'ID de l'utilisateur avec le cache
    return _sortNovels(novels);
  }

  List<Novel> _sortNovels(List<Novel> novels) {
    final sortOption = ref.read(sortOptionProvider);
    
    if (sortOption == SortOption.updatedAt) {
      return novels; 
    }
    
    switch (sortOption) {
      case SortOption.createdAt:
        novels.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.title:
        novels.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortOption.genre:
        novels.sort((a, b) {
          final genreComparison = a.genre.toLowerCase().compareTo(b.genre.toLowerCase());
          if (genreComparison != 0) return genreComparison;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case SortOption.updatedAt:
        break; 
    }
    return novels;
  }
  
  Map<String, dynamic> _novelToSupabaseJson(Novel novel, String userId) {
    final data = novel.toJson();
    data['user_id'] = userId;
    data.remove('chapters');
    return data;
  }

  Future<void> addNovel(Novel novel) async {
    final supabase = ref.read(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw 'Utilisateur non authentifié';

    final novelData = _novelToSupabaseJson(novel, userId);

    final currentNovels = state.value ?? [];
    state = AsyncValue.data([novel, ...currentNovels]);

    try {
      // 1. Insérer le roman
      await supabase.from('novels').insert(novelData);
      
      // 2. Insérer les chapitres
      if (novel.chapters.isNotEmpty) {
        final chaptersData = novel.chapters.map((chapter) {
          final chapterJson = chapter.toJson();
          chapterJson['novel_id'] = novel.id;
          return chapterJson;
        }).toList();
        
        await supabase.from('chapters').insert(chaptersData);
      }
      
      _lastFetch = DateTime.now(); 
      _cachedUserId = userId; // <-- ✅ Met à jour le user du cache
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de l'ajout, rechargement...");
      state = await AsyncValue.guard(() => build());
      rethrow;
    }
  }

  Future<void> updateNovel(Novel novel) async {
    final supabase = ref.read(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw 'Utilisateur non authentifié';

    final novelData = _novelToSupabaseJson(novel, userId);

    final currentNovels = state.value ?? [];
    final updatedList = currentNovels.map((n) => n.id == novel.id ? novel : n).toList();
    state = AsyncValue.data(updatedList);

    try {
      // 1. Mettre à jour le roman
      await supabase
        .from('novels')
        .update(novelData)
        .eq('id', novel.id);
      
      // 2. Mettre à jour les chapitres (en supprimant et recréant)
      await supabase.from('chapters').delete().eq('novel_id', novel.id);
      
      if (novel.chapters.isNotEmpty) {
        final chaptersData = novel.chapters.map((chapter) {
          final chapterJson = chapter.toJson();
          chapterJson['novel_id'] = novel.id;
          return chapterJson;
        }).toList();
        
        await supabase.from('chapters').insert(chaptersData);
      }
      
      _lastFetch = DateTime.now();
      _cachedUserId = userId; // <-- ✅ Met à jour le user du cache
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la mise à jour, rechargement...");
      state = await AsyncValue.guard(() => build());
      rethrow;
    }
  }
  
  Future<void> addChapter(String novelId, Chapter newChapter) async {
    final currentNovels = state.value ?? [];
    final novelToUpdate = currentNovels.firstWhere(
      (n) => n.id == novelId, 
      orElse: () => throw 'Roman non trouvé'
    );
    
    novelToUpdate.addChapter(newChapter);
    await updateNovel(novelToUpdate);
  }

  Future<void> deleteNovel(String novelId) async {
    final supabase = ref.read(supabaseProvider);
    
    final currentNovels = state.value ?? [];
    state = AsyncValue.data(currentNovels.where((n) => n.id != novelId).toList());
    
    try {
      await supabase.from('novels').delete().eq('id', novelId);
      _lastFetch = DateTime.now();
      _cachedUserId = supabase.auth.currentUser?.id; // <-- ✅ Met à jour le user du cache
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la suppression, rechargement...");
      state = await AsyncValue.guard(() => build());
      rethrow;
    }
  }
  
  Future<void> refresh() async {
    _lastFetch = null; 
    _cachedUserId = null; // <-- ✅ Vide aussi le user du cache
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

final vocabularyServiceProvider = Provider<VocabularyService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VocabularyService(prefs: prefs);
});