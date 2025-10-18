// lib/providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';
import 'models.dart';
import 'services/local_context_service.dart';
import 'services/roadmap_service.dart';
import 'services/sync_service.dart';

// --- Providers existants qui ne changent pas (ou peu) ---
enum ServerStatus { connecting, connected, failed }
final serverStatusProvider = StateProvider<ServerStatus>((ref) => ServerStatus.connecting);

enum SyncQueueStatus { idle, processing, hasPendingTasks }
final syncQueueStatusProvider = StateProvider<SyncQueueStatus>((ref) => SyncQueueStatus.idle);

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(); // Sur-chargé dans main.dart
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

// --- NOUVEAU PROVIDER POUR LE CLIENT SUPABASE ---
final supabaseProvider = Provider((ref) => Supabase.instance.client);

// --- LE NOVELSPROVIDER EST COMPLÈTEMENT RÉÉCRIT POUR SUPABASE ---
final novelsProvider = AsyncNotifierProvider<NovelsNotifier, List<Novel>>(NovelsNotifier.new);

class NovelsNotifier extends AsyncNotifier<List<Novel>> {
  @override
  Future<List<Novel>> build() async {
    final supabase = ref.watch(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      return [];
    }

    final data = await supabase
        .from('novels')
        .select()
        .eq('user_id', userId);
        
    final novels = data.map((row) => Novel.fromJson(row)).toList();
    
    return _sortNovels(novels);
  }

  List<Novel> _sortNovels(List<Novel> novels) {
    final sortOption = ref.read(sortOptionProvider);
    switch (sortOption) {
      case SortOption.updatedAt:
        novels.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
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
    }
    return novels;
  }
  
  // Convertit notre objet Novel en un Map que Supabase peut comprendre
  Map<String, dynamic> _novelToSupabaseJson(Novel novel, String userId) {
    // On utilise la méthode toJson() du modèle Novel, qui est maintenant correcte
    final data = novel.toJson();
    // On s'assure que le user_id est bien présent
    data['user_id'] = userId;
    return data;
  }


  Future<void> addNovel(Novel novel) async {
    final supabase = ref.read(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw 'Utilisateur non authentifié';

    // La méthode toJson() s'occupe maintenant de formater les données correctement
    final novelData = _novelToSupabaseJson(novel, userId);

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await supabase.from('novels').insert(novelData);
      return build();
    });
  }

  Future<void> updateNovel(Novel novel) async {
    final supabase = ref.read(supabaseProvider);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw 'Utilisateur non authentifié';

    final novelData = _novelToSupabaseJson(novel, userId);

    state = await AsyncValue.guard(() async {
      await supabase
        .from('novels')
        .update(novelData)
        .eq('id', novel.id);
      return build();
    });
  }
  
  Future<void> addChapter(String novelId, Chapter newChapter) async {
      final currentNovels = state.valueOrNull ?? [];
      final novelToUpdate = currentNovels.firstWhere((n) => n.id == novelId, orElse: () => throw 'Roman non trouvé');
      
      novelToUpdate.addChapter(newChapter);
      await updateNovel(novelToUpdate);
  }


  Future<void> deleteNovel(String novelId) async {
    final supabase = ref.read(supabaseProvider);
    state = await AsyncValue.guard(() async {
      await supabase.from('novels').delete().eq('id', novelId);
      return build();
    });
  }
  
  Future<void> refresh() async {
     state = const AsyncValue.loading();
     state = await AsyncValue.guard(() => build());
  }
}