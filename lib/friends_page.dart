// lib/friends_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'controllers/friends_controller.dart';
import 'models.dart';
import 'widgets/optimized_common_widgets.dart'; // Pour LoadingWidget et ConfirmDialog

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surveille les providers pour la liste d'amis et les demandes
    final friendsAsync = ref.watch(friendsListProvider);
    final pendingRequestsAsync = ref.watch(pendingFriendRequestsProvider);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2, // Deux onglets : Amis, Demandes Reçues
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes Amis'),
          actions: [
            // Bouton pour ouvrir le dialogue d'ajout d'ami
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Ajouter un ami par email',
              onPressed: () => _showAddFriendDialog(context, ref),
            ),
          ],
          // Barre d'onglets sous l'AppBar
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Amis'),
              // Utilise un Badge pour montrer le nombre de demandes en attente
              Tab(
                child: pendingRequestsAsync.when(
                  data: (requests) => Badge(
                    label: Text('${requests.length}'),
                    isLabelVisible: requests.isNotEmpty,
                    child: const Text('Demandes Reçues'),
                  ),
                  loading: () => const Text('Demandes Reçues'), // Ou un indicateur
                  error: (e, s) => const Row( // Indique une erreur
                    mainAxisSize: MainAxisSize.min,
                    children: [ Icon(Icons.error_outline, size: 16, color: Colors.orange), SizedBox(width: 4), Text('Demandes'),],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ================== CONTENU DE L'ONGLET AMIS ==================
            friendsAsync.when(
              loading: () => const LoadingWidget(message: 'Chargement des amis...'),
              error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Erreur: $err', textAlign: TextAlign.center),
                  )
              ),
              data: (friends) {
                if (friends.isEmpty) {
                  // Widget affiché si la liste est vide
                  return const EmptyStateWidget(
                    icon: Icons.people_outline,
                    title: 'Aucun ami',
                    subtitle: 'Ajoutez des amis en utilisant le bouton + en haut à droite pour partager vos histoires !',
                  );
                }
                // Liste des amis si non vide
                return RefreshIndicator(
                  // Permet de rafraîchir la liste en tirant vers le bas
                  onRefresh: () async {
                      ref.invalidate(friendsListProvider);
                      ref.invalidate(pendingFriendRequestsProvider); // Rafraîchit aussi les demandes
                  },
                  child: ListView.separated(
                    itemCount: friends.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final friendship = friends[index];
                      return ListTile(
                        leading: CircleAvatar( // Affiche initiale ou avatar
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Text(friendship.friendProfile.firstName.isNotEmpty
                              ? friendship.friendProfile.firstName[0].toUpperCase()
                              : friendship.friendProfile.email[0].toUpperCase()),
                        ),
                        title: Text(friendship.friendProfile.fullName), // Nom complet
                        subtitle: Text(friendship.friendProfile.email), // Email
                        trailing: IconButton(
                          icon: Icon(Icons.person_remove_outlined, color: Colors.redAccent.withOpacity(0.7)),
                          tooltip: 'Retirer cet ami',
                          // Appelle la fonction de confirmation avant suppression
                          onPressed: () => _confirmRemoveFriend(context, ref, friendship),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            // ================== CONTENU DE L'ONGLET DEMANDES REÇUES ==================
            pendingRequestsAsync.when(
              loading: () => const LoadingWidget(message: 'Chargement des demandes...'),
              error: (err, stack) => Center(
                child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Erreur: $err', textAlign: TextAlign.center),
                  )
              ),
              data: (requests) {
                if (requests.isEmpty) {
                  // Widget affiché si aucune demande en attente
                  return const EmptyStateWidget(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'Aucune demande',
                    subtitle: 'Vous n\'avez pas de demande d\'ami en attente.',
                  );
                }
                // Liste des demandes reçues
                return RefreshIndicator(
                  onRefresh: () async {
                      ref.invalidate(friendsListProvider); // Rafraîchit aussi les amis
                      ref.invalidate(pendingFriendRequestsProvider);
                  },
                  child: ListView.separated(
                    itemCount: requests.length,
                     separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final friendship = requests[index];
                      return ListTile(
                        leading: CircleAvatar( // Initiale ou avatar
                           backgroundColor: theme.colorScheme.secondaryContainer,
                           foregroundColor: theme.colorScheme.onSecondaryContainer,
                          child: Text(friendship.friendProfile.firstName.isNotEmpty
                              ? friendship.friendProfile.firstName[0].toUpperCase()
                              : friendship.friendProfile.email[0].toUpperCase()),
                        ),
                        title: Text(friendship.friendProfile.fullName), // Nom
                        subtitle: Text(friendship.friendProfile.email), // Email
                        // Boutons Accepter/Refuser
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                              tooltip: 'Accepter la demande',
                              onPressed: () => _acceptRequest(context, ref, friendship.friendProfile.id),
                            ),
                            IconButton(
                              icon: Icon(Icons.cancel_outlined, color: Colors.redAccent.withOpacity(0.7)),
                              tooltip: 'Refuser la demande',
                              onPressed: () => _rejectRequest(context, ref, friendship.friendProfile.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Fonctions d'aide pour les dialogues et actions ---

  // Dialogue pour ajouter un ami par email
  void _showAddFriendDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false; // Gère l'état de chargement interne au dialogue

    showDialog(
      context: context,
      barrierDismissible: !isLoading, // Empêche de fermer pendant le chargement
      builder: (dialogContext) {
        return StatefulBuilder( // Permet de mettre à jour l'état du dialogue (bouton loading)
           builder: (context, setStateDialog) {
             return AlertDialog(
              title: const Text('Ajouter un ami'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email de l\'ami',
                    hintText: 'nom@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty || !value.contains('@')) {
                      return 'Veuillez entrer une adresse email valide.';
                    }
                    return null;
                  },
                  enabled: !isLoading, // Désactive le champ pendant le chargement
                ),
              ),
              actions: [
                TextButton(
                  // Désactivé pendant le chargement
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  // Affiche un indicateur de chargement si isLoading est vrai
                  onPressed: isLoading ? null : () async {
                    if (formKey.currentState!.validate()) {
                      // Met à jour l'état pour afficher le chargement
                      setStateDialog(() => isLoading = true);
                      try {
                        // Appelle le controller pour envoyer la demande
                        await ref.read(friendsControllerProvider).sendFriendRequest(emailController.text);
                        // Ferme le dialogue si succès
                        Navigator.pop(dialogContext);
                        // Affiche un message de succès
                        ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text("Demande d'ami envoyée à ${emailController.text}!"), backgroundColor: Colors.green)
                        );
                        // Le controller invalide les providers, l'UI se mettra à jour
                      } catch (e) {
                         // Affiche l'erreur si l'envoi échoue
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
                         );
                         // Réactive les boutons/champ en cas d'erreur
                         setStateDialog(() => isLoading = false);
                      }
                      // Pas besoin de remettre isLoading à false ici si succès car le dialogue est fermé
                    }
                  },
                  child: isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Envoyer la demande'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // Confirmation avant de retirer un ami
  Future<void> _confirmRemoveFriend(BuildContext context, WidgetRef ref, Friendship friendship) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Retirer ${friendship.friendProfile.fullName} ?',
      content: 'Voulez-vous vraiment retirer cet ami ? Les romans partagés ne seront plus accessibles.',
      confirmLabel: 'Retirer',
      isDangerous: true,
    );

    if (confirmed == true && context.mounted) { // Vérifie le montage après l'await
      try {
        // Appelle le controller pour supprimer l'amitié
        await ref.read(friendsControllerProvider).removeOrRejectFriendship(friendship.friendProfile.id);
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("${friendship.friendProfile.fullName} retiré de vos amis."), backgroundColor: Colors.orange)
        );
         // L'invalidation est gérée par le controller
      } catch (e) {
         if(context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
           );
         }
      }
    }
  }

  // Accepter une demande d'ami
  Future<void> _acceptRequest(BuildContext context, WidgetRef ref, String friendId) async {
     try {
       // Appelle le controller pour accepter
       await ref.read(friendsControllerProvider).acceptFriendRequest(friendId);
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Demande d'ami acceptée !"), backgroundColor: Colors.green)
       );
       // L'invalidation est gérée par le controller
     } catch (e) {
        if(context.mounted) { // Vérifier avant d'afficher
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
          );
        }
     }
  }

  // Refuser une demande d'ami
   Future<void> _rejectRequest(BuildContext context, WidgetRef ref, String friendId) async {
     try {
       // Appelle le controller pour supprimer/refuser
       await ref.read(friendsControllerProvider).removeOrRejectFriendship(friendId);
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Demande d'ami refusée."), backgroundColor: Colors.orange)
       );
       // L'invalidation est gérée par le controller
     } catch (e) {
       if(context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
         );
       }
     }
  }

} // Fin FriendsPage