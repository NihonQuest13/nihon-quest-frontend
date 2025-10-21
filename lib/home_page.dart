// lib/home_page.dart
import 'dart:async';
import 'dart:ui'; // Pour BackdropFilter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:japanese_story_app/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:collection/collection.dart'; // Pour firstWhereOrNull

// Imports locaux
import 'admin_page.dart';
import 'controllers/home_controller.dart';
import 'controllers/sharing_controller.dart'; // Controller de partage
import 'controllers/friends_controller.dart'; // Controller des amis
import 'create_novel_page.dart' as create;
import 'edit_novel_page.dart';
import 'models.dart';
import 'novel_reader_page.dart';
import 'providers.dart'; // Tous les providers
import 'services/ai_service.dart'; // Pour le dialogue de création
import 'services/sync_service.dart'; // Pour SyncTask
import 'services/startup_service.dart';
import 'services/vocabulary_service.dart';
import 'widgets/streaming_text_widget.dart'; // Pour le dialogue de création
import 'widgets/cached_cover_image.dart'; // Pour les couvertures
import 'widgets/optimized_common_widgets.dart'; // Pour ConfirmDialog, LoadingWidget, etc.
import 'friends_page.dart'; // Page de gestion des amis
import 'utils/app_logger.dart'; // ✅ AJOUT: Pour le log de débogage

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // Controller pour les actions de la page d'accueil (ping, synchro forcée, tri)
  late HomeController _homeController;

  @override
  void initState() {
    super.initState();
    // Initialise le controller après le premier build
    // Utilise addPostFrameCallback pour accéder au contexte et ref en toute sécurité
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) { // Vérifie si le widget est toujours dans l'arbre
        _initializeController();
      }
    });
  }

  // Initialise le HomeController et lance la vérification du backend
  void _initializeController() {
    _homeController = HomeController(ref, context);
    _homeController.checkBackendStatus();
    // La synchronisation au démarrage est déclenchée par le listener sur serverStatusProvider
  }

  @override
  Widget build(BuildContext context) {
    // Écoute les changements de statut du serveur pour déclencher des actions
    ref.listen<ServerStatus>(serverStatusProvider, (previous, next) async {
      if (next == ServerStatus.connected) {
        AppLogger.info("Serveur connecté. Lancement synchro démarrage.", tag: "HomePageListener");
        // Lance la synchronisation des romans au démarrage si le serveur est connecté
        await ref.read(startupServiceProvider).synchronizeOnStartup();
        // Tente de traiter la file de synchronisation (si elle n'est pas vide)
        ref.read(syncServiceProvider).processQueue();
      }
    });

    // Récupération des données et états nécessaires depuis Riverpod
    final theme = Theme.of(context);
    final novelsAsyncValue = ref.watch(novelsProvider); // État de la liste des romans (chargement, données, erreur)
    final isDarkMode = ref.watch(themeServiceProvider) == ThemeMode.dark; // État du thème
    final serverStatus = ref.watch(serverStatusProvider); // État du backend
    // Compte des demandes d'amis en attente pour le badge
    final pendingRequestsAsync = ref.watch(pendingFriendRequestsProvider);
    final pendingRequestsCount = pendingRequestsAsync.when(
          data: (requests) => requests.length,
          loading: () => 0, // Pas de badge pendant le chargement
          error: (e, s) => 0, // Pas de badge en cas d'erreur
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma bibliothèque'),
        centerTitle: true, // Centre le titre
        leadingWidth: 120, // Largeur pour les icônes de statut/synchro
        leading: _buildLeadingActions(serverStatus), // Construit les actions de gauche
        actions: _buildAppBarActions(isDarkMode, pendingRequestsCount), // Construit les actions de droite
      ),
      // Corps principal de la page
      body: novelsAsyncValue.when(
        // État de chargement initial
        loading: () => const LoadingWidget(message: 'Chargement de la bibliothèque...'),
        // État d'erreur
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            // Affiche l'erreur et un bouton pour réessayer
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                const SizedBox(height: 16),
                Text('Erreur de chargement:', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText('Détails: $err\n$stack', // Afficher stacktrace en debug?
                   textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                 const SizedBox(height: 24),
                 ElevatedButton.icon(
                   icon: const Icon(Icons.refresh),
                   label: const Text('Rafraîchir'),
                   onPressed: () {
                     ref.invalidate(novelsProvider);
                     ref.invalidate(friendsListProvider);
                     ref.invalidate(pendingFriendRequestsProvider);
                   }
                 ),
              ],
            ),
          ),
        ),
        // État où les données sont disponibles
        data: (novels) {
          // Si la liste est vide, affiche un message d'accueil
          if (novels.isEmpty) {
            return _buildEmptyState(theme);
          }
          // Sinon, affiche la grille des romans
          return RefreshIndicator(
            // Permet de rafraîchir en tirant vers le bas
            onRefresh: () async {
                ref.invalidate(novelsProvider); // Recharge les romans
                // Invalider les providers autoDispose forcera leur rechargement
                ref.invalidate(friendsListProvider);
                ref.invalidate(pendingFriendRequestsProvider);
            },
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Espace autour de la grille
              // Configuration de la grille
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200, // Largeur max de chaque élément
                childAspectRatio: 0.7, // Ratio largeur/hauteur (pour couvertures)
                crossAxisSpacing: 16, // Espace horizontal
                mainAxisSpacing: 24, // Espace vertical (augmenté pour titre/divider)
              ),
              itemCount: novels.length, // Nombre d'éléments
              // Construit chaque élément de la grille
              itemBuilder: (context, index) {
                final novel = novels[index];
                // Utilise le widget _NovelCoverItem pour afficher chaque roman
                return _NovelCoverItem(novel: novel);
              },
            ),
          );
        },
      ),
      // Boutons flottants en bas
      floatingActionButton: _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // Position au centre
    );
  }

  // ==================== NOUVELLE FONCTION DE RÉORGANISATION ====================

  void _showReorderChaptersDialog(BuildContext context, Novel novel) {
    // ⚠️ Crée une copie modifiable des chapitres pour le glisser-déposer local
    List<Chapter> localChapters = List.from(novel.chapters);
    bool isSaving = false;
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final theme = Theme.of(context);
            
            // Si le roman n'a pas de chapitres, on ne fait rien
            if (localChapters.isEmpty) {
              return AlertDialog(
                title: const Text('Réorganisation des chapitres'),
                content: const Text('Ce roman ne contient pas encore de chapitres à réorganiser.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))
                ],
              );
            }

            return AlertDialog(
              title: const Text('Réorganiser les chapitres'),
              contentPadding: const EdgeInsets.fromLTRB(0, 20.0, 0, 0),
              content: SizedBox(
                width: 500,
                height: 400,
                child: ReorderableListView(
                  // Le titre et le bouton Fermer ne font pas partie de la liste
                  header: Padding(
                    padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 8.0),
                    child: Text(
                      'Faites glisser les chapitres pour changer leur ordre.',
                      style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                  onReorder: (int oldIndex, int newIndex) {
                    if (isSaving) return; // Ne rien faire pendant la sauvegarde

                    setStateDialog(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final Chapter item = localChapters.removeAt(oldIndex);
                      localChapters.insert(newIndex, item);
                    });
                  },
                  children: <Widget>[
                    for (int index = 0; index < localChapters.length; index += 1)
                      ListTile(
                        key: ValueKey(localChapters[index].id), // Clé requise pour ReorderableListView
                        tileColor: index % 2 == 0 ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface,
                        title: Text('Chapitre ${index + 1}: ${localChapters[index].title}', overflow: TextOverflow.ellipsis),
                        subtitle: Text(localChapters[index].createdAt.toLocal().toString().substring(0, 16)),
                        trailing: const Icon(Icons.drag_handle), // Icône de glisser-déposer
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    setStateDialog(() => isSaving = true);
                    final currentContext = context; // Capture le contexte pour le Snackbar
                    Navigator.pop(dialogContext); // Ferme le dialogue immédiatement

                    try {
                      // 1. Appel du notifier pour la réorganisation
                      await ref.read(novelsProvider.notifier).reorderChapters(novel.id, localChapters.map((c) => c.id).toList());
                      
                      // 2. Afficher la confirmation
                      if (currentContext.mounted) {
                        ScaffoldMessenger.of(currentContext).showSnackBar(
                          const SnackBar(content: Text('Ordre des chapitres sauvegardé !'), backgroundColor: Colors.green)
                        );
                      }
                    } catch (e) {
                       AppLogger.error("Erreur lors de la réorganisation des chapitres", error: e, tag: "HomePage");
                       if (currentContext.mounted) {
                        ScaffoldMessenger.of(currentContext).showSnackBar(
                          SnackBar(content: Text('Erreur: Impossible de sauvegarder l\'ordre. ${e.toString()}'), backgroundColor: Colors.redAccent)
                        );
                      }
                    }
                    // Le set state ne se fait pas ici car on a pop le dialogue.
                    // L'état de l'application est mis à jour par le ref.read().reorderChapters.
                  },
                  child: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sauvegarder l\'ordre'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== MÉTHODES DE CONSTRUCTION UI (INCHANGÉES) ====================

  // Construit les icônes à gauche de l'AppBar (Statut Backend, Synchro)
  Widget _buildLeadingActions(ServerStatus serverStatus) {
    return Row(
      children: [
        const SizedBox(width: 8), // Petit espace
        // Icône de statut du backend avec tooltip
        Tooltip(
          message: switch (serverStatus) { // Texte différent selon le statut
            ServerStatus.connecting => "Connexion au serveur local...",
            ServerStatus.connected => 'Connecté au serveur local',
            ServerStatus.failed => 'Serveur local déconnecté. Vérifiez le backend Python.',
          },
          child: IconButton(
            // Icône différente selon le statut
            icon: switch (serverStatus) {
              ServerStatus.connecting => const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5), // Indicateur de chargement
                ),
              ServerStatus.connected => const Icon(Icons.cloud_done_outlined, color: Colors.green), // Connecté
              ServerStatus.failed => const Icon(Icons.cloud_off_outlined, color: Colors.red), // Déconnecté
            },
            // Au clic, retente la vérification du statut
            onPressed: () => _homeController.checkBackendStatus(),
          ),
        ),
        // Affiche le bouton de synchro forcée seulement si connecté
        if (serverStatus == ServerStatus.connected)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Forcer la synchronisation avec le serveur',
            // Au clic, lance la synchro forcée via le controller
            onPressed: () => _homeController.forceSyncWithServer(),
          ),
      ],
    );
  }

  // Construit les icônes à droite de l'AppBar (Admin, Amis, Thème, Info, Logout)
  List<Widget> _buildAppBarActions(bool isDarkMode, int pendingRequestsCount) {
    return [
      // Bouton Admin (visible seulement si l'utilisateur est admin)
      FutureBuilder<bool>(
        future: _checkIfAdmin(), // Vérifie le statut admin
        builder: (context, snapshot) {
          // Affiche le bouton si admin, sinon un espace vide
          if (snapshot.data == true) {
            return IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Administration',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPage()));
              },
            );
          }
          return const SizedBox.shrink(); // Widget vide si non admin
        },
      ),

      // Bouton Amis avec Badge
      IconButton(
        icon: Badge(
          label: Text('$pendingRequestsCount'), // Affiche le nombre
          isLabelVisible: pendingRequestsCount > 0, // Cache si 0
          child: const Icon(Icons.people_alt_outlined),
        ),
        tooltip: 'Gérer les amis et demandes',
        onPressed: () {
          // Navigue vers la page des amis
          Navigator.push(context, MaterialPageRoute(builder: (context) => const FriendsPage()));
        },
      ),

      // Bouton pour changer le thème (Clair/Sombre)
      IconButton(
        icon: Icon(isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
        tooltip: 'Changer de thème',
        onPressed: () {
          // Appelle le notifier pour changer et sauvegarder le thème
          ref.read(themeServiceProvider.notifier).updateTheme(
                isDarkMode ? ThemeMode.light : ThemeMode.dark,
              );
        },
      ),

      // Bouton Informations (aide)
      IconButton(
        icon: const Icon(Icons.help_outline), // Changé pour une icône plus standard
        tooltip: 'Informations et Aide',
        onPressed: _showHelpDialog, // Affiche le dialogue d'aide
      ),

      // Bouton Déconnexion
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Se déconnecter',
        onPressed: () async {
          // Appelle Supabase pour déconnecter l'utilisateur
          await Supabase.instance.client.auth.signOut();
          // AuthGuard gèrera la redirection vers LoginPage
        },
      ),
      const SizedBox(width: 8), // Espace final
    ];
  }

  // Vérifie si l'utilisateur actuel a le rôle admin dans Supabase
  Future<bool> _checkIfAdmin() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return false; // Non connecté

      // Requête pour obtenir le champ 'is_admin' du profil
      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_admin')
          .eq('id', userId)
          .maybeSingle(); // Récupère une seule ligne ou null

      // Retourne vrai si 'is_admin' est vrai, sinon faux
      return response?['is_admin'] == true;
    } catch (e) {
      AppLogger.error('Erreur vérification admin', error: e, tag: "HomePage");
      return false; // En cas d'erreur, suppose non admin
    }
  }

  // Construit les deux boutons flottants (Trier, Ajouter)
  Widget _buildFloatingActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0), // Espace sur les côtés
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Place les boutons aux extrémités
        children: [
          // Bouton Trier
          FloatingActionButton.small( // Utilise .small pour moins d'encombrement
            heroTag: 'sort_button', // Tag unique pour l'animation Hero
            onPressed: _showSortOptions, // Affiche les options de tri
            tooltip: 'Trier les romans',
            child: const Icon(Icons.filter_list_rounded),
          ),
          // Bouton Ajouter
          FloatingActionButton( // Garde la taille standard pour l'action principale
            heroTag: 'add_button',
            onPressed: _navigateToCreateNovel, // Navigue vers la page de création
            tooltip: 'Créer un nouveau roman',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  // Affiche un message quand la bibliothèque est vide
  Widget _buildEmptyState(ThemeData theme) {
    // Utilise le widget réutilisable pour l'état vide
    return EmptyStateWidget(
        icon: Icons.library_books_outlined,
        title: 'Votre bibliothèque est vide.',
        subtitle: 'Appuyez sur le bouton + pour commencer une nouvelle histoire.',
    );
  }

  // ==================== MÉTHODES D'ACTION ====================

  // Affiche le bottom sheet pour choisir l'option de tri
  void _showSortOptions() {
    // Récupère l'option de tri actuelle
    final currentSort = ref.read(sortOptionProvider);
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min, // Prend la hauteur nécessaire
        children: SortOption.values.map((option) { // Itère sur toutes les options de tri
          return RadioListTile<SortOption>(
            title: Text(_homeController.sortOptionToString(option)), // Affiche le nom de l'option
            value: option, // La valeur de cette option
            groupValue: currentSort, // L'option actuellement sélectionnée
            onChanged: (value) {
              if (value != null) {
                // Met à jour l'état du provider de tri
                ref.read(sortOptionProvider.notifier).state = value;
                // La liste se mettra à jour automatiquement grâce au watch dans build()
              }
              Navigator.pop(context); // Ferme le bottom sheet
            },
          );
        }).toList(),
      ),
    );
  }

  // Navigue vers la page de création de roman
  Future<void> _navigateToCreateNovel() async {
    // Navigue et attend un résultat potentiel (le Novel créé)
    await Navigator.push<Novel?>(
      context,
      MaterialPageRoute(builder: (context) => const create.CreateNovelPage()),
    );
    // Après le retour de CreateNovelPage, invalide le provider pour rafraîchir
    if (mounted) {
       ref.invalidate(novelsProvider);
    }
  }

  // Affiche le dialogue d'aide/informations
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Utilise BackdropFilter pour un effet de flou derrière le dialogue
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: DefaultTabController( // Gère les onglets
            length: 5, // Nombre d'onglets
            child: AlertDialog(
              title: const Text("Informations et Aide"),
              contentPadding: const EdgeInsets.only(top: 10.0), // Réduit l'espace haut
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9, // Largeur adaptative
                height: MediaQuery.of(context).size.height * 0.6, // Hauteur adaptative
                child: Column(
                  children: [
                    // Barre d'onglets
                    const TabBar(
                      isScrollable: true, // Permet le défilement si les titres sont longs
                      tabs: [
                        Tab(text: "Guide"),
                        Tab(text: "Principe"),
                        Tab(text: "Écrivains"),
                        Tab(text: "Mémoire"),
                        Tab(text: "À propos"),
                      ],
                    ),
                    // Contenu des onglets
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildHelpTabContent( /* Guide */
                            context,
                            icon: Icons.tour_outlined,
                            title: "Guide d'utilisation",
                            spans: const [
                              TextSpan(text: "Gérer un roman :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nFaites un appui long sur sa couverture. Un menu apparaîtra pour modifier les détails, gérer la couverture, partager ou supprimer le roman.\n\n"),
                              TextSpan(text: "Lire un roman :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nUn simple clic sur la couverture ouvre le lecteur.\n\n"),
                              TextSpan(text: "Trier :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nUtilisez le bouton filtre (entonnoir) en bas à gauche.\n\n"),
                              TextSpan(text: "Créer :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nLe bouton plus (+) en bas à droite ouvre la page de création.\n\n"),
                              TextSpan(text: "Partager :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nAjoutez d'abord des amis via le bouton 'Amis' (icône bonhommes) en haut. Ensuite, via l'appui long sur un roman, choisissez 'Partager' et sélectionnez un ami.\n\n"),
                              TextSpan(text: "Synchronisation :", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "\nL'icône nuage indique l'état du serveur local. Cliquez sur l'icône synchro (flèches) pour forcer la réindexation de tous vos chapitres si besoin."),
                            ],
                          ),
                          _buildHelpTabContent( /* Principe */
                            context, icon: Icons.auto_stories_outlined, title: "Votre rôle", spans: const [ /* ... texte ... */
                              TextSpan(text: "Vous êtes le "), TextSpan(text: "Maître d'œuvre", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: ". Vous définissez l'univers, les personnages, l'intrigue de départ et le style via les options de création. Des "), TextSpan(text: "écrivains IA", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: " rédigent ensuite les chapitres pour vous.\n\nVotre rôle est crucial : guidez l'IA, corrigez ses textes dans le lecteur (appui long sur le chapitre -> Modifier), et décidez de la direction que prend l'histoire. C'est une "), TextSpan(text: "collaboration créative", style: TextStyle(fontStyle: FontStyle.italic)), TextSpan(text: " !"),
                             ],
                          ),
                          _buildHelpTabContent( /* Écrivains */
                             context, icon: Icons.psychology_outlined, title: "Vos Écrivains IA", spans: const [ /* ... texte ... */
                              TextSpan(text: "Chaque roman peut avoir son propre écrivain IA, avec des styles variés (liste susceptible d'évoluer) :\n\n"),
                              TextSpan(text: "• Qwen : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Souvent très créatif, bon pour imaginer des scénarios originaux et surprenants. Peut parfois nécessiter un peu plus de guidage.\n\n"),
                              TextSpan(text: "• Llama : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Un modèle très performant, généralement cohérent et bon pour suivre des instructions détaillées. Excellent pour des genres établis.\n\n"),
                              TextSpan(text: "• Venice (expérimental) : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Un modèle en test, peut offrir des styles uniques mais potentiellement moins stable.\n\n"),
                              TextSpan(text: "N'hésitez pas à tester différents écrivains pour différents types d'histoires !"),
                            ],
                          ),
                          _buildHelpTabContent( /* Mémoire */
                             context, icon: Icons.memory_outlined, title: "La Mémoire Contextuelle", spans: const [ /* ... texte ... */
                              TextSpan(text: "Comment l'IA se souvient-elle de l'histoire ? Grâce à plusieurs mécanismes :\n\n"),
                              TextSpan(text: "1. Ancrage Immédiat : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "L'IA reçoit systématiquement la toute dernière phrase du chapitre précédent pour assurer une continuité directe.\n\n"),
                              TextSpan(text: "2. Chapitre Précédent (N-1) : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "L'intégralité du chapitre juste avant est fournie pour le contexte immédiat.\n\n"),
                              TextSpan(text: "3. Fiche de Route (Passé) : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Tous les 3 chapitres, l'IA génère un résumé de tout ce qui s'est passé depuis le début. Ce résumé est fourni pour garder une vision globale.\n\n"),
                              TextSpan(text: "4. Plan Directeur (Futur) : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Si la 'Trame Évolutive' est activée, l'IA génère (et met à jour tous les 10 chapitres) un plan pour les chapitres suivants, servant de fil conducteur.\n\n"),
                              TextSpan(text: "5. Recherche Vectorielle (FAISS) : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Le serveur local transforme chaque chapitre en 'vecteur' (empreinte sémantique). Avant d'écrire, l'IA recherche les 1 ou 2 chapitres les plus similaires sémantiquement dans le passé pour retrouver des détails pertinents oubliés dans les autres contextes."),
                            ],
                          ),
                           _buildHelpTabContent( /* À propos */
                             context, icon: Icons.info_outline, title: "À propos de l'IA", spans: const [ /* ... texte ... */
                               TextSpan(text: "Qualité & Limites : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Les modèles IA sont des outils puissants mais imparfaits. Ils peuvent générer des répétitions, des incohérences ou oublier des détails malgré les systèmes de mémoire. Votre rôle d'éditeur est essentiel pour peaufiner le résultat.\n\n"),
                               TextSpan(text: "Coûts & Utilisation : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "L'utilisation des modèles IA a un coût (calcul, énergie). Les modèles marqués ':free' sont généralement moins chers ou gratuits dans certaines limites via des services comme OpenRouter, but peuvent être plus lents ou sujets à des quotas.\n\n"),
                               TextSpan(text: "Confidentialité : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "Vos romans sont stockés dans votre compte Supabase. Le contenu envoyé aux API d'IA (OpenRouter, etc.) transite par leurs serveurs. Consultez leurs politiques de confidentialité pour plus de détails. Le backend local FAISS fonctionne entièrement sur votre machine."),
                             ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // Construit le contenu d'un onglet d'aide
  Widget _buildHelpTabContent(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<InlineSpan> spans,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0), // Padding uniforme
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row( // Titre avec icône
            crossAxisAlignment: CrossAxisAlignment.start, // Aligne en haut si titre long
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600), // Police un peu plus épaisse
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // Espace après titre
          // Texte formaté
          Text.rich(
            TextSpan(
              // Style par défaut pour le texte de l'aide
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5, // Interligne
                color: theme.colorScheme.onSurfaceVariant, // Couleur légèrement atténuée
              ),
              children: spans, // Liste des TextSpans (normal, gras, etc.)
            ),
            textAlign: TextAlign.justify, // Justifie le texte
          ),
        ],
      ),
    );
  }

  // Affiche un Snackbar (message temporaire en bas)
  void _showFeedback(
    String message, {
    bool isError = false,
    Color? color,
    int duration = 4,
  }) {
    // Vérifie si le widget est toujours monté avant d'afficher
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Cache le précédent
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : (color ?? Colors.green), // Couleur selon erreur/succès
        duration: Duration(seconds: duration), // Durée d'affichage
      ),
    );
  }

} // Fin _HomePageState


// ==================== WIDGET POUR UNE COUVERTURE DE ROMAN ====================

class _NovelCoverItem extends ConsumerStatefulWidget {
  const _NovelCoverItem({required this.novel});
  final Novel novel;

  @override
  ConsumerState<_NovelCoverItem> createState() => _NovelCoverItemState();
}

class _NovelCoverItemState extends ConsumerState<_NovelCoverItem> {
   bool _isHovering = false; // Gère l'effet de survol (pour web/desktop)
   // Récupère l'ID de l'utilisateur actuel pour vérifier la propriété
   final String? _currentUserId = Supabase.instance.client.auth.currentUser?.id;

   // Retourne une icône basée sur le genre du roman
   IconData _getGenreIcon(String genre) {
      switch (genre.toLowerCase()) {
        case 'aventure': return Icons.explore_outlined;
        case 'romance': return Icons.favorite_border;
        case 'science-fiction': return Icons.rocket_launch_outlined;
        case 'fantasy': return Icons.fort_outlined;
        case 'mystère': return Icons.search_outlined;
        case 'historique': return Icons.account_balance_outlined;
        case 'slice of life': return Icons.cottage_outlined;
        case 'horreur': return Icons.bug_report_outlined;
        case 'philosophie': return Icons.psychology_outlined;
        case 'poésie': return Icons.edit_note_outlined;
        case 'thriller': return Icons.movie_filter_outlined;
        case 'western': return Icons.public_outlined;
        case 'smut': return Icons.whatshot_outlined; // Icône suggestive
        default: return Icons.book_outlined; // Icône par défaut
      }
   }

   // --- Affichage du menu contextuel (appui long) ---
   Future<void> _manageCover() async {
    final currentContext = context; // Capture le contexte avant les opérations asynchrones
    if (!currentContext.mounted) return; // Vérifie si le widget est toujours là

    final bool isOwner = widget.novel.user_id == _currentUserId; // Est-ce le propriétaire ?

    showModalBottomSheet(
      context: currentContext,
      builder: (BuildContext sheetContext) {
        return SafeArea( // Assure que le contenu ne va pas sous les barres système
          child: Wrap( // Utilise Wrap pour s'adapter à la hauteur du contenu
            children: <Widget>[
              // --- Options toujours visibles ---
              ListTile(
                 leading: const Icon(Icons.info_outline),
                 title: const Text('Détails du roman'),
                 onTap: () {
                    Navigator.pop(sheetContext); // Ferme le bottom sheet
                    _showNovelDetailsDialog(currentContext, widget.novel); // Appel de la fonction helper
                 },
              ),
              const Divider(height: 1),

              // --- Options réservées au propriétaire ---
              if (isOwner) ...[
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Modifier les détails'),
                  onTap: () async {
                    Navigator.pop(sheetContext); // Ferme le sheet
                    // Navigue vers la page d'édition
                    await Navigator.push<void>(
                      currentContext,
                      MaterialPageRoute(builder: (context) => EditNovelPage(novel: widget.novel)),
                    );
                    // L'invalidation du novelsProvider rafraîchira si nécessaire
                  },
                ),
                // ✅ NOUVELLE OPTION DE RÉORGANISATION
                if (widget.novel.chapters.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.swap_vert_outlined),
                    title: const Text('Réorganiser les chapitres'),
                    onTap: () {
                      Navigator.pop(sheetContext); // Ferme le sheet
                      // Appelle la fonction pour ouvrir le dialogue de glisser-déposer
                      (_manageCoverState()._showReorderChaptersDialog(currentContext, widget.novel));
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.image_search_outlined), // Icône plus pertinente
                  title: Text(widget.novel.coverImagePath != null ? 'Changer la couverture' : 'Ajouter une couverture'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _addOrChangeCover(); // Appelle la fonction de gestion de couverture
                  },
                ),
                // Option pour supprimer la couverture seulement si elle existe
                if (widget.novel.coverImagePath != null)
                  ListTile(
                    leading: Icon(Icons.hide_image_outlined, color: Colors.orange.shade700), // Icône différente
                    title: Text('Supprimer la couverture', style: TextStyle(color: Colors.orange.shade700)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _deleteCover(); // Appelle la fonction de suppression de couverture
                    },
                  ),
                const Divider(height: 1),
                 // Option de Partage
                 ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Partager / Gérer l\'accès'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    // Ouvre le dialogue de partage spécifique
                    _showShareDialog(currentContext, widget.novel.id, widget.novel.title);
                  },
                ),
                const Divider(height: 1),
                 // Option de Suppression du roman entier
                 ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
                  title: Text('Supprimer le roman entier', style: TextStyle(color: Colors.red.shade700)),
                  onTap: () async {
                    // Appelle la fonction de confirmation et suppression
                    await _confirmAndDeleteNovel(sheetContext, widget.novel.title, widget.novel.id);
                  },
                ),
              ],

               // --- Option pour quitter le partage (si lecteur invité) ---
              if (!isOwner) ...[
                  ListTile(
                    leading: Icon(Icons.exit_to_app, color: Colors.orange.shade800),
                    title: Text('Quitter ce roman partagé', style: TextStyle(color: Colors.orange.shade800)),
                    onTap: () async {
                       Navigator.pop(sheetContext); // Ferme le sheet d'abord
                       await _confirmAndLeaveSharedNovel(currentContext, widget.novel.id, widget.novel.title);
                    },
                  ),
              ]
            ],
          ),
        );
      },
    );
  }

  // Helper pour accéder à l'état parent
  _HomePageState _manageCoverState() {
     // Nécessaire pour appeler _showReorderChaptersDialog qui est dans _HomePageState
     return context.findAncestorStateOfType<_HomePageState>()!;
  }

  // --- Fonctions d'action du menu ---

  // Placeholder pour l'ajout/modification de couverture
  Future<void> _addOrChangeCover() async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fonctionnalité de couverture à venir !"), backgroundColor: Colors.blueAccent),
      );
  }

  // Placeholder pour la suppression de couverture
  Future<void> _deleteCover() async {
     if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fonctionnalité de couverture à venir !"), backgroundColor: Colors.blueAccent),
      );
  }

  // Dialogue de confirmation avant suppression du roman
   Future<void> _confirmAndDeleteNovel(BuildContext sheetContext, String novelTitle, String novelId) async {
      // Capture les contextes nécessaires avant les opérations
      final currentNavContext = Navigator.of(sheetContext);
      final parentScaffoldMessenger = ScaffoldMessenger.of(context);
      final currentRef = ref;

      // Ferme le bottom sheet
      currentNavContext.pop();

      // Affiche le dialogue de confirmation en utilisant le contexte parent
      final bool? confirmDelete = await ConfirmDialog.show(
        context,
        title: 'Confirmer la suppression',
        content: 'Voulez-vous vraiment supprimer le roman "$novelTitle" et tous ses chapitres ? Cette action est irréversible.',
        confirmLabel: 'Supprimer',
        isDangerous: true,
      );

      // Vérifie si la suppression est confirmée ET si le widget est toujours monté
      if (confirmDelete != true || !mounted) return;

      try {
        // Ajoute la tâche de suppression pour le backend local
        final syncTask = SyncTask(action: 'delete_novel', novelId: novelId);
        await currentRef.read(syncServiceProvider).addTask(syncTask);
        // Supprime de Supabase et de l'état local
        await currentRef.read(novelsProvider.notifier).deleteNovel(novelId);

        // Affiche la confirmation (si toujours monté)
        if (mounted) {
          parentScaffoldMessenger.showSnackBar(
             SnackBar(content: Text('Roman "$novelTitle" supprimé.'), backgroundColor: Colors.green)
          );
        }
      } catch (e) {
        AppLogger.error("Erreur suppression roman", error: e, tag: "HomePage");
        // Affiche l'erreur (si toujours monté)
        if (mounted) {
           parentScaffoldMessenger.showSnackBar(
             SnackBar(content: Text('Erreur lors de la suppression: ${e.toString()}'), backgroundColor: Colors.redAccent)
           );
        }
      }
   }

   // Dialogue de confirmation avant de quitter un roman partagé
   Future<void> _confirmAndLeaveSharedNovel(BuildContext parentContext, String novelId, String novelTitle) async {
       final currentUserId = _currentUserId;
       // Vérifie l'ID et si le widget est monté
       if (currentUserId == null || !parentContext.mounted) return;

       final confirm = await ConfirmDialog.show(
         parentContext,
         title: "Quitter le roman ?",
         content: "Voulez-vous retirer \"$novelTitle\" de votre bibliothèque ? Vous n'y aurez plus accès à moins d'être réinvité.",
         confirmLabel: "Quitter",
         isDangerous: true,
       );

       if (confirm == true && parentContext.mounted) {
          try {
             // Appelle la révocation sur soi-même
             await ref.read(sharingControllerProvider).revokeReaderAccess(novelId, currentUserId);
              // Affiche confirmation (si toujours monté)
             if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(content: Text("Vous avez quitté le roman \"$novelTitle\"."), backgroundColor: Colors.orange)
                );
             }
             // Rafraîchir la liste des romans pour qu'il disparaisse (déjà fait par revokeReaderAccess)
             // ref.invalidate(novelsProvider);
          } catch (e) {
             AppLogger.error("Erreur en quittant le roman partagé", error: e, tag: "HomePage");
             // Affiche erreur (si toujours monté)
             if (parentContext.mounted) {
               ScaffoldMessenger.of(parentContext).showSnackBar(
                 SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
               );
             }
          }
       }
   }


   // Dialogue pour afficher les détails du roman (simplifié)
    void _showNovelDetailsDialog(BuildContext context, Novel novel) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(novel.title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Genre: ${novel.genre}'),
                Text('Langue: ${novel.language} (${novel.level})'),
                Text('Écrivain: ${kWritersMap[novel.modelId]?['name'] ?? novel.modelId ?? 'Inconnu'}'),
                const SizedBox(height: 10),
                Text('Spécifications:', style: theme.textTheme.labelMedium),
                Text(novel.specifications.isNotEmpty ? novel.specifications : 'Aucune'),
                 const SizedBox(height: 10),
                Text('Trame évolutive: ${novel.isDynamicOutline ? "Oui" : "Non"}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }


   // Dialogue de Partage
   void _showShareDialog(BuildContext parentContext, String novelId, String novelTitle) {
    // Lire les controllers une seule fois
    final sharingController = ref.read(sharingControllerProvider);
    final friendsController = ref.read(friendsControllerProvider); // Pour vérifier si on appelle la bonne fonction

    // Utiliser watch pour réagir aux changements
    final friendsAsync = ref.watch(friendsListProvider);
    final collaboratorsAsync = ref.watch(novelCollaboratorsProvider(novelId));

    String? selectedFriendId;
    bool isSharingLoading = false;
    Map<String, bool> isRevokingLoadingMap = {};

    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isLoadingOverall = isSharingLoading || isRevokingLoadingMap.containsValue(true);

            return AlertDialog(
              title: Text('Partager "$novelTitle"'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Partager avec un ami :", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),

                      // --- Section Sélection Ami ---
                      Consumer(builder: (context, ref, _) {
                        final currentFriendsAsync = ref.watch(friendsListProvider);
                        final currentCollaboratorsAsync = ref.watch(novelCollaboratorsProvider(novelId));

                        return currentFriendsAsync.when(
                           loading: () => const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Text("Chargement amis...", style: TextStyle(fontStyle: FontStyle.italic)))),
                           error: (err, stack) => Text("Erreur chargement amis: $err", style: const TextStyle(color: Colors.red)),
                           data: (friends) {
                             if (friends.isEmpty) {
                               return Column(
                                 children: [
                                   const Text("Vous n'avez aucun ami à inviter.", style: TextStyle(fontStyle: FontStyle.italic)),
                                   TextButton(
                                     child: const Text("Ajouter des amis ?"),
                                     onPressed: isLoadingOverall ? null : (){
                                          Navigator.pop(dialogContext);
                                          Navigator.push(parentContext, MaterialPageRoute(builder: (_) => const FriendsPage()));
                                     },
                                   )
                                 ],
                               );
                             }

                             // Filtrer les amis déjà collaborateurs
                              final currentCollaboratorIds = currentCollaboratorsAsync.valueOrNull?.map((c) => c.userId).toSet() ?? {};
                              final availableFriends = friends.where((f) => !currentCollaboratorIds.contains(f.friendProfile.id)).toList();

                             if (availableFriends.isEmpty) {
                                 return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text("Tous vos amis ont déjà accès.", style: TextStyle(fontStyle: FontStyle.italic)),
                                );
                             }

                             // Liste déroulante
                             return DropdownButtonFormField<String>(
                               value: selectedFriendId,
                               hint: const Text('Sélectionnez un ami'),
                               isExpanded: true,
                               items: availableFriends.map((friendship) {
                                 return DropdownMenuItem<String>(
                                   value: friendship.friendProfile.id,
                                   child: Text(
                                      friendship.friendProfile.fullName.isNotEmpty
                                          ? friendship.friendProfile.fullName
                                          : friendship.friendProfile.email,
                                      overflow: TextOverflow.ellipsis
                                   ),
                                 );
                               }).toList(),
                               onChanged: isLoadingOverall ? null : (value) {
                                 setStateDialog(() => selectedFriendId = value);
                               },
                               validator: (value) => value == null ? 'Choisissez un ami' : null,
                               decoration: const InputDecoration(
                                 prefixIcon: Icon(Icons.person_outline),
                                 contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
                                 border: OutlineInputBorder(),
                               ),
                             );
                           }
                        );
                      }),
                      const SizedBox(height: 15),

                      // Bouton Partager
                      Consumer(builder: (context, ref, _) {
                        final friendsExist = ref.watch(friendsListProvider).maybeWhen(data: (f) => f.isNotEmpty, orElse: () => false);
                        return friendsExist
                           ? Center(
                             child: ElevatedButton.icon(
                               icon: isSharingLoading
                                   ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                   : const Icon(Icons.send_outlined, size: 18),
                               label: Text(isSharingLoading ? 'Partage...' : 'Partager en lecture'),
                               onPressed: (isLoadingOverall || selectedFriendId == null) ? null : () async {
                                 if (selectedFriendId != null) {
                                   setStateDialog(() => isSharingLoading = true);
                                   try {
                                     AppLogger.info("Appel de shareWithFriend pour $selectedFriendId", tag: "ShareDialog");
                                     await sharingController.shareWithFriend(novelId, selectedFriendId!);
                                     final friendName = ref.read(friendsListProvider).value?.firstWhereOrNull((f) => f.friendProfile.id == selectedFriendId!)?.friendProfile.fullName ?? 'cet ami';
                                     if (parentContext.mounted) {
                                        ScaffoldMessenger.of(parentContext).showSnackBar(
                                          SnackBar(content: Text("Roman partagé avec $friendName !"), backgroundColor: Colors.green)
                                        );
                                     }
                                     setStateDialog((){ selectedFriendId = null; });
                                   } catch (e) {
                                      AppLogger.error("Erreur partage", error: e, tag: "ShareDialog");
                                      if (parentContext.mounted) {
                                         ScaffoldMessenger.of(parentContext).showSnackBar(
                                          SnackBar(content: Text("Erreur partage: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString()}"), backgroundColor: Colors.redAccent)
                                        );
                                      }
                                   } finally {
                                       // Utiliser try-finally pour s'assurer que l'état de chargement est réinitialisé
                                       if(mounted) { // Vérifier si le widget StatefulBuilder est toujours monté
                                            setStateDialog(() => isSharingLoading = false);
                                       }
                                   }
                                 }
                               },
                             ),
                           )
                           : const SizedBox.shrink();
                      }),
                      const Divider(height: 30),

                      // --- Section Collaborateurs Actuels ---
                      const Text("Personnes ayant accès :", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Consumer(builder: (context, ref, _) {
                        final currentCollaboratorsAsync = ref.watch(novelCollaboratorsProvider(novelId));
                        return currentCollaboratorsAsync.when(
                           loading: () {
                             AppLogger.info("Collaborators: Loading", tag: "ShareDialog");
                             return const SizedBox(
                                height: 50,
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2))
                             );
                           },
                           error: (err, stack) {
                             AppLogger.error("Collaborators: Error", error: err, stackTrace: stack, tag: "ShareDialog");
                             return Text("Erreur chargement accès: $err", style: const TextStyle(color: Colors.red));
                           },
                           data: (collaborators) {
                             AppLogger.info("Collaborators: Data loaded (${collaborators.length})", tag: "ShareDialog");
                             if (collaborators.isEmpty) {
                               return const Padding(
                                 padding: EdgeInsets.symmetric(vertical: 8.0),
                                 child: Text("Personne n'a accès (à part vous).", style: TextStyle(fontStyle: FontStyle.italic)),
                               );
                             }
                             // Utilisation de Column
                             return Column(
                               mainAxisSize: MainAxisSize.min,
                               children: collaborators.map((collab) {
                                 final isRevokingThisOne = isRevokingLoadingMap[collab.userId] ?? false;
                                 return ListTile(
                                   dense: true,
                                   leading: const Icon(Icons.person_outline, size: 20),
                                   title: Text(collab.displayName, style: const TextStyle(fontSize: 14)),
                                   trailing: IconButton(
                                     icon: isRevokingThisOne
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                          : Icon(Icons.person_remove_outlined, color: Colors.redAccent.withOpacity(0.8), size: 22),
                                     tooltip: 'Révoquer l\'accès',
                                     onPressed: (isLoadingOverall || isRevokingThisOne) ? null : () async {
                                         final confirm = await ConfirmDialog.show(
                                             parentContext,
                                             title: "Révoquer l'accès ?",
                                             content: "Voulez-vous retirer l'accès en lecture à ${collab.displayName} ?",
                                             confirmLabel: "Révoquer",
                                             isDangerous: true
                                         );
                                         if (confirm == true && mounted) {
                                             setStateDialog(() => isRevokingLoadingMap[collab.userId] = true);
                                             try {
                                                 // ✅ VÉRIFICATION ET LOG: S'assurer qu'on appelle la bonne fonction
                                                 AppLogger.info("Appel de revokeReaderAccess pour ${collab.userId}", tag: "ShareDialog");
                                                 // await friendsController.removeOrRejectFriendship(collab.userId); // <- LIGNE INCORRECTE (exemple de ce qu'il ne faut PAS faire)
                                                 await sharingController.revokeReaderAccess(novelId, collab.userId); // <- LIGNE CORRECTE

                                                 if (parentContext.mounted) {
                                                     ScaffoldMessenger.of(parentContext).showSnackBar(
                                                       SnackBar(content: Text("Accès de ${collab.displayName} révoqué."), backgroundColor: Colors.orange)
                                                     );
                                                 }
                                             } catch (e) {
                                                 AppLogger.error("Erreur révocation", error: e, tag: "ShareDialog");
                                                 if (parentContext.mounted) {
                                                     ScaffoldMessenger.of(parentContext).showSnackBar(
                                                       SnackBar(content: Text("Erreur révocation: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString()}"), backgroundColor: Colors.redAccent)
                                                     );
                                                 }
                                             } finally {
                                                 // Utiliser try-finally pour garantir la réinitialisation de l'état
                                                 if(mounted) { // Vérifier si StatefulBuilder est monté
                                                     setStateDialog(() => isRevokingLoadingMap.remove(collab.userId));
                                                 }
                                             }
                                         }
                                     },
                                   ),
                                   contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                                 );
                               }).toList(),
                             );
                           },
                        );
                      }), // Fin Consumer pour liste collaborateurs
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoadingOverall ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        );
      },
    );
  }


   // --- Construction de l'UI de la carte ---
   @override
   Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverPath = widget.novel.coverImagePath;
    final bool doesCoverExist = coverPath != null && coverPath.startsWith('http');
    final bool isOwner = widget.novel.user_id == _currentUserId; // Est-ce le propriétaire ?

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovering ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          onTap: () async {
             final vocabularyService = ref.read(vocabularyServiceProvider);
             // Utiliser l'instance globale themeService définie dans providers.dart
             final themeServiceInstance = themeService;
             final currentNavContext = Navigator.of(context);
             final currentRef = ref;

             await currentNavContext.push<void>(
               MaterialPageRoute(
                 builder: (context) => NovelReaderPage(
                   novelId: widget.novel.id,
                   vocabularyService: vocabularyService,
                   themeService: themeServiceInstance, // Passer l'instance ThemeService
                 ),
               ),
             );
             if(mounted) {
                currentRef.invalidate(novelsProvider);
             }
          },
          onLongPress: _manageCover,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Card(
                      elevation: _isHovering ? 6 : 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias,
                      child: doesCoverExist
                          ? CachedCoverImage(imageUrl: coverPath!, fit: BoxFit.cover)
                          : Container(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      _getGenreIcon(widget.novel.genre),
                                      size: 50,
                                      color: theme.colorScheme.primary.withOpacity(0.8)
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text(
                                      widget.novel.genre,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (!isOwner)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Tooltip(
                          message: 'Partagé avec vous',
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.people_alt_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0, left: 4.0, right: 4.0),
                    child: Text(
                      widget.novel.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.2
                      ),
                    ),
                  ),
                   Container(
                     height: 3,
                     width: 80,
                     margin: const EdgeInsets.only(top: 4),
                     decoration: BoxDecoration(
                       color: theme.cardTheme.color?.withOpacity(0.5) ?? theme.colorScheme.surfaceVariant.withOpacity(0.4),
                       borderRadius: BorderRadius.circular(2),
                       boxShadow: [
                         BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1)
                         )
                       ]
                     ),
                   ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} // Fin _NovelCoverItemState