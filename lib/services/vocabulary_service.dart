// lib/services/vocabulary_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart'; // Pour VocabularyEntry

// AMÉLIORATION : Cette fonction est exécutée en arrière-plan pour ne pas geler l'interface.
List<VocabularyEntry> _parseVocabulary(String jsonString) {
  final List<dynamic> decodedList = jsonDecode(jsonString);
  final List<VocabularyEntry> vocabularyList = decodedList
      .map((jsonItem) {
        if (jsonItem is Map<String, dynamic>) {
          try {
            return VocabularyEntry.fromJson(jsonItem);
          } catch (e) {
            debugPrint("Erreur désérialisation entrée vocabulaire: $e - Data: $jsonItem");
            return null;
          }
        }
        debugPrint("Élément non-map trouvé dans la liste vocabulaire: $jsonItem");
        return null;
      })
      .whereType<VocabularyEntry>()
      .toList();
  return vocabularyList;
}

class VocabularyService {
  final SharedPreferences _prefs;
  static const String _vocabKey = 'global_vocabulary_list_v1';

  VocabularyService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<List<VocabularyEntry>> loadVocabulary() async {
    final String? vocabJson = _prefs.getString(_vocabKey);
    if (vocabJson == null || vocabJson.isEmpty) {
      debugPrint("Aucune liste de vocabulaire globale trouvée (clé: $_vocabKey).");
      return [];
    }

    debugPrint("Chargement et décodage de la liste de vocabulaire en arrière-plan...");
    try {
      // AMÉLIORATION : Utilise compute pour décoder le JSON sans bloquer l'UI.
      final List<VocabularyEntry> vocabularyList = await compute(_parseVocabulary, vocabJson);

      // Le tri reste sur le thread principal car il est généralement très rapide.
      vocabularyList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      debugPrint("Chargé et trié ${vocabularyList.length} entrées de vocabulaire.");
      return vocabularyList;

    } catch (e) {
      debugPrint("ERREUR CRITIQUE lors du décodage de la liste vocabulaire (clé: $_vocabKey): $e");
      debugPrint("Contenu JSON brut: $vocabJson");
      return [];
    }
  }

  Future<bool> saveVocabulary(List<VocabularyEntry> vocabulary) async {
    try {
      vocabulary.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final List<Map<String, dynamic>> jsonList =
          vocabulary.map((entry) => entry.toJson()).toList();
      final String vocabJson = jsonEncode(jsonList);

      debugPrint("Sauvegarde de ${vocabulary.length} entrées vocabulaire (clé: $_vocabKey)...");
      final success = await _prefs.setString(_vocabKey, vocabJson);
      if (!success) {
         debugPrint("ÉCHEC de la sauvegarde SharedPreferences pour la clé $_vocabKey.");
      } else {
         debugPrint("Sauvegarde Vocabulaire Global réussie.");
      }
      return success;
    } catch (e) {
      debugPrint("ERREUR lors de l'encodage JSON ou sauvegarde vocabulaire: $e");
      return false;
    }
  }

  Future<bool> addEntry(VocabularyEntry entry) async {
    try {
      List<VocabularyEntry> currentVocabulary = await loadVocabulary();

      if (!currentVocabulary.contains(entry)) {
        currentVocabulary.add(entry);
        debugPrint("Vocabulaire Global: Ajout de '${entry.word}'. Nouvelle taille: ${currentVocabulary.length}");
        return await saveVocabulary(currentVocabulary);
      } else {
        debugPrint("Vocabulaire Global: Mot '${entry.word}' déjà présent. Non ajouté.");
        return true;
      }
    } catch (e) {
        debugPrint("Erreur lors de l'ajout d'une entrée au vocabulaire global: $e");
        return false;
    }
  }

  Future<bool> removeEntry(VocabularyEntry entryToRemove) async {
     try {
        List<VocabularyEntry> currentVocabulary = await loadVocabulary();
        final bool removed = currentVocabulary.remove(entryToRemove);

        if (removed) {
           debugPrint("Vocabulaire Global: Suppression de '${entryToRemove.word}'. Nouvelle taille: ${currentVocabulary.length}");
           return await saveVocabulary(currentVocabulary);
        } else {
           debugPrint("Vocabulaire Global: Tentative de suppression de '${entryToRemove.word}', mais non trouvé.");
           return true;
        }
     } catch (e) {
         debugPrint("Erreur lors de la suppression d'une entrée du vocabulaire global: $e");
         return false;
     }
  }
}
