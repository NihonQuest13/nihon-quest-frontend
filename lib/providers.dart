// lib/providers.dart (AJOUT DU WRITER_MODE_PROVIDER)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'services/local_context_service.dart';
import 'services/roadmap_service.dart';
import 'services/sync_service.dart';
import 'services/vocabulary_service.dart';

// --- NOUVEAU PROVIDER ---
/// Gère l'état du mode de lecture (Lecteur vs. Écrivain)
final writerModeProvider = StateProvider<bool>((ref) => false);
// --- FIN DU NOUVEAU PROVIDER ---

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

final authStateProvider = StreamProvider<AuthState>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.auth.onAuthStateChange;
});

final novelsProvider = AsyncNotifierProvider<NovelsNotifier, List<Novel>>(NovelsNotifier.new);

class NovelsNotifier extends AsyncNotifier<List<Novel>> {

  @override
  Future<List<Novel>> build() async {
    ref.watch(authStateProvider);
    final sortOption = ref.watch(sortOptionProvider);

    final supabase = ref.read(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      debugPrint("[NovelsProvider] Aucun utilisateur, retour d'une liste vide.");
      return [];
    }

    debugPrint("[NovelsProvider] Récupération depuis Supabase (User: $userId, Tri: $sortOption)...");
    
    final novelsData = await supabase
        .from('novels')
        .select('*, chapters(*)')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .order('created_at', referencedTable: 'chapters', ascending: true); 
    
    final novels = novelsData.map((novelRow) {
      return Novel.fromJson(novelRow);
    }).toList();
    
    return _sortNovels(novels, sortOption);
  }

  List<Novel> _sortNovels(List<Novel> novels, SortOption sortOption) {
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
      await supabase.from('novels').insert(novelData);
      
      if (novel.chapters.isNotEmpty) {
        final chaptersData = novel.chapters.map((chapter) {
          final chapterJson = chapter.toJson();
          chapterJson['novel_id'] = novel.id;
          return chapterJson;
        }).toList();
        await supabase.from('chapters').insert(chaptersData);
      }
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de l'ajout, rechargement...");
      ref.invalidateSelf();
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
      await supabase
        .from('novels')
        .update(novelData)
        .eq('id', novel.id);
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la mise à jour du roman, rechargement...");
      ref.invalidateSelf();
      rethrow;
    }
  }
  
  Future<void> addChapter(String novelId, Chapter newChapter) async {
    final supabase = ref.read(supabaseProvider);
    final currentNovels = state.value ?? [];
    final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
    if (novelIndex == -1) return;

    final novelToUpdate = currentNovels[novelIndex];
    novelToUpdate.addChapter(newChapter);
    novelToUpdate.updatedAt = DateTime.now();

    state = AsyncValue.data([...currentNovels]);

    try {
        final chapterData = newChapter.toJson();
        chapterData['novel_id'] = novelId;

        await supabase.from('chapters').insert(chapterData);
        await supabase
            .from('novels')
            .update({'updated_at': novelToUpdate.updatedAt.toIso8601String()})
            .eq('id', novelId);
    } catch (e) {
        debugPrint("[NovelsProvider] Erreur lors de l'ajout du chapitre, rechargement...");
        ref.invalidateSelf();
        rethrow;
    }
  }

  Future<void> updateChapter(String novelId, Chapter updatedChapter) async {
    final supabase = ref.read(supabaseProvider);
    final currentNovels = state.value ?? [];

    final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
    if (novelIndex == -1) return;
    final novel = currentNovels[novelIndex];

    final chapterIndex = novel.chapters.indexWhere((c) => c.id == updatedChapter.id);
    if (chapterIndex == -1) return;

    novel.chapters[chapterIndex] = updatedChapter;
    novel.updatedAt = DateTime.now();

    state = AsyncValue.data([...currentNovels]);

    try {
      await supabase
        .from('chapters')
        .update(updatedChapter.toJson())
        .eq('id', updatedChapter.id);
      
      await supabase
        .from('novels')
        .update({'updated_at': novel.updatedAt.toIso8601String()})
        .eq('id', novelId);
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la mise à jour du chapitre, rechargement...");
      ref.invalidateSelf();
      rethrow;
    }
  }

  Future<void> deleteChapter(String novelId, String chapterId) async {
    final supabase = ref.read(supabaseProvider);
    final currentNovels = state.value ?? [];

    final novelIndex = currentNovels.indexWhere((n) => n.id == novelId);
    if (novelIndex == -1) return;
    final novel = currentNovels[novelIndex];

    novel.chapters.removeWhere((c) => c.id == chapterId);
    novel.updatedAt = DateTime.now();
    
    state = AsyncValue.data([...currentNovels]);

    try {
      await supabase
        .from('chapters')
        .delete()
        .eq('id', chapterId);
      
      await supabase
        .from('novels')
        .update({'updated_at': novel.updatedAt.toIso8601String()})
        .eq('id', novelId);
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la suppression du chapitre, rechargement...");
      ref.invalidateSelf();
      rethrow;
    }
  }

  Future<void> deleteNovel(String novelId) async {
    final supabase = ref.read(supabaseProvider);
    
    final currentNovels = state.value ?? [];
    state = AsyncValue.data(currentNovels.where((n) => n.id != novelId).toList());
    
    try {
      await supabase.from('novels').delete().eq('id', novelId);
    } catch (e) {
      debugPrint("[NovelsProvider] Erreur lors de la suppression, rechargement...");
      ref.invalidateSelf();
      rethrow;
    }
  }
  
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final vocabularyServiceProvider = Provider<VocabularyService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VocabularyService(prefs: prefs);
});

