// lib/novel_reader_page.dart (CORRIGÉ POUR LA GESTION DE SUPPRESSION/MODIFICATION)
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import 'models.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/ai_prompts.dart';
import 'services/vocabulary_service.dart';
import 'services/sync_service.dart';
import 'widgets/streaming_text_widget.dart';
import 'utils/app_logger.dart';


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

  final TextEditingController _futureOutlineController = TextEditingController();
  bool _isEditingOutline = false;

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
    _futureOutlineController.dispose();

    _pageController.removeListener(_onPageChanged);
    if (mounted && _pageController.hasClients) {
        _saveCurrentScrollPosition();
    }
    if (_pageController.hasClients) {
        _pageController.dispose();
    }
    _chapterProgressNotifier.dispose();
    for (var controller in _scrollControllers.values) {
       try {
           controller.removeListener(_updateScrollProgress);
       } catch (e) {
           AppLogger.warning("Listener non trouvé pour ScrollController lors du dispose", tag: "NovelReaderPage");
       }
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

    AppLogger.info("Demande de traduction pour : '$trimmedWord'", tag: "NovelReaderPage");
    try {
      final Map<String, String?> result = await AIService.getReadingAndTranslation(trimmedWord, _prefs);
      AppLogger.info("Résultat traduction reçu: $result", tag: "NovelReaderPage");

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
      AppLogger.error("Erreur catchée dans _triggerReadingAndTranslation (communication backend)", error: e, tag: "NovelReaderPage");
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
      if (!mounted || !_pageController.hasClients || _pageController.page == null) return;
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
      for (var entry in _scrollControllers.entries) {
          try {
             entry.value.removeListener(_updateScrollProgress);
          } catch (e) {
             AppLogger.warning("Listener non trouvé pour ScrollController ${entry.key}", tag: "NovelReaderPage");
          }
      }

      final controller = _scrollControllers[_currentPage];
      if (controller != null && controller.hasClients) {
          controller.addListener(_updateScrollProgress);
          _updateScrollProgress();
      } else {
          _chapterProgressNotifier.value = 0.0;
          AppLogger.info("Aucun ScrollController actif trouvé pour la page $_currentPage.", tag: "NovelReaderPage");
      }
  }


  void _updateScrollProgress() {
    final controller = _scrollControllers[_currentPage];
    if (controller != null && controller.hasClients) {
        final maxScroll = controller.position.maxScrollExtent;
        if (maxScroll > 0) {
            final progress = controller.offset / maxScroll;
            _chapterProgressNotifier.value = progress.clamp(0.0, 1.0);
        } else {
            _chapterProgressNotifier.value = 0.0;
        }
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
      initialPage = lastViewedPage.clamp(0, novel.chapters.length - 1);
    } else {
      initialPage = -1;
    }

    if (mounted) {
      setState(() {
        _currentPage = initialPage;
        _prefsLoaded = true;
      });
       if (_pageController.hasClients) {
          _pageController.removeListener(_onPageChanged);
          _pageController.dispose();
       }
      _pageController = PageController(initialPage: max(0, _currentPage));
      _pageController.addListener(_onPageChanged);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _currentPage != -1) {
           _attachScrollListenerToCurrentPage();
        } else if (mounted && _currentPage == -1) {
           _chapterProgressNotifier.value = 0.0;
        }
      });
    }
  }


  Future<Novel?> _getNovelFromProvider() async {
    if (!mounted) return null;
    final asyncNovels = ref.read(novelsProvider);
    return asyncNovels.when(
      data: (novels) => novels.firstWhereOrNull((n) => n.id == widget.novelId),
      loading: () {
        AppLogger.info("Accès à novelsProvider pendant le chargement.", tag: "NovelReaderPage");
        return null;
      },
      error: (e, s) {
        AppLogger.error("Erreur lors de l'accès à novelsProvider", error: e, stackTrace: s, tag: "NovelReaderPage");
        return null;
      },
    );
  }


  Future<void> _saveCurrentScrollPosition() async {
    if (!_prefsLoaded || !mounted) return;

    final novel = await _getNovelFromProvider();
    if (novel == null) return;

    if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
      final controller = _scrollControllers[_currentPage];
      if (controller != null && controller.hasClients) {
        try {
          await _prefs.setDouble('scroll_pos_${widget.novelId}_$_currentPage', controller.position.pixels);
           AppLogger.info("Scroll position saved for page $_currentPage: ${controller.position.pixels}", tag: "NovelReaderPage");
        } catch (e) {
           AppLogger.error("Failed to save scroll position for page $_currentPage", error: e, tag: "NovelReaderPage");
        }
      } else {
         AppLogger.warning("ScrollController for page $_currentPage not ready or detached, cannot save position.", tag: "NovelReaderPage");
      }
    } else {
       AppLogger.warning("Current page $_currentPage is invalid, cannot save scroll position.", tag: "NovelReaderPage");
    }
  }


  Future<void> _loadAndJumpToScrollPosition(int chapterIndex, ScrollController controller) async {
    if (!_prefsLoaded || !mounted) return;
    final key = 'scroll_pos_${widget.novelId}_$chapterIndex';
    final savedPosition = _prefs.getDouble(key);

    AppLogger.info("Attempting to load scroll position for page $chapterIndex (key: $key). Found: $savedPosition", tag: "NovelReaderPage");


    if (savedPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          final maxScroll = controller.position.maxScrollExtent;
           final positionToJump = savedPosition.clamp(0.0, maxScroll);

          if (positionToJump != savedPosition) {
             AppLogger.warning("Clamped saved position $savedPosition to $positionToJump (max: $maxScroll)", tag: "NovelReaderPage");
          }

          controller.jumpTo(positionToJump);
          AppLogger.info("Jumped to saved scroll position $positionToJump for page $chapterIndex", tag: "NovelReaderPage");
        } else if (mounted) {
           AppLogger.warning("ScrollController for page $chapterIndex not ready during jump attempt.", tag: "NovelReaderPage");
        }
      });
    }
  }


  Future<void> _saveLastViewedPage(int page) async {
    if (!_prefsLoaded || !mounted || page < 0) return;
    try {
      await _prefs.setInt('last_page_${widget.novelId}', page);
      AppLogger.info("Last viewed page saved: $page", tag: "NovelReaderPage");
    } catch (e) {
      AppLogger.error("Failed to save last viewed page", error: e, tag: "NovelReaderPage");
    }
  }


  Future<void> _saveFontSizePreference(double size) async {
    if (!_prefsLoaded || !mounted) return;
    try {
        await _prefs.setDouble(_prefFontSizeKey, size);
        AppLogger.info("Font size preference saved: $size", tag: "NovelReaderPage");
    } catch (e) {
        AppLogger.error("Failed to save font size preference", error: e, tag: "NovelReaderPage");
    }
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
     if (chapterIndex < 0 || chapterIndex >= novel.chapters.length) {
        AppLogger.warning("Attempted to edit invalid chapter index: $chapterIndex", tag: "NovelReaderPage");
        return;
     }
    final Chapter currentChapter = novel.chapters[chapterIndex];
    final readerScrollController = _scrollControllers[chapterIndex];
    double currentScrollOffset = 0.0;

    if (readerScrollController != null && readerScrollController.hasClients) {
      currentScrollOffset = readerScrollController.offset;
    }
     AppLogger.info("Starting edit for chapter $chapterIndex. Initial scroll offset: $currentScrollOffset", tag: "NovelReaderPage");

    setState(() {
      _isEditing = true;
      _editingChapterIndex = chapterIndex;
      _editingTitleController.text = currentChapter.title;
      _editingContentController.text = currentChapter.content;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingScrollController.hasClients) {
        _editingScrollController.jumpTo(currentScrollOffset);
      } else if (mounted) {
          AppLogger.warning("Editing ScrollController not ready on startEditing callback.", tag: "NovelReaderPage");
      }
    });
  }


  void _cancelEditing() {
     AppLogger.info("Cancelling edit for chapter $_editingChapterIndex", tag: "NovelReaderPage");
    setState(() {
      _isEditing = false;
      _editingChapterIndex = null;
      _editingTitleController.clear();
      _editingContentController.clear();
    });
  }


  Future<void> _saveEdits(Novel novel) async {
    if (_editingChapterIndex == null || !mounted) return;

    final int chapterIndexToUpdate = _editingChapterIndex!;
    final double editorScrollOffset = _editingScrollController.hasClients ? _editingScrollController.offset : 0.0;
     AppLogger.info("Saving edits for chapter $chapterIndexToUpdate. Editor scroll offset: $editorScrollOffset", tag: "NovelReaderPage");

    if (chapterIndexToUpdate < 0 || chapterIndexToUpdate >= novel.chapters.length) {
        AppLogger.error("Cannot save edits, chapter index $chapterIndexToUpdate is invalid.", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de sauvegarder, le chapitre semble invalide.", Colors.redAccent);
         setState(() { _isEditing = false; _editingChapterIndex = null; });
        return;
    }

    final originalChapter = novel.chapters[chapterIndexToUpdate];
    final updatedChapter = Chapter(
      id: originalChapter.id,
      title: _editingTitleController.text.trim(),
      content: _editingContentController.text.trim(),
      createdAt: originalChapter.createdAt,
    );

    try {
        await ref.read(novelsProvider.notifier).updateChapter(novel.id, updatedChapter);

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
              final maxScroll = readerScrollController.position.maxScrollExtent;
              final positionToJump = editorScrollOffset.clamp(0.0, maxScroll);
              readerScrollController.jumpTo(positionToJump);
              AppLogger.info("Restored reader scroll position to $positionToJump after saving edits.", tag: "NovelReaderPage");
          } else if (mounted) {
               AppLogger.warning("Reader ScrollController for page $chapterIndexToUpdate not available after saving edits.", tag: "NovelReaderPage");
          }
        });

    } catch (e) {
        AppLogger.error("Error saving chapter edits", error: e, tag: "NovelReaderPage");
        if (mounted) {
            _showSnackbarMessage("Erreur lors de la sauvegarde du chapitre: ${e.toString()}", Colors.redAccent);
        }
    }
  }


  Future<void> _guardedGenerateChapter(Novel novel) async {
    AppLogger.info(">>> _guardedGenerateChapter appelé. Novel ID: ${novel.id}, Chapitres: ${novel.chapters.length}", tag: "NovelReaderPage");

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

    AppLogger.info(">>> Appel de _generateAndAddNewChapter depuis _guardedGenerateChapter...", tag: "NovelReaderPage");
    await _generateAndAddNewChapter(novel);
  }


  Future<void> _generateAndAddNewChapter(Novel novel, {bool finalChapter = false}) async {
    AppLogger.info(">>> _generateAndAddNewChapter appelé. Novel ID: ${novel.id}, Chapitres: ${novel.chapters.length}, finalChapter: $finalChapter", tag: "NovelReaderPage");

    if (!mounted) return;

    setState(() {
      _isGeneratingNextChapter = true;
      _chapterStream = null;
    });

    try {
      AppLogger.info(">>> Appel de AIService.preparePrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      final prompt = await AIService.preparePrompt(
        novel: novel,
        isFirstChapter: novel.chapters.isEmpty,
        isFinalChapter: finalChapter,
      );
      AppLogger.success(">>> AIService.preparePrompt terminé avec succès dans _generateAndAddNewChapter.", tag: "NovelReaderPage");

      if (kDebugMode) {
          debugPrint(prompt);
      } else {
           AppLogger.info("Prompt généré (longueur: ${prompt.length})", tag: "NovelReaderPage");
      }
      AppLogger.info("=========================================================", tag: "NovelReaderPage");


      if (!mounted) return;

      AppLogger.info(">>> Appel de AIService.streamChapterFromPrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      final stream = AIService.streamChapterFromPrompt(
        prompt: prompt,
        modelId: novel.modelId,
        language: novel.language,
      );

      if (mounted) {
         setState(() => _chapterStream = stream);
      }

    } catch (e, stackTrace) {
      AppLogger.error("❌ Erreur DANS _generateAndAddNewChapter (probablement pendant preparePrompt)", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
      _handleGenerationError(e);
    }
  }


  Future<void> _finalizeChapterGeneration(Novel novel, String fullText) async {
     AppLogger.info("Finalizing chapter generation. Received text length: ${fullText.length}", tag: "NovelReaderPage");
    if (fullText.trim().isEmpty) {
      AppLogger.error("Erreur: L'IA a renvoyé un stream vide (probable surcharge du modèle).", tag: "NovelReaderPage");
      _handleGenerationError(ApiServerException("L'écrivain a renvoyé un chapitre vide. Réessayez.", statusCode: null));
      return;
    }
    if (!mounted) {
         AppLogger.warning("Widget non monté lors de la finalisation du chapitre.", tag: "NovelReaderPage");
        return;
    }

    final newChapter = AIService.extractTitleAndContent(
      fullText,
      novel.chapters.length,
      novel.chapters.isEmpty,
      false,
      AIPrompts.getPromptsFor(novel.language),
    );

    try {
        await ref.read(novelsProvider.notifier).addChapter(novel.id, newChapter);
        AppLogger.success("Nouveau chapitre ajouté au provider: ${newChapter.title}", tag: "NovelReaderPage");

        if (!mounted) return;

        final updatedNovelState = await ref.read(novelsProvider.future);
        final updatedNovel = updatedNovelState.firstWhereOrNull((n) => n.id == novel.id);

        if (updatedNovel == null) {
             AppLogger.error("Impossible de retrouver le novel mis à jour après ajout du chapitre.", tag: "NovelReaderPage");
        } else {
             Future microtask = ref.read(roadmapServiceProvider).triggerRoadmapUpdateIfNeeded(updatedNovel, context);
             Future microtask2 = ref.read(roadmapServiceProvider).triggerFutureOutlineUpdateIfNeeded(updatedNovel, context);
        }

        final syncTask = SyncTask(
          action: 'add',
          novelId: novel.id,
          content: newChapter.content,
          chapterIndex: novel.chapters.length,
        );
        await ref.read(syncServiceProvider).addTask(syncTask);
         AppLogger.info("Tâche de synchronisation 'add' ajoutée pour le nouveau chapitre.", tag: "NovelReaderPage");


        _showSnackbarMessage('Chapitre "${newChapter.title}" ajouté.', Colors.green, durationSeconds: 5);


        setState(() {
          _isGeneratingNextChapter = false;
          _chapterStream = null;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            final currentNovels = ref.read(novelsProvider).value ?? [];
            final currentNovel = currentNovels.firstWhereOrNull((n) => n.id == novel.id);
            final lastPageIndex = (currentNovel?.chapters.length ?? 1) - 1;

            if (lastPageIndex >= 0) {
                 AppLogger.info("Animation vers la nouvelle page: $lastPageIndex", tag: "NovelReaderPage");
                _pageController.animateToPage(
                  lastPageIndex,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                );
            } else {
                 AppLogger.warning("Impossible de naviguer, index de page invalide: $lastPageIndex", tag: "NovelReaderPage");
            }
          } else if (mounted) {
               AppLogger.warning("PageController non prêt pour l'animation vers la nouvelle page.", tag: "NovelReaderPage");
          }
        });

    } catch (e, stackTrace) {
        AppLogger.error("Erreur lors de la finalisation/sauvegarde du chapitre", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
        _handleGenerationError(ApiException("Erreur lors de la sauvegarde du chapitre: ${e.toString()}"));
    }
  }


  void _handleGenerationError(Object error) {
    if (!mounted) {
         AppLogger.warning("handleGenerationError appelé mais widget non monté.", tag: "NovelReaderPage");
        return;
    }

     AppLogger.error("Gestion de l'erreur de génération: $error", tag: "NovelReaderPage");


    setState(() {
      _isGeneratingNextChapter = false;
      _chapterStream = null;
    });

    String message;
    if (error is ApiServerException) {
      message = error.toString();
    } else if (error is ApiConnectionException) {
      message = error.toString();
    } else if (error is ApiException) {
       message = error.message;
    }
    else {
      message = "Une erreur inattendue est survenue lors de la rédaction.";
      AppLogger.error("Erreur de génération non gérée de type ${error.runtimeType}", error: error, tag: "NovelReaderPage");
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

  // ✅ CORRIGÉ : Logique de navigation après suppression
  Future<void> _deleteCurrentChapter(Novel novel) async {
    if (!mounted || novel.chapters.isEmpty || _isGeneratingNextChapter) {
        AppLogger.warning("Suppression annulée: !mounted=${!mounted}, isEmpty=${novel.chapters.isEmpty}, isGenerating=$_isGeneratingNextChapter", tag: "NovelReaderPage");
        return;
    }

    final int chapterIndexToDelete = _currentPage;
    if (chapterIndexToDelete < 0 || chapterIndexToDelete >= novel.chapters.length) {
        AppLogger.error("Tentative de suppression d'un index invalide: $chapterIndexToDelete (total: ${novel.chapters.length})", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de déterminer quel chapitre supprimer.", Colors.redAccent);
        return;
    }
    final Chapter chapterToDelete = novel.chapters[chapterIndexToDelete];
    final int chapterNumber = chapterIndexToDelete + 1;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text('Voulez-vous vraiment supprimer le chapitre $chapterNumber ("${chapterToDelete.title}") ?'),
          actions: <Widget>[
            TextButton( child: const Text('Annuler'), onPressed: () => Navigator.of(context).pop(false), ),
            TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Supprimer'), onPressed: () => Navigator.of(context).pop(true), ),
          ],
        );
      },
    );

    if (confirmDelete != true || !mounted) {
         AppLogger.info("Suppression du chapitre $chapterIndexToDelete annulée par l'utilisateur ou widget non monté.", tag: "NovelReaderPage");
        return;
    }

    AppLogger.info("Demande de suppression confirmée pour le chapitre $chapterIndexToDelete (ID: ${chapterToDelete.id})", tag: "NovelReaderPage");

    final syncTask = SyncTask(
      action: 'delete_chapter',
      novelId: novel.id,
      chapterIndex: chapterIndexToDelete,
    );
    await ref.read(syncServiceProvider).addTask(syncTask);
     AppLogger.info("Tâche de synchronisation 'delete_chapter' ajoutée.", tag: "NovelReaderPage");

    try {
      if(_prefsLoaded) {
        final key = 'scroll_pos_${widget.novelId}_$chapterIndexToDelete';
        if (_prefs.containsKey(key)) {
            await _prefs.remove(key);
             AppLogger.info("Position de scroll supprimée pour le chapitre $chapterIndexToDelete.", tag: "NovelReaderPage");
        }
      }

       AppLogger.info("Appel de novelsProvider.notifier.deleteChapter...", tag: "NovelReaderPage");
      await ref.read(novelsProvider.notifier).deleteChapter(novel.id, chapterToDelete.id);
       AppLogger.success("Chapitre supprimé avec succès via le provider.", tag: "NovelReaderPage");

      _showSnackbarMessage('Chapitre "${chapterToDelete.title}" supprimé.', Colors.green);

      // ✅ Nouvelle logique pour gérer la navigation après suppression
      // Le `ref.watch` va reconstruire le widget. `build` s'exécutera à nouveau
      // avec la nouvelle liste de chapitres. Nous n'avons plus besoin de gérer manuellement
      // le `PageController` ici, car la reconstruction du `PageView.builder` avec un
      // nouvel `itemCount` et une nouvelle `key` forcera Flutter à se réajuster correctement.
      // Le listener `_onPageChanged` s'occupera de mettre à jour `_currentPage` si l'index
      // actuel n'est plus valide.

    } catch (e, stackTrace) {
      AppLogger.error("Erreur critique lors de la suppression du chapitre", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
       if (mounted) {
         _showSnackbarMessage("Erreur critique lors de la suppression : ${e.toString()}", Colors.redAccent);
       }
       ref.invalidate(novelsProvider);
    }
  }


  void _toggleUI() {
    if(mounted) {
      setState(() => _showUIElements = !_showUIElements);
      if(!_showUIElements) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _selectionTimer?.cancel();
         if (mounted) {
             setState(() { _selectedWord = ''; _translationResult = null; _isLoadingTranslation = false; });
         }
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }


  void _handleTapToToggleUI(TapUpDetails details) {
    if (!mounted) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final double navigationBarHeight = kBottomNavigationBarHeight + 10;
    final double translationAreaHeight = (_selectedWord.isNotEmpty || _isLoadingTranslation) ? 120 : 0;
    final double deadZoneHeight = bottomSafeArea + navigationBarHeight + translationAreaHeight;

    if (localPosition.dy < renderBox.size.height - deadZoneHeight) {
      _toggleUI();
    } else {
       AppLogger.info("Tap détecté dans la zone morte (UI/Traduction), UI non basculée.", tag: "NovelReaderPage");
    }
  }


  void _showFontSizeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Taille de la police'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _currentFontSize <= 10.0 ? null : () {
                      _decreaseFontSize();
                      setDialogState(() {});
                    },
                  ),
                  Text(
                    _currentFontSize.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                     onPressed: _currentFontSize >= 50.0 ? null : () {
                      _increaseFontSize();
                      setDialogState(() {});
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
    if (!mounted) return;
    setState(() {
      _currentFontSize = (_currentFontSize + 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize);
  }

  void _decreaseFontSize() {
     if (!mounted) return;
    setState(() {
      _currentFontSize = (_currentFontSize - 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize);
  }

  Future<bool> _saveFutureOutline(Novel novel) async {
    if (!mounted) return false;

    final newOutline = _futureOutlineController.text.trim();
    if (newOutline == (novel.futureOutline ?? '')) {
      return true;
    }

    AppLogger.info("Sauvegarde du nouveau plan directeur...", tag: "NovelReaderPage");
    final updatedNovel = novel.copyWith(
      futureOutline: newOutline,
      updatedAt: DateTime.now(),
    );

    try {
      await ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
      _showSnackbarMessage("Plan directeur mis à jour.", Colors.green);
      return true;
    } catch (e) {
      AppLogger.error("Erreur sauvegarde plan directeur", error: e, tag: "NovelReaderPage");
      _showSnackbarMessage("Erreur lors de la sauvegarde du plan.", Colors.redAccent);
      return false;
    }
  }

  void _showNovelInfoSheet(Novel novel) {
    _futureOutlineController.text = novel.futureOutline ?? '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer(builder: (context, ref, child) {
          final isWriterMode = ref.watch(writerModeProvider);
          final asyncNovels = ref.watch(novelsProvider);
          final Novel? currentNovel = asyncNovels.when(
            data: (novels) => novels.firstWhereOrNull((n) => n.id == widget.novelId),
            loading: () => novel,
            error: (err, stack) => novel,
          );

          if (currentNovel == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: DefaultTabController(
              length: isWriterMode ? 3 : 2,
              child: AlertDialog(
                title: const Text("Détails de l'Intrigue"),
                contentPadding: const EdgeInsets.only(top: 20.0),
                content: SizedBox(
                  width: 500,
                  height: 400,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabs: [
                          const Tab(text: "Spécifications"),
                          const Tab(text: "Fiche de route (Passé)"),
                          if (isWriterMode)
                            const Tab(text: "Plan Directeur (Futur)"),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildInfoTabContent(
                              context,
                              children: [
                                SelectableText(
                                  currentNovel.specifications.isNotEmpty
                                      ? currentNovel.specifications
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
                                  currentNovel.roadMap ?? "La fiche de route (résumé du passé) sera générée après quelques chapitres.",
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                                  textAlign: TextAlign.justify,
                                ),
                              ],
                            ),
                            if (isWriterMode)
                              _buildFutureOutlineTab(currentNovel),
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
        });
      },
    );
  }

  Widget _buildFutureOutlineTab(Novel novel) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final theme = Theme.of(context);
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: _isEditingOutline
                    ? TextField(
                        controller: _futureOutlineController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: "Décrivez les prochains chapitres...",
                        ),
                      )
                    : SelectableText(
                        novel.futureOutline?.isNotEmpty == true
                            ? novel.futureOutline!
                            : "Aucun plan directeur (futur) n'a été défini ou généré.",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                        textAlign: TextAlign.justify,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_isEditingOutline)
                    TextButton(
                      child: const Text('Annuler'),
                      onPressed: () {
                        setDialogState(() {
                          _isEditingOutline = false;
                          _futureOutlineController.text = novel.futureOutline ?? '';
                        });
                      },
                    ),
                  IconButton(
                    icon: Icon(_isEditingOutline ? Icons.check : Icons.edit_outlined),
                    tooltip: _isEditingOutline ? 'Sauvegarder le plan' : 'Modifier le plan',
                    onPressed: () {
                      if (_isEditingOutline) {
                        _saveFutureOutline(novel).then((success) {
                           if (success && mounted) {
                             setDialogState((){
                               _isEditingOutline = false;
                             });
                           }
                        });
                      } else {
                        setDialogState(() => _isEditingOutline = true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
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

  // ✅ CORRECTION : Le nettoyage est retiré d'ici
  List<TextSpan> _buildFormattedTextSpans(String text, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    // Le texte est maintenant splitté directement, sans nettoyage préalable.
    final List<String> parts = text.split('*');

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
       AppLogger.info("Creating ScrollController for page $index", tag: "NovelReaderPage");
      _loadAndJumpToScrollPosition(index, newController);
      return newController;
    });

     if (index == _currentPage && controller.hasClients && !controller.hasListeners) {
          AppLogger.info("Re-attaching scroll listener to controller for page $index during build", tag: "NovelReaderPage");
         controller.addListener(_updateScrollProgress);
     } else if (index != _currentPage && controller.hasListeners) {
           try {
              controller.removeListener(_updateScrollProgress);
               AppLogger.info("Detached listener from non-current page $index during build", tag: "NovelReaderPage");
           } catch (e) { /* Ignorer si déjà détaché */ }
     }


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
          try { if (selection.start >= 0 && selection.end <= fullRenderedText.length && selection.start < selection.end) { selectedText = fullRenderedText.substring(selection.start, selection.end).trim(); } } catch (e) { AppLogger.error("Erreur substring", error: e, tag: "NovelReaderPage"); selectedText = ''; }

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

     return RepaintBoundary(
        child: Container(
         color: _getCurrentBackgroundColor(),
         key: ValueKey("chapter_${novel.id}_$index"),
         child: SingleChildScrollView(
           controller: controller,
           padding: EdgeInsets.fromLTRB(
              20.0,
              MediaQuery.of(context).padding.top + kToolbarHeight + 24.0,
              20.0,
              bottomPadding
           ),
           child: textContent,
         ),
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
    bool isLastPage = hasChapters && _currentPage >= 0 && _currentPage == novel.chapters.length - 1;
    bool navigationDisabled = isGenerating || !hasChapters;

    String pageText;
    if (!hasChapters) {
      pageText = 'Pas de chapitres';
    } else if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
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
                : (isLastPage || !hasChapters)
                    ? _buildAddChapterMenu(theme, novel)
                    : IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            tooltip: 'Chapitre suivant',
                            iconSize: 20,
                            color: !navigationDisabled ? primaryColor : disabledColor,
                            disabledColor: disabledColor,
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
      default:
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
        if (!mounted) return;
        if (result == 'next' || result == 'first') {
           final currentNovel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == novel.id);
           if (currentNovel != null) {
              _guardedGenerateChapter(currentNovel);
           } else {
               _showSnackbarMessage("Erreur : Impossible de retrouver les détails du roman.", Colors.redAccent);
           }
        } else if (result == 'final') {
           final currentNovel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == novel.id);
            if (currentNovel != null) {
               _generateAndAddNewChapter(currentNovel, finalChapter: true);
            } else {
                 _showSnackbarMessage("Erreur : Impossible de retrouver les détails du roman.", Colors.redAccent);
            }
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeServiceProvider) == ThemeMode.dark;
    final theme = Theme.of(context);
    final currentBackgroundColor = _getCurrentBackgroundColor();

    final isWriterMode = ref.watch(writerModeProvider);

    final novelsAsyncValue = ref.watch(novelsProvider);

    return novelsAsyncValue.when(
      loading: () => Scaffold(backgroundColor: currentBackgroundColor, body: const Center(child: CircularProgressIndicator())),
      error: (err, stack) {
         AppLogger.error("Erreur chargement novelsProvider", error: err, stackTrace: stack, tag: "NovelReaderPage");
         return Scaffold(backgroundColor: currentBackgroundColor, body: Center(child: Text('Erreur: $err')));
      },
      data: (novels) {
        final novel = novels.firstWhereOrNull((n) => n.id == widget.novelId);

        if (novel == null) {
          // ✅ Correction: Naviguer en arrière si le roman est supprimé/introuvable
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return Scaffold(
            backgroundColor: currentBackgroundColor,
            body: const Center(child: Text("Ce roman n'est plus disponible.")),
          );
        }

        // ✅ Correction : S'assurer que _currentPage est toujours un index valide
        if (_currentPage >= novel.chapters.length) {
          AppLogger.warning("_currentPage ($_currentPage) est invalide après reconstruction. Ajustement à ${max(0, novel.chapters.length - 1)}", tag: "NovelReaderPage");
          // Utiliser un post-frame callback pour éviter de modifier l'état pendant le build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              final newPage = max(0, novel.chapters.length - 1);
              _pageController.jumpToPage(newPage);
              // Le listener _onPageChanged mettra à jour _currentPage
            }
          });
        }


        Color navBarBgColor = theme.colorScheme.surfaceContainer;
        Color navBarPrimaryColor = theme.colorScheme.primary;
        Color navBarTextColor = theme.colorScheme.onSurfaceVariant;
        Color navBarDisabledColor = theme.disabledColor;

        final bool isGenerating = _isGeneratingNextChapter;
         final bool isCurrentPageValid = _currentPage >= 0 && _currentPage < novel.chapters.length;
        final bool canDeleteChapter = novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;
        final bool canEditChapter = novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;

        final bool shouldShowTranslationArea = _selectedWord.isNotEmpty && (_isLoadingTranslation || _translationResult != null);

        return PopScope(
          canPop: !isGenerating,
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
                              IconButton(
                                icon: Icon(
                                  isWriterMode ? Icons.auto_stories_outlined : Icons.edit_note_outlined,
                                  color: isWriterMode ? theme.colorScheme.secondary : null,
                                ),
                                tooltip: isWriterMode ? 'Passer en mode Lecteur' : 'Passer en mode Écrivain',
                                onPressed: () {
                                  ref.read(writerModeProvider.notifier).state = !isWriterMode;
                                  _showSnackbarMessage(
                                    isWriterMode ? 'Mode Lecteur activé.' : 'Mode Écrivain activé. Le plan est maintenant visible.',
                                    isWriterMode ? Colors.grey : Colors.blueAccent,
                                  );
                                },
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: 'Ouvrir le menu',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'info':
                                      _showNovelInfoSheet(novel);
                                      break;
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
                      child: isGenerating
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
                                           AppLogger.warning("PageView.builder called with invalid index $index (max: ${novel.chapters.length - 1})", tag: "NovelReaderPage");
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
    if (novel == null || !mounted) return const SizedBox.shrink();

    final hasChapters = novel.chapters.isNotEmpty;
    final double novelProgress = hasChapters ? ((_currentPage + 1).clamp(1, novel.chapters.length) / novel.chapters.length) : 0.0;


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

