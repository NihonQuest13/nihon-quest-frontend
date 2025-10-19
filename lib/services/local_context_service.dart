// lib/services/local_context_service.dart (CORRECTION PING)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;

class BackendException implements Exception {
  final String message;
  final int? statusCode;
  BackendException(this.message, {this.statusCode});

  @override
  String toString() {
    if (statusCode != null) {
      return "Erreur du backend ($statusCode) : $message";
    }
    return "Erreur de communication avec le backend : $message";
  }
}

class LocalContextService {
  final http.Client _client;
  final String baseUrl;

  static String _getBaseUrl() {
    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      } else {
        return 'http://127.0.0.1:8000';
      }
    } else {
      // ✅ CORRECTION : URL de production correcte
      return 'https://nihon-quest-api.onrender.com';
    }
  }

  LocalContextService()
      : _client = http.Client(),
        baseUrl = _getBaseUrl();
        
  LocalContextService.withUrl(String url)
      : _client = http.Client(),
        baseUrl = url;

  void dispose() {
    _client.close();
  }

  Future<bool> pingBackend() async {
    try {
      debugPrint("SERVICE: Pinging backend at $baseUrl...");
      
      // ✅ CORRECTION : Utiliser /list_novels au lieu de /healthz
      // C'est un endpoint plus simple et plus fiable
      final response = await _client
          .get(Uri.parse('$baseUrl/list_novels'))
          .timeout(const Duration(seconds: 10)); // ✅ Timeout augmenté à 10s pour Render
      
      if (response.statusCode == 200) {
        debugPrint("SERVICE: Backend ping success.");
        return true;
      }
      debugPrint("SERVICE: Backend ping failed with status ${response.statusCode}.");
      return false;
    } on TimeoutException {
      debugPrint("SERVICE: Backend ping timed out.");
      throw BackendException("Le serveur n'a pas répondu à temps (timeout).");
    } catch (e) {
      debugPrint("Erreur de ping non gérée : $e");
      throw BackendException("Impossible de joindre le serveur. Est-il bien démarré sur $baseUrl ? Erreur: ${e.toString()}");
    }
  }

  Future<bool> isBackendRunning() async {
    try {
      return await pingBackend();
    } catch (e) {
      debugPrint("Le backend n'est pas accessible : $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> _postJson(String endpoint, Map<String, dynamic> data) async {
    try {
      final String body = jsonEncode(data);
      
      final response = await _client.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        if (decodedData is Map) {
          return decodedData.cast<String, dynamic>();
        }
        throw BackendException("La réponse du backend est invalide (format incorrect).");
      } else {
        String errorMessage = "Une erreur inconnue est survenue.";
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          if(errorBody['detail'] != null) {
            errorMessage = errorBody['detail'];
          }
        } catch (_) {
          errorMessage = utf8.decode(response.bodyBytes, allowMalformed: true);
        }
        throw BackendException(errorMessage, statusCode: response.statusCode);
      }
    } on TimeoutException {
      throw BackendException("La requête a expiré (timeout de 60s). Le backend est peut-être occupé.");
    } catch (e) {
      if (e is BackendException) rethrow;
      debugPrint("Erreur non gérée dans _postJson ($endpoint): $e");
      throw BackendException("Une erreur de communication inattendue est survenue : ${e.toString()}");
    }
  }

  Future<List<String>> listIndexedNovels() async {
    debugPrint("SERVICE: Récupération de la liste des romans indexés sur le backend...");
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/list_novels'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['indexed_novels'] is List) {
          final novelIds = List<String>.from(data['indexed_novels']);
          debugPrint("SERVICE: ${novelIds.length} roman(s) trouvé(s) sur le backend.");
          return novelIds;
        }
      }
      throw BackendException("Réponse invalide de /list_novels", statusCode: response.statusCode);
    } on TimeoutException {
      throw BackendException("La requête /list_novels a expiré (timeout de 10s).");
    } catch (e) {
      if (e is BackendException) rethrow;
      debugPrint("SERVICE ERROR (listIndexedNovels): $e");
      throw BackendException("Erreur de communication inattendue : ${e.toString()}");
    }
  }

  Future<void> addChapter({ required String novelId, required String chapterText, }) async {
    debugPrint("SERVICE: Ajout du chapitre (JSON) au contexte pour le roman $novelId...");
    await _postJson('/add_chapter', { 'novel_id': novelId, 'chapter_text': chapterText, });
    debugPrint("SERVICE: Chapitre ajouté avec succès.");
  }

  Future<List<String>> getContext({ required String novelId, required String query, int topK = 3, }) async {
    debugPrint("SERVICE: Récupération du contexte (JSON) pour le roman $novelId...");
    final data = await _postJson('/get_context', { 'novel_id': novelId, 'query': query, 'top_k': topK, });
    if (data['context'] is List) {
      debugPrint("SERVICE: Contexte reçu avec ${data['context'].length} éléments.");
      return List<String>.from(data['context']);
    }
    return [];
  }

  Future<bool> deleteNovelData(String novelId) async {
    debugPrint("SERVICE: Suppression des données du roman (JSON) $novelId sur le backend...");
    try {
      await _postJson('/delete_novel', {'novel_id': novelId});
      debugPrint("SERVICE: Données du roman supprimées avec succès.");
      return true;
    } catch (e) {
      debugPrint("SERVICE ERROR (deleteNovelData): $e");
      return false;
    }
  }

  Future<void> updateChapter({ required String novelId, required int chapterIndex, required String newContent, }) async {
    debugPrint("SERVICE: Mise à jour du chapitre (JSON) $chapterIndex pour le roman $novelId...");
    await _postJson('/update_chapter', { 'novel_id': novelId, 'chapter_id': chapterIndex, 'new_chapter_text': newContent, });
    debugPrint("SERVICE: Chapitre mis à jour avec succès.");
  }

  Future<void> deleteChapter({required String novelId, required int chapterIndex}) async {
    debugPrint("SERVICE: Suppression du chapitre (JSON) $chapterIndex pour le roman $novelId...");
    await _postJson('/delete_chapter', { 'novel_id': novelId, 'chapter_id': chapterIndex, });
    debugPrint("SERVICE: Chapitre supprimé avec succès.");
  }
}