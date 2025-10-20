// lib/novel_reader_page.dart (CORRIGÉ)
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // ✅ Cet import fonctionnera après le 'pub get'
import 'package:url_launcher/url_launcher.dart'; // ✅ Cet import fonctionnera après le 'pub get'

// ⛔️ import 'main.dart'; // Import inutilisé supprimé
import 'models.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/ai_prompts.dart';
import 'services/vocabulary_service.dart';
import 'services/sync_service.dart';
// ⛔️ import 'services/roadmap_service.dart'; // Import inutilisé supprimé (le provider suffit)
import 'widgets/streaming_text_widget.dart';

// ⛔️ Imports inutilisés supprimés
// import 'utils/error_handler.dart';
// import 'edit_novel_page.dart';
// import 'vocabulary_list_page.dart';


class NovelReaderPage extends ConsumerStatefulWidget {
  final String novelId;
  final VocabularyService vocabularyService;
  final ThemeService themeService;

  const NovelReaderPage({
    super.key,
    required this.novelId,
    required this.vocabularyService,
    required this.themeService,
  });

  @override
  NovelReaderPageState createState() => NovelReaderPageState();
}

class NovelReaderPageState extends ConsumerState<NovelReaderPage> {
  late PageController _pageController;
  int _currentPage = 0;
  final Map<int, ScrollController> _scrollControllers = {};
  final ValueNotifier<double> _chapterProgressNotifier = ValueNotifier(0.0);
  bool _isGeneratingNextChapter = false;
  String _selectedWord = '';
  bool _isLoadingTranslation = false;
  Map<String, String?>? _translationResult;
  Timer? _selectionTimer;
  late SharedPreferences _prefs;
  bool _prefsLoaded = false;
  static const String _prefFontSizeKey = 'reader_font_size_pref';
  double _currentFontSize = 19.0;
  bool _isEditing = false;
  int? _editingChapterIndex;
  late TextEditingController _editingTitleController;
  late TextEditingController _editingContentController;
  late ScrollController _editingScrollController;
  Stream<String>? _chapterStream;
  bool _showUIElements = true;


  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _pageController.addListener(_onPageChanged);
    _editingTitleController = TextEditingController();
    _editingContentController = TextEditingController();
    _editingScrollController = ScrollController();
    _loadPrefsAndInitialData();
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _editingTitleController.dispose();
    _editingContentController.dispose();
    _editingScrollController.dispose();

    _pageController.removeListener(_onPageChanged);
    if (mounted && _pageController.hasClients) {
        _saveCurrentScrollPosition();
        _pageController.dispose();
    }
    _chapterProgressNotifier.dispose();
    for (var controller in _scrollControllers.values) {
      controller.removeListener(_updateScrollProgress);
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  Future<void> _triggerReadingAndTranslation(String word) async {
    if (_isGeneratingNextChapter || !_prefsLoaded) return;
    final trimmedWord = word.trim().replaceAll(RegExp(r'[.,!?"、。」？！]'), '');
    if (trimmedWord.isEmpty || trimmedWord.length > 50) return;
    if (_selectedWord == trimmedWord && _isLoadingTranslation) return;

    if (mounted) {
      setState(() {
        _selectedWord = trimmedWord;
        _isLoadingTranslation = true;
        _translationResult = null;
      });
    }
    HapticFeedback.lightImpact();

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _selectedWord != trimmedWord) return;

    debugPrint("Demande de traduction pour : '$trimmedWord'");
    try {
      final Map<String, String?> result = await AIService.getReadingAndTranslation(trimmedWord, _prefs);
      debugPrint("Résultat traduction reçu: $result");

      if (mounted && _selectedWord == trimmedWord) {
        setState(() {
          _translationResult = result;
          _isLoadingTranslation = false;
        });

        final String? reading = result['reading'];
        final String? translation = result['translation'];
        final novel = await _getNovelFromProvider();
        if (novel?.language == 'Japonais' &&
            reading != null && reading.isNotEmpty &&
            translation != null && translation.isNotEmpty &&
            result['readingError'] == null &&
            result['translationError'] == null)
        {
          final newEntry = VocabularyEntry(word: trimmedWord, reading: reading, translation: translation, createdAt: DateTime.now());
          if (await widget.vocabularyService.addEntry(newEntry) && mounted) {
            _showSnackbarMessage('"$trimmedWord" ajouté au vocabulaire', Colors.blueGrey, durationSeconds: 2);
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur catchée dans _triggerReadingAndTranslation (communication backend): $e");
      if (mounted && _selectedWord == trimmedWord) {
        setState(() {
          _translationResult = {
            'readingError': 'Erreur serveur',
            'translationError': e.toString()
          };
          _isLoadingTranslation = false;
        });
      }
    }
  }

  void _onPageChanged() {
      if (!_pageController.hasClients || _pageController.page == null) return;
      final newPage = _pageController.page!.round();
      if (newPage != _currentPage) {
        _saveCurrentScrollPosition();
        if (mounted) {
            setState(() {
              _currentPage = newPage;
              _selectedWord = '';
              _isLoadingTranslation = false;
              _translationResult = null;
              _selectionTimer?.cancel();
            });
        }
        _saveLastViewedPage(newPage);
        _attachScrollListenerToCurrentPage();
      }
  }

  void _attachScrollListenerToCurrentPage() {
    for (var c in _scrollControllers.values) {
        c.removeListener(_updateScrollProgress);
    }
    final controller = _scrollControllers[_currentPage];
    if (controller != null) {
        controller.addListener(_updateScrollProgress);
        _updateScrollProgress();
    }
  }


  void _updateScrollProgress() {
    final controller = _scrollControllers[_currentPage];
    if (controller != null && controller.hasClients && controller.position.maxScrollExtent > 0) {
      final progress = controller.offset / controller.position.maxScrollExtent;
      _chapterProgressNotifier.value = progress.clamp(0.0, 1.0);
    } else {
      _chapterProgressNotifier.value = 0.0;
    }
  }

  Future<void> _loadPrefsAndInitialData() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    _currentFontSize = _prefs.getDouble(_prefFontSizeKey) ?? 19.0;

    final novel = await _getNovelFromProvider();
    if (novel == null || !mounted) return;

    int lastViewedPage = _prefs.getInt('last_page_${widget.novelId}') ?? 0;
    int initialPage = 0;
    if (novel.chapters.isNotEmpty) {
      if (lastViewedPage >= 0 && lastViewedPage < novel.chapters.length) {
        initialPage = lastViewedPage;
      }
    } else {
      initialPage = -1;
    }

    if (mounted) {
      setState(() {
        _currentPage = initialPage;
        _prefsLoaded = true;
      });
      _pageController = PageController(initialPage: max(0, _currentPage));
      _pageController.addListener(_onPageChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _currentPage != -1) {
          _pageController.jumpToPage(_currentPage);
        }
        _attachScrollListenerToCurrentPage();
      });
    }
  }

  Future<Novel?> _getNovelFromProvider() async {
    if (!mounted) return null;
    final asyncNovels = ref.read(novelsProvider);
    return asyncNovels.when(
      data: (novels) => novels.firstWhereOrNull((n) => n.id == widget.novelId),
      loading: () => null,
      error: (e, s) => null,
    );
  }

  Future<void> _saveCurrentScrollPosition() async {
    final novel = await _getNovelFromProvider();
    if (novel == null || !_prefsLoaded) return;
    if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
      final controller = _scrollControllers[_currentPage];
      if (controller != null && controller.hasClients) {
        await _prefs.setDouble('scroll_pos_${widget.novelId}_$_currentPage', controller.position.pixels);
      }
    }
  }

  Future<void> _loadAndJumpToScrollPosition(int chapterIndex, ScrollController controller) async {
    if (!_prefsLoaded) return;
    final key = 'scroll_pos_${widget.novelId}_$chapterIndex';
    final savedPosition = _prefs.getDouble(key);

    if (savedPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          controller.jumpTo(savedPosition);
        }
      });
    }
  }

  Future<void> _saveLastViewedPage(int page) async {
    if (!_prefsLoaded || page < 0) return;
    await _prefs.setInt('last_page_${widget.novelId}', page);
  }

  Future<void> _saveFontSizePreference(double size) async {
    if (!_prefsLoaded) return;
    await _prefs.setDouble(_prefFontSizeKey, size);
  }

  Color _getCurrentBackgroundColor() => Theme.of(context).scaffoldBackgroundColor;
  Color _getCurrentTextColor() => Theme.of(context).colorScheme.onSurface;

  TextStyle _getBaseTextStyle() {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: _currentFontSize,
      color: _getCurrentTextColor(),
      height: 1.6,
    );
  }

  void _startEditing(Novel novel) {
    if (_isGeneratingNextChapter || novel.chapters.isEmpty) return;

    final int chapterIndex = _currentPage;
    final Chapter currentChapter = novel.chapters[chapterIndex];
    final readerScrollController = _scrollControllers[chapterIndex];
    double currentScrollOffset = 0.0;

    if (readerScrollController != null && readerScrollController.hasClients) {
      currentScrollOffset = readerScrollController.offset;
    }

    setState(() {
      _isEditing = true;
      _editingChapterIndex = chapterIndex;
      _editingTitleController.text = currentChapter.title;
      _editingContentController.text = currentChapter.content;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingScrollController.hasClients) {
        _editingScrollController.jumpTo(currentScrollOffset);
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingChapterIndex = null;
      _editingTitleController.clear();
      _editingContentController.clear();
    });
  }

  Future<void> _saveEdits(Novel novel) async {
    if (_editingChapterIndex == null) return;

    final int chapterIndexToUpdate = _editingChapterIndex!;
    final double editorScrollOffset = _editingScrollController.hasClients ? _editingScrollController.offset : 0.0;

    final originalChapter = novel.chapters[chapterIndexToUpdate];
    final updatedChapter = Chapter(
      id: originalChapter.id,
      title: _editingTitleController.text.trim(),
      content: _editingContentController.text.trim(),
      createdAt: originalChapter.createdAt,
    );

    novel.chapters[chapterIndexToUpdate] = updatedChapter;
    novel.updatedAt = DateTime.now();
    novel.roadMap = null;
    novel.previousRoadMap = null;
    await ref.read(novelsProvider.notifier).updateNovel(novel);

    final syncTask = SyncTask(
      action: 'update',
      novelId: novel.id,
      chapterIndex: chapterIndexToUpdate,
      content: updatedChapter.content,
    );
    await ref.read(syncServiceProvider).addTask(syncTask);

    _showSnackbarMessage("Chapitre sauvegardé. La synchronisation se fera en arrière-plan.", Colors.green);

    setState(() {
      _isEditing = false;
      _editingChapterIndex = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final readerScrollController = _scrollControllers[chapterIndexToUpdate];
      if (mounted && readerScrollController != null && readerScrollController.hasClients) {
        readerScrollController.jumpTo(editorScrollOffset);
      }
    });
  }

  Future<void> _guardedGenerateChapter(Novel novel) async {
    final syncStatus = ref.read(syncQueueStatusProvider);
    if (syncStatus != SyncQueueStatus.idle) {
      String message = syncStatus == SyncQueueStatus.processing
          ? "Finalisation d'une synchronisation..."
          : "Des modifications sont en attente de synchronisation...";
      _showSnackbarMessage(message, Colors.blueAccent);
      ref.read(syncServiceProvider).processQueue();
      return;
    }

    if (_isGeneratingNextChapter) {
      _showSnackbarMessage("L'écrivain est déjà en train de rédiger, patience !", Colors.orangeAccent);
      return;
    }

    await _generateAndAddNewChapter(novel);
  }

  Future<void> _generateAndAddNewChapter(Novel novel, {bool finalChapter = false}) async {
    setState(() {
      _isGeneratingNextChapter = true;
      _chapterStream = null;
    });

    try {
      final prompt = await AIService.preparePrompt(
        novel: novel,
        isFirstChapter: novel.chapters.isEmpty,
        isFinalChapter: finalChapter,
      );

      if (!mounted) return;

      final stream = AIService.streamChapterFromPrompt(
        prompt: prompt,
        modelId: novel.modelId,
        language: novel.language,
      );

      setState(() => _chapterStream = stream);

    } catch (e) {
      _handleGenerationError(e);
    }
  }

  Future<void> _finalizeChapterGeneration(Novel novel, String fullText) async {
    if (fullText.trim().isEmpty) {
      debugPrint("Erreur: L'IA a renvoyé un stream vide (probable surcharge du modèle).");
      _handleGenerationError(ApiServerException("L'écrivain a renvoyé un chapitre vide. Réessayez.", statusCode: null));
      return;
    }
    if (!mounted) return;

    final syncService = ref.read(syncServiceProvider);
    final novelsNotifier = ref.read(novelsProvider.notifier);
    final roadmapService = ref.read(roadmapServiceProvider);

    final newChapter = AIService.extractTitleAndContent(
      fullText,
      novel.chapters.length,
      novel.chapters.isEmpty,
      false,
      AIPrompts.getPromptsFor(novel.language),
    );

    novel.chapters.add(newChapter);
    novel.updatedAt = DateTime.now();

    await novelsNotifier.updateNovel(novel);

    if (!mounted) return;
    await roadmapService.triggerRoadmapUpdateIfNeeded(novel, context);

    final syncTask = SyncTask(
      action: 'add',
      novelId: novel.id,
      content: newChapter.content,
      chapterIndex: novel.chapters.length - 1,
    );
    await syncService.addTask(syncTask);

    _showSnackbarMessage('Chapitre "${newChapter.title}" ajouté.', Colors.green, durationSeconds: 5);

    // --- ✅ AUTOMATISATION PLAN DIRECTEUR (Régénération) ---
    final chapterCount = novel.chapters.length;
    if (chapterCount >= 10 && chapterCount % 10 == 0) {
      debugPrint("Seuil de $chapterCount chapitres atteint. Régénération du plan directeur...");
      _regenerateFutureOutline(novel); // Appel non bloquant
    }
    // --- FIN AUTOMATISATION ---

    setState(() {
      _isGeneratingNextChapter = false;
      _chapterStream = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.animateToPage(
          novel.chapters.length - 1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleGenerationError(Object error) {
    if (!mounted) return;

    setState(() {
      _isGeneratingNextChapter = false;
      _chapterStream = null;
    });

    String message;
    if (error is ApiServerException) {
      message = "Le service de l'écrivain rencontre un problème. Il sera bientôt de retour.";
    } else if (error is ApiConnectionException) {
      message = "Impossible de contacter l'écrivain. Vérifiez votre connexion internet ou que le backend est bien lancé.";
    } else {
      message = "Une erreur inattendue est survenue lors de la rédaction.";
      debugPrint("Erreur de génération non gérée: $error");
    }

    _showSnackbarMessage(message, Colors.redAccent, durationSeconds: 8);
  }

  void _showSnackbarMessage(String message, Color backgroundColor, {int durationSeconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: Duration(seconds: durationSeconds)
      )
    );
  }

  Future<void> _deleteCurrentChapter(Novel novel) async {
    if (novel.chapters.isEmpty || _isGeneratingNextChapter) { return; }

    final int chapterIndexToDelete = _currentPage;
    if (chapterIndexToDelete < 0 || chapterIndexToDelete >= novel.chapters.length) {
        return;
    }
    final String chapterTitle = novel.chapters[chapterIndexToDelete].title;
    final int chapterNumber = chapterIndexToDelete + 1;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text('Voulez-vous vraiment supprimer le chapitre $chapterNumber ("$chapterTitle") ?'),
          actions: <Widget>[
            TextButton( child: const Text('Annuler'), onPressed: () => Navigator.of(context).pop(false), ),
            TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Supprimer'), onPressed: () => Navigator.of(context).pop(true), ),
          ],
        );
      },
    );

    if (confirmDelete != true || !mounted) { return; }

    final syncTask = SyncTask(
      action: 'delete_chapter',
      novelId: novel.id,
      chapterIndex: chapterIndexToDelete,
    );
    await ref.read(syncServiceProvider).addTask(syncTask);

    try {
      if(_prefsLoaded) {
        await _prefs.remove('scroll_pos_${widget.novelId}_$chapterIndexToDelete');
      }

      novel.removeChapter(chapterIndexToDelete);
      novel.roadMap = null;
      novel.previousRoadMap = null;
      novel.updatedAt = DateTime.now();
      await ref.read(novelsProvider.notifier).updateNovel(novel);

      _showSnackbarMessage('Chapitre "$chapterTitle" supprimé.', Colors.green);
    } catch (e) {
      _showSnackbarMessage("Erreur critique lors de la suppression locale : ${e.toString()}", Colors.redAccent);
    }
  }

  void _toggleUI() {
    if(mounted) {
      setState(() => _showUIElements = !_showUIElements);
      if(!_showUIElements) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _selectionTimer?.cancel();
        setState(() { _selectedWord = ''; _translationResult = null; _isLoadingTranslation = false; });
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  void _handleTapToToggleUI(TapUpDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final double navigationBarHeight = kBottomNavigationBarHeight + 10;
    final double translationAreaHeight = _selectedWord.isNotEmpty ? 100 : 0;
    final double deadZoneHeight = bottomSafeArea + navigationBarHeight + translationAreaHeight;

    if (localPosition.dy < renderBox.size.height - deadZoneHeight) {
      _toggleUI();
    }
  }

  void _showFontSizeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              title: const Text('Taille de la police'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      setInnerState(() {
                        _decreaseFontSize();
                      });
                    },
                  ),
                  Text(
                    _currentFontSize.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      setInnerState(() {
                        _increaseFontSize();
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _increaseFontSize() {
    setState(() {
      _currentFontSize = (_currentFontSize + 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize);
  }

  void _decreaseFontSize() {
    setState(() {
      _currentFontSize = (_currentFontSize - 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize);
  }

  // --- ✅ NOUVELLE FONCTION : Dialogue du Plan Directeur ---
  void _showFutureOutlineDialog(Novel novel) async {
    Novel currentNovel = novel;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isGeneratingOutline = false;

            Future<void> generateOutline() async {
              setDialogState(() => isGeneratingOutline = true);
              try {
                final latestNovelState = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == novel.id) ?? currentNovel;
                final String newOutline = await AIService.generateFutureOutline(latestNovelState);

                if (!mounted) return;

                final updatedNovel = latestNovelState.copyWith(
                  futureOutline: newOutline,
                  updatedAt: DateTime.now()
                );
                await ref.read(novelsProvider.notifier).updateNovel(updatedNovel);

                if (!mounted) return;
                setDialogState(() {
                  currentNovel = updatedNovel;
                  isGeneratingOutline = false;
                });

                // --- ✅ AUTOMATISATION CHAPITRE 1 ---
                if (updatedNovel.chapters.isEmpty) {
                  debugPrint("Plan généré, lancement auto du chapitre 1...");
                  Navigator.of(context).pop();
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (mounted) {
                    _guardedGenerateChapter(updatedNovel);
                  }
                }
                // --- FIN AUTOMATISATION CHAPITRE 1 ---

              } catch (e) {
                 if (!mounted) return;
                 setDialogState(() => isGeneratingOutline = false);
                 final errorMessage = (e is ApiException) ? e.message : e.toString();
                 if (mounted) _showSnackbarMessage("Erreur génération plan: $errorMessage", Colors.red);
              }
            }

            return AlertDialog(
              title: const Text('🧭 Plan Directeur (Futur)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isGeneratingOutline)
                      const Center(child: CircularProgressIndicator())
                    else if ((currentNovel.futureOutline ?? "").isEmpty)
                      const Text("Aucun plan directeur n'a encore été généré pour ce roman.")
                    else
                      MarkdownBody( // ✅ Cet appel fonctionnera après le 'pub get'
                        data: currentNovel.futureOutline!,
                        selectable: true,
                        onTapLink: (text, href, title) {
                            if (href != null) launchUrl(Uri.parse(href));
                        },
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                if (isGeneratingOutline)
                  const TextButton(onPressed: null, child: Text('Génération en cours...'))
                else
                  TextButton(
                    onPressed: generateOutline,
                    child: Text((currentNovel.futureOutline ?? "").isEmpty
                        ? 'Générer le plan'
                        : 'Régénérer le plan'),
                  ),
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }
  // --- FIN NOUVELLE FONCTION ---

  // --- ✅ NOUVELLE FONCTION : Régénération du Plan en arrière-plan ---
  Future<void> _regenerateFutureOutline(Novel novel) async {
    if (!mounted) return;

    _showSnackbarMessage("🚀 Mise à jour du plan directeur en arrière-plan...", Colors.blueGrey);

    try {
      final String newOutline = await AIService.generateFutureOutline(novel);
      if (!mounted) return;

      final updatedNovel = novel.copyWith(
        futureOutline: newOutline,
        updatedAt: DateTime.now(),
      );

      await ref.read(novelsProvider.notifier).updateNovel(updatedNovel);

      if (mounted) {
        debugPrint("Plan directeur régénéré et sauvegardé avec succès.");
        _showSnackbarMessage("✅ Plan directeur mis à jour !", Colors.green);
      }
    } catch (e) {
      debugPrint("Erreur lors de la régénération auto du plan: $e");
      if (mounted) {
        final errorMessage = (e is ApiException) ? e.message : e.toString();
        _showSnackbarMessage("⚠️ Erreur mise à jour plan: $errorMessage", Colors.orange);
      }
    }
  }
  // --- FIN NOUVELLE FONCTION ---


  void _showNovelInfoSheet(Novel novel) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: const Text("Détails de l'Intrigue"),
              contentPadding: const EdgeInsets.only(top: 20.0),
              content: SizedBox(
                width: 500,
                height: 350,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: "Spécifications"),
                        Tab(text: "Fiche de route"),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildInfoTabContent(
                            context,
                            children: [
                              SelectableText(
                                novel.specifications.isNotEmpty
                                    ? novel.specifications
                                    : 'Aucune spécification particulière.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                                textAlign: TextAlign.justify,
                              )
                            ],
                          ),
                          _buildInfoTabContent(
                            context,
                            children: [
                              SelectableText(
                                novel.roadMap ?? novel.previousRoadMap ?? "La fiche de route sera générée après 3 chapitres.",
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                                textAlign: TextAlign.justify,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[ TextButton(child: const Text('Fermer'), onPressed: () => Navigator.of(context).pop())],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoTabContent(BuildContext context, {required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  List<TextSpan> _buildFormattedTextSpans(String text, TextStyle baseStyle) {
    String processedText = text.replaceAll('—', ', ').replaceAll(',,', ',');

    final List<TextSpan> spans = [];
    final List<String> parts = processedText.split('*');

    for (int i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        spans.add(TextSpan(
          text: parts[i],
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(text: parts[i], style: baseStyle));
      }
    }
    return spans;
  }

  Widget _buildChapterReader(Chapter chapter, int index, Novel novel) {
    final baseStyle = _getBaseTextStyle();

    final titleStyle = baseStyle.copyWith(
        fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! + 4 : null,
        fontWeight: FontWeight.w800,
        height: 1.8,
        color: baseStyle.color?.withAlpha((255 * 0.9).round())
    );
    final contentStyle = baseStyle.copyWith(height: 1.7);

    final controller = _scrollControllers.putIfAbsent(index, () {
      final newController = ScrollController();
      _loadAndJumpToScrollPosition(index, newController);
      return newController;
    });

    final textContent = SelectableText.rich(
      TextSpan(
        children: [
          ..._buildFormattedTextSpans("${chapter.title}\n\n", titleStyle),
          ..._buildFormattedTextSpans(chapter.content, contentStyle),
        ],
      ),
      textAlign: TextAlign.justify,
      onSelectionChanged: (selection, cause) {
        final String fullRenderedText = "${chapter.title}\n\n${chapter.content}";
        if (selection.isValid && !selection.isCollapsed && (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.drag || cause == SelectionChangedCause.doubleTap)) {
          String selectedText = '';
          try { if (selection.start >= 0 && selection.end <= fullRenderedText.length && selection.start < selection.end) { selectedText = fullRenderedText.substring(selection.start, selection.end).trim(); } } catch (e) { debugPrint("Erreur substring: $e"); selectedText = ''; }

          bool isValidForLookup = selectedText.isNotEmpty && selectedText != chapter.title.trim() && selectedText.length <= 50 && !selectedText.contains('\n');
          if (isValidForLookup && novel.language == 'Japonais') {
            _selectionTimer?.cancel();
             if (mounted) { _triggerReadingAndTranslation(selectedText); }
          } else {
            if ((_selectedWord.isNotEmpty || _isLoadingTranslation || _translationResult != null) && mounted) {
              setState(() {
                _selectedWord = '';
                _translationResult = null;
                _isLoadingTranslation = false;
              });
            }
          }
        } else if (cause == SelectionChangedCause.tap || cause == SelectionChangedCause.keyboard) {
            if ((_selectedWord.isNotEmpty || _isLoadingTranslation || _translationResult != null) && mounted) {
              setState(() {
                _selectedWord = '';
                _translationResult = null;
                _isLoadingTranslation = false;
              });
            }
        }
      },
      cursorColor: Theme.of(context).colorScheme.primary,
      selectionControls: MaterialTextSelectionControls(),
    );

    final bottomPadding = _showUIElements ? 120.0 : 60.0;

      return Container(
        color: _getCurrentBackgroundColor(),
        child: SingleChildScrollView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(20.0, MediaQuery.of(context).padding.top + kToolbarHeight + 24.0, 20.0, bottomPadding),
          child: textContent,
        ),
      );
  }


  Widget _buildChapterEditor() {
    final baseStyle = _getBaseTextStyle();
    final theme = Theme.of(context);
    final hintColor = baseStyle.color?.withAlpha((255 * 0.5).round());

    return Container(
      color: _getCurrentBackgroundColor(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        controller: _editingScrollController,
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        child: Column(
          children: [
            TextField(
              controller: _editingTitleController,
              style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! + 4 : null),
              decoration: InputDecoration(
                labelText: 'Titre du chapitre',
                labelStyle: theme.textTheme.labelLarge?.copyWith(color: hintColor),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _editingContentController,
              style: baseStyle.copyWith(height: 1.7),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Contenu du chapitre...',
                hintStyle: baseStyle.copyWith(color: hintColor),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationArea(ThemeData theme) {
    final translationBg = theme.colorScheme.surfaceContainerHighest;
    final textColor = _getCurrentTextColor();

    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: textColor.withAlpha((255 * 0.7).round()));
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(color: textColor, height: 1.5);
    final errorStyle = valueStyle?.copyWith(color: theme.colorScheme.error);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textColor.withAlpha((255 * 0.9).round()));

    final String? reading = _translationResult?['reading'];
    final String? translation = _translationResult?['translation'];
    final String? readingError = _translationResult?['readingError'];
    final String? translationError = _translationResult?['translationError'];

    final bool hasReadingInfo = reading != null || readingError != null;
    final bool hasTranslationInfo = translation != null || translationError != null;
    final bool hasAnyInfo = hasReadingInfo || hasTranslationInfo;

    return Material(
      elevation: 2,
      color: translationBg,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.only(
          top: 16.0,
          left: 20.0,
          right: 20.0,
          bottom: max(16.0, MediaQuery.of(context).padding.bottom + 4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Infos pour : "${_selectedWord.length > 30 ? "${_selectedWord.substring(0, 30)}..." : _selectedWord}"',
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            _isLoadingTranslation
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row( children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Recherche infos...', style: theme.textTheme.bodyMedium?.copyWith(color: textColor.withAlpha((255 * 0.8).round()))),
                    ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasReadingInfo) ...[
                        Text("Lecture Hiragana :", style: labelStyle),
                        const SizedBox(height: 3),
                        readingError != null
                            ? SelectableText(readingError, style: errorStyle)
                            : SelectableText(reading ?? '(Non trouvée)', style: valueStyle),
                        if (hasTranslationInfo) const SizedBox(height: 10),
                      ],
                      if (hasTranslationInfo) ...[
                        Text("Traduction Français :", style: labelStyle),
                        const SizedBox(height: 3),
                        translationError != null
                            ? SelectableText(translationError, style: errorStyle)
                            : SelectableText(translation ?? '(Non trouvée)', style: valueStyle),
                      ],
                      if (!hasAnyInfo)
                        Text("(Aucune information trouvée)", style: valueStyle?.copyWith(fontStyle: FontStyle.italic, color: textColor.withAlpha((255 * 0.6).round()))),
                    ],
                  ),
          ],
        ),
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
            Icon(Icons.menu_book, size: 80, color: _getCurrentTextColor().withAlpha((255 * 0.4).round())),
            const SizedBox(height: 24),
            Text(
              'Ce roman n\'a pas encore de chapitre.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(color: _getCurrentTextColor().withAlpha((255 * 0.8).round())),
            ),
            const SizedBox(height: 16),
            Text(
              "Utilisez le bouton '+' en bas à droite pour générer le premier chapitre.",
              style: theme.textTheme.bodyMedium?.copyWith(color: _getCurrentTextColor().withAlpha((255 * 0.6).round())),
              textAlign: TextAlign.center
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterNavigation({
    required ThemeData theme,
    required Color backgroundColor,
    required Color primaryColor,
    required Color textColor,
    required Color disabledColor,
    required bool isGenerating,
    required Novel novel,
  }) {
    bool canGoBack = _currentPage > 0;
    bool hasChapters = novel.chapters.isNotEmpty;
    bool isLastPage = hasChapters && _currentPage == novel.chapters.length - 1;
    bool navigationDisabled = isGenerating || !hasChapters;

    String pageText;
    if (!hasChapters) {
      pageText = 'Pas de chapitres';
    } else if (_currentPage >= 0) {
      pageText = 'Chapitre ${_currentPage + 1} / ${novel.chapters.length}';
    } else {
      pageText = 'Chargement...';
    }

    return Material(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 4,
          bottom: max(8.0, MediaQuery.of(context).padding.bottom)
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: 'Chapitre précédent',
              iconSize: 20,
              color: canGoBack && !navigationDisabled ? primaryColor : disabledColor,
              disabledColor: disabledColor,
              onPressed: canGoBack && !navigationDisabled
                  ? () {
                      _selectionTimer?.cancel();
                      if (_pageController.hasClients) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    }
                  : null,
            ),
            Flexible(
              child: Text(
                pageText,
                style: theme.textTheme.labelLarge?.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            isGenerating
                ? const SizedBox(
                    width: 48,
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5)
                      )
                    ),
                  )
                : hasChapters && isLastPage
                    ? _buildAddChapterMenu(theme, novel)
                    : hasChapters
                        ? IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            tooltip: 'Chapitre suivant',
                            iconSize: 20,
                            color: !navigationDisabled ? primaryColor : disabledColor,
                            onPressed: !navigationDisabled
                                ? () {
                                    _selectionTimer?.cancel();
                                    if (_pageController.hasClients) {
                                      _pageController.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  }
                                : null,
                          )
                        : (!hasChapters
                            ? _buildAddChapterMenu(theme, novel)
                            : const SizedBox(width: 48)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddChapterMenu(ThemeData theme, Novel novel) {
    final iconColor = _isGeneratingNextChapter ? theme.disabledColor : theme.colorScheme.primary;
    Color popupMenuColor;
    Color popupMenuTextColor;
    switch (Theme.of(context).brightness) {
      case Brightness.dark:
        popupMenuColor = theme.colorScheme.surfaceContainerHighest;
        popupMenuTextColor = theme.colorScheme.onSurface;
        break;
      case Brightness.light:
        popupMenuColor = theme.colorScheme.surfaceContainerHigh;
        popupMenuTextColor = theme.colorScheme.onSurface;
        break;
    }
    final bool isMenuEnabled = !_isGeneratingNextChapter;
    final bool hasChapters = novel.chapters.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(Icons.add_circle_outline, color: iconColor),
      tooltip: hasChapters ? 'Options du chapitre suivant' : 'Générer le premier chapitre',
      offset: const Offset(0, -120),
      color: popupMenuColor,
      enabled: isMenuEnabled,
      onOpened: () { if (!_showUIElements) _toggleUI(); },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if(hasChapters)
          PopupMenuItem<String>(
            value: 'next',
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.playlist_add_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withAlpha((255 * 0.8).round()) : theme.disabledColor),
              title: Text(
                'Générer chapitre suivant',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          )
        else
          PopupMenuItem<String>(
            value: 'first',
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.auto_stories_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withAlpha((255 * 0.8).round()) : theme.disabledColor),
              title: Text(
                'Générer le premier chapitre',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),

        if (hasChapters)
          PopupMenuItem<String>(
            value: 'final',
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.flag_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withAlpha((255 * 0.8).round()) : theme.disabledColor),
              title: Text(
                'Générer chapitre final',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
      ],
      onSelected: (String result) {
        if (result == 'next' || result == 'first') {
          _guardedGenerateChapter(novel);
        } else if (result == 'final') {
          _generateAndAddNewChapter(novel, finalChapter: true);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeServiceProvider) == ThemeMode.dark;
    final theme = Theme.of(context);
    final currentBackgroundColor = _getCurrentBackgroundColor();

    final novelsAsyncValue = ref.watch(novelsProvider);

    return novelsAsyncValue.when(
      loading: () => Scaffold(backgroundColor: currentBackgroundColor, body: const Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(backgroundColor: currentBackgroundColor, body: Center(child: Text('Erreur: $err'))),
      data: (novels) {
        final novel = novels.firstWhereOrNull((n) => n.id == widget.novelId);
        if (novel == null) {
          return Scaffold(
            backgroundColor: currentBackgroundColor,
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: const Center(child: Text("Ce roman n'a pas pu être chargé ou a été supprimé.")),
          );
        }

        Color navBarBgColor = theme.colorScheme.surfaceContainer;
        Color navBarPrimaryColor = theme.colorScheme.primary;
        Color navBarTextColor = theme.colorScheme.onSurfaceVariant;
        Color navBarDisabledColor = theme.disabledColor;

        final bool isGenerating = _isGeneratingNextChapter;
        final bool canDeleteChapter = novel.chapters.isNotEmpty && !isGenerating && _currentPage >= 0 && _currentPage < novel.chapters.length;
        final bool shouldShowTranslationArea = _selectedWord.isNotEmpty && (_isLoadingTranslation || _translationResult != null);
        final bool canEditChapter = novel.chapters.isNotEmpty && !isGenerating && _currentPage >= 0 && _currentPage < novel.chapters.length;

        return PopScope(
          canPop: !isGenerating,
          // ✅ CORRECTION (Ligne 1310) : Signature de onPopInvoked corrigée
          onPopInvoked: (bool didPop) { 
            if (!didPop) {
              if (isGenerating && mounted) {
                _showSnackbarMessage("Veuillez attendre la fin de la génération en cours.", Colors.orangeAccent);
              }
            } else {
              _saveCurrentScrollPosition();
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            }
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: currentBackgroundColor,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: _isEditing
                ? AppBar(
                    backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
                    foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
                    title: Text('Modifier le chapitre', style: Theme.of(context).appBarTheme.titleTextStyle),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Annuler les modifications',
                      onPressed: _cancelEditing,
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: 'Sauvegarder les modifications',
                        onPressed: () => _saveEdits(novel),
                      ),
                    ],
                  )
                : AnimatedOpacity(
                    opacity: _showUIElements ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showUIElements,
                      child: ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: AppBar(
                            title: Text(novel.title, style: Theme.of(context).appBarTheme.titleTextStyle),
                            backgroundColor: Theme.of(context).appBarTheme.backgroundColor?.withAlpha((255 * 0.75).round()),
                            elevation: 0,
                            scrolledUnderElevation: 0,
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Retour à la bibliothèque',
                              onPressed: () => Navigator.pop(context),
                            ),
                            actions: [
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: 'Ouvrir le menu',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'info':
                                      _showNovelInfoSheet(novel);
                                      break;
                                    // --- ✅ NOUVELLE ACTION : PLAN DIRECTEUR ---
                                    case 'outline':
                                      _showFutureOutlineDialog(novel);
                                      break;
                                    // --- FIN NOUVELLE ACTION ---
                                    case 'edit':
                                      _startEditing(novel);
                                      break;
                                    case 'font_size':
                                      _showFontSizeDialog();
                                      break;
                                    case 'theme':
                                      ref.read(themeServiceProvider.notifier).updateTheme(isDarkMode ? ThemeMode.light : ThemeMode.dark);
                                      break;
                                    case 'delete':
                                      _deleteCurrentChapter(novel);
                                      break;
                                  }
                                },
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'info',
                                    child: ListTile(leading: Icon(Icons.info_outline), title: Text('Informations du roman')),
                                  ),
                                  // --- ✅ NOUVEL ITEM DE MENU : PLAN DIRECTEUR ---
                                  const PopupMenuItem<String>(
                                    value: 'outline',
                                    child: ListTile(leading: Icon(Icons.compass_calibration_outlined), title: Text('Plan Directeur')),
                                  ),
                                  // --- FIN NOUVEL ITEM ---
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    enabled: canEditChapter,
                                    child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier ce chapitre')),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem<String>(
                                    value: 'font_size',
                                    child: ListTile(leading: Icon(Icons.format_size), title: Text('Taille de la police')),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'theme',
                                    child: ListTile(leading: Icon(isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: Text(isDarkMode ? 'Thème clair' : 'Thème sombre')),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    enabled: canDeleteChapter,
                                    child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red.shade300), title: Text('Supprimer ce chapitre', style: TextStyle(color: Colors.red.shade300))),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTapUp: _handleTapToToggleUI,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        if (notification is UserScrollNotification) {
                          final UserScrollNotification userScroll = notification;
                          if (userScroll.direction == ScrollDirection.reverse && _showUIElements) {
                            _toggleUI();
                          } else if (userScroll.direction == ScrollDirection.forward && !_showUIElements) {
                            _toggleUI();
                          }
                        }
                        return false;
                      },
                      child: _isGeneratingNextChapter
                          ? _chapterStream == null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: CircularProgressIndicator(strokeWidth: 3.5),
                                        ),
                                        const SizedBox(height: 24),
                                        Text(
                                          "L'écrivain consulte le contexte...",
                                          textAlign: TextAlign.center,
                                          style: _getBaseTextStyle().copyWith(
                                            fontSize: (_getBaseTextStyle().fontSize ?? 19.0) * 1.1,
                                            color: _getCurrentTextColor().withAlpha((255 * 0.75).round()),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: StreamingTextAnimation(
                                    stream: _chapterStream!,
                                    style: _getBaseTextStyle(),
                                    onDone: (fullText) => _finalizeChapterGeneration(novel, fullText),
                                    onError: (error) => _handleGenerationError(error),
                                  ),
                                )
                          : !_prefsLoaded
                              ? const Center(child: CircularProgressIndicator())
                              : novel.chapters.isEmpty
                                  ? _buildEmptyState(theme)
                                  : PageView.builder(
                                      physics: _isEditing ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                                      key: ValueKey("${novel.id}_${novel.chapters.length}"),
                                      controller: _pageController,
                                      itemCount: novel.chapters.length,
                                      itemBuilder: (context, index) {
                                        if (index >= novel.chapters.length) {
                                          return Container(color: _getCurrentBackgroundColor(), child: Center(child: Text("Chargement...", style: TextStyle(color: _getCurrentTextColor()))));
                                        }
                                        final chapter = novel.chapters[index];

                                        if (_isEditing && index == _editingChapterIndex) {
                                          return _buildChapterEditor();
                                        } else {
                                          return _buildChapterReader(chapter, index, novel);
                                        }
                                      },
                                    ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: shouldShowTranslationArea ? _buildTranslationArea(theme) : const SizedBox.shrink(),
                      ),
                      if (!_isEditing)
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          offset: _showUIElements ? Offset.zero : const Offset(0, 2),
                          child: Column(
                            children: [
                              _buildProgressBars(theme, navBarPrimaryColor, navBarTextColor),
                              _buildChapterNavigation(
                                theme: theme,
                                backgroundColor: navBarBgColor,
                                primaryColor: navBarPrimaryColor,
                                textColor: navBarTextColor,
                                disabledColor: navBarDisabledColor,
                                isGenerating: isGenerating,
                                novel: novel,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBars(ThemeData theme, Color primaryColor, Color textColor) {
    final novel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == widget.novelId);
    if (novel == null) return const SizedBox.shrink();

    final hasChapters = novel.chapters.isNotEmpty;
    final double novelProgress = hasChapters ? (_currentPage + 1) / novel.chapters.length : 0.0;

    return IgnorePointer(
      child: Container(
        color: theme.colorScheme.surfaceContainer.withAlpha(200),
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _chapterProgressNotifier,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: primaryColor.withAlpha((255 * 0.2).round()),
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  minHeight: 2,
                );
              },
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: novelProgress,
              backgroundColor: textColor.withAlpha((255 * 0.2).round()),
              valueColor: AlwaysStoppedAnimation<Color>(textColor.withAlpha((255 * 0.5).round())),
              minHeight: 2,
            ),
          ],
        ),
      ),
    );
  }
}