// lib/controllers/friends_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import '../providers.dart'; // Pour authStateProvider

// Provider pour le controller lui-même
final friendsControllerProvider = Provider((ref) => FriendsController(ref));

// Provider pour la liste d'amis acceptés
// ✅ CORRECTION: Ajouter .autoDispose
final friendsListProvider = FutureProvider.autoDispose<List<Friendship>>((ref) async {
  // Se reconstruit si l'état d'authentification change ou si plus écouté
  ref.watch(authStateProvider);
  final controller = ref.watch(friendsControllerProvider);
  return controller.getFriends();
});

// Provider pour les demandes d'amis reçues en attente
// ✅ CORRECTION: Ajouter .autoDispose (par cohérence)
final pendingFriendRequestsProvider = FutureProvider.autoDispose<List<Friendship>>((ref) async {
  ref.watch(authStateProvider);
  final controller = ref.watch(friendsControllerProvider);
  return controller.getPendingIncomingRequests();
});


class FriendsController {
  final Ref _ref;
  final _supabase = Supabase.instance.client;

  FriendsController(this._ref);

  // Helper pour obtenir l'ID de l'utilisateur actuel
  String? get _currentUserId => _supabase.auth.currentUser?.id;

  /// Méthode interne pour récupérer les relations et profils associés
  Future<List<Friendship>> _fetchFriendships({String? filterStatus}) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return []; // Retourne vide si non connecté

    try {
      // 1. Récupérer les lignes de la table 'friendships' où l'utilisateur est impliqué
      var query = _supabase
          .from('friendships')
          .select('user_id_1, user_id_2, status, requester_id')
          .or('user_id_1.eq.$currentUserId,user_id_2.eq.$currentUserId');

      // Appliquer le filtre de statut si fourni
      if (filterStatus != null) {
        query = query.eq('status', filterStatus);
      }

      final friendshipsData = await query;

      if (friendshipsData.isEmpty) {
        debugPrint("[FriendsController] Aucune relation trouvée pour le filtre: $filterStatus");
        return []; // Aucune relation trouvée
      }

      // 2. Extraire les IDs de tous les *autres* utilisateurs dans ces relations
      final friendIds = <String>{}; // Utilise un Set pour éviter les doublons
      for (var row in friendshipsData) {
        final userId1 = row['user_id_1'];
        final userId2 = row['user_id_2'];
        if (userId1 != null && userId1 != currentUserId) {
          friendIds.add(userId1 as String);
        }
        if (userId2 != null && userId2 != currentUserId) {
          friendIds.add(userId2 as String);
        }
      }

      if (friendIds.isEmpty) {
         debugPrint("[FriendsController] Aucun ID d'ami extrait.");
         return [];
      }

      // 3. Récupérer les profils correspondants depuis la table 'profiles'
      final profilesData = await _supabase
          .from('profiles')
          .select('id, first_name, last_name, email') // Sélectionne les champs nécessaires
          .inFilter('id', friendIds.toList()); // Utilise inFilter

      // Créer une map pour un accès facile aux profils par leur ID
      final profileMap = {
          for (var profile in profilesData)
            profile['id']: FriendProfile.fromJson(profile)
      };

      // 4. Combiner les données de 'friendships' et 'profiles' pour créer la liste finale
      final friendshipsList = <Friendship>[];
      for (var row in friendshipsData) {
        // Déterminer l'ID de l'autre utilisateur dans cette relation
        String friendId;
        final userId1 = row['user_id_1'];
        final userId2 = row['user_id_2'];

        if (userId1 == currentUserId) {
          friendId = userId2;
        } else {
          friendId = userId1;
        }

        // Récupérer le profil de l'ami depuis la map
        final friendProfile = profileMap[friendId];

        // Créer l'objet Friendship si le profil a été trouvé
        if (friendProfile != null) {
          friendshipsList.add(Friendship(
            friendProfile: friendProfile,
            status: Friendship.statusFromString(row['status']),
            requesterId: row['requester_id'],
          ));
        } else {
          // Log si un profil est manquant (devrait être rare)
          debugPrint("[FriendsController] Profil non trouvé pour l'ID ami: $friendId dans la relation $row");
        }
      }

      debugPrint("[FriendsController] ${friendshipsList.length} relations formatées récupérées pour le filtre: $filterStatus");
      return friendshipsList;

    } catch (e, stacktrace) {
      debugPrint("[FriendsController] Erreur _fetchFriendships: $e\n$stacktrace");
      throw Exception("Impossible de récupérer les relations d'amitié.");
    }
  }

  /// Récupère la liste des amis acceptés
  Future<List<Friendship>> getFriends() async {
    debugPrint("[FriendsController] Appel getFriends (status: accepted)");
    return _fetchFriendships(filterStatus: 'accepted');
  }

  /// Récupère les demandes d'amis reçues et en attente
  Future<List<Friendship>> getPendingIncomingRequests() async {
    debugPrint("[FriendsController] Appel getPendingIncomingRequests (status: pending, entrant)");
    final pending = await _fetchFriendships(filterStatus: 'pending');
    // Garde seulement les demandes où l'utilisateur actuel N'EST PAS le demandeur
    final incoming = pending.where((f) => f.requesterId != _currentUserId).toList();
    debugPrint("[FriendsController] ${incoming.length} demandes entrantes trouvées.");
    return incoming;
  }

  /// Récupère les demandes d'amis envoyées et en attente (optionnel, si UI nécessaire)
  Future<List<Friendship>> getPendingOutgoingRequests() async {
     debugPrint("[FriendsController] Appel getPendingOutgoingRequests (status: pending, sortant)");
     final pending = await _fetchFriendships(filterStatus: 'pending');
     // Garde seulement les demandes où l'utilisateur actuel EST le demandeur
     final outgoing = pending.where((f) => f.requesterId == _currentUserId).toList();
     debugPrint("[FriendsController] ${outgoing.length} demandes sortantes trouvées.");
     return outgoing;
  }

  /// Envoie une demande d'ami
  Future<void> sendFriendRequest(String friendEmail) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) throw Exception("Utilisateur non connecté.");
    final cleanedEmail = friendEmail.trim().toLowerCase();
    if (cleanedEmail.isEmpty) throw Exception("L'email ne peut pas être vide.");

    debugPrint("[FriendsController] Tentative d'envoi de demande à: $cleanedEmail");

    // 1. Trouver l'ID du destinataire
    final friendData = await _supabase
        .from('profiles')
        .select('id, email') // Sélectionne l'email pour vérifier la casse exacte si besoin
        .eq('email', cleanedEmail) // Supabase gère l'insensibilité à la casse par défaut sur `text`
        .maybeSingle();

    if (friendData == null) {
      throw Exception("Aucun utilisateur trouvé avec l'email '$cleanedEmail'.");
    }
    final friendId = friendData['id'];

    // 2. Vérifier l'auto-ajout
    if (friendId == currentUserId) {
      throw Exception("Vous ne pouvez pas vous ajouter comme ami.");
    }

    // 3. Préparer les données en respectant user_id_1 < user_id_2
    final userId1 = currentUserId.compareTo(friendId) < 0 ? currentUserId : friendId;
    final userId2 = currentUserId.compareTo(friendId) > 0 ? currentUserId : friendId;

    // 4. Insérer la demande
    try {
      await _supabase.from('friendships').insert({
        'user_id_1': userId1,
        'user_id_2': userId2,
        'status': 'pending',
        'requester_id': currentUserId, // Qui a fait la demande
      });
      debugPrint("[FriendsController] Demande envoyée de $currentUserId à $friendId.");
      _invalidateFriendCaches(); // Rafraîchir les listes
    } on PostgrestException catch (e) {
      if (e.code == '23505') { // Code d'erreur pour violation d'unicité (clé primaire)
        debugPrint("[FriendsController] Violation d'unicité lors de l'envoi de la demande (relation existe déjà).");
        throw Exception("Une relation (en attente ou acceptée) existe déjà avec cet utilisateur.");
      }
      debugPrint("[FriendsController] Erreur Postgrest sendFriendRequest: ${e.message} (code: ${e.code})");
      throw Exception("Erreur base de données: ${e.message}");
    } catch (e) {
      debugPrint("[FriendsController] Erreur inconnue sendFriendRequest: $e");
      throw Exception("Une erreur inconnue est survenue.");
    }
  }

  /// Accepte une demande d'ami
  Future<void> acceptFriendRequest(String friendId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) throw Exception("Utilisateur non connecté.");
    debugPrint("[FriendsController] Tentative d'acceptation de la demande de: $friendId");

    // Détermine l'ordre des IDs pour la clé primaire
    final userId1 = currentUserId.compareTo(friendId) < 0 ? currentUserId : friendId;
    final userId2 = currentUserId.compareTo(friendId) > 0 ? currentUserId : friendId;

    try {
      // Met à jour la ligne correspondante en 'accepted'
      // La politique RLS s'assure que seul le destinataire peut faire ça
      await _supabase
          .from('friendships')
          .update({'status': 'accepted', 'updated_at': DateTime.now().toIso8601String()})
          .match({
            'user_id_1': userId1,
            'user_id_2': userId2,
            'status': 'pending', // Condition supplémentaire de sécurité
          })
         .neq('requester_id', currentUserId); // Double vérification qu'on n'est pas le demandeur

      debugPrint("[FriendsController] Demande de $friendId acceptée.");
      _invalidateFriendCaches();
    } catch (e) {
      debugPrint("[FriendsController] Erreur acceptFriendRequest: $e");
      throw Exception("Erreur lors de l'acceptation de la demande.");
    }
  }

  /// Refuse une demande ou supprime un ami
  Future<void> removeOrRejectFriendship(String friendId) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) throw Exception("Utilisateur non connecté.");
    debugPrint("[FriendsController] Tentative de suppression/refus de la relation avec: $friendId");

    // Détermine l'ordre des IDs pour trouver la bonne ligne
    final userId1 = currentUserId.compareTo(friendId) < 0 ? currentUserId : friendId;
    final userId2 = currentUserId.compareTo(friendId) > 0 ? currentUserId : friendId;

    try {
      // Supprime la ligne correspondante
      // La politique RLS permet à l'un ou l'autre de supprimer
      await _supabase
          .from('friendships')
          .delete()
          .match({'user_id_1': userId1, 'user_id_2': userId2});

      debugPrint("[FriendsController] Relation avec $friendId supprimée/refusée.");
      _invalidateFriendCaches();
    } catch (e) {
      debugPrint("[FriendsController] Erreur removeOrRejectFriendship: $e");
      throw Exception("Erreur lors de la suppression/refus de l'ami.");
    }
  }

  /// Helper pour invalider les providers liés aux amis
  void _invalidateFriendCaches() {
    _ref.invalidate(friendsListProvider);
    _ref.invalidate(pendingFriendRequestsProvider);
    // Ajoutez ici d'autres providers si nécessaire (ex: demandes sortantes)
    debugPrint("[FriendsController] Caches amis invalidés.");
  }
}