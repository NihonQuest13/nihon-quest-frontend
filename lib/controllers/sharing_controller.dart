// lib/controllers/sharing_controller.dart
import 'dart:async'; // ✅ AJOUT: Importer dart:async pour Future.microtask
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart'; // Pour authStateProvider, etc.
import '../models.dart';
// import 'friends_controller.dart'; // Import inutilisé

// Provider pour ce controller
final sharingControllerProvider = Provider((ref) => SharingController(ref));

// Provider pour la liste des collaborateurs d'un roman spécifique
// AutoDispose pour recharger quand on quitte/revient, et family pour passer l'ID du roman
final novelCollaboratorsProvider = FutureProvider.autoDispose.family<List<CollaboratorInfo>, String>((ref, novelId) {
   // Dépend de l'état d'authentification
   ref.watch(authStateProvider);
   final controller = ref.watch(sharingControllerProvider);
   return controller.getCollaborators(novelId);
});


class SharingController {
  final Ref _ref;
  final _supabase = Supabase.instance.client;

  SharingController(this._ref);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Récupère la liste formatée des collaborateurs pour un roman
  Future<List<CollaboratorInfo>> getCollaborators(String novelId) async {
    if (_currentUserId == null) return []; // Non connecté
    debugPrint("[SharingController] Récupération des collaborateurs pour novel: $novelId");

    try {
      // 1. Récupérer les IDs et rôles depuis novel_collaborators
      final collaboratorsData = await _supabase
          .from('novel_collaborators')
          .select('collaborator_id, role')
          .eq('novel_id', novelId);

      if (collaboratorsData.isEmpty) {
        debugPrint("[SharingController] Aucun collaborateur trouvé pour $novelId.");
        return [];
      }

      // 2. Extraire les IDs des collaborateurs
      final collaboratorIds = collaboratorsData
          .map((c) => c['collaborator_id'] as String?) // Peut être null si problème BDD
          .whereType<String>() // Filtre les nulls
          .toList();

       if (collaboratorIds.isEmpty) {
         debugPrint("[SharingController] Erreur: Données de collaboration trouvées mais IDs invalides.");
         return [];
       }

      // 3. Récupérer les profils correspondants
      final profilesData = await _supabase
          .from('profiles')
          .select('id, email, first_name, last_name') // Champs nécessaires
          .inFilter('id', collaboratorIds); // Utilise inFilter

      // Map pour accès rapide par ID
      final profileMap = {
          for (var profile in profilesData)
             profile['id']: FriendProfile.fromJson(profile) // Utilise le factory FriendProfile
      };

      // 4. Combiner les informations
      final List<CollaboratorInfo> collaboratorsInfo = [];
      for (var collab in collaboratorsData) {
        final collabId = collab['collaborator_id'];
        final profile = profileMap[collabId];
        if (profile != null) {
          collaboratorsInfo.add(CollaboratorInfo(
            userId: collabId,
            displayName: profile.fullName.isNotEmpty ? profile.fullName : profile.email, // Nom complet ou email
            role: collab['role'] ?? 'inconnu',
          ));
        } else {
           debugPrint("[SharingController] Profil manquant pour collaborateur ID: $collabId");
           collaboratorsInfo.add(CollaboratorInfo(
             userId: collabId,
             displayName: "Utilisateur inconnu ($collabId)", // Afficher l'ID
             role: collab['role'] ?? 'inconnu',
           ));
        }
      }

      // 5. Trier par nom/email
      collaboratorsInfo.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      debugPrint("[SharingController] ${collaboratorsInfo.length} collaborateurs formatés pour $novelId.");
      return collaboratorsInfo;

    } catch (e, stacktrace) {
      debugPrint("[SharingController] Erreur getCollaborators pour $novelId: $e\n$stacktrace");
      throw Exception("Impossible de récupérer les collaborateurs.");
    }
  }

  /// Partage un roman en lecture seule avec un ami (via son ID)
  Future<void> shareWithFriend(String novelId, String friendUserId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) throw Exception("Utilisateur non connecté.");
    if (friendUserId == currentUserId) throw Exception("Vous ne pouvez pas partager un roman avec vous-même.");

    debugPrint("[SharingController] Tentative de partage du novel $novelId avec l'ami $friendUserId.");

    try {
      // Insère ou met à jour (si déjà partagé, ne fait rien grâce à onConflict)
      await _supabase.from('novel_collaborators').upsert({
        'novel_id': novelId,
        'collaborator_id': friendUserId,
        'role': 'reader', // Définit explicitement le rôle
      }, onConflict: 'novel_id, collaborator_id'); // La clé primaire composite

      debugPrint("[SharingController] Roman $novelId partagé avec succès avec $friendUserId.");

      // ✅ CORRECTION: Utiliser Future.microtask pour retarder l'invalidation
      // Cela exécute l'invalidation juste après la fin de la frame actuelle,
      // laissant le temps à l'opération en cours de se terminer proprement.
      Future.microtask(() {
        _ref.invalidate(novelCollaboratorsProvider(novelId));
        debugPrint("[SharingController] Invalidation de novelCollaboratorsProvider($novelId) programmée.");
      });


    } on PostgrestException catch (e) {
       debugPrint("[SharingController] Erreur Postgrest shareWithFriend: ${e.message} (code: ${e.code})");
       // ✅ CORRECTION: Relancer l'erreur pour que l'UI puisse l'attraper
       throw Exception("Erreur base de données lors du partage: ${e.message}");
    } catch (e) {
      // ✅ CORRECTION: Transformer l'erreur en Exception pour une meilleure gestion dans l'UI
      debugPrint("[SharingController] Erreur inconnue shareWithFriend: $e");
      // Si l'erreur est déjà une Exception, la relancer, sinon en créer une nouvelle.
      if (e is Exception) {
        rethrow;
      } else {
        throw Exception("Une erreur inconnue est survenue lors du partage: ${e.toString()}");
      }
    }
  }

  /// Révoque l'accès d'un collaborateur à un roman
  Future<void> revokeReaderAccess(String novelId, String collaboratorId) async {
     final currentUserId = _currentUserId;
     if (currentUserId == null) throw Exception("Utilisateur non connecté.");
     debugPrint("[SharingController] Tentative de révocation de l'accès pour $collaboratorId au novel $novelId.");

    try {
      // Supprime l'entrée correspondante
      await _supabase
          .from('novel_collaborators')
          .delete()
          .match({'novel_id': novelId, 'collaborator_id': collaboratorId});

      debugPrint("[SharingController] Accès révoqué pour $collaboratorId au novel $novelId.");

      // ✅ CORRECTION: Utiliser Future.microtask ici aussi par cohérence
      Future.microtask(() {
         _ref.invalidate(novelCollaboratorsProvider(novelId));
         debugPrint("[SharingController] Invalidation de novelCollaboratorsProvider($novelId) programmée après révocation.");
         // Optionnel : Invalider aussi la liste des romans pour l'utilisateur révoqué ?
         // Cela nécessiterait de connaître son Ref ou d'utiliser une autre approche.
         // Pour l'instant, l'utilisateur révoqué verra le roman disparaître au prochain rechargement.
         _ref.invalidate(novelsProvider); // Force le rafraichissement de la liste principale
      });


    } on PostgrestException catch (e) {
       debugPrint("[SharingController] Erreur Postgrest revokeReaderAccess: ${e.message} (code: ${e.code})");
       throw Exception("Erreur base de données lors de la révocation: ${e.message}");
    } catch (e) {
      debugPrint("[SharingController] Erreur inconnue revokeReaderAccess: $e");
       if (e is Exception) {
        rethrow;
      } else {
        throw Exception("Erreur inconnue lors de la révocation de l'accès: ${e.toString()}");
      }
    }
  }

  // == CONSERVÉ : Invitation par Email ==
  /// Invite un utilisateur par email à lire un roman (alternative)
  Future<void> inviteReaderByEmail(String novelId, String invitedUserEmail) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) throw Exception("Utilisateur non connecté.");
    final cleanedEmail = invitedUserEmail.trim().toLowerCase();
    if(cleanedEmail.isEmpty) throw Exception("L'email ne peut pas être vide.");

    debugPrint("[SharingController] Tentative d'invitation par email: $cleanedEmail pour novel $novelId");

    // 1. Trouver l'ID
    final invitedUserData = await _supabase
        .from('profiles')
        .select('id')
        .eq('email', cleanedEmail)
        .maybeSingle();

    if (invitedUserData == null) {
      throw Exception("Utilisateur avec l'email '$cleanedEmail' non trouvé.");
    }
    final invitedUserId = invitedUserData['id'];

    if (invitedUserId == currentUserId) {
      throw Exception("Vous ne pouvez pas vous inviter vous-même.");
    }

     // 2. Insérer (ou mettre à jour)
    try {
      await _supabase.from('novel_collaborators').upsert({
        'novel_id': novelId,
        'collaborator_id': invitedUserId,
        'role': 'reader',
      }, onConflict: 'novel_id, collaborator_id');

      debugPrint("[SharingController] Invitation par email réussie pour $cleanedEmail.");
      // ✅ CORRECTION: Utiliser Future.microtask
       Future.microtask(() {
         _ref.invalidate(novelCollaboratorsProvider(novelId));
         debugPrint("[SharingController] Invalidation de novelCollaboratorsProvider($novelId) programmée après invitation email.");
      });

    } on PostgrestException catch (e) {
       debugPrint("[SharingController] Erreur Postgrest inviteReaderByEmail: ${e.message} (code: ${e.code})");
       throw Exception("Erreur base de données lors de l'invitation: ${e.message}");
    } catch (e) {
      debugPrint("[SharingController] Erreur inconnue inviteReaderByEmail: $e");
       if (e is Exception) {
        rethrow;
      } else {
        throw Exception("Erreur inconnue lors de l'invitation: ${e.toString()}");
      }
    }
  }

} // Fin SharingController