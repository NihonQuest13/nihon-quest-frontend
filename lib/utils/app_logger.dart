// lib/utils/app_logger.dart
import 'package:flutter/foundation.dart';

/// Logger centralisé qui désactive automatiquement les logs en production
class AppLogger {
  static const String _prefix = '🔵';
  static const String _errorPrefix = '🔴';
  static const String _warningPrefix = '⚠️';
  static const String _successPrefix = '✅';

  /// Log d'information (seulement en debug)
  static void info(String message, {String? tag}) {
    if (kDebugMode) {
      final tagString = tag != null ? '[$tag] ' : '';
      debugPrint('$_prefix $tagString$message');
    }
  }

  /// Log d'erreur (visible en debug et release pour le monitoring)
  static void error(String message, {Object? error, StackTrace? stackTrace, String? tag}) {
    final tagString = tag != null ? '[$tag] ' : '';
    debugPrint('$_errorPrefix $tagString$message');
    
    if (error != null) {
      debugPrint('Error object: $error');
    }
    
    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace:\n$stackTrace');
    }
    
    // TODO: Envoyer à un service de monitoring en production (Sentry, Firebase Crashlytics, etc.)
    // if (kReleaseMode) {
    //   FirebaseCrashlytics.instance.recordError(error, stackTrace);
    // }
  }

  /// Log d'avertissement
  static void warning(String message, {String? tag}) {
    if (kDebugMode) {
      final tagString = tag != null ? '[$tag] ' : '';
      debugPrint('$_warningPrefix $tagString$message');
    }
  }

  /// Log de succès
  static void success(String message, {String? tag}) {
    if (kDebugMode) {
      final tagString = tag != null ? '[$tag] ' : '';
      debugPrint('$_successPrefix $tagString$message');
    }
  }

  /// Log de performance (pour mesurer les temps d'exécution)
  static Future<T> measure<T>({
    required String operation,
    required Future<T> Function() action,
  }) async {
    if (!kDebugMode) {
      return await action();
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      info('⏱️  $operation completed in ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      stopwatch.stop();
      error('⏱️  $operation failed after ${stopwatch.elapsedMilliseconds}ms', error: e);
      rethrow;
    }
  }
}

// 📝 EXEMPLE DE MIGRATION :
//
// ❌ AVANT :
// debugPrint("SERVICE: Ajout du chapitre au contexte...");
//
// ✅ APRÈS :
// AppLogger.info("Ajout du chapitre au contexte...", tag: 'LocalContextService');
//
// // Pour mesurer les performances :
// final novels = await AppLogger.measure(
//   operation: 'Chargement des romans',
//   action: () => supabase.from('novels').select(),
// );