// lib/services/sync_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'local_context_service.dart';
import '../providers.dart';

class SyncTask {
  final String action;
  final String novelId;
  final int? chapterIndex;
  final String? content;
  final String taskId;
  int retries;

  SyncTask({
    required this.action,
    required this.novelId,
    this.chapterIndex,
    this.content,
    this.retries = 0,
  }) : taskId = DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'action': action,
    'novelId': novelId,
    'chapterIndex': chapterIndex,
    'content': content,
    'taskId': taskId,
    'retries': retries,
  };

  factory SyncTask.fromJson(Map<String, dynamic> json) => SyncTask(
    action: json['action'],
    novelId: json['novelId'],
    chapterIndex: json['chapterIndex'],
    content: json['content'],
    retries: json['retries'] ?? 0,
  );
}

class SyncService {
  final Ref _ref;
  final SharedPreferences _prefs;
  static const _queueKey = 'sync_queue_key';
  bool _isProcessing = false;

  SyncService(this._ref, this._prefs);
  
  void _updateQueueStatus() {
    final queue = _getQueue();
    final statusNotifier = _ref.read(syncQueueStatusProvider.notifier);
    if (_isProcessing) {
      statusNotifier.state = SyncQueueStatus.processing;
    } else if (queue.isNotEmpty) {
      statusNotifier.state = SyncQueueStatus.hasPendingTasks;
    } else {
      statusNotifier.state = SyncQueueStatus.idle;
    }
  }

  Future<void> addTask(SyncTask task) async {
    final queue = _getQueue();
    queue.add(task);
    await _saveQueue(queue);
    debugPrint("Tâche de synchronisation ajoutée : ${task.action} pour le roman ${task.novelId}");
    _updateQueueStatus();
    processQueue();
  }

  Future<void> processQueue() async {
    if (_isProcessing) {
      debugPrint("Le traitement de la file est déjà en cours.");
      return;
    }

    final queue = _getQueue();
    if (queue.isEmpty) {
      debugPrint("File de synchronisation vide.");
      _updateQueueStatus();
      return;
    }
    
    _isProcessing = true;
    _updateQueueStatus();
    debugPrint("Début du traitement de la file (${queue.length} tâches)...");

    final task = queue.first;
    final localContextService = _ref.read(localContextServiceProvider);
    
    try {
      // On vérifie si le roman existe toujours dans notre état d'application
      final novelExists = _ref.read(novelsProvider).value?.any((novel) => novel.id == task.novelId) ?? false;
      if (!novelExists && task.action != 'delete_novel') {
        debugPrint("Tâche invalide détectée : le roman ${task.novelId} n'existe plus. Suppression de la tâche '${task.action}'.");
        queue.removeAt(0);
        await _saveQueue(queue);
        _isProcessing = false;
        _updateQueueStatus();
        processQueue();
        return;
      }
      
      if (_ref.read(serverStatusProvider) != ServerStatus.connected) {
        throw BackendException("Serveur déconnecté, la tâche ne peut pas être exécutée.");
      }

      switch (task.action) {
        case 'add':
          await localContextService.addChapter(novelId: task.novelId, chapterText: task.content!);
          break;
        case 'update':
          await localContextService.updateChapter(novelId: task.novelId, chapterIndex: task.chapterIndex!, newContent: task.content!);
          break;
        case 'delete_chapter':
          await localContextService.deleteChapter(novelId: task.novelId, chapterIndex: task.chapterIndex!);
          break;
        case 'delete_novel':
          await localContextService.deleteNovelData(task.novelId);
          break;
      }
      debugPrint("Tâche '${task.action}' pour le roman ${task.novelId} réussie.");

      queue.removeAt(0);
      await _saveQueue(queue);

    } catch (e) {
      debugPrint("ERREUR lors du traitement de la tâche '${task.action}' : $e.");
      
      task.retries++;
      const maxRetries = 2;
      final bool isBackendConnected = _ref.read(serverStatusProvider) == ServerStatus.connected;

      if (isBackendConnected && task.retries >= maxRetries) {
        debugPrint("La tâche a échoué ${task.retries} fois. Suppression de la tâche invalide.");
        queue.removeAt(0);
        await _saveQueue(queue);
      
      } else {
        debugPrint("Échec de la tâche. La tâche est conservée et remise en fin de file.");
        queue.removeAt(0);
        queue.add(task);
        await _saveQueue(queue);
      }

    } finally {
      _isProcessing = false;
      _updateQueueStatus();
      if (_getQueue().isNotEmpty) {
        Future.delayed(const Duration(seconds: 5), () => processQueue());
      }
    }
  }

  List<SyncTask> _getQueue() {
    final jsonString = _prefs.getString(_queueKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => SyncTask.fromJson(json)).toList();
    } catch (e) {
      debugPrint("Erreur de décodage de la file de synchronisation : $e. La file va être réinitialisée.");
      _prefs.remove(_queueKey);
      return [];
    }
  }

  Future<void> _saveQueue(List<SyncTask> queue) async {
    final List<Map<String, dynamic>> jsonList = queue.map((task) => task.toJson()).toList();
    await _prefs.setString(_queueKey, jsonEncode(jsonList));
  }
}

// Exception pour le service de synchronisation
class BackendException implements Exception {
  final String message;
  BackendException(this.message);
}