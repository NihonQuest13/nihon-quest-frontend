// lib/utils/error_handler.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ai_service.dart';
import '../services/local_context_service.dart';

/// Gestionnaire centralisé d'erreurs pour l'application
/// Fournit des messages utilisateur appropriés selon le type d'erreur
class ErrorHandler {
  /// Affiche un message d'erreur à l'utilisateur
  static void showError(BuildContext context, Object error, {StackTrace? stackTrace}) {
    final message = getErrorMessage(error);
    
    debugPrint("❌ ERREUR: $error");
    if (stackTrace != null) {
      debugPrint("Stack trace: $stackTrace");
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  /// Transforme une exception en message utilisateur compréhensible
  static String getErrorMessage(Object error) {
    // Erreurs Supabase
    if (error is AuthException) {
      return _handleAuthException(error);
    }
    
    if (error is PostgrestException) {
      return _handlePostgrestException(error);
    }

    // Erreurs backend IA
    if (error is ApiServerException) {
      return "Le service d'écriture est temporairement indisponible. Réessayez dans quelques instants.";
    }

    if (error is ApiConnectionException) {
      return "Impossible de contacter le serveur. Vérifiez votre connexion internet.";
    }

    if (error is BackendException) {
      return "Erreur de communication avec le serveur: ${error.message}";
    }

    // Erreurs réseau
    if (error.toString().contains('SocketException') || 
        error.toString().contains('TimeoutException')) {
      return "Problème de connexion réseau. Vérifiez votre connexion internet.";
    }

    // Erreur générique
    return "Une erreur inattendue s'est produite. Veuillez réessayer.";
  }

  static String _handleAuthException(AuthException error) {
    switch (error.statusCode) {
      case '400':
        return "Identifiants invalides. Vérifiez votre email et mot de passe.";
      case '422':
        return "Email déjà utilisé ou format invalide.";
      case '429':
        return "Trop de tentatives. Réessayez dans quelques minutes.";
      default:
        return error.message;
    }
  }

  static String _handlePostgrestException(PostgrestException error) {
    if (error.code == '23505') {
      return "Cette donnée existe déjà.";
    }
    if (error.code == '42501') {
      return "Vous n'avez pas les permissions nécessaires.";
    }
    return "Erreur de base de données: ${error.message}";
  }

  /// Wrapper pour exécuter une action avec gestion d'erreur
  static Future<T?> tryAsync<T>({
    required Future<T> Function() action,
    required BuildContext context,
    String? successMessage,
    bool showLoading = false,
  }) async {
    if (showLoading && context.mounted) {
      // Afficher un indicateur de chargement si demandé
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      final result = await action();
      
      if (showLoading && context.mounted) {
        Navigator.of(context).pop(); // Fermer le loading
      }

      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return result;
    } catch (e, stackTrace) {
      if (showLoading && context.mounted) {
        Navigator.of(context).pop(); // Fermer le loading
      }
      
      showError(context, e, stackTrace: stackTrace);
      return null;
    }
  }
}

// 📝 EXEMPLE D'UTILISATION :
//
// // Dans un widget :
// await ErrorHandler.tryAsync(
//   context: context,
//   showLoading: true,
//   successMessage: 'Roman créé avec succès !',
//   action: () async {
//     await ref.read(novelsProvider.notifier).addNovel(novel);
//   },
// );
//
// // Ou pour juste afficher une erreur :
// try {
//   await someAction();
// } catch (e) {
//   ErrorHandler.showError(context, e);
// }