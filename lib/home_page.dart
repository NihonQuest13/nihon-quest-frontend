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
        debugPrint("[HomePage Listener] Serveur connecté. Lancement de la synchronisation de démarrage et traitement file.");
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
    final pendingRequestsCount = ref.watch(pendingFriendRequestsProvider).when(
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
        // Optionnel: Style pour l'AppBar (peut être défini dans AppTheme)
        // backgroundColor: theme.appBarTheme.backgroundColor,
        // elevation: theme.appBarTheme.elevation,
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
                Text('$err', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                 const SizedBox(height: 24),
                 ElevatedButton.icon(
                   icon: const Icon(Icons.refresh),
                   label: const Text('Rafraîchir'),
                   onPressed: () => ref.invalidate(novelsProvider), // Invalide le provider pour retenter le fetch
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
                ref.invalidate(friendsListProvider); // Recharge les amis
                ref.invalidate(pendingFriendRequestsProvider); // Recharge les demandes
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

  // ==================== MÉTHODES DE CONSTRUCTION UI ====================

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
      debugPrint('Erreur vérification admin: $e');
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
        // Optionnel: Ajouter un bouton d'action ici si désiré
        // action: ElevatedButton.icon(
        //   icon: const Icon(Icons.add),
        //   label: const Text('Créer un roman'),
        //   onPressed: _navigateToCreateNovel,
        // ),
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
    // Bien que la création se fasse maintenant via un dialogue, on garde la structure
    await Navigator.push<Novel?>(
      context,
      MaterialPageRoute(builder: (context) => const create.CreateNovelPage()),
    );
    // Après le retour de CreateNovelPage (même si annulé), on rafraîchit la liste
    // pour s'assurer que l'UI est à jour (au cas où la création aurait réussi
    // mais la navigation retour aurait été rapide).
    if (mounted) {
       ref.invalidate(novelsProvider);
    }
    // L'ancienne logique _handleNovelCreation et _showStreamingDialog n'est plus ici,
    // elle est gérée entièrement dans CreateNovelPage.
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
                               TextSpan(text: "Coûts & Utilisation : ", style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: "L'utilisation des modèles IA a un coût (calcul, énergie). Les modèles marqués ':free' sont généralement moins chers ou gratuits dans certaines limites via des services comme OpenRouter, mais peuvent être plus lents ou sujets à des quotas.\n\n"),
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
                    // TODO: Implémenter une fonction/dialogue pour afficher les détails complets
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
                    // Pas besoin de refresh ici, la page d'accueil le fera au retour si nécessaire
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
                    // Gère la fermeture du sheet à l'intérieur
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

  // --- Fonctions d'action du menu ---

  // Placeholder pour l'ajout/modification de couverture
  Future<void> _addOrChangeCover() async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fonctionnalité de couverture à venir !"), backgroundColor: Colors.blueAccent),
      );
      // TODO: Implémenter la logique d'upload/sélection d'image et mise à jour Supabase
  }

  // Placeholder pour la suppression de couverture
  Future<void> _deleteCover() async {
     if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fonctionnalité de couverture à venir !"), backgroundColor: Colors.blueAccent),
      );
      // TODO: Implémenter la logique de suppression du fichier dans Supabase Storage et màj BDD
  }

  // Dialogue de confirmation avant suppression du roman
   Future<void> _confirmAndDeleteNovel(BuildContext sheetContext, String novelTitle, String novelId) async {
      final currentNavContext = Navigator.of(sheetContext); // Capture navigator before async
      final currentScaffoldMessenger = ScaffoldMessenger.of(context); // Capture scaffold messenger
      final currentRef = ref; // Capture ref

      // Ferme le bottom sheet d'abord
      currentNavContext.pop();

      final bool? confirmDelete = await ConfirmDialog.show(
        context, // Utilise le contexte principal pour afficher par-dessus
        title: 'Confirmer la suppression',
        content: 'Voulez-vous vraiment supprimer le roman "$novelTitle" et tous ses chapitres ? Cette action est irréversible.',
        confirmLabel: 'Supprimer',
        isDangerous: true,
      );

      // Vérifie si le widget est toujours monté APRÈS l'attente du dialogue
      if (confirmDelete != true || !mounted) return;

      try {
        // Ajoute la tâche de suppression au service de synchronisation (pour le backend local si utilisé)
        final syncTask = SyncTask(action: 'delete_novel', novelId: novelId);
        await currentRef.read(syncServiceProvider).addTask(syncTask);
        // Supprime le roman de l'état local et de Supabase via le notifier
        await currentRef.read(novelsProvider.notifier).deleteNovel(novelId);

        currentScaffoldMessenger.showSnackBar(
           SnackBar(content: Text('Roman "$novelTitle" supprimé.'), backgroundColor: Colors.green)
        );
      } catch (e) {
        debugPrint("Erreur suppression roman: $e");
        // Vérifie à nouveau le montage avant d'afficher le snackbar d'erreur
        if (mounted) {
           currentScaffoldMessenger.showSnackBar(
             SnackBar(content: Text('Erreur lors de la suppression: ${e.toString()}'), backgroundColor: Colors.redAccent)
           );
        }
      }
   }

   // ⭐ NOUVEAU : Dialogue de confirmation avant de quitter un roman partagé
   Future<void> _confirmAndLeaveSharedNovel(BuildContext parentContext, String novelId, String novelTitle) async {
       final currentUserId = _currentUserId;
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
             // Appelle directement la révocation sur soi-même
             await ref.read(sharingControllerProvider).revokeReaderAccess(novelId, currentUserId);
              ScaffoldMessenger.of(parentContext).showSnackBar(
               SnackBar(content: Text("Vous avez quitté le roman \"$novelTitle\"."), backgroundColor: Colors.orange)
             );
             // Rafraîchir la liste des romans pour qu'il disparaisse
             ref.invalidate(novelsProvider);
          } catch (e) {
             if (parentContext.mounted) {
               ScaffoldMessenger.of(parentContext).showSnackBar(
                 SnackBar(content: Text("Erreur: ${e.toString()}"), backgroundColor: Colors.redAccent)
               );
             }
          }
       }
   }


   // ⭐ NOUVEAU : Dialogue pour afficher les détails du roman (simplifié)
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


   // --- Dialogue de Partage (utilise maintenant la liste d'amis) ---
   void _showShareDialog(BuildContext parentContext, String novelId, String novelTitle) {
    final sharingController = ref.read(sharingControllerProvider);
    // ⭐ Récupère l'état actuel du provider des amis (peut être en chargement, erreur, ou data)
    final friendsAsync = ref.watch(friendsListProvider);
    // Provider pour la liste des collaborateurs actuels de CE roman
    final collaboratorsAsync = ref.watch(novelCollaboratorsProvider(novelId));

    String? selectedFriendId; // ID de l'ami sélectionné dans la dropdown
    bool isSharingLoading = false; // Pour le bouton "Partager"
    bool isRevokingLoading = false; // Pour les boutons "Révoquer"

    showDialog(
      context: parentContext,
      // barrierDismissible: !(isSharingLoading || isRevokingLoading), // Empêche de fermer pendant chargement
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // Nécessaire pour gérer isLoading et selectedFriendId
          builder: (context, setStateDialog) {
            final isLoading = isSharingLoading || isRevokingLoading; // État de chargement global du dialogue

            return AlertDialog(
              title: Text('Partager "$novelTitle"'),
              scrollable: true, // Permet au contenu de défiler
              content: SizedBox(
                width: double.maxFinite, // Utilise la largeur max disponible
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Prend la hauteur minimale nécessaire
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Partager avec un ami :", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // --- Section Sélection Ami ---
                    friendsAsync.when(
                       loading: () => const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Text("Chargement amis...", style: TextStyle(fontStyle: FontStyle.italic)))),
                       error: (err, stack) => Text("Erreur chargement amis: $err", style: const TextStyle(color: Colors.red)),
                       data: (friends) {
                         if (friends.isEmpty) {
                           return Column( // Message + lien vers page amis
                             children: [
                               const Text("Vous n'avez aucun ami à inviter.", style: TextStyle(fontStyle: FontStyle.italic)),
                               TextButton(
                                 child: const Text("Ajouter des amis ?"),
                                 onPressed: (){
                                      Navigator.pop(dialogContext); // Ferme dialogue partage
                                      Navigator.push(parentContext, MaterialPageRoute(builder: (_) => const FriendsPage())); // Ouvre page amis
                                 },
                               )
                             ],
                           );
                         }

                         // Filtrer les amis déjà collaborateurs (optionnel, upsert gère les doublons)
                          final currentCollaboratorIds = collaboratorsAsync.valueOrNull?.map((c) => c.userId).toSet() ?? {};
                          final availableFriends = friends.where((f) => !currentCollaboratorIds.contains(f.friendProfile.id)).toList();

                         if(availableFriends.isEmpty && friends.isNotEmpty) {
                             return const Text("Tous vos amis ont déjà accès.", style: TextStyle(fontStyle: FontStyle.italic));
                         }

                         // Liste déroulante des amis disponibles
                         return DropdownButtonFormField<String>(
                           value: selectedFriendId,
                           hint: const Text('Sélectionnez un ami'),
                           isExpanded: true, // Prend toute la largeur
                           items: availableFriends.map((friendship) {
                             return DropdownMenuItem<String>(
                               value: friendship.friendProfile.id,
                               child: Text(
                                  friendship.friendProfile.fullName.isNotEmpty
                                      ? friendship.friendProfile.fullName
                                      : friendship.friendProfile.email, // Affiche nom ou email
                                  overflow: TextOverflow.ellipsis // Empêche le texte long de déborder
                               ),
                             );
                           }).toList(),
                           onChanged: isLoading ? null : (value) {
                             setStateDialog(() => selectedFriendId = value);
                           },
                           validator: (value) => value == null ? 'Choisissez un ami' : null,
                           decoration: const InputDecoration(
                             prefixIcon: Icon(Icons.person_outline),
                             contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
                             border: OutlineInputBorder(), // Style standard
                           ),
                         );
                       }
                    ),
                    const SizedBox(height: 15),
                    // Bouton Partager (centré)
                    if (friendsAsync.hasValue && friendsAsync.value!.isNotEmpty) // Affiche seulement si des amis sont chargeables
                       Center(
                         child: ElevatedButton.icon(
                           icon: isSharingLoading
                               ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                               : const Icon(Icons.send_outlined, size: 18),
                           label: Text(isSharingLoading ? 'Partage...' : 'Partager en lecture'),
                           // Désactivé si chargement ou aucun ami sélectionné
                           onPressed: (isLoading || selectedFriendId == null) ? null : () async {
                             if (selectedFriendId != null) {
                               setStateDialog(() => isSharingLoading = true);
                               try {
                                 await sharingController.shareWithFriend(novelId, selectedFriendId!);
                                 // Trouve le nom de l'ami pour le message
                                 final friendName = friendsAsync.value?.firstWhereOrNull((f) => f.friendProfile.id == selectedFriendId!)?.friendProfile.fullName ?? 'cet ami';
                                  ScaffoldMessenger.of(parentContext).showSnackBar(
                                   SnackBar(content: Text("Roman partagé avec $friendName !"), backgroundColor: Colors.green)
                                 );
                                 // Réinitialise la sélection et rafraîchit la liste des collaborateurs
                                 setStateDialog((){ selectedFriendId = null; });
                                  ref.invalidate(novelCollaboratorsProvider(novelId)); // Force le rebuild du FutureBuilder

                               } catch (e) {
                                  ScaffoldMessenger.of(parentContext).showSnackBar(
                                   SnackBar(content: Text("Erreur partage: ${e.toString()}"), backgroundColor: Colors.redAccent)
                                 );
                               } finally {
                                    // Vérifier si le dialogue est toujours monté
                                    try {
                                       if(Navigator.of(context).canPop()) { // Utilise le context du StatefulBuilder
                                            setStateDialog(() => isSharingLoading = false);
                                       }
                                    } catch (e) { /* Gère l'erreur si le contexte n'est plus valide */ }
                               }
                             }
                           },
                         ),
                       ),
                    const Divider(height: 30),

                    // --- Section Collaborateurs Actuels ---
                    const Text("Personnes ayant accès :", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    // Affiche la liste des collaborateurs actuels
                    collaboratorsAsync.when(
                       loading: () => const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2))),
                       error: (err, stack) => Text("Erreur chargement accès: $err", style: const TextStyle(color: Colors.red)),
                       data: (collaborators) {
                         if (collaborators.isEmpty) {
                           return const Text("Personne n'a accès à ce roman (à part vous).", style: TextStyle(fontStyle: FontStyle.italic));
                         }
                         // Liste des personnes ayant accès
                         return ConstrainedBox(
                           constraints: const BoxConstraints(maxHeight: 150), // Limite la hauteur
                           child: ListView.builder(
                             shrinkWrap: true, // S'adapte à la hauteur du contenu
                             itemCount: collaborators.length,
                             itemBuilder: (context, index) {
                               final collab = collaborators[index];
                               return ListTile(
                                 dense: true, // Rend la ligne moins haute
                                 leading: const Icon(Icons.person_outline, size: 20),
                                 title: Text(collab.displayName, style: const TextStyle(fontSize: 14)),
                                 // Affiche le rôle (sera 'reader' pour l'instant)
                                 // subtitle: Text("Rôle : ${collab.role}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                 trailing: IconButton(
                                   icon: isRevokingLoading // Affiche indicateur si en cours de révocation pour CET utilisateur
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Icon(Icons.person_remove_outlined, color: Colors.redAccent.withOpacity(0.8), size: 22),
                                   tooltip: 'Révoquer l\'accès',
                                   // Désactivé pendant toute opération de chargement
                                   onPressed: isLoading ? null : () async {
                                       // Confirmation avant de révoquer
                                       final confirm = await ConfirmDialog.show(
                                           parentContext, // Contexte parent pour afficher par-dessus
                                           title: "Révoquer l'accès ?",
                                           content: "Voulez-vous retirer l'accès en lecture à ${collab.displayName} ?",
                                           confirmLabel: "Révoquer",
                                           isDangerous: true
                                       );
                                       if (confirm == true) {
                                           setStateDialog(() => isRevokingLoading = true);
                                           try {
                                               await sharingController.revokeReaderAccess(novelId, collab.userId);
                                                ScaffoldMessenger.of(parentContext).showSnackBar(
                                                 SnackBar(content: Text("Accès de ${collab.displayName} révoqué."), backgroundColor: Colors.orange)
                                               );
                                               // Rafraîchit la liste des collaborateurs
                                                ref.invalidate(novelCollaboratorsProvider(novelId));
                                                // Potentiellement rafraîchir la liste d'amis disponibles si l'UI le nécessite
                                                // setStateDialog((){}); // Déclenché par l'invalidation

                                           } catch (e) {
                                                ScaffoldMessenger.of(parentContext).showSnackBar(
                                                 SnackBar(content: Text("Erreur révocation: ${e.toString()}"), backgroundColor: Colors.redAccent)
                                               );
                                           } finally {
                                               try {
                                                 if(Navigator.of(context).canPop()) { // Contexte du StatefulBuilder
                                                    setStateDialog(() => isRevokingLoading = false);
                                                 }
                                               } catch(e) {}
                                           }
                                       }
                                   },
                                 ),
                                 contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0), // Padding réduit
                               );
                             },
                           ),
                         );
                       },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(),
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
      // Change l'apparence au survol (pour web/desktop)
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click, // Curseur main au survol
      child: AnimatedScale(
        scale: _isHovering ? 1.03 : 1.0, // Léger agrandissement au survol
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          // Navigation vers le lecteur au clic simple
          onTap: () async {
             final vocabularyService = ref.read(vocabularyServiceProvider);
             // Note: themeService est maintenant global via le provider
             final currentNavContext = Navigator.of(context); // Capture navigator before async gap
             final currentRef = ref; // Capture ref

             await currentNavContext.push<void>(
               MaterialPageRoute(
                 builder: (context) => NovelReaderPage(
                   novelId: widget.novel.id,
                   vocabularyService: vocabularyService,
                   themeService: themeService, // Pass themeService instance
                 ),
               ),
             );
             // Après le retour du lecteur, rafraîchit la liste des romans
             // Vérifie si le widget est toujours monté
             if(mounted) {
                currentRef.invalidate(novelsProvider);
             }
          },
          // Affiche le menu contextuel à l'appui long
          onLongPress: _manageCover,
          // ✅ CORRECTION: Utilisation de Column pour centrer verticalement
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // Aligne en haut
            crossAxisAlignment: CrossAxisAlignment.stretch, // Étire les enfants horizontalement
            children: [
              // La couverture ou le placeholder
              Expanded(
                child: Stack(
                  fit: StackFit.expand, // Le Stack prend toute la place de l'Expanded
                  children: [
                    // Carte contenant l'image ou le placeholder
                    Card(
                      elevation: _isHovering ? 6 : 3, // Ombre plus marquée au survol
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias, // Pour arrondir l'image
                      child: doesCoverExist
                          // Affiche l'image en cache si elle existe
                          ? CachedCoverImage(imageUrl: coverPath!, fit: BoxFit.cover)
                          // Sinon, affiche un placeholder avec icône et genre
                          : Container(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.5), // Fond léger
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon( // Icône basée sur le genre
                                      _getGenreIcon(widget.novel.genre),
                                      size: 50, // Taille de l'icône
                                      color: theme.colorScheme.primary.withOpacity(0.8) // Couleur thème
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text( // Nom du genre
                                      widget.novel.genre,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant, // Couleur texte secondaire
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    // Icône "Partagé" si l'utilisateur n'est pas le propriétaire
                    if (!isOwner)
                      Positioned(
                        top: 6, // Positionnement
                        left: 6,
                        child: Tooltip( // Ajout d'un tooltip
                          message: 'Partagé avec vous',
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65), // Fond semi-transparent
                              shape: BoxShape.circle, // Forme ronde
                            ),
                            child: const Icon(
                              Icons.people_alt_outlined, // Icône de groupe
                              color: Colors.white,
                              size: 16, // Taille de l'icône
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ✅ CORRECTION: Utilisation de Column pour le titre et l'étagère
              Column(
                mainAxisSize: MainAxisSize.min, // Prend la hauteur minimale
                children: [
                  // Titre du roman sous la couverture
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0, left: 4.0, right: 4.0), // Espace au-dessus et sur les côtés
                    child: Text(
                      widget.novel.title,
                      textAlign: TextAlign.center, // Centré
                      maxLines: 2, // Max 2 lignes
                      overflow: TextOverflow.ellipsis, // Points de suspension si trop long
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500, // Semi-gras
                          height: 1.2 // Interligne réduit
                      ),
                    ),
                  ),
                   // ✅ NOUVEAU: Effet étagère
                   Container(
                     height: 3, // Hauteur de l'étagère
                     width: 80, // Largeur de l'étagère (ajuster selon vos préférences)
                     margin: const EdgeInsets.only(top: 4), // Espace entre titre et étagère
                     decoration: BoxDecoration(
                       // Couleur de l'étagère (légèrement plus sombre que le fond de la carte)
                       color: theme.cardTheme.color?.withOpacity(0.5) ?? theme.colorScheme.surfaceVariant.withOpacity(0.4),
                       borderRadius: BorderRadius.circular(2), // Bords arrondis
                       boxShadow: [ // Légère ombre pour donner du relief
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