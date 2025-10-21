// lib/novel_reader_page.dart (MODIFIÉ POUR CACHER LE PLAN FUTUR)
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
// import 'package:flutter_markdown/flutter_markdown.dart'; // Plus nécessaire ici
// import 'package:url_launcher/url_launcher.dart'; // Plus nécessaire ici

import 'models.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/ai_prompts.dart';
import 'services/vocabulary_service.dart';
import 'services/sync_service.dart';
import 'widgets/streaming_text_widget.dart';
import 'utils/app_logger.dart'; // Utilisation du logger


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
    // Correction : vérifier mounted avant d'accéder à _pageController
    if (mounted && _pageController.hasClients) {
        _saveCurrentScrollPosition(); // Sauvegarde la position avant de disposer
    }
     // Dispose seulement s'il a été initialisé et a des clients
    if (_pageController.hasClients) {
        _pageController.dispose();
    }
    _chapterProgressNotifier.dispose();
    for (var controller in _scrollControllers.values) {
      // Vérifier si le listener a été ajouté avant de le supprimer
      // (peut ne pas être le cas si la page n'a jamais été affichée)
      // Ceci évite une erreur si le listener n'était pas attaché.
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
      // Correction: Ne rien faire si le contrôleur n'est plus utilisable
      if (!mounted || !_pageController.hasClients || _pageController.page == null) return;
      final newPage = _pageController.page!.round();
      if (newPage != _currentPage) {
        _saveCurrentScrollPosition(); // Sauvegarder la position de l'ancienne page
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
        _attachScrollListenerToCurrentPage(); // Attacher à la nouvelle page
      }
  }


  void _attachScrollListenerToCurrentPage() {
      // Détacher tous les listeners précédents pour éviter les appels multiples
      for (var entry in _scrollControllers.entries) {
          // Utiliser un try-catch au cas où le listener n'aurait pas été ajouté
          try {
             entry.value.removeListener(_updateScrollProgress);
          } catch (e) {
             AppLogger.warning("Listener non trouvé pour ScrollController ${entry.key}", tag: "NovelReaderPage");
          }
      }

      final controller = _scrollControllers[_currentPage];
      if (controller != null && controller.hasClients) {
          // Attacher le listener uniquement au contrôleur de la page actuelle
          controller.addListener(_updateScrollProgress);
          // Mettre à jour immédiatement la progression pour la nouvelle page
          _updateScrollProgress();
      } else {
          // S'il n'y a pas de contrôleur ou qu'il n'est pas prêt, réinitialiser la progression
          _chapterProgressNotifier.value = 0.0;
          AppLogger.info("Aucun ScrollController actif trouvé pour la page $_currentPage.", tag: "NovelReaderPage");
      }
  }


  void _updateScrollProgress() {
    final controller = _scrollControllers[_currentPage];
    if (controller != null && controller.hasClients) {
        // Ajouter une vérification pour éviter la division par zéro si maxScrollExtent est 0
        final maxScroll = controller.position.maxScrollExtent;
        if (maxScroll > 0) {
            final progress = controller.offset / maxScroll;
            _chapterProgressNotifier.value = progress.clamp(0.0, 1.0);
        } else {
            // Si le contenu ne dépasse pas l'écran, considérer comme 100% ou 0% ?
            // 0% semble plus logique si on ne peut pas scroller.
            _chapterProgressNotifier.value = 0.0;
        }
    } else {
        // Si le contrôleur n'est pas prêt, la progression est 0.
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
      // S'assurer que l'index est valide
      initialPage = lastViewedPage.clamp(0, novel.chapters.length - 1);
    } else {
      initialPage = -1; // Indique qu'il n'y a pas de chapitres
    }

    if (mounted) {
      setState(() {
        _currentPage = initialPage;
        _prefsLoaded = true;
      });
      // Recréer le PageController avec la page initiale correcte
      // S'il n'y a pas de chapitre (initialPage = -1), on met 0 pour éviter une erreur
       if (_pageController.hasClients) {
          _pageController.removeListener(_onPageChanged);
          _pageController.dispose();
       }
      _pageController = PageController(initialPage: max(0, _currentPage));
      _pageController.addListener(_onPageChanged);

      // Utiliser addPostFrameCallback pour s'assurer que le widget est construit
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Vérifier à nouveau `mounted` et `hasClients` avant de sauter ou attacher
        if (mounted && _pageController.hasClients && _currentPage != -1) {
          // Pas besoin de jumpToPage si initialPage est correct
          // _pageController.jumpToPage(_currentPage);
           _attachScrollListenerToCurrentPage(); // Important d'attacher ici après la construction
        } else if (mounted && _currentPage == -1) {
           _chapterProgressNotifier.value = 0.0; // État vide
        }
      });
    }
  }


  Future<Novel?> _getNovelFromProvider() async {
    if (!mounted) return null;
    // Utiliser watch pour réagir aux changements ou read si on veut juste la valeur actuelle?
    // 'read' est suffisant ici car on l'appelle dans des méthodes spécifiques.
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
    // Ne rien faire si les préférences ne sont pas chargées ou si le widget n'est plus monté
    if (!_prefsLoaded || !mounted) return;

    final novel = await _getNovelFromProvider();
    if (novel == null) return;

    // Vérifier si la page actuelle est valide
    if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
      final controller = _scrollControllers[_currentPage];
      // Vérifier si le contrôleur existe et est attaché à une vue
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
      // Utiliser addPostFrameCallback pour s'assurer que le layout est prêt
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Vérifier à nouveau que tout est prêt avant de sauter
        if (mounted && controller.hasClients) {
          // Vérifier si la position est valide par rapport aux limites actuelles
          final maxScroll = controller.position.maxScrollExtent;
           final positionToJump = savedPosition.clamp(0.0, maxScroll); // Clamp pour éviter les erreurs

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
    // S'assurer que les préférences sont chargées et que la page est valide
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
     // Vérifier si l'index est valide
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

    // S'assurer que le contrôleur d'édition est prêt avant de sauter
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


  // ✅ CORRIGÉ : Utilise la nouvelle méthode `updateChapter` du provider.
  Future<void> _saveEdits(Novel novel) async {
    if (_editingChapterIndex == null || !mounted) return;

    final int chapterIndexToUpdate = _editingChapterIndex!;
    final double editorScrollOffset = _editingScrollController.hasClients ? _editingScrollController.offset : 0.0;
     AppLogger.info("Saving edits for chapter $chapterIndexToUpdate. Editor scroll offset: $editorScrollOffset", tag: "NovelReaderPage");

    // Vérifier si l'index est toujours valide (au cas où des chapitres auraient été supprimés entre temps?)
    if (chapterIndexToUpdate < 0 || chapterIndexToUpdate >= novel.chapters.length) {
        AppLogger.error("Cannot save edits, chapter index $chapterIndexToUpdate is invalid.", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de sauvegarder, le chapitre semble invalide.", Colors.redAccent);
         setState(() { _isEditing = false; _editingChapterIndex = null; }); // Reset state
        return;
    }

    final originalChapter = novel.chapters[chapterIndexToUpdate];
    final updatedChapter = Chapter(
      id: originalChapter.id, // Garder l'ID original
      title: _editingTitleController.text.trim(),
      content: _editingContentController.text.trim(),
      createdAt: originalChapter.createdAt, // Garder la date de création originale
    );

    try {
        // Appel à la méthode optimisée du provider
        await ref.read(novelsProvider.notifier).updateChapter(novel.id, updatedChapter);

        final syncTask = SyncTask(
          action: 'update',
          novelId: novel.id,
          // Correction : L'index pour le backend peut être différent de l'ID string
          // Il faut le re-calculer ou passer l'ID si le backend le gère.
          // Supposons que le backend utilise l'index dans la liste actuelle.
          chapterIndex: chapterIndexToUpdate,
          content: updatedChapter.content,
        );
        await ref.read(syncServiceProvider).addTask(syncTask);

        _showSnackbarMessage("Chapitre sauvegardé. La synchronisation se fera en arrière-plan.", Colors.green);

        setState(() {
          _isEditing = false;
          _editingChapterIndex = null;
        });

        // Restaurer la position de lecture après la sauvegarde
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final readerScrollController = _scrollControllers[chapterIndexToUpdate];
          if (mounted && readerScrollController != null && readerScrollController.hasClients) {
              // S'assurer que la position est dans les limites après la mise à jour potentielle du contenu
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
             // On ne sort pas forcément du mode édition en cas d'erreur
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
      // Essayer de forcer le traitement, mais ne pas générer pour l'instant
      ref.read(syncServiceProvider).processQueue();
      return;
    }

    if (_isGeneratingNextChapter) {
      _showSnackbarMessage("L'écrivain est déjà en train de rédiger, patience !", Colors.orangeAccent);
      return;
    }

    AppLogger.info(">>> Appel de _generateAndAddNewChapter depuis _guardedGenerateChapter...", tag: "NovelReaderPage");
    // Passer une copie du novel pour éviter les modifications concurrentes? Non, preparePrompt prend déjà une copie via toJsonForIsolate.
    await _generateAndAddNewChapter(novel);
  }


  Future<void> _generateAndAddNewChapter(Novel novel, {bool finalChapter = false}) async {
    AppLogger.info(">>> _generateAndAddNewChapter appelé. Novel ID: ${novel.id}, Chapitres: ${novel.chapters.length}, finalChapter: $finalChapter", tag: "NovelReaderPage");

    if (!mounted) return; // Vérification précoce

    setState(() {
      _isGeneratingNextChapter = true;
      _chapterStream = null; // Réinitialiser le stream
    });

    try {
      AppLogger.info(">>> Appel de AIService.preparePrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      final prompt = await AIService.preparePrompt(
        novel: novel, // Passer l'objet novel actuel
        isFirstChapter: novel.chapters.isEmpty,
        isFinalChapter: finalChapter,
      );
      AppLogger.success(">>> AIService.preparePrompt terminé avec succès dans _generateAndAddNewChapter.", tag: "NovelReaderPage");

      // Log détaillé du prompt (utile pour le débogage)
      AppLogger.info("================ PROMPT FINAL ENVOYÉ À L'IA ================", tag: "NovelReaderPage");
      // Attention: Ne pas logger des prompts trop longs en production
      if (kDebugMode) {
          debugPrint(prompt); // Utiliser debugPrint pour les logs potentiellement longs
      } else {
           AppLogger.info("Prompt généré (longueur: ${prompt.length})", tag: "NovelReaderPage");
      }
      AppLogger.info("=========================================================", tag: "NovelReaderPage");


      if (!mounted) return;

      AppLogger.info(">>> Appel de AIService.streamChapterFromPrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      final stream = AIService.streamChapterFromPrompt(
        prompt: prompt,
        modelId: novel.modelId, // Utiliser le modelId du novel actuel
        language: novel.language,
      );

      // Mettre à jour l'état uniquement si le widget est toujours monté
      if (mounted) {
         setState(() => _chapterStream = stream);
      }

    } catch (e, stackTrace) {
      AppLogger.error("❌ Erreur DANS _generateAndAddNewChapter (probablement pendant preparePrompt)", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
      _handleGenerationError(e); // Gérer l'erreur (met à jour l'état, affiche message)
    }
  }


  // ✅ CORRIGÉ : Utilise la nouvelle méthode `addChapter` du provider.
  Future<void> _finalizeChapterGeneration(Novel novel, String fullText) async {
     AppLogger.info("Finalizing chapter generation. Received text length: ${fullText.length}", tag: "NovelReaderPage");
    if (fullText.trim().isEmpty) {
      AppLogger.error("Erreur: L'IA a renvoyé un stream vide (probable surcharge du modèle).", tag: "NovelReaderPage");
      _handleGenerationError(ApiServerException("L'écrivain a renvoyé un chapitre vide. Réessayez.", statusCode: null));
      return;
    }
    // Vérifier si le widget est toujours monté avant de continuer
    if (!mounted) {
         AppLogger.warning("Widget non monté lors de la finalisation du chapitre.", tag: "NovelReaderPage");
        return;
    }

    final newChapter = AIService.extractTitleAndContent(
      fullText,
      novel.chapters.length, // L'index du nouveau chapitre sera la taille actuelle
      novel.chapters.isEmpty,
      false, // Supposer que ce n'est pas le chapitre final (géré par le bouton dédié)
      AIPrompts.getPromptsFor(novel.language),
    );

    try {
        // Appel à la méthode optimisée du provider pour ajouter le chapitre
        await ref.read(novelsProvider.notifier).addChapter(novel.id, newChapter);
        AppLogger.success("Nouveau chapitre ajouté au provider: ${newChapter.title}", tag: "NovelReaderPage");

        // --- Déplacement de la logique de mise à jour des plans ici ---
        if (!mounted) return; // Re-vérifier après l'appel asynchrone

        // Re-lire l'état mis à jour du Novel depuis le provider
        // C'est crucial car `addChapter` a modifié l'état
        final updatedNovelState = await ref.read(novelsProvider.future);
        final updatedNovel = updatedNovelState.firstWhereOrNull((n) => n.id == novel.id);

        if (updatedNovel == null) {
             AppLogger.error("Impossible de retrouver le novel mis à jour après ajout du chapitre.", tag: "NovelReaderPage");
             // Gérer l'erreur? Pour l'instant on continue la synchro
        } else {
             // Déclencher la mise à jour du roadmap (passé) si nécessaire
             // Passer le contexte actuel et le novel mis à jour
            // Ne pas await ici pour ne pas bloquer l'UI, le service gère l'affichage des snackbars
             Future microtask = ref.read(roadmapServiceProvider).triggerRoadmapUpdateIfNeeded(updatedNovel, context);

             // Déclencher la mise à jour du plan directeur (futur) si nécessaire
             // Ne pas await ici non plus
             Future microtask2 = ref.read(roadmapServiceProvider).triggerFutureOutlineUpdateIfNeeded(updatedNovel, context);
        }
        // --- Fin du déplacement ---


        // Ajouter à la file de synchronisation backend
        final syncTask = SyncTask(
          action: 'add',
          novelId: novel.id,
          content: newChapter.content,
          // L'index pour le backend pourrait être basé sur la longueur *avant* l'ajout
          // ou l'ID si le backend le gère. Utilisons la longueur *après* ajout (nouvel index).
          chapterIndex: novel.chapters.length, // L'index du chapitre ajouté est la nouvelle longueur - 1
        );
        await ref.read(syncServiceProvider).addTask(syncTask);
         AppLogger.info("Tâche de synchronisation 'add' ajoutée pour le nouveau chapitre.", tag: "NovelReaderPage");


        _showSnackbarMessage('Chapitre "${newChapter.title}" ajouté.', Colors.green, durationSeconds: 5);


        // Mise à jour de l'état UI et navigation vers la nouvelle page
        setState(() {
          _isGeneratingNextChapter = false;
          _chapterStream = null;
          // _currentPage est mis à jour par le listener de PageController quand on navigue
        });

        // Naviguer vers la nouvelle page ajoutée
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            // Aller à la dernière page (le chapitre nouvellement ajouté)
             // Re-calculer la longueur au cas où l'état aurait changé
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
        // Gérer l'erreur - Afficher un message et réinitialiser l'état de génération
        _handleGenerationError(ApiException("Erreur lors de la sauvegarde du chapitre: ${e.toString()}"));
    }
  }


  void _handleGenerationError(Object error) {
    // S'assurer que le widget est toujours monté
    if (!mounted) {
         AppLogger.warning("handleGenerationError appelé mais widget non monté.", tag: "NovelReaderPage");
        return;
    }

     AppLogger.error("Gestion de l'erreur de génération: $error", tag: "NovelReaderPage");


    setState(() {
      _isGeneratingNextChapter = false;
      _chapterStream = null; // S'assurer que l'animation de streaming s'arrête
    });

    String message;
    if (error is ApiServerException) {
      message = error.toString(); // Utiliser le message personnalisé de l'exception
    } else if (error is ApiConnectionException) {
      message = error.toString();
    } else if (error is ApiException) {
       message = error.message; // Message générique de l'API
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

  // ✅ CORRIGÉ : Utilise la nouvelle méthode `deleteChapter` du provider.
  Future<void> _deleteCurrentChapter(Novel novel) async {
    if (!mounted || novel.chapters.isEmpty || _isGeneratingNextChapter) {
        AppLogger.warning("Suppression annulée: !mounted=${!mounted}, isEmpty=${novel.chapters.isEmpty}, isGenerating=$_isGeneratingNextChapter", tag: "NovelReaderPage");
        return;
    }

    final int chapterIndexToDelete = _currentPage;
    // Vérification robuste de l'index
    if (chapterIndexToDelete < 0 || chapterIndexToDelete >= novel.chapters.length) {
        AppLogger.error("Tentative de suppression d'un index invalide: $chapterIndexToDelete (total: ${novel.chapters.length})", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de déterminer quel chapitre supprimer.", Colors.redAccent);
        return;
    }
    final Chapter chapterToDelete = novel.chapters[chapterIndexToDelete];
    final int chapterNumber = chapterIndexToDelete + 1; // Pour l'affichage utilisateur

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

    // Ajouter la tâche de synchro AVANT de modifier l'état local
    final syncTask = SyncTask(
      action: 'delete_chapter',
      novelId: novel.id,
      chapterIndex: chapterIndexToDelete, // L'index actuel avant suppression
    );
    await ref.read(syncServiceProvider).addTask(syncTask);
     AppLogger.info("Tâche de synchronisation 'delete_chapter' ajoutée.", tag: "NovelReaderPage");


    try {
      // Supprimer la position de scroll enregistrée pour ce chapitre
      if(_prefsLoaded) {
        final key = 'scroll_pos_${widget.novelId}_$chapterIndexToDelete';
        if (_prefs.containsKey(key)) {
            await _prefs.remove(key);
             AppLogger.info("Position de scroll supprimée pour le chapitre $chapterIndexToDelete.", tag: "NovelReaderPage");
        }
      }

      // Appel à la méthode optimisée du provider pour supprimer le chapitre de l'état local et Supabase
       AppLogger.info("Appel de novelsProvider.notifier.deleteChapter...", tag: "NovelReaderPage");
      await ref.read(novelsProvider.notifier).deleteChapter(novel.id, chapterToDelete.id);
       AppLogger.success("Chapitre supprimé avec succès via le provider.", tag: "NovelReaderPage");

      _showSnackbarMessage('Chapitre "${chapterToDelete.title}" supprimé.', Colors.green);

      // Important : Il n'est pas nécessaire de gérer manuellement la navigation ici.
      // Le PageView.builder se reconstruira avec la nouvelle liste de chapitres
      // et ajustera automatiquement l'affichage. Le listener _onPageChanged
      // mettra à jour _currentPage si l'index actuel devient invalide.
      // On force juste une reconstruction via invalidateSelf si besoin (déjà fait par le provider)
      // ref.invalidate(novelsProvider); // Normalement pas nécessaire car deleteChapter met à jour l'état


    } catch (e, stackTrace) {
      AppLogger.error("Erreur critique lors de la suppression du chapitre", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
       if (mounted) {
         _showSnackbarMessage("Erreur critique lors de la suppression : ${e.toString()}", Colors.redAccent);
       }
       // Que faire ici ? L'état local peut être désynchronisé de Supabase.
       // Invalider le provider pour forcer un rechargement ?
       ref.invalidate(novelsProvider);
    }
  }


  void _toggleUI() {
    if(mounted) {
      setState(() => _showUIElements = !_showUIElements);
      if(!_showUIElements) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // Cacher aussi la zone de traduction si elle est visible
        _selectionTimer?.cancel();
         // Vérifier `mounted` à nouveau avant `setState` dans ce bloc
         if (mounted) {
             setState(() { _selectedWord = ''; _translationResult = null; _isLoadingTranslation = false; });
         }
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }


  void _handleTapToToggleUI(TapUpDetails details) {
    // Vérifier si le widget est toujours monté
    if (!mounted) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return; // Ne rien faire si le RenderBox n'est pas trouvé

    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final double navigationBarHeight = kBottomNavigationBarHeight + 10; // Barre de nav + marge
    final double translationAreaHeight = (_selectedWord.isNotEmpty || _isLoadingTranslation) ? 120 : 0; // Estimation hauteur zone traduction + padding
    final double deadZoneHeight = bottomSafeArea + navigationBarHeight + translationAreaHeight;

    // S'assurer que localPosition.dy est valide
    if (localPosition.dy < renderBox.size.height - deadZoneHeight) {
      _toggleUI();
    } else {
       AppLogger.info("Tap détecté dans la zone morte (UI/Traduction), UI non basculée.", tag: "NovelReaderPage");
    }
  }


  void _showFontSizeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // Permettre de fermer en cliquant à l'extérieur
      builder: (BuildContext context) {
        // Utiliser StatefulBuilder pour que seul le contenu du dialogue se mette à jour
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Taille de la police'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    // Désactiver si la taille minimale est atteinte
                    onPressed: _currentFontSize <= 10.0 ? null : () {
                      // Mettre à jour l'état global ET l'état local du dialogue
                      _decreaseFontSize(); // Met à jour l'état du widget principal
                      setDialogState(() {}); // Redessine le dialogue
                    },
                  ),
                  // Afficher la taille actuelle
                  Text(
                    _currentFontSize.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    // Désactiver si la taille maximale est atteinte
                     onPressed: _currentFontSize >= 50.0 ? null : () {
                      _increaseFontSize(); // Met à jour l'état du widget principal
                      setDialogState(() {}); // Redessine le dialogue
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
    // Vérifier mounted avant setState
    if (!mounted) return;
    setState(() {
      _currentFontSize = (_currentFontSize + 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize); // Sauvegarder la préférence
  }

  void _decreaseFontSize() {
     if (!mounted) return;
    setState(() {
      _currentFontSize = (_currentFontSize - 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize);
  }

  // ✅ FONCTION SUPPRIMÉE : _showFutureOutlineDialog
  // ✅ FONCTION SUPPRIMÉE : _regenerateFutureOutline


  void _showNovelInfoSheet(Novel novel) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: DefaultTabController(
            length: 2, // Garder 2 onglets : Spécifications et Fiche de route (passé)
            child: AlertDialog(
              title: const Text("Détails de l'Intrigue"),
              contentPadding: const EdgeInsets.only(top: 20.0),
              content: SizedBox(
                width: 500, // Ajuster selon besoin
                height: 350, // Ajuster selon besoin
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: "Spécifications"),
                        Tab(text: "Fiche de route (Passé)"), // Renommer pour clarifier
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Onglet Spécifications (inchangé)
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
                          // Onglet Fiche de route (Passé)
                          _buildInfoTabContent(
                            context,
                            children: [
                              SelectableText(
                                // Afficher roadMap (le résumé du passé)
                                novel.roadMap ?? "La fiche de route (résumé du passé) sera générée après quelques chapitres.",
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

  // Fonction pour construire les TextSpans (inchangée)
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

  // Widget _buildChapterReader (inchangé dans sa logique principale)
  Widget _buildChapterReader(Chapter chapter, int index, Novel novel) {
    final baseStyle = _getBaseTextStyle();

    final titleStyle = baseStyle.copyWith(
        fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! + 4 : null,
        fontWeight: FontWeight.w800,
        height: 1.8,
        color: baseStyle.color?.withAlpha((255 * 0.9).round())
    );
    final contentStyle = baseStyle.copyWith(height: 1.7);

    // Récupérer ou créer le ScrollController pour cette page
    final controller = _scrollControllers.putIfAbsent(index, () {
      final newController = ScrollController();
       AppLogger.info("Creating ScrollController for page $index", tag: "NovelReaderPage");
       // Charger la position après la création et l'attachement potentiel
      _loadAndJumpToScrollPosition(index, newController);
      return newController;
    });

    // S'assurer que le listener est attaché si c'est la page actuelle
     if (index == _currentPage && controller.hasClients && !controller.hasListeners) {
          AppLogger.info("Re-attaching scroll listener to controller for page $index during build", tag: "NovelReaderPage");
         controller.addListener(_updateScrollProgress);
     } else if (index != _currentPage && controller.hasListeners) {
          // Détacher le listener si ce n'est pas la page actuelle (sécurité)
          // Normalement géré par _attachScrollListenerToCurrentPage
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
           // Correction : Vérifier si la langue est Japonais avant de déclencher
          if (isValidForLookup && novel.language == 'Japonais') {
            _selectionTimer?.cancel();
            // Appeler _triggerReadingAndTranslation uniquement si monté
            if (mounted) { _triggerReadingAndTranslation(selectedText); }
          } else {
             // Si la sélection n'est pas valide pour la recherche ou si ce n'est pas Japonais,
             // cacher la zone de traduction si elle est visible.
            if ((_selectedWord.isNotEmpty || _isLoadingTranslation || _translationResult != null) && mounted) {
              setState(() {
                _selectedWord = '';
                _translationResult = null;
                _isLoadingTranslation = false;
              });
            }
          }
        } else if (cause == SelectionChangedCause.tap || cause == SelectionChangedCause.keyboard) {
            // Cacher la zone de traduction sur un simple tap ou action clavier
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
      selectionControls: MaterialTextSelectionControls(), // Contrôles de sélection standards
    );

    // Ajuster le padding en fonction de la visibilité de l'UI
    final bottomPadding = _showUIElements ? 120.0 : 60.0;

      // Utiliser RepaintBoundary pour optimiser le rendu si le contenu est complexe
     return RepaintBoundary(
        child: Container(
         color: _getCurrentBackgroundColor(), // Couleur de fond
         // Utiliser un Key pour aider Flutter à identifier le widget quand on change de page
         key: ValueKey("chapter_${novel.id}_$index"),
         child: SingleChildScrollView(
           controller: controller,
           padding: EdgeInsets.fromLTRB(
              20.0, // Gauche
              MediaQuery.of(context).padding.top + kToolbarHeight + 24.0, // Haut (safe area + app bar + marge)
              20.0, // Droite
              bottomPadding // Bas (variable selon UI)
           ),
           child: textContent,
         ),
       ),
     );
  }



  // Widget _buildChapterEditor (inchangé)
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
              maxLines: null, // Permet plusieurs lignes
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Contenu du chapitre...',
                hintStyle: baseStyle.copyWith(color: hintColor),
                border: InputBorder.none, // Pas de bordure visible
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget _buildTranslationArea (inchangé)
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
          bottom: max(16.0, MediaQuery.of(context).padding.bottom + 4), // Prend en compte la safe area du bas
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Prend la hauteur minimum nécessaire
          children: [
            // Titre avec le mot sélectionné
            Text(
              'Infos pour : "${_selectedWord.length > 30 ? "${_selectedWord.substring(0, 30)}..." : _selectedWord}"',
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Affichage du chargement ou des résultats/erreurs
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
                : Column( // Affichage des résultats ou erreurs
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Lecture Hiragana (si applicable)
                      if (hasReadingInfo) ...[
                        Text("Lecture Hiragana :", style: labelStyle),
                        const SizedBox(height: 3),
                        readingError != null
                            ? SelectableText(readingError, style: errorStyle) // Afficher l'erreur de lecture
                            : SelectableText(reading ?? '(Non trouvée)', style: valueStyle), // Afficher la lecture ou fallback
                        if (hasTranslationInfo) const SizedBox(height: 10), // Espace si traduction suit
                      ],
                      // Traduction Français
                      if (hasTranslationInfo) ...[
                        Text("Traduction Français :", style: labelStyle),
                        const SizedBox(height: 3),
                        translationError != null
                            ? SelectableText(translationError, style: errorStyle) // Afficher l'erreur de traduction
                            : SelectableText(translation ?? '(Non trouvée)', style: valueStyle), // Afficher la traduction ou fallback
                      ],
                      // Message si aucune info n'est disponible
                      if (!hasAnyInfo)
                        Text("(Aucune information trouvée)", style: valueStyle?.copyWith(fontStyle: FontStyle.italic, color: textColor.withAlpha((255 * 0.6).round()))),
                    ],
                  ),
          ],
        ),
      ),
    );
  }


  // Widget _buildEmptyState (inchangé)
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

  // Widget _buildChapterNavigation (inchangé)
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
    // Correction : s'assurer que _currentPage est valide avant de comparer
    bool isLastPage = hasChapters && _currentPage >= 0 && _currentPage == novel.chapters.length - 1;
    bool navigationDisabled = isGenerating || !hasChapters;

    String pageText;
    if (!hasChapters) {
      pageText = 'Pas de chapitres';
    } else if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
      // Affichage 1-based pour l'utilisateur
      pageText = 'Chapitre ${_currentPage + 1} / ${novel.chapters.length}';
    } else {
       // Cas où _currentPage pourrait être invalide (ex: après suppression)
      pageText = 'Chargement...';
    }


    return Material(
      color: backgroundColor, // Fond de la barre de navigation
      child: Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 4,
          bottom: max(8.0, MediaQuery.of(context).padding.bottom) // Prend en compte la safe area
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Bouton Précédent
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: 'Chapitre précédent',
              iconSize: 20,
              color: canGoBack && !navigationDisabled ? primaryColor : disabledColor,
              disabledColor: disabledColor, // Assure que la couleur désactivée est correcte
              onPressed: canGoBack && !navigationDisabled
                  ? () {
                      _selectionTimer?.cancel(); // Annuler la sélection de texte
                      if (_pageController.hasClients) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    }
                  : null, // Désactivé si on ne peut pas reculer
            ),
            // Indicateur de page
            Flexible( // Pour gérer les titres longs
              child: Text(
                pageText,
                style: theme.textTheme.labelLarge?.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis, // Points de suspension si trop long
              ),
            ),
            // Bouton Suivant ou Ajout/Génération
            isGenerating
                ? const SizedBox( // Indicateur de chargement pendant la génération
                    width: 48, // Largeur fixe pour alignement
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5)
                      )
                    ),
                  )
                 // Si c'est la dernière page (ou s'il n'y a pas de chapitre), montrer le menu d'ajout
                : (isLastPage || !hasChapters)
                    ? _buildAddChapterMenu(theme, novel)
                    // Sinon, montrer le bouton Suivant
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
                                : null, // Désactivé si on ne peut pas avancer
                          )

          ],
        ),
      ),
    );
  }


  // Widget _buildAddChapterMenu (inchangé)
  Widget _buildAddChapterMenu(ThemeData theme, Novel novel) {
    final iconColor = _isGeneratingNextChapter ? theme.disabledColor : theme.colorScheme.primary;
    // Déterminer la couleur du menu popup en fonction du thème
    Color popupMenuColor;
    Color popupMenuTextColor;
    switch (Theme.of(context).brightness) {
      case Brightness.dark:
        popupMenuColor = theme.colorScheme.surfaceContainerHighest; // Plus sombre en thème sombre
        popupMenuTextColor = theme.colorScheme.onSurface;
        break;
      case Brightness.light:
      default:
        popupMenuColor = theme.colorScheme.surfaceContainerHigh; // Plus clair en thème clair
        popupMenuTextColor = theme.colorScheme.onSurface;
        break;
    }
    final bool isMenuEnabled = !_isGeneratingNextChapter;
    final bool hasChapters = novel.chapters.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(Icons.add_circle_outline, color: iconColor),
      tooltip: hasChapters ? 'Options du chapitre suivant' : 'Générer le premier chapitre',
      offset: const Offset(0, -120), // Positionner le menu au-dessus du bouton
      color: popupMenuColor,
      enabled: isMenuEnabled,
      onOpened: () { if (!_showUIElements) _toggleUI(); }, // Afficher l'UI si elle est cachée
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        // Option différente si c'est le premier chapitre ou les suivants
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
              contentPadding: EdgeInsets.zero, // Compact
              dense: true,
            ),
          )
        else // S'il n'y a pas de chapitres
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

        // Option pour générer le chapitre final (seulement si des chapitres existent)
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
        if (!mounted) return; // Vérifier avant d'agir
        if (result == 'next' || result == 'first') {
          // Relire l'état actuel du novel avant de générer
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

    // Surveiller l'état des romans
    final novelsAsyncValue = ref.watch(novelsProvider);

    return novelsAsyncValue.when(
      loading: () => Scaffold(backgroundColor: currentBackgroundColor, body: const Center(child: CircularProgressIndicator())),
      error: (err, stack) {
         AppLogger.error("Erreur chargement novelsProvider", error: err, stackTrace: stack, tag: "NovelReaderPage");
         return Scaffold(backgroundColor: currentBackgroundColor, body: Center(child: Text('Erreur: $err')));
      },
      data: (novels) {
        // Trouver le roman spécifique par ID
        final novel = novels.firstWhereOrNull((n) => n.id == widget.novelId);

        // Gérer le cas où le roman n'est pas trouvé (supprimé ?)
        if (novel == null) {
          return Scaffold(
            backgroundColor: currentBackgroundColor,
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context))),
            body: const Center(child: Text("Ce roman n'a pas pu être chargé ou a été supprimé.")),
          );
        }

        // Définir les couleurs pour la barre de navigation
        Color navBarBgColor = theme.colorScheme.surfaceContainer;
        Color navBarPrimaryColor = theme.colorScheme.primary;
        Color navBarTextColor = theme.colorScheme.onSurfaceVariant;
        Color navBarDisabledColor = theme.disabledColor;

        final bool isGenerating = _isGeneratingNextChapter;
        // Vérifier si la page actuelle est valide pour la suppression/édition
         final bool isCurrentPageValid = _currentPage >= 0 && _currentPage < novel.chapters.length;
        final bool canDeleteChapter = novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;
        final bool canEditChapter = novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;

        // Déterminer si la zone de traduction doit être affichée
        final bool shouldShowTranslationArea = _selectedWord.isNotEmpty && (_isLoadingTranslation || _translationResult != null);

        // PopScope gère le bouton retour du système
        return PopScope(
          canPop: !isGenerating, // Empêcher de quitter pendant la génération
          onPopInvoked: (bool didPop) {
            if (!didPop) { // Si la navigation retour a été empêchée
              if (isGenerating && mounted) {
                _showSnackbarMessage("Veuillez attendre la fin de la génération en cours.", Colors.orangeAccent);
              }
            } else { // Si la navigation a réussi (retour autorisé)
              _saveCurrentScrollPosition(); // Sauvegarder la position avant de quitter
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // Restaurer l'UI système
            }
          },
          child: Scaffold(
            extendBodyBehindAppBar: true, // Le corps passe sous l'AppBar transparente
            backgroundColor: currentBackgroundColor,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight), // Hauteur standard AppBar
              child: _isEditing // Afficher l'AppBar d'édition ou de lecture
                ? AppBar( // AppBar pour le mode édition
                    backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
                    foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
                    title: Text('Modifier le chapitre', style: Theme.of(context).appBarTheme.titleTextStyle),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Annuler les modifications',
                      onPressed: _cancelEditing, // Annuler
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: 'Sauvegarder les modifications',
                        onPressed: () => _saveEdits(novel), // Sauvegarder
                      ),
                    ],
                  )
                : AnimatedOpacity( // AppBar pour le mode lecture (avec fondu)
                    opacity: _showUIElements ? 1.0 : 0.0, // Visible ou non selon _showUIElements
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer( // Ignorer les clics si invisible
                      ignoring: !_showUIElements,
                      child: ClipRRect( // Pour l'effet de flou
                        child: BackdropFilter( // Effet de flou
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: AppBar(
                            title: Text(novel.title, style: Theme.of(context).appBarTheme.titleTextStyle),
                            backgroundColor: Theme.of(context).appBarTheme.backgroundColor?.withAlpha((255 * 0.75).round()), // Semi-transparent
                            elevation: 0,
                            scrolledUnderElevation: 0, // Pas d'ombre au scroll
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Retour à la bibliothèque',
                              onPressed: () => Navigator.pop(context), // Retour simple
                            ),
                            actions: [ // Menu d'options
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: 'Ouvrir le menu',
                                onSelected: (value) {
                                  // Gérer la sélection du menu
                                  switch (value) {
                                    case 'info':
                                      _showNovelInfoSheet(novel);
                                      break;
                                    // ✅ MODIFICATION : Option 'outline' supprimée
                                    // case 'outline':
                                    //   _showFutureOutlineDialog(novel);
                                    //   break;
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
                                  // ✅ MODIFICATION : Option 'outline' supprimée du menu
                                  // const PopupMenuItem<String>(
                                  //   value: 'outline',
                                  //   child: ListTile(leading: Icon(Icons.compass_calibration_outlined), title: Text('Plan Directeur')),
                                  // ),
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    enabled: canEditChapter, // Activer/désactiver selon l'état
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
                                    enabled: canDeleteChapter, // Activer/désactiver selon l'état
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
            body: Stack( // Empiler le contenu principal et les contrôles en bas
              children: [
                // Contenu principal (PageView ou indicateur de chargement)
                Positioned.fill( // Prend tout l'espace disponible
                  child: GestureDetector( // Détecter les taps pour afficher/cacher l'UI
                    onTapUp: _handleTapToToggleUI,
                    child: NotificationListener<ScrollNotification>( // Détecter le scroll pour afficher/cacher l'UI
                      onNotification: (ScrollNotification notification) {
                        if (notification is UserScrollNotification) {
                          final UserScrollNotification userScroll = notification;
                          if (userScroll.direction == ScrollDirection.reverse && _showUIElements) {
                             // Scrolle vers le bas -> Cacher l'UI
                             _toggleUI();
                          } else if (userScroll.direction == ScrollDirection.forward && !_showUIElements) {
                             // Scrolle vers le haut -> Afficher l'UI
                             _toggleUI();
                          }
                        }
                        return false; // Ne pas empêcher le scroll normal
                      },
                      child: isGenerating // Afficher l'indicateur de génération ou le PageView
                          ? _chapterStream == null // Si le stream n'est pas encore prêt
                              ? Center( // Afficher "consulte le contexte"
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
                              : Padding( // Si le stream est actif, afficher l'animation
                                  padding: const EdgeInsets.all(20.0), // Marge autour du texte streamé
                                  child: StreamingTextAnimation(
                                    stream: _chapterStream!,
                                    style: _getBaseTextStyle(),
                                    onDone: (fullText) => _finalizeChapterGeneration(novel, fullText), // Finaliser quand le stream est complet
                                    onError: (error) => _handleGenerationError(error), // Gérer les erreurs du stream
                                  ),
                                )
                          : !_prefsLoaded // Si les préférences ne sont pas chargées
                              ? const Center(child: CircularProgressIndicator()) // Afficher chargement initial
                              : novel.chapters.isEmpty // S'il n'y a pas de chapitres
                                  ? _buildEmptyState(theme) // Afficher l'état vide
                                  : PageView.builder( // Afficher les pages des chapitres
                                      physics: _isEditing ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(), // Bloquer le swipe en mode édition
                                      // Clé importante pour forcer la reconstruction si le nombre de chapitres change
                                      key: ValueKey("${novel.id}_${novel.chapters.length}"),
                                      controller: _pageController,
                                      itemCount: novel.chapters.length,
                                      itemBuilder: (context, index) {
                                        // Sécurité: vérifier si l'index est valide
                                        if (index >= novel.chapters.length) {
                                           AppLogger.warning("PageView.builder called with invalid index $index (max: ${novel.chapters.length - 1})", tag: "NovelReaderPage");
                                          return Container(color: _getCurrentBackgroundColor(), child: Center(child: Text("Chargement...", style: TextStyle(color: _getCurrentTextColor()))));
                                        }
                                        final chapter = novel.chapters[index];

                                        // Afficher l'éditeur ou le lecteur
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
                // Contrôles en bas de l'écran (zone de traduction, barre de progression, navigation)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Prend la hauteur minimum
                    children: [
                      // Zone de traduction (animée)
                      AnimatedSize( // S'anime en hauteur quand elle apparaît/disparaît
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: shouldShowTranslationArea ? _buildTranslationArea(theme) : const SizedBox.shrink(), // Afficher ou non
                      ),
                      // Barre de progression et navigation (si pas en mode édition)
                      if (!_isEditing)
                        AnimatedSlide( // Glisse vers le bas pour se cacher
                          duration: const Duration(milliseconds: 200),
                          offset: _showUIElements ? Offset.zero : const Offset(0, 2), // Position normale ou décalée vers le bas
                          child: Column(
                            children: [
                              // Barres de progression
                              _buildProgressBars(theme, navBarPrimaryColor, navBarTextColor),
                              // Barre de navigation entre chapitres
                              _buildChapterNavigation(
                                theme: theme,
                                backgroundColor: navBarBgColor,
                                primaryColor: navBarPrimaryColor,
                                textColor: navBarTextColor,
                                disabledColor: navBarDisabledColor,
                                isGenerating: isGenerating, // État de génération en cours
                                novel: novel, // Passer le novel actuel
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
    // Lire une seule fois le novel au début de la construction
    final novel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == widget.novelId);
    if (novel == null || !mounted) return const SizedBox.shrink(); // Ne rien afficher si novel non trouvé ou widget démonté

    final hasChapters = novel.chapters.isNotEmpty;
    // Calculer la progression globale (attention à la division par zéro)
    final double novelProgress = hasChapters ? ((_currentPage + 1).clamp(1, novel.chapters.length) / novel.chapters.length) : 0.0;


    return IgnorePointer( // Ignorer les interactions sur les barres
      child: Container(
        // Couleur de fond légèrement transparente pour se superposer au contenu
        color: theme.colorScheme.surfaceContainer.withAlpha(200),
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0), // Marges internes
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre de progression du chapitre actuel (écoute ValueNotifier)
            ValueListenableBuilder<double>(
              valueListenable: _chapterProgressNotifier,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value, // Valeur de 0.0 à 1.0
                  backgroundColor: primaryColor.withAlpha((255 * 0.2).round()), // Fond transparent
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor), // Couleur de progression
                  minHeight: 2, // Hauteur fine
                );
              },
            ),
            const SizedBox(height: 4), // Espace entre les barres
            // Barre de progression globale du roman
            LinearProgressIndicator(
              value: novelProgress, // Progression globale calculée
              backgroundColor: textColor.withAlpha((255 * 0.2).round()),
              valueColor: AlwaysStoppedAnimation<Color>(textColor.withAlpha((255 * 0.5).round())),
              minHeight: 2,
            ),
          ],
        ),
      ),
    );
  }

} // Fin de NovelReaderPageState