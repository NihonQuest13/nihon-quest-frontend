// lib/home_page.dart (REFACTORISÉ ET CORRIGÉ)
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controllers/home_controller.dart';
import 'create_novel_page.dart' as create;
import 'edit_novel_page.dart';
import 'models.dart';
import 'novel_reader_page.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/sync_service.dart';
import 'services/startup_service.dart';
import 'services/vocabulary_service.dart'; // ✅ Import nécessaire
import 'widgets/streaming_text_widget.dart';

class HomePage extends ConsumerStatefulWidget {
  
  // ✅ OPTIMISATION : Utiliser un constructeur const simple.
  const HomePage({ super.key });

  // ⛔️ Les services requis dans le constructeur ont été supprimés.
  // final VocabularyService vocabularyService;
  // final ThemeService themeService;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late HomeController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeController();
    });
  }

  void _initializeController() {
    if (!mounted) return;
    // 'ref' est automatiquement disponible dans ConsumerState
    _controller = HomeController(ref, context);
    _controller.checkBackendStatus();
  }

  @override
  Widget build(BuildContext context) {
    // Écoute les changements de statut du serveur
    ref.listen<ServerStatus>(serverStatusProvider, (previous, next) async {
      if (next == ServerStatus.connected) {
        debugPrint("[HomePage Listener] Serveur connecté. Lancement de la synchronisation de démarrage.");
        // ✅ Lire les services directement depuis 'ref'
        await ref.read(startupServiceProvider).synchronizeOnStartup();
        ref.read(syncServiceProvider).processQueue();
      }
    });

    final theme = Theme.of(context);
    final novelsAsyncValue = ref.watch(novelsProvider);
    final isDarkMode = ref.watch(themeServiceProvider) == ThemeMode.dark;
    final serverStatus = ref.watch(serverStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma bibliothèque'),
        centerTitle: true,
        leadingWidth: 120,
        leading: _buildLeadingActions(serverStatus),
        actions: _buildAppBarActions(isDarkMode),
      ),
      body: novelsAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Erreur: $err')),
        data: (novels) {
          if (novels.isEmpty) {
            return _buildEmptyState(theme);
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(novelsProvider.notifier).refresh(),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: novels.length,
              itemBuilder: (context, index) {
                final novel = novels[index];
                return Column(
                  children: [
                    Expanded(
                      // ✅ OPTIMISATION : Ne plus passer les services.
                      child: _NovelCoverItem(
                        novel: novel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: theme.dividerColor.withAlpha(128)),
                  ],
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildLeadingActions(ServerStatus serverStatus) {
    return Row(
      children: [
        const SizedBox(width: 8),
        Tooltip(
          message: switch (serverStatus) {
            ServerStatus.connecting => "Connexion au serveur distant...",
            ServerStatus.connected => 'Connecté au serveur distant',
            ServerStatus.failed => 'Serveur distant déconnecté. Vérifiez que le backend Python est lancé.',
          },
          child: IconButton(
            icon: switch (serverStatus) {
              ServerStatus.connecting => const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ServerStatus.connected => const Icon(Icons.cloud_done_rounded, color: Colors.green),
              ServerStatus.failed => const Icon(Icons.cloud_off_rounded, color: Colors.red),
            },
            onPressed: () => _controller.checkBackendStatus(),
          ),
        ),
        if (serverStatus == ServerStatus.connected)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Forcer la synchronisation avec le serveur',
            onPressed: () => _controller.forceSyncWithServer(),
          ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(bool isDarkMode) {
    return [
      IconButton(
        icon: Icon(isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
        tooltip: 'Changer de thème',
        onPressed: () {
          ref.read(themeServiceProvider.notifier).updateTheme(
                isDarkMode ? ThemeMode.light : ThemeMode.dark,
              );
        },
      ),
      IconButton(
        icon: const Icon(Icons.info_outline),
        tooltip: 'Informations',
        onPressed: _showHelpDialog,
      ),
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Se déconnecter',
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
        },
      ),
      const SizedBox(width: 8),
    ];
  }

  Widget _buildFloatingActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          FloatingActionButton(
            heroTag: 'sort_button',
            onPressed: _showSortOptions,
            tooltip: 'Trier les romans',
            child: const Icon(Icons.filter_list_rounded),
          ),
          FloatingActionButton(
            heroTag: 'add_button',
            onPressed: _navigateToCreateNovel,
            tooltip: 'Créer un nouveau roman',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              'Votre bibliothèque est vide.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Appuyez sur le bouton + pour commencer une nouvelle histoire.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================

  void _showSortOptions() {
    final currentSort = ref.read(sortOptionProvider);
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: SortOption.values.map((option) {
          return RadioListTile<SortOption>(
            title: Text(_controller.sortOptionToString(option)),
            value: option,
            groupValue: currentSort,
            onChanged: (value) {
              if (value != null) {
                ref.read(sortOptionProvider.notifier).state = value;
              }
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _navigateToCreateNovel() async {
    final newNovel = await Navigator.push<Novel?>(
      context,
      MaterialPageRoute(builder: (context) => const create.CreateNovelPage()),
    );

    if (newNovel != null && mounted) {
      await _handleNovelCreation(newNovel);
    }
  }

  Future<void> _handleNovelCreation(Novel newNovel) async {
    if (!mounted) return;

    try {
      final chapterText = await _showStreamingDialog(newNovel);

      if (chapterText == null || chapterText.isEmpty) {
        if (mounted) {
          _showFeedback("Création du roman annulée.", isError: false, color: Colors.grey, duration: 2);
        }
        return;
      }

      await _controller.handleNovelCreation(newNovel, chapterText);

    } catch (e) {
      if (mounted) {
        _showFeedback(
          'Erreur lors de la création du roman : ${e.toString()}',
          isError: true,
          duration: 8,
        );
      }
    }
  }

  Future<String?> _showStreamingDialog(Novel novel) async {
    final prompt = await AIService.preparePrompt(
      novel: novel,
      isFirstChapter: true,
    );

    if (!mounted || prompt.isEmpty) {
      throw Exception("La préparation du prompt a échoué.");
    }

    final stream = AIService.streamChapterFromPrompt(
      prompt: prompt,
      modelId: novel.modelId,
      language: novel.language,
    );

    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: AlertDialog(
              backgroundColor: Theme.of(dialogContext).colorScheme.surface,
              title: const Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
                  SizedBox(width: 16),
                  Text('Création du premier chapitre...'),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: MediaQuery.of(dialogContext).size.height * 0.6,
                child: StreamingTextAnimation(
                  stream: stream,
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                  onDone: (fullText) {
                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext, fullText);
                    }
                  },
                  onError: (error) {
                    _showFeedback("Erreur de génération : $error", isError: true, duration: 8);
                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext, null);
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext, null);
                    }
                  },
                  child: const Text("Annuler"),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: DefaultTabController(
            length: 5,
            child: AlertDialog(
              title: const Text("Informations sur la bibliothèque magique"),
              contentPadding: const EdgeInsets.only(top: 20.0),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: "Guide"),
                        Tab(text: "Le principe"),
                        Tab(text: "Les écrivains"),
                        Tab(text: "La mémoire"),
                        Tab(text: "À propos de l'IA"),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildHelpTabContent(
                            context,
                            icon: Icons.tour_outlined,
                            title: "Guide d'utilisation",
                            spans: const [
                              TextSpan(text: "Gérer un roman :", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "\nPour modifier un roman, faites un appui long sur sa couverture. Un menu apparaîtra vous permettant d'ajouter, changer ou supprimer la couverture, ainsi que de supprimer le roman entier.\n\n"),
                              TextSpan(text: "Lire un roman :", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "\nUn simple clic sur la couverture d'un roman vous emmène directement à la page de lecture.\n\n"),
                              TextSpan(text: "Trier votre bibliothèque :", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "\nUtilisez le bouton filtre (icône d'entonnoir) en bas à gauche pour organiser vos romans par date, titre ou genre.\n\n"),
                              TextSpan(text: "Créer une histoire :", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "\nLe bouton plus (+) en bas à droite vous ouvre les portes de la création. Remplissez les détails et laissez l'IA écrire le premier chapitre pour vous !\n\n"),
                              TextSpan(text: "Synchronisation :", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "\nL'icône nuage en haut à gauche indique l'état de la connexion au service de mémoire distant. Cliquez sur l'icône de synchronisation à côté pour forcer la réindexation de tous vos chapitres."),
                            ],
                          ),
                          _buildHelpTabContent(
                            context,
                            icon: Icons.auto_stories_outlined,
                            title: "Votre rôle de bibliothécaire",
                            spans: const [
                              TextSpan(text: "Imaginez cette application comme votre propre "),
                              TextSpan(text: "bibliothèque magique", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: ". Vous êtes le "),
                              TextSpan(text: "bibliothécaire", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: " et votre mission est de créer des histoires fascinantes. Vous donnez les grandes lignes (le genre, les personnages, les thèmes) et des "),
                              TextSpan(text: "écrivains fantômes", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: " (nos IA !) rédigent les chapitres pour vous.\n\n"),
                              TextSpan(text: "Votre rôle est de les guider, de corriger leurs écrits et de peaufiner la narration pour qu'elle corresponde parfaitement à votre vision créative. C'est une collaboration magique !"),
                            ],
                          ),
                          _buildHelpTabContent(
                            context,
                            icon: Icons.psychology_outlined,
                            title: "Rencontrez vos écrivains fantômes",
                            spans: const [
                              TextSpan(text: "Chaque roman est écrit par un "),
                              TextSpan(text: "écrivain fantôme", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: " unique, chacun avec son propre style et ses forces :\n\n"),
                              TextSpan(text: "• Le conteur poétique (DeepSeek) : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Réputé pour son style d'écriture riche, son vocabulaire étendu et sa capacité à créer des ambiances profondes. Parfait pour les œuvres littéraires.\n\n"),
                              TextSpan(text: "• Le géant polyglotte (Mistral Nemo) : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Un modèle puissant et multilingue avec une mémoire contextuelle gigantesque. Excellent pour les récits complexes et internationaux.\n\n"),
                              TextSpan(text: "• Le rêveur imaginatif (Qwen) : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Souvent le plus créatif et audacieux, il peut proposer des idées inattendues et des rebondissements surprenants. Pour les histoires qui sortent de l'ordinaire."),
                            ],
                          ),
                          _buildHelpTabContent(
                            context,
                            icon: Icons.memory_outlined,
                            title: "L'index de mémoire de la bibliothèque",
                            spans: const [
                              TextSpan(text: "Comment vos écrivains fantômes se souviennent-ils de tout ? Grâce à l'"),
                              TextSpan(text: "index de mémoire", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: " de la bibliothèque (une technologie appelée FAISS) :\n\n"),
                              TextSpan(text: "1. Cartes mentales : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Chaque chapitre que vous créez est transformé en une "),
                              TextSpan(text: "carte mentale", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                              TextSpan(text: " (un 'vecteur', une série de nombres) qui représente son sens profond. C'est comme si la bibliothèque créait une empreinte unique de chaque page.\n\n"),
                              TextSpan(text: "2. Classement intelligent : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Ces cartes mentales sont stockées dans un ordre spécial. Les chapitres qui parlent de choses similaires se retrouvent 'proches' les uns des autres dans cet index.\n\n"),
                              TextSpan(text: "3. Rappel instantané : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Avant d'écrire un nouveau chapitre, l'écrivain fantôme consulte l'index de mémoire pour retrouver les cartes mentales (chapitres passés) les plus pertinentes. Cela lui permet de se rafraîchir la mémoire et de s'assurer que la suite de l'histoire est logique et cohérente avec ce qui a déjà été écrit. Ainsi, votre livre reste toujours fidèle à lui-même !"),
                            ],
                          ),
                          _buildHelpTabContent(
                            context,
                            icon: Icons.warning_amber_rounded,
                            title: "Quelques mots sur la magie (l'IA)",
                            spans: const [
                              TextSpan(text: "Qualité d'écriture : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "Les écrivains fantômes sont des assistants puissants, mais ils ne sont pas infaillibles. Ils peuvent parfois faire des erreurs, se répéter ou oublier des détails. En tant que bibliothécaire, n'hésitez jamais à éditer leurs écrits ou à leur demander de régénérer un chapitre pour améliorer la qualité de votre livre. C'est votre histoire !\n\n"),
                              TextSpan(text: "Énergie magique : ", style: TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: "L'entraînement et l'utilisation de ces écrivains fantômes consomment une quantité significative d'énergie magique (l'équivalent de l'électricité dans notre monde). En utilisant cette application, vous participez à cette consommation. Il est bon d'en avoir conscience et d'utiliser cette magie à bon escient."),
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

  Widget _buildHelpTabContent(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<InlineSpan> spans,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.secondary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              children: spans,
            ),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  void _showFeedback(
    String message, {
    bool isError = false,
    Color? color,
    int duration = 4,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : (color ?? Colors.green),
        duration: Duration(seconds: duration),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== NOVEL COVER ITEM ====================

// ✅ Doit être un ConsumerStatefulWidget pour accéder à 'ref'
class _NovelCoverItem extends ConsumerStatefulWidget {
  
  // ✅ OPTIMISATION : Utiliser un constructeur const
  const _NovelCoverItem({
    required this.novel,
    // ⛔️ Supprimer les services du constructeur
    // required this.vocabularyService,
    // required this.themeService,
  });

  final Novel novel;
  // ⛔️ Supprimer les variables
  // final VocabularyService vocabularyService;
  // final ThemeService themeService;

  @override
  ConsumerState<_NovelCoverItem> createState() => _NovelCoverItemState();
}

// ✅ Doit être un ConsumerState pour accéder à 'ref'
class _NovelCoverItemState extends ConsumerState<_NovelCoverItem> {
  bool _isHovering = false;

  IconData _getGenreIcon(String genre) {
    switch (genre.toLowerCase()) {
      case 'aventure':
        return Icons.explore_outlined;
      case 'romance':
        return Icons.favorite_border;
      case 'science-fiction':
        return Icons.rocket_launch_outlined;
      case 'fantasy':
        return Icons.fort_outlined;
      case 'mystère':
        return Icons.search_outlined;
      case 'historique':
        return Icons.account_balance_outlined;
      case 'slice of life':
        return Icons.cottage_outlined;
      case 'horreur':
        return Icons.bug_report_outlined;
      case 'philosophie':
        return Icons.psychology_outlined;
      case 'poésie':
        return Icons.edit_note_outlined;
      case 'thriller':
        return Icons.movie_filter_outlined;
      case 'western':
        return Icons.public_outlined;
      case 'smut':
        return Icons.whatshot_outlined;
      case 'autre':
        return Icons.more_horiz_outlined;
      default:
        return Icons.book_outlined;
    }
  }

  Future<void> _manageCover() async {
    final currentContext = context;
    if (!currentContext.mounted) return;

    showModalBottomSheet(
      context: currentContext,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Modifier les détails et l\'écrivain'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Navigator.push<void>(
                    currentContext,
                    MaterialPageRoute(
                      builder: (context) => EditNovelPage(novel: widget.novel),
                    ),
                  );
                  if (mounted) {
                    // ✅ Utiliser 'ref' (disponible dans ConsumerState)
                    ref.read(novelsProvider.notifier).refresh();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(widget.novel.coverImagePath != null
                    ? 'Changer la couverture'
                    : 'Ajouter une couverture'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _addOrChangeCover();
                },
              ),
              if (widget.novel.coverImagePath != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red.shade300),
                  title: Text('Supprimer la couverture',
                      style: TextStyle(color: Colors.red.shade300)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _deleteCover();
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
                title: Text('Supprimer le roman entier',
                    style: TextStyle(color: Colors.red.shade700)),
                onTap: () async {
                  await _confirmAndDeleteNovel(sheetContext, widget.novel.title, widget.novel.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addOrChangeCover() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("La gestion des couvertures sera implémentée bientôt !"),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _deleteCover() async {
    // Logique à adapter pour Supabase Storage
  }

  Future<void> _confirmAndDeleteNovel(
      BuildContext sheetContext, String novelTitle, String novelId) async {
    final currentContext = context;
    if (!currentContext.mounted) return;

    final bool? confirmDelete = await showDialog<bool>(
      context: currentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmer la suppression du roman'),
          content: Text(
              'Voulez-vous vraiment supprimer le roman "$novelTitle" et tous ses chapitres ? Cette action est irréversible.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }

    if (confirmDelete == true) {
      try {
        final syncTask = SyncTask(action: 'delete_novel', novelId: novelId);
        // ✅ Utiliser 'ref' pour lire les providers
        await ref.read(syncServiceProvider).addTask(syncTask);
        await ref.read(novelsProvider.notifier).deleteNovel(novelId);

        if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            SnackBar(
              content: Text('Roman "$novelTitle" supprimé avec succès.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint("Erreur lors de la suppression du roman: $e");
        if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            SnackBar(
              content: Text('Erreur lors de la suppression du roman : $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverPath = widget.novel.coverImagePath;
    final bool doesCoverExist = coverPath != null && coverPath.startsWith('http');

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedScale(
        scale: _isHovering ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: () async {
            // ✅ CORRECTION CLÉ :
            // On lit les services nécessaires depuis 'ref' *au moment du clic*.
            final vocabularyService = ref.read(vocabularyServiceProvider);
            // 'themeService' est l'instance globale importée de providers.dart
            
            final currentContext = context;
            if (!currentContext.mounted) return;
            
            await Navigator.push<void>(
              currentContext,
              MaterialPageRoute(
                builder: (context) => NovelReaderPage(
                  novelId: widget.novel.id,
                  // ✅ On passe les services qu'on vient de lire
                  vocabularyService: vocabularyService,
                  themeService: themeService, // Utilise l'instance globale
                ),
              ),
            );
            if (mounted) {
              ref.read(novelsProvider.notifier).refresh();
            }
          },
          onLongPress: _manageCover,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Card(
                      elevation: _isHovering ? 8 : 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias,
                      child: doesCoverExist
                          ? Image.network(
                              coverPath,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_getGenreIcon(widget.novel.genre),
                                      size: 60, color: theme.colorScheme.primary),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text(
                                      widget.novel.genre,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _isHovering ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                            child: Container(
                              alignment: Alignment.center,
                              color: Colors.black45,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _InfoChip(
                                      icon: Icons.library_books_outlined,
                                      text: '${widget.novel.chapters.length} chapitres',
                                    ),
                                    const SizedBox(height: 8),
                                    _InfoChip(
                                      icon: _getGenreIcon(widget.novel.genre),
                                      text: widget.novel.genre,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 40,
                alignment: Alignment.topCenter,
                child: Text(
                  widget.novel.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}