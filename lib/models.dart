// lib/models.dart 
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

// --- ON AJOUTE UN GÉNÉRATEUR D'UUID GLOBAL ---
const uuid = Uuid();

// Les classes VocabularyEntry et ChapterSummary restent inchangées
class VocabularyEntry {
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
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) {
    DateTime createdAt = DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now();

    return VocabularyEntry(
      word: json['word'] ?? 'Mot manquant',
      reading: json['reading'] ?? 'Lecture manquante',
      translation: json['translation'] ?? 'Traduction manquante',
      createdAt: createdAt,
    );
  }
}

class ChapterSummary {
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


class Novel {
  final String id;
  final String user_id; 
  String title;
  String level; 
  String genre; 
  String specifications; 
  final List<Chapter> chapters;
  final List<ChapterSummary> summaries;
  final DateTime createdAt;
  DateTime updatedAt;
  final String language;
  String? coverImagePath;
  String? roadMap;
  String? previousRoadMap;
  String? modelId;
  
  // --- MODIFICATION : Ajout du plan directeur (ton "sommaire") ---
  String? futureOutline;
  // --- FIN MODIFICATION ---

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
    this.futureOutline, // --- MODIFICATION : Ajout au constructeur ---
  }) : id = id ?? uuid.v4(),
       chapters = chapters ?? [],
       summaries = summaries ?? [],
       updatedAt = updatedAt ?? createdAt;

  // ⬇️⬇️ MÉTHODE copyWith AJOUTÉE ICI ⬇️⬇️
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
    String? coverImagePath,
    String? roadMap,
    String? previousRoadMap,
    String? modelId,
    String? futureOutline,
  }) {
    return Novel(
      id: id ?? this.id,
      user_id: user_id ?? this.user_id,
      title: title ?? this.title,
      level: level ?? this.level,
      genre: genre ?? this.genre,
      specifications: specifications ?? this.specifications,
      chapters: chapters ?? this.chapters,
      summaries: summaries ?? this.summaries,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      language: language ?? this.language,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      roadMap: roadMap ?? this.roadMap,
      previousRoadMap: previousRoadMap ?? this.previousRoadMap,
      modelId: modelId ?? this.modelId,
      futureOutline: futureOutline ?? this.futureOutline,
    );
  }
  // ⬆️⬆️ FIN DE L'AJOUT ⬆️⬆️

  void addChapter(Chapter chapter) {
    chapters.add(chapter);
    updatedAt = DateTime.now();
  }

  void addSummary(ChapterSummary summary) {
    summaries.removeWhere((s) => s.endChapterIndex == summary.endChapterIndex);
    summaries.add(summary);
    summaries.sort((a, b) => a.endChapterIndex.compareTo(b.endChapterIndex));
    updatedAt = DateTime.now();
  }

  bool removeChapter(int index) {
    if (index < 0 || index >= chapters.length) {
      debugPrint("Tentative de suppression d'un chapitre à un index invalide: $index");
      return false;
    }

    chapters.removeAt(index);
    updatedAt = DateTime.now();
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': user_id, 
      'title': title,
      'level': level,
      'genre': genre,
      'specifications': specifications,
      // 'chapters' est retiré, car il a sa propre table
      'summaries': summaries.map((summary) => summary.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'language': language,
      'cover_image_path': coverImagePath,
      'roadmap': roadMap,
      'model_id': modelId,
      'future_outline': futureOutline, // --- MODIFICATION : Ajout au JSON (snake_case pour la BDD) ---
    };
  }

  factory Novel.fromJson(Map<String, dynamic> json) {
    var chapterList = <Chapter>[];
    if (json['chapters'] != null && json['chapters'] is List) {
      chapterList = (json['chapters'] as List)
          .map((chapterJson) => Chapter.fromJson(chapterJson as Map<String, dynamic>))
          .toList();
    }

    var summaryList = <ChapterSummary>[];
    if (json['summaries'] != null && json['summaries'] is List) {
       summaryList = (json['summaries'] as List)
           .map((summaryJson) => ChapterSummary.fromJson(summaryJson as Map<String, dynamic>))
           .toList();
        summaryList.sort((a, b) => a.endChapterIndex.compareTo(b.endChapterIndex));
    }

    DateTime parseDateTime(dynamic dateString, DateTime fallback) {
       if (dateString is String) {
          return DateTime.tryParse(dateString) ?? fallback;
       }
       return fallback;
    }

    final now = DateTime.now();
    final createdAt = parseDateTime(json['created_at'], now);
    final updatedAt = parseDateTime(json['updated_at'], createdAt);
    
    final userId = json['user_id']?.toString();
    if (userId == null) {
      debugPrint("ALERTE: Roman ${json['id']} chargé sans user_id !");
    }

    return Novel(
      id: json['id']?.toString() ?? uuid.v4(),
      user_id: userId ?? '00000000-0000-0000-0000-000000000000', // Fallback
      title: json['title']?.toString() ?? 'Titre inconnu',
      level: json['level']?.toString() ?? 'N3',
      genre: json['genre']?.toString() ?? 'Fantasy',
      specifications: json['specifications']?.toString() ?? '',
      chapters: chapterList,
      summaries: summaryList,
      createdAt: createdAt,
      updatedAt: updatedAt,
      language: json['language']?.toString() ?? 'Japonais',
      coverImagePath: json['cover_image_path']?.toString(),
      roadMap: json['roadmap']?.toString(),
      modelId: json['model_id']?.toString(),
      futureOutline: json['future_outline']?.toString(), // --- MODIFICATION : Ajout depuis JSON ---
    );
  }
}

class Chapter {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  Chapter({
    String? id,
    required this.title,
    required this.content,
    required this.createdAt,
  }) : id = id ?? uuid.v4();

  // --- ⬇️ CORRECTION PRINCIPALE ICI ⬇️ ---
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(), // ✅ CORRIGÉ: 'createdAt' -> 'created_at'
    };
  }

  // --- ⬇️ CORRECTION PRINCIPALE ICI ⬇️ ---
  factory Chapter.fromJson(Map<String, dynamic> json) {
     DateTime parseDateTime(dynamic dateString, DateTime fallback) {
       if (dateString is String) {
          return DateTime.tryParse(dateString) ?? fallback;
       }
       return fallback;
     }
     // ✅ CORRIGÉ: 'createdAt' -> 'created_at'
     final createdAt = parseDateTime(json['created_at'], DateTime.now()); 

    return Chapter(
      id: json['id']?.toString() ?? uuid.v4(),
      title: json['title'] ?? 'Titre chapitre inconnu',
      content: json['content'] ?? '',
      createdAt: createdAt,
    );
  }
}