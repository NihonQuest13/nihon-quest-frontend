// lib/novel_reader_page.dart (CORRIGÉ POUR LA GESTION DE SUPPRESSION/MODIFICATION ET LECTURE SEULE)
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:japanese_story_app/widgets/optimized_common_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ✅ AJOUT: Pour récupérer l'ID utilisateur

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

  // ✅ AJOUT: Récupérer l'ID de l'utilisateur actuel
  final String? _currentUserId = Supabase.instance.client.auth.currentUser?.id;

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
    // ✅ CORRECTION: Ne pas cacher la barre d'état si showUIElements est déjà true
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_showUIElements) {
       SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
      // ✅ MODIFICATION: Utilisation de _prefs directement (déjà disponible)
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
      // Détacher les listeners précédents sur TOUS les contrôleurs de manière robuste
      for (var entry in _scrollControllers.entries) {
          // On tente de retirer le listener de manière robuste, car on ne peut pas vérifier hasListeners (propriété protégée)
          try {
             entry.value.removeListener(_updateScrollProgress);
          } catch (e) {
             // Ignorer les erreurs si le listener n'était pas là (pas de log, c'est l'état normal)
          }
      }

      final controller = _scrollControllers[_currentPage];
      if (controller != null && controller.hasClients) {
          // Re-ajouter le listener pour le contrôleur actuel (il sera le seul)
          controller.addListener(_updateScrollProgress);
          
          // Mettre à jour immédiatement après l'attachement
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollProgress());
          AppLogger.info("Listener attaché au ScrollController pour la page $_currentPage. (via attachement forcé)", tag: "NovelReaderPage");
      }
       else {
          // Aucun controller ou pas prêt
          _chapterProgressNotifier.value = 0.0;
          AppLogger.info("Aucun ScrollController actif trouvé ou non prêt pour la page $_currentPage.", tag: "NovelReaderPage");
      }
  }


  void _updateScrollProgress() {
    if (!mounted) return; // Sécurité supplémentaire
    final controller = _scrollControllers[_currentPage];
    if (controller != null && controller.hasClients) {
        final maxScroll = controller.position.maxScrollExtent;
        final currentScroll = controller.offset;
        // Gérer le cas où maxScrollExtent est 0 (contenu plus petit que l'écran)
        if (maxScroll > 0) {
            final progress = (currentScroll / maxScroll).clamp(0.0, 1.0);
            // Vérifier si la valeur a changé pour éviter des rebuilds inutiles
            if (_chapterProgressNotifier.value != progress) {
              _chapterProgressNotifier.value = progress;
            }
        } else {
             // Si pas de scroll possible, considérer comme 0% ou 100% ?
             // 0% semble plus logique si on n'a pas bougé
            if (_chapterProgressNotifier.value != 0.0) {
               _chapterProgressNotifier.value = 0.0;
            }
        }
    } else {
        // Si pas de controller, le progrès est 0
        if (_chapterProgressNotifier.value != 0.0) {
          _chapterProgressNotifier.value = 0.0;
        }
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
      initialPage = -1; // Indicateur pour "pas de chapitres"
    }

    if (mounted) {
      setState(() {
        _currentPage = initialPage;
        _prefsLoaded = true;
      });
      // Recréer le PageController avec la page initiale correcte
      // S'assurer que l'ancien est disposé s'il existe
       if (_pageController.hasClients) {
          _pageController.removeListener(_onPageChanged);
          // Ne pas appeler dispose() ici, car cela pourrait être appelé trop tôt.
          // Le dispose() dans la méthode dispose() de la classe State gérera cela.
       }
      _pageController = PageController(initialPage: max(0, _currentPage)); // Utiliser max(0, ...) car -1 n'est pas valide
      _pageController.addListener(_onPageChanged);

      // S'assurer que le listener de scroll est attaché après le layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients && _currentPage != -1) {
           _attachScrollListenerToCurrentPage();
        } else if (mounted && _currentPage == -1) {
           _chapterProgressNotifier.value = 0.0; // Cas sans chapitres
        }
      });
    }
  }


  Future<Novel?> _getNovelFromProvider() async {
    if (!mounted) return null;
    // Utiliser ref.read pour obtenir la valeur actuelle sans écouter les changements ici
    final asyncNovels = ref.read(novelsProvider);
    return asyncNovels.when(
      data: (novels) => novels.firstWhereOrNull((n) => n.id == widget.novelId),
      // Gérer loading/error est moins crucial ici car on s'attend à ce que les données soient chargées
      // avant d'entrer dans le lecteur, mais on logue pour le débogage.
      loading: () {
        AppLogger.warning("Accès à novelsProvider pendant le chargement initial dans _getNovelFromProvider.", tag: "NovelReaderPage");
        return null; // Ou attendre si nécessaire ?
      },
      error: (e, s) {
        AppLogger.error("Erreur lors de l'accès à novelsProvider dans _getNovelFromProvider", error: e, stackTrace: s, tag: "NovelReaderPage");
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
          final currentPosition = controller.position.pixels;
          await _prefs.setDouble('scroll_pos_${widget.novelId}_$_currentPage', currentPosition);
           AppLogger.info("Position scroll sauvegardée pour page $_currentPage: $currentPosition", tag: "NovelReaderPage");
        } catch (e) {
           AppLogger.error("Échec sauvegarde position scroll pour page $_currentPage", error: e, tag: "NovelReaderPage");
        }
      } else {
         AppLogger.warning("ScrollController pour page $_currentPage non prêt/détaché, sauvegarde impossible.", tag: "NovelReaderPage");
      }
    } else {
       AppLogger.warning("Page actuelle $_currentPage invalide, sauvegarde scroll impossible.", tag: "NovelReaderPage");
    }
  }


  Future<void> _loadAndJumpToScrollPosition(int chapterIndex, ScrollController controller) async {
    if (!_prefsLoaded || !mounted) return;
    final key = 'scroll_pos_${widget.novelId}_$chapterIndex';
    final savedPosition = _prefs.getDouble(key);

    AppLogger.info("Tentative chargement position scroll page $chapterIndex (clé: $key). Trouvé: $savedPosition", tag: "NovelReaderPage");


    if (savedPosition != null) {
      // Utiliser addPostFrameCallback pour s'assurer que le widget est rendu et que maxScrollExtent est calculé
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          final maxScroll = controller.position.maxScrollExtent;
           // S'assurer que la position est valide
           final positionToJump = savedPosition.clamp(0.0, maxScroll);

          if (positionToJump != savedPosition) {
             AppLogger.warning("Position sauvegardée ($savedPosition) clampée à $positionToJump (max: $maxScroll)", tag: "NovelReaderPage");
          }

          controller.jumpTo(positionToJump);
          AppLogger.info("Saut vers position scroll $positionToJump pour page $chapterIndex", tag: "NovelReaderPage");
          // Mettre à jour la barre de progression après le saut
          _updateScrollProgress();
        } else if (mounted) {
           AppLogger.warning("ScrollController page $chapterIndex non prêt lors tentative de saut.", tag: "NovelReaderPage");
        }
      });
    } else {
       // Si pas de position sauvegardée, s'assurer que la progression est à 0
       WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollProgress());
    }
  }


  Future<void> _saveLastViewedPage(int page) async {
    if (!_prefsLoaded || !mounted || page < 0) return;
    try {
      await _prefs.setInt('last_page_${widget.novelId}', page);
      AppLogger.info("Dernière page vue sauvegardée: $page", tag: "NovelReaderPage");
    } catch (e) {
      AppLogger.error("Échec sauvegarde dernière page vue", error: e, tag: "NovelReaderPage");
    }
  }


  Future<void> _saveFontSizePreference(double size) async {
    if (!_prefsLoaded || !mounted) return;
    try {
        await _prefs.setDouble(_prefFontSizeKey, size);
        AppLogger.info("Préférence taille police sauvegardée: $size", tag: "NovelReaderPage");
    } catch (e) {
        AppLogger.error("Échec sauvegarde préférence taille police", error: e, tag: "NovelReaderPage");
    }
  }


  Color _getCurrentBackgroundColor() => Theme.of(context).scaffoldBackgroundColor;
  Color _getCurrentTextColor() => Theme.of(context).colorScheme.onSurface;

  TextStyle _getBaseTextStyle() {
    // TODO: Permettre la sélection de police plus tard
    return TextStyle(
      fontFamily: 'Inter', // Police par défaut
      fontSize: _currentFontSize,
      color: _getCurrentTextColor(),
      height: 1.6, // Interligne
    );
  }

  // ✅ NOUVELLE FONCTION: Réinitialiser la position de lecture
  Future<void> _clearLastViewedPageAndScroll() async {
    if (!_prefsLoaded || !mounted) return;
    
    final novel = await _getNovelFromProvider();
    if (novel == null) return;

    try {
      // 1. Supprime la dernière page vue
      final pageKey = 'last_page_${widget.novelId}';
      await _prefs.remove(pageKey);
      AppLogger.info("Dernière page vue réinitialisée pour ${widget.novelId}.", tag: "NovelReaderPage");

      // 2. Supprime la position de scroll pour tous les chapitres existants
      for (int i = 0; i < novel.chapters.length; i++) {
        final scrollKey = 'scroll_pos_${widget.novelId}_$i';
        await _prefs.remove(scrollKey);
        AppLogger.info("Position scroll réinitialisée pour chap $i.", tag: "NovelReaderPage");
      }

      // 3. Réinitialise l'état local et la navigation
      if (mounted) {
         // Si l'index actuel n'est pas 0 et qu'il y a des chapitres
         if (novel.chapters.isNotEmpty) {
           setState(() {
             _currentPage = 0; // Définit la page à 0
           });
           if (_pageController.hasClients) {
              // Aller à la page 0
              _pageController.jumpToPage(0);
              // Ré-attacher le listener de scroll pour relancer la lecture du scroll (qui sera 0)
              _attachScrollListenerToCurrentPage();
           }
         }
         _showSnackbarMessage('Position de lecture réinitialisée. Retour au Chapitre 1.', Colors.orange);
      }
    } catch (e) {
       AppLogger.error("Erreur réinitialisation position de lecture", error: e, tag: "NovelReaderPage");
       // ❌ CORRECTION: Retrait de 'isError: true' qui n'est pas dans la signature de _showSnackbarMessage
       _showSnackbarMessage("Échec de la réinitialisation de la position de lecture.", Colors.redAccent); 
    }
  }

  void _startEditing(Novel novel) {
    // ✅ VÉRIFICATION: Seul le propriétaire peut éditer
    final bool isOwner = novel.user_id == _currentUserId;
    if (!isOwner || _isGeneratingNextChapter || novel.chapters.isEmpty) return;


    final int chapterIndex = _currentPage;
     if (chapterIndex < 0 || chapterIndex >= novel.chapters.length) {
        AppLogger.warning("Tentative édition index chapitre invalide: $chapterIndex", tag: "NovelReaderPage");
        return;
     }
    final Chapter currentChapter = novel.chapters[chapterIndex];
    final readerScrollController = _scrollControllers[chapterIndex];
    double currentScrollOffset = 0.0;

    if (readerScrollController != null && readerScrollController.hasClients) {
      currentScrollOffset = readerScrollController.offset;
    }
     AppLogger.info("Démarrage édition chap $chapterIndex. Offset scroll initial: $currentScrollOffset", tag: "NovelReaderPage");

    setState(() {
      _isEditing = true;
      _editingChapterIndex = chapterIndex;
      _editingTitleController.text = currentChapter.title;
      _editingContentController.text = currentChapter.content;
    });

    // Restaurer la position de scroll dans l'éditeur
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingScrollController.hasClients) {
        // Clamp la position au cas où le contenu aurait changé légèrement
        final maxScroll = _editingScrollController.position.maxScrollExtent;
        final positionToJump = currentScrollOffset.clamp(0.0, maxScroll);
        _editingScrollController.jumpTo(positionToJump);
      } else if (mounted) {
          AppLogger.warning("ScrollController éditeur non prêt au démarrage de l'édition.", tag: "NovelReaderPage");
      }
    });
  }


  void _cancelEditing() {
     AppLogger.info("Annulation édition chap $_editingChapterIndex", tag: "NovelReaderPage");
    setState(() {
      _isEditing = false;
      _editingChapterIndex = null;
      _editingTitleController.clear();
      _editingContentController.clear();
      // Optionnel: réinitialiser la position de scroll de l'éditeur
      // if (_editingScrollController.hasClients) _editingScrollController.jumpTo(0);
    });
  }


  Future<void> _saveEdits(Novel novel) async {
    // ✅ VÉRIFICATION: Seul le propriétaire peut sauvegarder
    final bool isOwner = novel.user_id == _currentUserId;
    if (!isOwner || _editingChapterIndex == null || !mounted) return;

    final int chapterIndexToUpdate = _editingChapterIndex!;
    final double editorScrollOffset = _editingScrollController.hasClients ? _editingScrollController.offset : 0.0;
     AppLogger.info("Sauvegarde éditions chap $chapterIndexToUpdate. Offset scroll éditeur: $editorScrollOffset", tag: "NovelReaderPage");

    if (chapterIndexToUpdate < 0 || chapterIndexToUpdate >= novel.chapters.length) {
        AppLogger.error("Sauvegarde impossible, index chap $chapterIndexToUpdate invalide.", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de sauvegarder, le chapitre semble invalide.", Colors.redAccent);
         setState(() { _isEditing = false; _editingChapterIndex = null; });
        return;
    }

    final originalChapter = novel.chapters[chapterIndexToUpdate];
    final updatedChapter = Chapter(
      id: originalChapter.id,
      title: _editingTitleController.text.trim(),
      content: _editingContentController.text.trim(),
      createdAt: originalChapter.createdAt, // Conserver la date de création originale
    );

    try {
        // Mettre à jour via le provider (met à jour l'état local + Supabase)
        await ref.read(novelsProvider.notifier).updateChapter(novel.id, updatedChapter);

        // Ajouter la tâche de synchronisation pour le backend local
        final syncTask = SyncTask(
          action: 'update',
          novelId: novel.id,
          chapterIndex: chapterIndexToUpdate, // Utiliser l'index pour le backend FAISS
          content: updatedChapter.content,
        );
        await ref.read(syncServiceProvider).addTask(syncTask);
         // La file sera traitée automatiquement

        _showSnackbarMessage("Chapitre sauvegardé. La synchronisation se fera en arrière-plan.", Colors.green);

        // Sortir du mode édition
        setState(() {
          _isEditing = false;
          _editingChapterIndex = null;
        });

        // Restaurer la position de scroll dans le lecteur
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final readerScrollController = _scrollControllers[chapterIndexToUpdate];
          if (mounted && readerScrollController != null && readerScrollController.hasClients) {
              final maxScroll = readerScrollController.position.maxScrollExtent;
              final positionToJump = editorScrollOffset.clamp(0.0, maxScroll);
              readerScrollController.jumpTo(positionToJump);
              AppLogger.info("Position scroll lecteur restaurée à $positionToJump après sauvegarde.", tag: "NovelReaderPage");
          } else if (mounted) {
               AppLogger.warning("ScrollController lecteur page $chapterIndexToUpdate non dispo après sauvegarde.", tag: "NovelReaderPage");
          }
        });

    } catch (e) {
        AppLogger.error("Erreur sauvegarde éditions chapitre", error: e, tag: "NovelReaderPage");
        if (mounted) {
            _showSnackbarMessage("Erreur lors de la sauvegarde du chapitre: ${e.toString()}", Colors.redAccent);
        }
        // Optionnel: Ne pas sortir du mode édition en cas d'erreur ?
    }
  }


  Future<void> _guardedGenerateChapter(Novel novel) async {
    // ✅ VÉRIFICATION: Seul le propriétaire peut générer
    final bool isOwner = novel.user_id == _currentUserId;
    if (!isOwner) {
       _showSnackbarMessage("Seul le propriétaire peut générer de nouveaux chapitres.", Colors.orangeAccent);
       return;
    }

    AppLogger.info(">>> _guardedGenerateChapter appelé. Novel ID: ${novel.id}, Chapitres: ${novel.chapters.length}", tag: "NovelReaderPage");

    // Vérifier l'état de la synchronisation
    final syncStatus = ref.read(syncQueueStatusProvider);
    if (syncStatus != SyncQueueStatus.idle) {
      String message = syncStatus == SyncQueueStatus.processing
          ? "Finalisation d'une synchronisation..."
          : "Des modifications sont en attente de synchronisation...";
      _showSnackbarMessage(message, Colors.blueAccent);
      // Essayer de traiter la file au cas où elle serait bloquée
      ref.read(syncServiceProvider).processQueue();
      return;
    }

    if (_isGeneratingNextChapter) {
      _showSnackbarMessage("L'écrivain est déjà en train de rédiger, patience !", Colors.orangeAccent);
      return;
    }

    AppLogger.info(">>> Appel de _generateAndAddNewChapter depuis _guardedGenerateChapter...", tag: "NovelReaderPage");
    // Passer le contexte actuel pour les messages d'erreur potentiels
    await _generateAndAddNewChapter(novel, context);
  }


  Future<void> _generateAndAddNewChapter(Novel novel, BuildContext context, {bool finalChapter = false}) async {
    // ✅ VÉRIFICATION: Seul le propriétaire peut générer (double vérification)
     final bool isOwner = novel.user_id == _currentUserId;
     if (!isOwner) return;

    AppLogger.info(">>> _generateAndAddNewChapter appelé. Novel ID: ${novel.id}, Chapitres: ${novel.chapters.length}, finalChapter: $finalChapter", tag: "NovelReaderPage");

    if (!mounted) return;

    setState(() {
      _isGeneratingNextChapter = true;
      _chapterStream = null; // Réinitialiser le stream pour l'affichage du chargement
    });

    try {
      AppLogger.info(">>> Appel de AIService.preparePrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      // Préparer le prompt (peut prendre du temps, surtout avec FAISS)
      final prompt = await AIService.preparePrompt(
        novel: novel,
        isFirstChapter: novel.chapters.isEmpty,
        isFinalChapter: finalChapter,
      );
      AppLogger.success(">>> AIService.preparePrompt terminé avec succès dans _generateAndAddNewChapter.", tag: "NovelReaderPage");

      // Logguer le prompt en mode debug
      if (kDebugMode) {
          // Utiliser debugPrint pour les longs strings
          debugPrint("================= PROMPT Chapitre ${novel.chapters.length + 1} =================");
          debugPrint(prompt);
          debugPrint("================= FIN PROMPT ================= ");
      } else {
           AppLogger.info("Prompt généré (longueur: ${prompt.length})", tag: "NovelReaderPage");
      }


      if (!mounted) return; // Vérifier à nouveau après l'await de preparePrompt

      AppLogger.info(">>> Appel de AIService.streamChapterFromPrompt depuis _generateAndAddNewChapter...", tag: "NovelReaderPage");

      // Obtenir le stream depuis le service IA
      final stream = AIService.streamChapterFromPrompt(
        prompt: prompt,
        modelId: novel.modelId,
        language: novel.language,
      );

      // Mettre à jour l'état pour afficher le widget de streaming
      if (mounted) {
         setState(() => _chapterStream = stream);
      }

    } catch (e, stackTrace) {
      // Gérer les erreurs survenues PENDANT la préparation ou l'initiation du stream
      AppLogger.error("❌ Erreur DANS _generateAndAddNewChapter (probablement pendant preparePrompt ou init stream)", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
      _handleGenerationError(e); // Utilise la fonction centralisée
    }
    // Note: La gestion de la fin du stream (onDone, onError) se fait dans StreamingTextAnimation
  }


  // Appelée par StreamingTextAnimation quand le stream est terminé
  Future<void> _finalizeChapterGeneration(Novel novel, String fullText) async {
     AppLogger.info("Finalisation génération chapitre. Texte reçu (longueur: ${fullText.length})", tag: "NovelReaderPage");
    if (fullText.trim().isEmpty) {
      AppLogger.error("Erreur: L'IA a renvoyé un stream vide (probable surcharge modèle ou erreur prompt).", tag: "NovelReaderPage");
      // Utiliser une exception spécifique si possible
      _handleGenerationError(ApiServerException("L'écrivain a renvoyé un chapitre vide. Réessayez.", statusCode: null));
      return;
    }
    if (!mounted) {
         AppLogger.warning("Widget non monté lors de la finalisation du chapitre.", tag: "NovelReaderPage");
        return;
    }

    // Extraire titre et contenu
    final newChapter = AIService.extractTitleAndContent(
      fullText,
      novel.chapters.length, // Index du nouveau chapitre (0-based)
      novel.chapters.isEmpty, // isFirstChapter
      false, // TODO: Gérer isFinalChapter si nécessaire ici
      AIPrompts.getPromptsFor(novel.language), // Obtenir les prompts pour les titres par défaut
    );

    try {
        // Ajouter le chapitre via le provider (met à jour état local + Supabase)
        await ref.read(novelsProvider.notifier).addChapter(novel.id, newChapter);
        AppLogger.success("Nouveau chapitre ajouté au provider: ${newChapter.title}", tag: "NovelReaderPage");

        if (!mounted) return; // Re-vérifier après l'await

        // Déclencher la mise à jour de la roadmap (PASSÉ) si nécessaire
        // Utiliser la valeur la plus récente du Novel après l'ajout
        final updatedNovelState = await ref.read(novelsProvider.future);
        final updatedNovel = updatedNovelState.firstWhereOrNull((n) => n.id == novel.id);

        if (updatedNovel == null) {
             AppLogger.error("Impossible de retrouver le novel mis à jour après ajout du chapitre.", tag: "NovelReaderPage");
        } else {
             // Utiliser Future.microtask pour s'assurer que ça s'exécute après le build actuel
             Future.microtask(() => ref.read(roadmapServiceProvider).triggerRoadmapUpdateIfNeeded(updatedNovel, context));
             Future.microtask(() => ref.read(roadmapServiceProvider).triggerFutureOutlineUpdateIfNeeded(updatedNovel, context));
        }


        // Ajouter la tâche de synchronisation pour le backend local
        final syncTask = SyncTask(
          action: 'add',
          novelId: novel.id,
          content: newChapter.content,
          chapterIndex: novel.chapters.length, // L'index du chapitre *avant* l'ajout pour FAISS
        );
        await ref.read(syncServiceProvider).addTask(syncTask);
         AppLogger.info("Tâche de synchronisation 'add' ajoutée pour le nouveau chapitre.", tag: "NovelReaderPage");


        _showSnackbarMessage('Chapitre "${newChapter.title}" ajouté.', Colors.green, durationSeconds: 5);


        // Mettre à jour l'état de l'UI pour sortir du mode génération
        setState(() {
          _isGeneratingNextChapter = false;
          _chapterStream = null; // Important de le remettre à null
        });

        // Animer vers la nouvelle page (le dernier chapitre ajouté)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            // Lire à nouveau l'état pour obtenir la longueur mise à jour
            final currentNovels = ref.read(novelsProvider).value ?? [];
            final currentNovel = currentNovels.firstWhereOrNull((n) => n.id == novel.id);
            final lastPageIndex = (currentNovel?.chapters.length ?? 1) - 1; // Index 0-based

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
        // Gérer les erreurs de sauvegarde (provider, syncService)
        AppLogger.error("Erreur lors de la finalisation/sauvegarde du chapitre", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
        _handleGenerationError(ApiException("Erreur lors de la sauvegarde du chapitre: ${e.toString()}"));
    }
  }


  // Appelée par StreamingTextAnimation ou _generateAndAddNewChapter en cas d'erreur
  void _handleGenerationError(Object error) {
    if (!mounted) {
         AppLogger.warning("handleGenerationError appelé mais widget non monté.", tag: "NovelReaderPage");
        return;
    }

     AppLogger.error("Gestion de l'erreur de génération: $error", tag: "NovelReaderPage");


    // Assurer que l'état de génération est réinitialisé
    setState(() {
      _isGeneratingNextChapter = false;
      _chapterStream = null;
    });

    // Formater le message d'erreur pour l'utilisateur
    String message;
    if (error is ApiServerException) {
      // Erreur spécifique du serveur backend (5xx, etc.)
      message = error.toString(); // Utilise le toString() de l'exception
    } else if (error is ApiConnectionException) {
      // Erreur de connexion (timeout, réseau)
      message = error.toString();
    } else if (error is ApiException) {
       // Autre erreur API (4xx, erreur de parsing, etc.)
       message = error.message;
    }
    else {
      // Erreur inattendue (Dart, Flutter, etc.)
      message = "Une erreur inattendue est survenue lors de la rédaction.";
      // Logguer l'erreur originale pour le débogage
      AppLogger.error("Erreur de génération non gérée de type ${error.runtimeType}", error: error, tag: "NovelReaderPage");
    }

    // Afficher le message d'erreur
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

  // Logique de suppression de chapitre
  Future<void> _deleteCurrentChapter(Novel novel) async {
    // ✅ VÉRIFICATION: Seul le propriétaire peut supprimer
    final bool isOwner = novel.user_id == _currentUserId;
    if (!isOwner || !mounted || novel.chapters.isEmpty || _isGeneratingNextChapter) {
        AppLogger.warning("Suppression annulée: !isOwner=$isOwner, !mounted=${!mounted}, isEmpty=${novel.chapters.isEmpty}, isGenerating=$_isGeneratingNextChapter", tag: "NovelReaderPage");
        if (!isOwner && mounted) {
           _showSnackbarMessage("Seul le propriétaire peut supprimer des chapitres.", Colors.orangeAccent);
        }
        return;
    }


    final int chapterIndexToDelete = _currentPage;
    if (chapterIndexToDelete < 0 || chapterIndexToDelete >= novel.chapters.length) {
        AppLogger.error("Tentative suppression index invalide: $chapterIndexToDelete (total: ${novel.chapters.length})", tag: "NovelReaderPage");
        _showSnackbarMessage("Erreur : Impossible de déterminer quel chapitre supprimer.", Colors.redAccent);
        return;
    }
    final Chapter chapterToDelete = novel.chapters[chapterIndexToDelete];
    final int chapterNumber = chapterIndexToDelete + 1; // Pour l'affichage (1-based)

    // Dialogue de confirmation
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
         AppLogger.info("Suppression chap $chapterIndexToDelete annulée ou widget non monté.", tag: "NovelReaderPage");
        return;
    }

    AppLogger.info("Demande suppression confirmée chap $chapterIndexToDelete (ID: ${chapterToDelete.id})", tag: "NovelReaderPage");

    // Ajouter la tâche de synchronisation AVANT la suppression locale/Supabase
    final syncTask = SyncTask(
      action: 'delete_chapter',
      novelId: novel.id,
      chapterIndex: chapterIndexToDelete, // Utiliser l'index pour FAISS
    );
    await ref.read(syncServiceProvider).addTask(syncTask);
     AppLogger.info("Tâche synchro 'delete_chapter' ajoutée.", tag: "NovelReaderPage");

    try {
      // Supprimer la position de scroll sauvegardée pour ce chapitre
      if(_prefsLoaded) {
        final key = 'scroll_pos_${widget.novelId}_$chapterIndexToDelete';
        if (_prefs.containsKey(key)) {
            await _prefs.remove(key);
             AppLogger.info("Position scroll supprimée pour chap $chapterIndexToDelete.", tag: "NovelReaderPage");
        }
      }

      // Supprimer via le provider (met à jour état local + Supabase)
       AppLogger.info("Appel de novelsProvider.notifier.deleteChapter...", tag: "NovelReaderPage");
      await ref.read(novelsProvider.notifier).deleteChapter(novel.id, chapterToDelete.id);
       AppLogger.success("Chapitre supprimé avec succès via le provider.", tag: "NovelReaderPage");

      _showSnackbarMessage('Chapitre "${chapterToDelete.title}" supprimé.', Colors.green);

      // La reconstruction du widget par ref.watch(novelsProvider) gère la navigation.
      // Le PageView.builder recevra une nouvelle liste et ajustera l'affichage.
      // Le listener _onPageChanged mettra à jour _currentPage si l'index actuel devient invalide.

    } catch (e, stackTrace) {
      // Gérer les erreurs critiques (Supabase, etc.)
      AppLogger.error("Erreur critique lors suppression chapitre", error: e, stackTrace: stackTrace, tag: "NovelReaderPage");
       if (mounted) {
         _showSnackbarMessage("Erreur critique lors de la suppression : ${e.toString()}", Colors.redAccent);
       }
       // En cas d'erreur grave, forcer un rechargement complet peut aider
       ref.invalidate(novelsProvider);
    }
  }


  // Gérer l'affichage/masquage de l'UI
  void _toggleUI() {
    if(mounted) {
      setState(() => _showUIElements = !_showUIElements);
      // Appliquer le mode immersif ou normal
      if(!_showUIElements) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // Cacher la traduction si elle est affichée
        _selectionTimer?.cancel();
         if (mounted && (_selectedWord.isNotEmpty || _isLoadingTranslation)) {
             setState(() { _selectedWord = ''; _translationResult = null; _isLoadingTranslation = false; });
         }
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }


  // Gérer le tap pour afficher/masquer l'UI (éviter zone traduction/navigation)
  void _handleTapToToggleUI(TapUpDetails details) {
    if (!mounted || _isEditing) return; // Ne pas basculer en mode édition

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    final Size screenSize = renderBox.size;
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom;

    // Hauteur approximative des zones à ignorer en bas
    const double navBarHeight = kBottomNavigationBarHeight + 20; // Barre nav + padding
    final double translationAreaHeight = (_selectedWord.isNotEmpty || _isLoadingTranslation) ? 140 : 0; // Zone traduction + marge
    final double progressBarHeight = 40; // Hauteur barres de progression
    final double deadZoneHeight = bottomSafeArea + navBarHeight + translationAreaHeight + progressBarHeight;

    // Zone à ignorer en haut (AppBar + padding)
    final double topSafeArea = MediaQuery.of(context).padding.top;
    const double appBarHeight = kToolbarHeight;
    final double topDeadZone = topSafeArea + appBarHeight;

    // Vérifier si le tap est dans la zone "morte" en bas OU en haut
    if (localPosition.dy > topDeadZone && localPosition.dy < screenSize.height - deadZoneHeight) {
      _toggleUI();
    } else {
       AppLogger.info("Tap détecté dans zone morte (UI/Traduction/AppBar), UI non basculée.", tag: "NovelReaderPage");
    }
  }


  // Afficher le dialogue de sélection de taille de police
  void _showFontSizeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // Permettre de fermer en cliquant à côté
      builder: (BuildContext context) {
        // Utiliser StatefulBuilder pour que le dialogue se mette à jour sans fermer
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Taille de la police'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    // Désactiver si taille min atteinte
                    onPressed: _currentFontSize <= 10.0 ? null : () {
                      _decreaseFontSize(); // Met à jour l'état du widget principal
                      setDialogState(() {}); // Met à jour l'état du dialogue
                    },
                  ),
                  // Afficher la taille actuelle
                  Text(
                    _currentFontSize.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                     // Désactiver si taille max atteinte
                     onPressed: _currentFontSize >= 50.0 ? null : () {
                      _increaseFontSize(); // Met à jour l'état du widget principal
                      setDialogState(() {}); // Met à jour l'état du dialogue
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
    _saveFontSizePreference(_currentFontSize); // Sauvegarder la préférence
  }

  void _decreaseFontSize() {
     if (!mounted) return;
    setState(() {
      _currentFontSize = (_currentFontSize - 1.0).clamp(10.0, 50.0);
    });
    _saveFontSizePreference(_currentFontSize); // Sauvegarder la préférence
  }

  // Sauvegarder le plan directeur édité par l'utilisateur
  Future<bool> _saveFutureOutline(Novel novel) async {
    // ✅ VÉRIFICATION: Seul le propriétaire peut éditer le plan
    final bool isOwner = novel.user_id == _currentUserId;
    if (!isOwner || !mounted) return false;

    final newOutline = _futureOutlineController.text.trim();
    // Ne pas sauvegarder si rien n'a changé
    if (newOutline == (novel.futureOutline ?? '')) {
      return true; // Considéré comme un succès car état désiré atteint
    }

    AppLogger.info("Sauvegarde du nouveau plan directeur...", tag: "NovelReaderPage");
    final updatedNovel = novel.copyWith(
      futureOutline: newOutline.isEmpty ? null : newOutline, // Mettre à null si vide
      updatedAt: DateTime.now(), // Mettre à jour la date de modification
    );

    try {
      // Mettre à jour via le provider
      await ref.read(novelsProvider.notifier).updateNovel(updatedNovel);
      _showSnackbarMessage("Plan directeur mis à jour.", Colors.green);
      return true;
    } catch (e) {
      AppLogger.error("Erreur sauvegarde plan directeur", error: e, tag: "NovelReaderPage");
      _showSnackbarMessage("Erreur lors de la sauvegarde du plan.", Colors.redAccent);
      return false;
    }
  }

  // Afficher la bottom sheet d'informations du roman
  void _showNovelInfoSheet(Novel novel) {
    // Pré-remplir le contrôleur si le plan existe
    _futureOutlineController.text = novel.futureOutline ?? '';
    // Réinitialiser l'état d'édition du plan
    _isEditingOutline = false;

    // ✅ VÉRIFICATION: Déterminer si l'utilisateur est propriétaire
    final bool isOwner = novel.user_id == _currentUserId;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Utiliser Consumer pour accéder à writerModeProvider
        return Consumer(builder: (context, ref, child) {
          // Lire l'état du mode écrivain
          final isWriterMode = ref.watch(writerModeProvider);
          // Lire l'état actuel du roman (pour les mises à jour en temps réel si nécessaire)
          final asyncNovels = ref.watch(novelsProvider);
          // Trouver le roman actuel dans la liste (ou utiliser celui passé en paramètre comme fallback)
          final Novel? currentNovel = asyncNovels.when(
            data: (novels) => novels.firstWhereOrNull((n) => n.id == widget.novelId),
            loading: () => novel, // Utiliser l'ancien pendant le chargement
            error: (err, stack) => novel, // Utiliser l'ancien en cas d'erreur
          );

          // Si le roman n'existe plus (ex: supprimé pendant l'affichage), fermer le dialogue
          if (currentNovel == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const Center(child: CircularProgressIndicator()); // Affichage temporaire
          }

          // Flou en arrière-plan
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            // Gérer les onglets
            child: DefaultTabController(
              // ✅ AJOUT: Condition pour le nombre d'onglets (Plan Directeur visible seulement si propriétaire ET mode écrivain)
              length: (isWriterMode && isOwner) ? 3 : 2,
              child: AlertDialog(
                title: const Text("Détails de l'Intrigue"),
                contentPadding: const EdgeInsets.only(top: 20.0),
                content: SizedBox(
                  // Limiter la taille du dialogue
                  width: 500, // max(300, MediaQuery.of(context).size.width * 0.8),
                  height: 400, // max(300, MediaQuery.of(context).size.height * 0.6),
                  child: Column(
                    children: [
                      // Barre d'onglets
                      TabBar(
                        isScrollable: true, // Permet le défilement si beaucoup d'onglets
                        tabs: [
                          const Tab(text: "Spécifications"),
                          const Tab(text: "Fiche de route (Passé)"),
                          // ✅ CONDITION: Afficher l'onglet Plan Directeur
                          if (isWriterMode && isOwner)
                            const Tab(text: "Plan Directeur (Futur)"),
                        ],
                      ),
                      // Contenu des onglets
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Onglet Spécifications
                            _buildInfoTabContent(
                              context,
                              children: [
                                SelectableText( // Permet de copier le texte
                                  currentNovel.specifications.isNotEmpty
                                      ? currentNovel.specifications
                                      : 'Aucune spécification particulière.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                                  textAlign: TextAlign.justify,
                                )
                              ],
                            ),
                            // Onglet Fiche de Route (Passé)
                            _buildInfoTabContent(
                              context,
                              children: [
                                SelectableText(
                                  currentNovel.roadMap?.isNotEmpty == true
                                    ? currentNovel.roadMap!
                                    : "La fiche de route (résumé du passé) sera générée après quelques chapitres.",
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                                  textAlign: TextAlign.justify,
                                ),
                              ],
                            ),
                            // ✅ CONDITION: Contenu de l'onglet Plan Directeur
                            if (isWriterMode && isOwner)
                              _buildFutureOutlineTab(currentNovel, isOwner), // Passer isOwner
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Bouton Fermer
                actions: <Widget>[ TextButton(child: const Text('Fermer'), onPressed: () => Navigator.of(context).pop())],
              ),
            ),
          );
        });
      },
    );
  }

  // Widget pour l'onglet Plan Directeur (Futur)
  Widget _buildFutureOutlineTab(Novel novel, bool isOwner) {
    // Utiliser StatefulBuilder pour gérer l'état d'édition (_isEditingOutline) localement dans le dialogue
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final theme = Theme.of(context);
        return Column(
          children: [
            Expanded(
              // Contenu scrollable
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: _isEditingOutline // Afficher TextField si en mode édition
                    ? TextField(
                        controller: _futureOutlineController,
                        maxLines: null, // Permet plusieurs lignes
                        keyboardType: TextInputType.multiline,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                        decoration: const InputDecoration(
                          border: InputBorder.none, // Pas de bordure pour intégration
                          hintText: "Décrivez les prochains chapitres...",
                        ),
                      )
                    : SelectableText( // Afficher texte si en mode lecture
                        novel.futureOutline?.isNotEmpty == true
                            ? novel.futureOutline!
                            : "Aucun plan directeur (futur) n'a été défini ou généré.",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                        textAlign: TextAlign.justify,
                      ),
              ),
            ),
            // Actions (Modifier/Sauvegarder/Annuler) en bas de l'onglet
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Bouton Annuler (visible seulement en mode édition)
                  if (_isEditingOutline)
                    TextButton(
                      child: const Text('Annuler'),
                      onPressed: () {
                        setDialogState(() {
                          _isEditingOutline = false; // Sortir du mode édition
                          // Restaurer le texte original
                          _futureOutlineController.text = novel.futureOutline ?? '';
                        });
                      },
                    ),
                  // Bouton Modifier/Sauvegarder (✅ Condition isOwner ajoutée)
                  if (isOwner) // Afficher seulement si propriétaire
                    IconButton(
                      icon: Icon(_isEditingOutline ? Icons.check : Icons.edit_outlined),
                      tooltip: _isEditingOutline ? 'Sauvegarder le plan' : 'Modifier le plan',
                      onPressed: () {
                        if (_isEditingOutline) {
                          // Sauvegarder les modifications
                          _saveFutureOutline(novel).then((success) {
                             if (success && mounted) { // Si sauvegarde réussie
                               setDialogState((){
                                 _isEditingOutline = false; // Sortir du mode édition
                               });
                               // Optionnel: rafraîchir le novel dans le dialogue via ref.invalidate si besoin
                             }
                          });
                        } else {
                          // Entrer en mode édition
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


  // Helper pour construire le contenu scrollable d'un onglet d'info
  Widget _buildInfoTabContent(BuildContext context, {required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // Helper pour parser et formater le texte (gras avec *)
  List<TextSpan> _buildFormattedTextSpans(String text, TextStyle baseStyle) {
    // Remplacer les tirets cadratins (souvent utilisés par IA) par des virgules
    String processedText = text.replaceAll('—', ', ').replaceAll(',,', ',');

    final List<TextSpan> spans = [];
    final List<String> parts = processedText.split('*'); // Séparer par *

    for (int i = 0; i < parts.length; i++) {
      if (i.isOdd && parts[i].isNotEmpty) { // Si index impair et non vide -> mettre en gras
        spans.add(TextSpan(
          text: parts[i],
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (parts[i].isNotEmpty) { // Si index pair et non vide -> style normal
        spans.add(TextSpan(text: parts[i], style: baseStyle));
      }
    }
    return spans;
  }

  // Widget affichant le contenu d'un chapitre dans le lecteur
  Widget _buildChapterReader(Chapter chapter, int index, Novel novel) {
    final baseStyle = _getBaseTextStyle(); // Style de base (police, taille, couleur)

    // Style pour le titre (plus grand, plus gras)
    final titleStyle = baseStyle.copyWith(
        fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! + 4 : null,
        fontWeight: FontWeight.w800, // Extra gras
        height: 1.8,
        color: baseStyle.color?.withAlpha(230) // Légèrement moins opaque
    );
    // Style pour le contenu (interligne ajusté)
    final contentStyle = baseStyle.copyWith(height: 1.7);

    // Récupérer ou créer le ScrollController pour cette page
    final controller = _scrollControllers.putIfAbsent(index, () {
      final newController = ScrollController();
       AppLogger.info("Création ScrollController pour page $index", tag: "NovelReaderPage");
      // Essayer de charger et sauter à la position sauvegardée
      _loadAndJumpToScrollPosition(index, newController);
      return newController;
    });

    // S'assurer que le listener est attaché/détaché correctement lors du build
     if (index == _currentPage) {
        // Le listener est géré par _attachScrollListenerToCurrentPage, mais on s'assure
        // qu'il est là si PageView le détache.
        if (controller.hasClients) {
           // Tente de retirer de manière robuste (même si le listener n'est pas là)
           try { controller.removeListener(_updateScrollProgress); } catch (_) {} 
           // Ré-ajoute le listener
           controller.addListener(_updateScrollProgress);
           // Mettre à jour la progression après l'attachement
           WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollProgress());
        }
     } else {
        // Si ce n'est pas la page actuelle, le détacher si nécessaire
        // On ne peut pas utiliser hasListeners (protégé), donc on tente de le retirer si hasClients est vrai.
         if (controller.hasClients) { 
           try {
              controller.removeListener(_updateScrollProgress);
           } catch (e) { /* Ignorer si déjà détaché */ }
         }
     }


    // Widget de texte sélectionnable formaté
    final textContent = SelectableText.rich(
      TextSpan(
        children: [
          ..._buildFormattedTextSpans("${chapter.title}\n\n", titleStyle), // Titre formaté
          ..._buildFormattedTextSpans(chapter.content, contentStyle), // Contenu formaté
        ],
      ),
      textAlign: TextAlign.justify, // Justifier le texte
      // Gérer la sélection de texte pour la traduction (Japonais)
      onSelectionChanged: (selection, cause) {
        final String fullRenderedText = "${chapter.title}\n\n${chapter.content}";
        // Gérer seulement si sélection valide, non vide, et déclenchée par appui long/drag/double tap
        if (selection.isValid && !selection.isCollapsed &&
           (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.drag || cause == SelectionChangedCause.doubleTap))
        {
          String selectedText = '';
          try {
             // Extraire le texte sélectionné
             if (selection.start >= 0 && selection.end <= fullRenderedText.length && selection.start < selection.end) {
               selectedText = fullRenderedText.substring(selection.start, selection.end).trim();
             }
          } catch (e) { AppLogger.error("Erreur substring", error: e, tag: "NovelReaderPage"); selectedText = ''; }

          // Vérifier si le texte est valide pour une recherche (pas titre, pas trop long, pas multiligne)
          bool isValidForLookup = selectedText.isNotEmpty &&
              selectedText != chapter.title.trim() &&
              selectedText.length <= 50 &&
              !selectedText.contains('\n');

          if (isValidForLookup && novel.language == 'Japonais') {
            // Annuler timer précédent et lancer la traduction
            _selectionTimer?.cancel();
            if (mounted) { _triggerReadingAndTranslation(selectedText); }
          } else {
            // Si sélection invalide ou autre langue, cacher la zone de traduction si elle était visible
            if ((_selectedWord.isNotEmpty || _isLoadingTranslation || _translationResult != null) && mounted) {
              setState(() {
                _selectedWord = '';
                _translationResult = null;
                _isLoadingTranslation = false;
              });
            }
          }
        } else if (cause == SelectionChangedCause.tap || cause == SelectionChangedCause.keyboard) {
            // Si simple tap ou clavier, cacher la zone de traduction
            if ((_selectedWord.isNotEmpty || _isLoadingTranslation || _translationResult != null) && mounted) {
              setState(() {
                _selectedWord = '';
                _translationResult = null;
                _isLoadingTranslation = false;
              });
            }
        }
      },
      cursorColor: Theme.of(context).colorScheme.primary, // Couleur du curseur
      selectionControls: MaterialTextSelectionControls(), // Contrôles de sélection standards
    );

    // Padding en bas pour éviter que le texte passe sous la barre de nav/traduction
    final bottomPadding = _showUIElements ? 160.0 : 60.0; // Plus d'espace si UI visible

    // Utiliser RepaintBoundary pour optimiser les repeints
     return RepaintBoundary(
        child: Container(
         color: _getCurrentBackgroundColor(), // Fond
         key: ValueKey("chapter_${novel.id}_${chapter.id}_$index"), // Clé unique pour PageView
         // Conteneur scrollable
         child: SingleChildScrollView(
           controller: controller, // Associer le controller
           padding: EdgeInsets.fromLTRB(
              20.0, // Gauche
              MediaQuery.of(context).padding.top + kToolbarHeight + 24.0, // Haut (sous AppBar)
              20.0, // Droite
              bottomPadding // Bas (variable)
           ),
           child: textContent, // Le texte formaté
         ),
       ),
     );
  }



  // Widget pour l'éditeur de chapitre
  Widget _buildChapterEditor() {
    final baseStyle = _getBaseTextStyle();
    final theme = Theme.of(context);
    final hintColor = baseStyle.color?.withAlpha(128); // Couleur pour les placeholders

    return Container(
      color: _getCurrentBackgroundColor(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        controller: _editingScrollController, // Controller pour restaurer la position
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        child: Column(
          children: [
            // Champ pour le titre
            TextField(
              controller: _editingTitleController,
              style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! + 4 : null),
              decoration: InputDecoration(
                labelText: 'Titre du chapitre',
                labelStyle: theme.textTheme.labelLarge?.copyWith(color: hintColor),
                border: InputBorder.none, // Pas de bordure
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            const SizedBox(height: 24),
            // Champ pour le contenu
            TextField(
              controller: _editingContentController,
              style: baseStyle.copyWith(height: 1.7), // Style de base avec interligne
              maxLines: null, // Multiligne illimité
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Contenu du chapitre...',
                hintStyle: baseStyle.copyWith(color: hintColor),
                border: InputBorder.none, // Pas de bordure
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget affichant la zone de traduction en bas
  Widget _buildTranslationArea(ThemeData theme) {
    // Couleurs basées sur le thème
    final translationBg = theme.colorScheme.surfaceContainerHighest; // Fond de la zone
    final textColor = _getCurrentTextColor(); // Couleur du texte

    // Styles de texte
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: textColor.withOpacity(0.7));
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(color: textColor, height: 1.5);
    final errorStyle = valueStyle?.copyWith(color: theme.colorScheme.error);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textColor.withOpacity(0.9));

    // Récupérer les résultats de traduction (peuvent être null ou contenir des erreurs)
    final String? reading = _translationResult?['reading'];
    final String? translation = _translationResult?['translation'];
    final String? readingError = _translationResult?['readingError'];
    final String? translationError = _translationResult?['translationError'];

    // Vérifier quelles informations sont disponibles
    final bool hasReadingInfo = reading != null || readingError != null;
    final bool hasTranslationInfo = translation != null || translationError != null;
    final bool hasAnyInfo = hasReadingInfo || hasTranslationInfo;

    // Construire le widget
    return Material(
      elevation: 2, // Légère ombre
      color: translationBg,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)), // Coins arrondis en haut
      child: Padding(
        padding: EdgeInsets.only(
          top: 16.0,
          left: 20.0,
          right: 20.0,
          // Ajuster le padding bas pour la safe area (encoche, etc.)
          bottom: max(16.0, MediaQuery.of(context).padding.bottom + 4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Prend la hauteur minimale nécessaire
          children: [
            // Afficher le mot sélectionné (tronqué si trop long)
            Text(
              'Infos pour : "${_selectedWord.length > 30 ? "${_selectedWord.substring(0, 30)}..." : _selectedWord}"',
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Afficher indicateur de chargement ou les résultats
            _isLoadingTranslation
                ? Padding( // Indicateur de chargement
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row( children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Recherche infos...', style: theme.textTheme.bodyMedium?.copyWith(color: textColor.withOpacity(0.8))),
                    ],
                    ),
                  )
                : Column( // Affichage des résultats/erreurs
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section Lecture Hiragana (si disponible)
                      if (hasReadingInfo) ...[
                        Text("Lecture Hiragana :", style: labelStyle),
                        const SizedBox(height: 3),
                        // Afficher erreur ou résultat
                        readingError != null
                            ? SelectableText(readingError, style: errorStyle)
                            : SelectableText(reading ?? '(Non trouvée)', style: valueStyle),
                        if (hasTranslationInfo) const SizedBox(height: 10), // Espace si traduction suit
                      ],
                      // Section Traduction Français (si disponible)
                      if (hasTranslationInfo) ...[
                        Text("Traduction Français :", style: labelStyle),
                        const SizedBox(height: 3),
                        // Afficher erreur ou résultat
                        translationError != null
                            ? SelectableText(translationError, style: errorStyle)
                            : SelectableText(translation ?? '(Non trouvée)', style: valueStyle),
                      ],
                      // Message si aucune information trouvée
                      if (!hasAnyInfo)
                        Text("(Aucune information trouvée)", style: valueStyle?.copyWith(fontStyle: FontStyle.italic, color: textColor.withOpacity(0.6))),
                    ],
                  ),
          ],
        ),
      ),
    );
  }


  // Widget affiché si le roman n'a pas de chapitres
  Widget _buildEmptyState(ThemeData theme) {
      return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: 80, color: _getCurrentTextColor().withOpacity(0.4)),
            const SizedBox(height: 24),
            Text(
              'Ce roman n\'a pas encore de chapitre.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(color: _getCurrentTextColor().withOpacity(0.8)),
            ),
            const SizedBox(height: 16),
             // ✅ CORRECTION: Instructions conditionnelles selon le propriétaire
             Consumer( // Utiliser Consumer pour lire l'état du novel
               builder: (context, ref, child) {
                  final novelAsync = ref.watch(novelsProvider);
                  final novel = novelAsync.value?.firstWhereOrNull((n) => n.id == widget.novelId);
                  final bool isOwner = novel?.user_id == _currentUserId;

                  return Text(
                    isOwner
                      ? "Utilisez le bouton '+' en bas à droite pour générer le premier chapitre."
                      : "Le propriétaire n'a pas encore ajouté de chapitres.",
                    style: theme.textTheme.bodyMedium?.copyWith(color: _getCurrentTextColor().withOpacity(0.6)),
                    textAlign: TextAlign.center
                  );
                }
             ),
          ],
        ),
      ),
    );
  }

  // Widget pour la barre de navigation entre chapitres en bas
  Widget _buildChapterNavigation({
    required ThemeData theme,
    required Color backgroundColor,
    required Color primaryColor,
    required Color textColor,
    required Color disabledColor,
    required bool isGenerating,
    required Novel novel,
    required bool isOwner, // ✅ AJOUT: Savoir si l'utilisateur est propriétaire
  }) {
    // Conditions pour activer/désactiver les boutons
    bool canGoBack = _currentPage > 0;
    bool hasChapters = novel.chapters.isNotEmpty;
    // Vérifier si on est sur la dernière page existante
    bool isLastPage = hasChapters && _currentPage >= 0 && _currentPage == novel.chapters.length - 1;
    bool canGoForward = hasChapters && _currentPage >= 0 && _currentPage < novel.chapters.length - 1;
    // Désactiver la navigation pendant la génération ou s'il n'y a pas de chapitres
    bool navigationDisabled = isGenerating || !hasChapters;

    // Texte affichant le numéro de page
    String pageText;
    if (!hasChapters) {
      pageText = 'Pas de chapitres';
    } else if (_currentPage >= 0 && _currentPage < novel.chapters.length) {
      pageText = 'Chapitre ${_currentPage + 1} / ${novel.chapters.length}';
    } else {
      pageText = 'Chargement...'; // Cas transitoire
    }


    return Material(
      color: backgroundColor, // Fond de la barre
      child: Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 4,
          // Ajuster pour la safe area en bas
          bottom: max(8.0, MediaQuery.of(context).padding.bottom)
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Espacer les éléments
          children: [
            // Bouton Précédent
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: 'Chapitre précédent',
              iconSize: 20,
              color: canGoBack && !navigationDisabled ? primaryColor : disabledColor, // Couleur active/inactive
              disabledColor: disabledColor,
              onPressed: canGoBack && !navigationDisabled
                  ? () {
                      _selectionTimer?.cancel(); // Annuler sélection traduction
                      if (_pageController.hasClients) {
                        _pageController.previousPage( // Aller page précédente
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    }
                  : null, // Désactivé si pas possible
            ),
            // Texte Numéro de Page (flexible pour s'adapter)
            Flexible(
              child: Text(
                pageText,
                style: theme.textTheme.labelLarge?.copyWith(color: textColor),
                overflow: TextOverflow.ellipsis, // Points si trop long
              ),
            ),
            // Espace à droite: Indicateur chargement OU Bouton '+' OU Bouton Suivant
            isGenerating // Si génération en cours
                ? const SizedBox( // Indicateur de chargement
                    width: 48, height: 24, // Taille fixe pour la mise en page
                    child: Center( child: SizedBox( width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5) ) ),
                  )
                : (isLastPage || !hasChapters) // Si dernière page ou pas de chapitres
                    // ✅ CONDITION: Afficher le bouton '+' seulement si propriétaire
                    ? isOwner
                      ? _buildAddChapterMenu(theme, novel) // Menu ajout chapitre
                      : const SizedBox(width: 48) // Placeholder vide pour non-propriétaire
                    // Sinon (ni génération, ni dernière page) -> Bouton Suivant
                    : IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            tooltip: 'Chapitre suivant',
                            iconSize: 20,
                            color: canGoForward && !navigationDisabled ? primaryColor : disabledColor,
                            disabledColor: disabledColor,
                            onPressed: canGoForward && !navigationDisabled
                                ? () {
                                    _selectionTimer?.cancel();
                                    if (_pageController.hasClients) {
                                      _pageController.nextPage( // Aller page suivante
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


  // Menu pour ajouter un chapitre (Générer Suivant / Générer Final)
  Widget _buildAddChapterMenu(ThemeData theme, Novel novel) {
    // ✅ VÉRIFICATION: Ce menu ne devrait être construit que si isOwner est true (vérifié dans _buildChapterNavigation)
    final iconColor = _isGeneratingNextChapter ? theme.disabledColor : theme.colorScheme.primary;
    // Couleurs du menu popup selon le thème
    Color popupMenuColor = theme.popupMenuTheme.color ?? theme.colorScheme.surfaceContainerHigh;
    Color popupMenuTextColor = theme.colorScheme.onSurface;

    final bool isMenuEnabled = !_isGeneratingNextChapter; // Actif seulement si pas de génération en cours
    final bool hasChapters = novel.chapters.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(Icons.add_circle_outline, color: iconColor), // Icône '+'
      tooltip: hasChapters ? 'Options du chapitre suivant' : 'Générer le premier chapitre',
      offset: const Offset(0, -120), // Positionner au-dessus du bouton
      color: popupMenuColor,
      enabled: isMenuEnabled, // Activer/désactiver le bouton
      onOpened: () { if (!_showUIElements) _toggleUI(); }, // Afficher UI si masquée à l'ouverture
      // Construire les items du menu
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        // Option "Générer chapitre suivant" (si au moins un chapitre existe)
        if(hasChapters)
          PopupMenuItem<String>(
            value: 'next', // Valeur retournée si sélectionné
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.playlist_add_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withOpacity(0.8) : theme.disabledColor),
              title: Text(
                'Générer chapitre suivant',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero, dense: true,
            ),
          )
        // Option "Générer le premier chapitre" (si aucun chapitre n'existe)
        else
          PopupMenuItem<String>(
            value: 'first',
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.auto_stories_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withOpacity(0.8) : theme.disabledColor),
              title: Text(
                'Générer le premier chapitre',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero, dense: true,
            ),
          ),

        // Option "Générer chapitre final" (toujours si au moins un chapitre existe)
        if (hasChapters)
          PopupMenuItem<String>(
            value: 'final',
            enabled: isMenuEnabled,
            child: ListTile(
              leading: Icon(Icons.flag_outlined, size: 20, color: isMenuEnabled ? popupMenuTextColor.withOpacity(0.8) : theme.disabledColor),
              title: Text(
                'Générer chapitre final',
                style: theme.textTheme.bodyMedium?.copyWith(color: isMenuEnabled ? popupMenuTextColor : theme.disabledColor)
              ),
              contentPadding: EdgeInsets.zero, dense: true,
            ),
          ),
      ],
      // Action quand un item est sélectionné
      onSelected: (String result) {
        if (!mounted) return;
        // Lire l'état actuel du novel depuis le provider pour avoir les dernières données
        final currentNovel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == novel.id);
        if (currentNovel == null) {
            _showSnackbarMessage("Erreur : Impossible de retrouver les détails du roman.", Colors.redAccent);
            return;
        }

        // Lancer la génération correspondante
        if (result == 'next' || result == 'first') {
           // _guardedGenerateChapter contient déjà la vérification isOwner
           _guardedGenerateChapter(currentNovel);
        } else if (result == 'final') {
           // Appeler directement _generateAndAddNewChapter pour le final
           _generateAndAddNewChapter(currentNovel, context, finalChapter: true);
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    // Lire le thème et le mode écrivain
    final isDarkMode = ref.watch(themeServiceProvider) == ThemeMode.dark;
    final theme = Theme.of(context);
    final currentBackgroundColor = _getCurrentBackgroundColor();
    final isWriterMode = ref.watch(writerModeProvider);

    // Observer l'état du provider de romans
    final novelsAsyncValue = ref.watch(novelsProvider);

    // Gérer les différents états (chargement, erreur, données)
    return novelsAsyncValue.when(
      loading: () => Scaffold(backgroundColor: currentBackgroundColor, body: const LoadingWidget(message: "Chargement du roman...")),
      error: (err, stack) {
         // Afficher l'erreur si le chargement échoue
         AppLogger.error("Erreur chargement novelsProvider dans build()", error: err, stackTrace: stack, tag: "NovelReaderPage");
         return Scaffold(backgroundColor: currentBackgroundColor, appBar: AppBar(title: const Text("Erreur")), body: Center(child: Text('Erreur chargement: $err')));
      },
      data: (novels) {
        // Trouver le roman actuel dans la liste
        final novel = novels.firstWhereOrNull((n) => n.id == widget.novelId);

        // Si le roman n'est plus trouvé (supprimé ?), retourner à la page précédente
        if (novel == null) {
          AppLogger.warning("Roman ${widget.novelId} non trouvé dans le provider. Retour arrière.", tag: "NovelReaderPage");
          // Utiliser postFrameCallback pour naviguer après le build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              // Afficher un message (optionnel)
              // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ce roman n'est plus disponible.")));
            }
          });
          // Afficher un état de chargement temporaire pendant la navigation retour
          return Scaffold(
            backgroundColor: currentBackgroundColor,
            body: const LoadingWidget(message: "Roman introuvable..."),
          );
        }

        // ✅ VÉRIFICATION: Déterminer si l'utilisateur est propriétaire
        final bool isOwner = novel.user_id == _currentUserId;

        // Assurer que _currentPage est un index valide après reconstruction (ex: après suppression)
        if (_currentPage >= novel.chapters.length && novel.chapters.isNotEmpty) {
          AppLogger.warning("_currentPage ($_currentPage) invalide après build. Ajustement à ${novel.chapters.length - 1}", tag: "NovelReaderPage");
          // Utiliser post-frame callback pour éviter modif état pendant build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              final newPage = novel.chapters.length - 1;
              _pageController.jumpToPage(newPage);
              // Le listener _onPageChanged mettra à jour _currentPage et le scroll listener
            }
          });
          // Retourner un état de chargement pendant la correction de la page
          // return Scaffold(backgroundColor: currentBackgroundColor, body: const LoadingWidget());
        } else if (_currentPage == -1 && novel.chapters.isNotEmpty) {
           // Si on était à -1 (pas de chapitre) mais qu'un chapitre est apparu
           AppLogger.info("Premier chapitre détecté. Passage à la page 0.", tag: "NovelReaderPage");
           WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted && _pageController.hasClients) {
                _pageController.jumpToPage(0);
             }
           });
        }


        // Couleurs pour la barre de navigation
        Color navBarBgColor = theme.colorScheme.surfaceContainer;
        Color navBarPrimaryColor = theme.colorScheme.primary;
        Color navBarTextColor = theme.colorScheme.onSurfaceVariant;
        Color navBarDisabledColor = theme.disabledColor;

        // Conditions pour activer/désactiver les actions
        final bool isGenerating = _isGeneratingNextChapter;
        final bool isCurrentPageValid = _currentPage >= 0 && _currentPage < novel.chapters.length;
        // ✅ MODIFICATION: Actions possibles seulement si propriétaire ET conditions remplies
        final bool canDeleteChapter = isOwner && novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;
        final bool canEditChapter = isOwner && novel.chapters.isNotEmpty && !isGenerating && isCurrentPageValid;
        // ❌ SUPPRESSION: Variable inutile
        // final bool canGenerateChapter = isOwner && !isGenerating; // Simplifié

        // Afficher la zone de traduction ?
        final bool shouldShowTranslationArea = _selectedWord.isNotEmpty && (_isLoadingTranslation || _translationResult != null);

        // Gérer le PopScope (confirmation avant de quitter si génération en cours)
        return PopScope(
          canPop: !isGenerating, // Bloquer si génération en cours
          onPopInvoked: (bool didPop) {
            if (!didPop && isGenerating && mounted) {
                _showSnackbarMessage("Veuillez attendre la fin de la génération en cours.", Colors.orangeAccent);
            } else if (didPop) {
              // Sauvegarder la position de scroll en quittant
              _saveCurrentScrollPosition();
              // Rétablir l'UI système si elle était cachée
              if (!_showUIElements) {
                 SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              }
            }
          },
          child: Scaffold(
            extendBodyBehindAppBar: true, // Permet au corps de passer sous l'AppBar
            backgroundColor: currentBackgroundColor,
            // --- AppBar ---
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: _isEditing // AppBar spécifique pour le mode édition
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
                        onPressed: () => _saveEdits(novel), // Sauvegarder
                      ),
                    ],
                  )
                : AnimatedOpacity( // AppBar normale (visible/invisible avec l'UI)
                    opacity: _showUIElements ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer( // Ignorer les clics si invisible
                      ignoring: !_showUIElements,
                      child: ClipRRect( // Pour le flou
                        child: BackdropFilter( // Flou derrière l'AppBar
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: AppBar(
                            title: Text(novel.title, style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 18)), // Titre du roman
                            backgroundColor: Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.75), // Semi-transparent
                            elevation: 0, // Pas d'ombre
                            scrolledUnderElevation: 0,
                            leading: IconButton( // Bouton retour
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Retour à la bibliothèque',
                              onPressed: () => Navigator.pop(context),
                            ),
                            actions: [
                              // ✅ AJOUT: Bouton Mode Écrivain désactivé si non propriétaire
                              IconButton(
                                icon: Icon(
                                  isWriterMode ? Icons.auto_stories_outlined : Icons.edit_note_outlined,
                                  color: isOwner // Grisé si non propriétaire
                                    ? (isWriterMode ? theme.colorScheme.secondary : null)
                                    : theme.disabledColor,
                                ),
                                tooltip: isOwner
                                  ? (isWriterMode ? 'Passer en mode Lecteur' : 'Passer en mode Écrivain (Propriétaire)')
                                  : 'Mode Écrivain (Propriétaire seulement)',
                                // Désactiver si non propriétaire
                                onPressed: isOwner ? () {
                                  ref.read(writerModeProvider.notifier).state = !isWriterMode;
                                  _showSnackbarMessage(
                                    isWriterMode ? 'Mode Lecteur activé.' : 'Mode Écrivain activé. Le plan est maintenant modifiable.',
                                    isWriterMode ? Colors.grey : Colors.blueAccent,
                                  );
                                } : null,
                              ),
                              // Menu d'options (...)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: 'Ouvrir le menu',
                                onSelected: (value) {
                                  // Gérer la sélection du menu
                                  switch (value) {
                                    case 'info': _showNovelInfoSheet(novel); break;
                                    case 'edit': _startEditing(novel); break; // _startEditing a déjà la vérif isOwner
                                    case 'font_size': _showFontSizeDialog(); break;
                                    case 'theme': ref.read(themeServiceProvider.notifier).updateTheme(isDarkMode ? ThemeMode.light : ThemeMode.dark); break;
                                    case 'delete': _deleteCurrentChapter(novel); break; // _deleteCurrentChapter a déjà la vérif isOwner
                                    // ✅ NOUVELLE ACTION
                                    case 'reset_position': _clearLastViewedPageAndScroll(); break;
                                  }
                                },
                                // Construire les items du menu
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  // Informations du roman (toujours visible)
                                  const PopupMenuItem<String>(
                                    value: 'info',
                                    child: ListTile(leading: Icon(Icons.info_outline), title: Text('Informations du roman')),
                                  ),
                                  // Modifier ce chapitre (✅ Condition isOwner ajoutée)
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    enabled: canEditChapter, // Utilise la variable calculée
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined, color: canEditChapter ? null : theme.disabledColor),
                                      title: Text('Modifier ce chapitre', style: TextStyle(color: canEditChapter ? null : theme.disabledColor))
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  // Taille de police (toujours visible)
                                  const PopupMenuItem<String>(
                                    value: 'font_size',
                                    child: ListTile(leading: Icon(Icons.format_size), title: Text('Taille de la police')),
                                  ),
                                  // Changer thème (toujours visible)
                                  PopupMenuItem<String>(
                                    value: 'theme',
                                    child: ListTile(leading: Icon(isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined), title: Text(isDarkMode ? 'Thème clair' : 'Thème sombre')),
                                  ),
                                  
                                  const PopupMenuDivider(),
                                  // ✅ NOUVEAU BOUTON
                                  const PopupMenuItem<String>(
                                    value: 'reset_position',
                                    child: ListTile(
                                      leading: Icon(Icons.refresh_outlined),
                                      title: Text('Réinitialiser la position de lecture')
                                    ),
                                  ),
                                  // ✅ CONDITION: Afficher seulement si propriétaire
                                  if (isOwner) ...[
                                    const PopupMenuDivider(),
                                    // Supprimer ce chapitre
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      enabled: canDeleteChapter, // Utilise la variable calculée
                                      child: ListTile(
                                        leading: Icon(Icons.delete_outline, color: canDeleteChapter ? Colors.red.shade300 : theme.disabledColor.withOpacity(0.5)),
                                        title: Text('Supprimer ce chapitre', style: TextStyle(color: canDeleteChapter ? Colors.red.shade300 : theme.disabledColor.withOpacity(0.5)))
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
            // --- Corps de la page ---
            body: Stack( // Superposer les éléments (lecteur, barre nav, traduction)
              children: [
                // Contenu principal (lecteur ou indicateur de chargement/génération)
                Positioned.fill( // Prend tout l'espace disponible
                  child: GestureDetector( // Détecter les taps pour afficher/masquer UI
                    onTapUp: _handleTapToToggleUI,
                    // Écouter le scroll pour afficher/masquer UI (optionnel)
                    // child: NotificationListener<ScrollNotification>(
                    //   onNotification: (ScrollNotification notification) {
                    //     if (notification is UserScrollNotification && !_isEditing) {
                    //       final UserScrollNotification userScroll = notification;
                    //       if (userScroll.direction == ScrollDirection.reverse && _showUIElements) {
                    //          _toggleUI();
                    //       } else if (userScroll.direction == ScrollDirection.forward && !_showUIElements) {
                    //          _toggleUI();
                    //       }
                    //     }
                    //     return false; // Ne pas consommer la notification
                    //   },
                      child: isGenerating // Si génération en cours
                          ? _chapterStream == null // Si stream pas encore prêt -> indicateur simple
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3.5)),
                                        const SizedBox(height: 24),
                                        Text( "L'écrivain consulte le contexte...", textAlign: TextAlign.center, style: _getBaseTextStyle().copyWith(fontSize: (_getBaseTextStyle().fontSize ?? 19.0) * 1.1, color: _getCurrentTextColor().withOpacity(0.75)), ),
                                      ],
                                    ),
                                  ),
                                )
                              : Padding( // Si stream prêt -> afficher texte en streaming
                                  padding: const EdgeInsets.fromLTRB(20.0, kToolbarHeight + 40, 20.0, 160), // Padding pour AppBar et Nav
                                  child: StreamingTextAnimation(
                                    stream: _chapterStream!,
                                    style: _getBaseTextStyle(),
                                    onDone: (fullText) => _finalizeChapterGeneration(novel, fullText), // Appel quand terminé
                                    onError: (error) => _handleGenerationError(error), // Appel si erreur stream
                                  ),
                                )
                          : !_prefsLoaded // Si préférences pas chargées -> indicateur
                              ? const LoadingWidget(message: "Chargement des préférences...")
                              : novel.chapters.isEmpty // Si pas de chapitres -> état vide
                                  ? _buildEmptyState(theme)
                                  : PageView.builder( // Sinon -> lecteur page par page
                                      // Désactiver scroll si en mode édition
                                      physics: _isEditing ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                                      // Clé unique pour forcer reconstruction si nb chapitres change
                                      key: ValueKey("${novel.id}_${novel.chapters.length}"),
                                      controller: _pageController,
                                      itemCount: novel.chapters.length,
                                      itemBuilder: (context, index) {
                                        // Vérifier si l'index est valide (sécurité)
                                        if (index >= novel.chapters.length) {
                                           AppLogger.warning("PageView.builder appelé avec index invalide $index (max: ${novel.chapters.length - 1})", tag: "NovelReaderPage");
                                          return Container(color: _getCurrentBackgroundColor(), child: const Center(child: Text("Erreur index chapitre")));
                                        }
                                        final chapter = novel.chapters[index];

                                        // Afficher éditeur ou lecteur selon l'état
                                        if (_isEditing && index == _editingChapterIndex) {
                                          return _buildChapterEditor();
                                        } else {
                                          // Passer le chapitre, l'index et le novel complet
                                          return _buildChapterReader(chapter, index, novel);
                                        }
                                      },
                                    ),
                    // ), // Fin NotificationListener (si utilisé)
                  ),
                ),
                // Éléments superposés en bas (Traduction, Barres Progrès, Navigation)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zone de traduction (animée)
                      AnimatedSize( // S'agrandit/rétrécit en douceur
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: shouldShowTranslationArea ? _buildTranslationArea(theme) : const SizedBox.shrink(), // Afficher/Cacher
                      ),
                      // Barre de navigation et progression (animée pour apparaître/disparaître)
                      if (!_isEditing) // Cacher si en mode édition
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          offset: _showUIElements ? Offset.zero : const Offset(0, 2), // Glisse vers le bas si caché
                          child: Column(
                            children: [
                              // Barres de progression (chapitre / roman)
                              _buildProgressBars(theme, navBarPrimaryColor, navBarTextColor),
                              // Barre de navigation (précédent, page, suivant/+)
                              _buildChapterNavigation(
                                theme: theme,
                                backgroundColor: navBarBgColor,
                                primaryColor: navBarPrimaryColor,
                                textColor: navBarTextColor,
                                disabledColor: navBarDisabledColor,
                                isGenerating: isGenerating,
                                novel: novel,
                                isOwner: isOwner, // ✅ Passer isOwner
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


  // Widget pour les barres de progression
  Widget _buildProgressBars(ThemeData theme, Color primaryColor, Color textColor) {
    // Lire le novel actuel pour le progrès global
    // Utiliser ref.read ici car on est dans une méthode build appelée par le build principal
    final novel = ref.read(novelsProvider).value?.firstWhereOrNull((n) => n.id == widget.novelId);
    if (novel == null || !mounted) return const SizedBox.shrink(); // Ne rien afficher si novel pas trouvé

    final hasChapters = novel.chapters.isNotEmpty;
    // Calculer le progrès dans le roman entier (basé sur la page actuelle)
    final double novelProgress = hasChapters
      ? ((_currentPage + 1).clamp(1, novel.chapters.length) / novel.chapters.length)
      : 0.0;


    return IgnorePointer( // Ignorer les clics sur les barres
      child: Container(
        color: theme.colorScheme.surfaceContainer.withOpacity(0.8), // Fond semi-transparent
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0), // Padding
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre de progression du chapitre actuel (écoute ValueNotifier)
            ValueListenableBuilder<double>(
              valueListenable: _chapterProgressNotifier,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value, // Valeur du notifier
                  backgroundColor: primaryColor.withOpacity(0.2), // Fond de la barre
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor), // Couleur de la progression
                  minHeight: 2, // Hauteur fine
                );
              },
            ),
            const SizedBox(height: 4), // Espace
            // Barre de progression du roman entier
            LinearProgressIndicator(
              value: novelProgress, // Valeur calculée
              backgroundColor: textColor.withOpacity(0.2), // Fond
              valueColor: AlwaysStoppedAnimation<Color>(textColor.withOpacity(0.5)), // Couleur progression
              minHeight: 2, // Hauteur fine
            ),
          ],
        ),
      ),
    );
  }

} // Fin NovelReaderPageState