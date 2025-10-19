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

  Novel({
    String? id,
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
  }) : id = id ?? uuid.v4(),
       chapters = chapters ?? [],
       summaries = summaries ?? [],
       updatedAt = updatedAt ?? createdAt;

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
      'title': title,
      'level': level,
      'genre': genre,
      'specifications': specifications,
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      'summaries': summaries.map((summary) => summary.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'language': language,
      'cover_image_path': coverImagePath,
      'roadmap': roadMap,
      'model_id': modelId,
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

    // ✅ CORRECTION : Conversion explicite en String avec toString() pour éviter l'erreur "field not initialized"
    return Novel(
      id: json['id']?.toString() ?? uuid.v4(),
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
     DateTime parseDateTime(dynamic dateString, DateTime fallback) {
       if (dateString is String) {
          return DateTime.tryParse(dateString) ?? fallback;
       }
       return fallback;
     }
     final createdAt = parseDateTime(json['createdAt'], DateTime.now());

    return Chapter(
      id: json['id']?.toString() ?? uuid.v4(),
      title: json['title'] ?? 'Titre chapitre inconnu',
      content: json['content'] ?? '',
      createdAt: createdAt,
    );
  }
}