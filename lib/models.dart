// lib/models.dart
import 'package:uuid/uuid.dart';
import 'package:japanese_story_app/utils/app_logger.dart'; // ✅ AJOUT: Importer AppLogger

const uuid = Uuid();

// ================== MODÈLE VOCABULAIRE ==================
class VocabularyEntry {
  // ... (code inchangé) ...
  final String word;
  final String reading;
  final String translation;
  final DateTime createdAt;

  VocabularyEntry({
    required this.word,
    required this.reading,
    required this.translation,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabularyEntry &&
          runtimeType == other.runtimeType &&
          word == other.word;

  @override
  int get hashCode => word.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'reading': reading,
      'translation': translation,
      'createdAt': createdAt.toIso8601String(), // Utiliser createdAt pour cohérence
    };
  }

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) {
    // Utiliser createdAt pour cohérence
    DateTime createdAt = DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now();

    return VocabularyEntry(
      word: json['word'] ?? 'Mot manquant',
      reading: json['reading'] ?? 'Lecture manquante',
      translation: json['translation'] ?? 'Traduction manquante',
      createdAt: createdAt,
    );
  }
}

// ================== MODÈLE RÉSUMÉ CHAPITRE ==================
class ChapterSummary {
 // ... (code inchangé) ...
  final int endChapterIndex;
  final String summaryText;
  final DateTime createdAt;

  ChapterSummary({
    required this.endChapterIndex,
    required this.summaryText,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'endChapterIndex': endChapterIndex,
      'summaryText': summaryText,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChapterSummary.fromJson(Map<String, dynamic> json) {
    final fallbackDate = DateTime.now();
    DateTime createdAt = fallbackDate;
    if (json['createdAt'] is String) {
      createdAt = DateTime.tryParse(json['createdAt']) ?? fallbackDate;
    } else if (json['createdAt'] is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(json['createdAt']);
    }

    return ChapterSummary(
      endChapterIndex: (json['endChapterIndex'] is int) ? json['endChapterIndex'] : -1,
      summaryText: json['summaryText'] ?? 'Résumé indisponible',
      createdAt: createdAt,
    );
  }
}

// ================== MODÈLE CHAPITRE ==================
class Chapter {
 // ... (code inchangé) ...
  final String id;
  final String title;
  final String content;
  final DateTime createdAt; // Doit correspondre à la colonne SQL

  Chapter({
    String? id,
    required this.title,
    required this.content,
    required this.createdAt,
  }) : id = id ?? uuid.v4();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(), // Correspond au nom de colonne SQL
    };
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
     DateTime parseDateTime(dynamic dateString, DateTime fallback) {
       if (dateString is String) {
          // Essayer de parser avec ou sans fuseau horaire
          return DateTime.tryParse(dateString)?.toLocal() ?? fallback;
       }
       return fallback;
     }
     // Utilise 'created_at' pour correspondre au JSON de Supabase et au nom de colonne SQL
     final createdAt = parseDateTime(json['created_at'], DateTime.now());

     // ✅ AJOUT LOG: Afficher l'ID et la date parsée
     AppLogger.info("Parsing Chapter ID: ${json['id']}, Raw created_at: ${json['created_at']}, Parsed DateTime: ${createdAt.toIso8601String()}", tag: "Chapter.fromJson");

    return Chapter(
      id: json['id']?.toString() ?? uuid.v4(),
      title: json['title'] ?? 'Titre chapitre inconnu',
      content: json['content'] ?? '',
      createdAt: createdAt, // Utilise la date parsée
    );
  }
}


// ================== MODÈLE ROMAN ==================
class Novel {
  // ... (propriétés inchangées) ...
  final String id;
  final String user_id; // UUID du propriétaire
  String title;
  String level;
  String genre;
  String specifications;
  final List<Chapter> chapters; // Rendre mutable temporairement pour tri facile ? Non, copyWith gère ça.
  final List<ChapterSummary> summaries;
  final DateTime createdAt;
  DateTime updatedAt;
  final String language;
  String? coverImagePath;
  String? roadMap;
  String? previousRoadMap; // Gardé au cas où, mais peut être optionnel
  String? modelId;
  String? futureOutline;
  bool isDynamicOutline;


  Novel({
    String? id,
    required this.user_id,
    required this.title,
    required this.level,
    required this.genre,
    required this.specifications,
    List<Chapter>? chapters,
    List<ChapterSummary>? summaries,
    required this.createdAt,
    DateTime? updatedAt,
    this.language = 'Japonais',
    this.coverImagePath,
    this.roadMap,
    this.previousRoadMap,
    this.modelId,
    this.futureOutline,
    this.isDynamicOutline = true,
  }) : id = id ?? uuid.v4(),
       // CORRECTION: Garantir l'immutabilité dès la construction
       chapters = List.unmodifiable(chapters ?? []), 
       summaries = List.unmodifiable(summaries ?? []),
       updatedAt = updatedAt ?? createdAt;

  // --- copyWith (inchangé) ---
  Novel copyWith({
    String? id,
    String? user_id,
    String? title,
    String? level,
    String? genre,
    String? specifications,
    List<Chapter>? chapters,
    List<ChapterSummary>? summaries,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? language,
    Object? coverImagePath = const _SentinelValue(),
    Object? roadMap = const _SentinelValue(),
    Object? previousRoadMap = const _SentinelValue(),
    Object? modelId = const _SentinelValue(),
    Object? futureOutline = const _SentinelValue(),
    bool? isDynamicOutline,
  }) {
    return Novel(
      id: id ?? this.id,
      user_id: user_id ?? this.user_id,
      title: title ?? this.title,
      level: level ?? this.level,
      genre: genre ?? this.genre,
      specifications: specifications ?? this.specifications,
      chapters: chapters ?? List.unmodifiable(this.chapters),
      summaries: summaries ?? List.unmodifiable(this.summaries),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      language: language ?? this.language,
      coverImagePath: coverImagePath is _SentinelValue ? this.coverImagePath : coverImagePath as String?,
      roadMap: roadMap is _SentinelValue ? this.roadMap : roadMap as String?,
      previousRoadMap: previousRoadMap is _SentinelValue ? this.previousRoadMap : previousRoadMap as String?,
      modelId: modelId is _SentinelValue ? this.modelId : modelId as String?,
      futureOutline: futureOutline is _SentinelValue ? this.futureOutline : futureOutline as String?,
      isDynamicOutline: isDynamicOutline ?? this.isDynamicOutline,
    );
  }


  // --- Fonctions utilitaires (inchangées) ---
   Novel novelWithAddedChapter(Chapter chapter) {
    // Retourne une NOUVELLE instance de Novel avec le chapitre ajouté et trié
    final newChapters = List<Chapter>.from(chapters)..add(chapter);
    newChapters.sort((a, b) {
      int dateCompare = a.createdAt.compareTo(b.createdAt);
      if (dateCompare != 0) return dateCompare;
      return a.id.compareTo(b.id); // Tri secondaire par ID si dates identiques
    });
    return copyWith(
      chapters: newChapters,
      updatedAt: DateTime.now(),
    );
  }

  Novel novelWithAddedSummary(ChapterSummary summary) {
     // ... (logique inchangée) ...
     final updatedSummaries = summaries.where((s) => s.endChapterIndex != summary.endChapterIndex).toList()
       ..add(summary)
       ..sort((a, b) => a.endChapterIndex.compareTo(b.endChapterIndex));
    return copyWith(
      summaries: updatedSummaries,
      updatedAt: DateTime.now(),
    );
  }

  Novel novelWithRemovedChapter(String chapterId) {
     // Retourne une NOUVELLE instance de Novel sans le chapitre
     final newChapters = chapters.where((c) => c.id != chapterId).toList();
     // Le tri n'est pas nécessaire car l'ordre relatif est préservé
     return copyWith(
       chapters: newChapters,
       updatedAt: DateTime.now(),
     );
  }

   Novel novelWithUpdatedChapter(Chapter updatedChapter) {
     // Retourne une NOUVELLE instance de Novel avec le chapitre mis à jour et la liste retriée
     final chapterIndex = chapters.indexWhere((c) => c.id == updatedChapter.id);
     if (chapterIndex == -1) return this;
     final newChapters = List<Chapter>.from(chapters);
     newChapters[chapterIndex] = updatedChapter;
     newChapters.sort((a, b) {
        int dateCompare = a.createdAt.compareTo(b.createdAt);
        if (dateCompare != 0) return dateCompare;
        return a.id.compareTo(b.id); // Tri secondaire par ID
     });
     return copyWith(
       chapters: newChapters,
       updatedAt: DateTime.now(),
     );
   }

  // --- Conversion JSON (inchangée pour toJson et toJsonForIsolate) ---
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': user_id,
      'title': title,
      'level': level,
      'genre': genre,
      'specifications': specifications,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'language': language,
      'cover_image_path': coverImagePath,
      'roadmap': roadMap,
      'model_id': modelId,
      'future_outline': futureOutline,
      'is_dynamic_outline': isDynamicOutline,
    };
  }

  Map<String, dynamic> toJsonForIsolate() {
    final data = toJson();
    data['chapters'] = chapters.map((c) => c.toJson()).toList();
    data['summaries'] = summaries.map((s) => s.toJson()).toList();
    return data;
  }

  factory Novel.fromJson(Map<String, dynamic> json) {
    var chapterList = <Chapter>[];
    if (json['chapters'] != null && json['chapters'] is List) {
      AppLogger.info("Parsing ${ (json['chapters'] as List).length} chapters for Novel ID: ${json['id']}", tag: "Novel.fromJson");
      chapterList = (json['chapters'] as List).map((chapterJson) {
        try {
          return Chapter.fromJson(chapterJson as Map<String, dynamic>);
        } catch (e) {
          // ❌ CORRECTION : Intégrer chapterJson au message
          AppLogger.error("Erreur parsing chapitre. Data: $chapterJson", error: e, tag: "Novel.fromJson");
          return null; // Ignore les romans qui ne peuvent pas être parsés
        }
      }).whereType<Chapter>().toList();

      // ✅ MODIFICATION: Tri explicite ici avec critère secondaire
      chapterList.sort((a, b) {
        int dateCompare = a.createdAt.compareTo(b.createdAt);
        if (dateCompare != 0) return dateCompare;
        // Si les dates sont identiques, trier par ID (qui est unique)
        return a.id.compareTo(b.id);
      });

       // ✅ AJOUT LOG: Afficher l'ordre après tri
      final sortedIds = chapterList.map((c) => c.id.substring(0, 4)).join(', ');
      AppLogger.info("Chapter IDs after sorting in fromJson: [$sortedIds]", tag: "Novel.fromJson");

    } else {
       AppLogger.info("No 'chapters' array found or invalid format for Novel ID: ${json['id']}", tag: "Novel.fromJson");
    }

    var summaryList = <ChapterSummary>[];
    // ... (parsing summaries inchangé) ...
    if (json['summaries'] != null && json['summaries'] is List) {
       summaryList = (json['summaries'] as List).map((summaryJson) {
         try {
             return ChapterSummary.fromJson(summaryJson as Map<String, dynamic>);
         } catch (e) {
             // ❌ CORRECTION : Intégrer summaryJson au message
             AppLogger.error("Erreur parsing summary. Data: $summaryJson", error: e, tag: "Novel.fromJson");
             return null;
         }
       }).whereType<ChapterSummary>().toList();
       summaryList.sort((a, b) => a.endChapterIndex.compareTo(b.endChapterIndex));
    }


    // ... (parsing dates et autres champs inchangé) ...
    DateTime parseDateTime(dynamic dateString, DateTime fallback) {
       if (dateString is String) {
          return DateTime.tryParse(dateString)?.toLocal() ?? fallback;
       }
       return fallback;
    }

    final now = DateTime.now();
    final createdAt = parseDateTime(json['created_at'], now);
    final updatedAt = parseDateTime(json['updated_at'], createdAt);

    final userId = json['user_id']?.toString();
    if (userId == null) {
      AppLogger.warning("Novel ${json['id']} chargé sans user_id !", tag: "Novel.fromJson");
    }

    return Novel(
      id: json['id']?.toString() ?? uuid.v4(),
      user_id: userId ?? '00000000-0000-0000-0000-000000000000',
      title: json['title']?.toString() ?? 'Titre inconnu',
      level: json['level']?.toString() ?? 'N3',
      genre: json['genre']?.toString() ?? 'Fantasy',
      specifications: json['specifications']?.toString() ?? '',
      chapters: chapterList, // Utilise la liste triée
      summaries: summaryList,
      createdAt: createdAt,
      updatedAt: updatedAt,
      language: json['language']?.toString() ?? 'Japonais',
      coverImagePath: json['cover_image_path']?.toString(),
      roadMap: json['roadmap']?.toString(),
      modelId: json['model_id']?.toString(),
      futureOutline: json['future_outline']?.toString(),
      isDynamicOutline: json['is_dynamic_outline'] ?? true,
    );
  }
}

// Classe interne pour copyWith (inchangée)
class _SentinelValue { const _SentinelValue(); }


// ================== MODÈLES POUR LES AMIS ==================
// ... (code inchangé) ...
enum FriendshipStatus { pending, accepted, blocked, unknown }

class FriendProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String email;

  FriendProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  String get fullName => '$firstName $lastName'.trim(); // Trim au cas où un nom est vide

  factory FriendProfile.fromJson(Map<String, dynamic> json) {
    return FriendProfile(
      id: json['id'] ?? '',
      firstName: json['first_name'] ?? '', // Retourne vide si null
      lastName: json['last_name'] ?? '',   // Retourne vide si null
      email: json['email'] ?? 'Email inconnu',
    );
  }
}

class Friendship {
  final FriendProfile friendProfile;
  final FriendshipStatus status;
  final String requesterId;

  Friendship({
    required this.friendProfile,
    required this.status,
    required this.requesterId,
  });

  bool get isPendingIncomingRequest => status == FriendshipStatus.pending && requesterId == friendProfile.id;
  bool get isPendingOutgoingRequest => status == FriendshipStatus.pending && requesterId != friendProfile.id;

  static FriendshipStatus statusFromString(String? statusStr) {
    switch (statusStr) {
      case 'pending': return FriendshipStatus.pending;
      case 'accepted': return FriendshipStatus.accepted;
      case 'blocked': return FriendshipStatus.blocked;
      default: return FriendshipStatus.unknown;
    }
  }
}

// ================== MODÈLE POUR COLLABORATEURS (Partage) ==================
class CollaboratorInfo {
  // ... (code inchangé) ...
  final String userId;
  final String displayName; // Nom complet ou email
  final String role;

  CollaboratorInfo({required this.userId, required this.displayName, required this.role});
}