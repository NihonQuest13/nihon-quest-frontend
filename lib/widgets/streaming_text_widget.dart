// lib/widgets/streaming_text_widget.dart (CORRIGÉ - Affichage caractère par caractère pour espaces)
import 'dart:async';
// Retire 'dart:collection' car on n'utilise plus la Queue de mots
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

class StreamingTextAnimation extends StatefulWidget {
  final Stream<String> stream;
  final TextStyle? style;
  final Function(String) onDone;
  final Function(Object) onError;
  // ✅ MODIFICATION : Durée par caractère au lieu de par mot
  final Duration characterDisplayDuration;
  final String initialLoadingMessage;

  const StreamingTextAnimation({
    super.key,
    required this.stream,
    required this.onDone,
    required this.onError,
    this.style,
    // ✅ Vitesse par défaut ajustée pour les caractères
    this.characterDisplayDuration = const Duration(milliseconds: 5), // Plus rapide
    this.initialLoadingMessage = "L'écrivain consulte le contexte...",
  });

  @override
  StreamingTextAnimationState createState() => StreamingTextAnimationState();
}

class StreamingTextAnimationState extends State<StreamingTextAnimation> {
  final StringBuffer _fullReceivedText = StringBuffer();
  final StringBuffer _displayedText = StringBuffer();
  // ✅ MODIFICATION : Queue de caractères au lieu de mots
  final List<String> _pendingChars = [];
  StreamSubscription<String>? _streamSubscription;
  // ✅ MODIFICATION : Renommé en _charTimer
  Timer? _charTimer;
  final ScrollController _scrollController = ScrollController();
  bool _streamDone = false;
  bool _hasReceivedFirstChunk = false;

  @override
  void initState() {
    super.initState();
    _subscribeToStream();
  }

  @override
  void didUpdateWidget(StreamingTextAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream) {
      _unsubscribeFromStream();
      _resetState();
      _subscribeToStream();
    }
    // Gérer changement de durée
    if (widget.characterDisplayDuration != oldWidget.characterDisplayDuration && _charTimer == null && _hasReceivedFirstChunk) {
       _startCharTimer();
    }
  }

  void _resetState() {
     _charTimer?.cancel();
     _charTimer = null;
     _pendingChars.clear(); // ✅ Vider la liste de caractères
     _fullReceivedText.clear();
     _displayedText.clear();
     _streamDone = false;
     _hasReceivedFirstChunk = false;
  }

  void _subscribeToStream() {
    _streamSubscription = widget.stream.listen(
      (chunk) {
        if (mounted) {
          if (!_hasReceivedFirstChunk && chunk.trim().isNotEmpty) {
             // Utiliser un microtask pour démarrer le timer après le build initial
             Future.microtask(() {
                if (mounted) {
                   setState(() {
                      _hasReceivedFirstChunk = true;
                   });
                   _startCharTimer();
                   AppLogger.info("Premier chunk reçu, démarrage affichage car. par car.", tag: "StreamingText");
                }
             });
          }

          _fullReceivedText.write(chunk);
          // ✅ MODIFICATION : Ajouter les caractères (pas les mots) à la liste
          _pendingChars.addAll(chunk.split(''));

          // S'assurer que le timer tourne s'il y a des caractères et que le premier chunk est arrivé
          if (_hasReceivedFirstChunk && (_charTimer == null || !_charTimer!.isActive)) {
             _startCharTimer();
          }
        }
      },
      onDone: () {
        _streamDone = true;
         AppLogger.info("Stream source done. Pending chars: ${_pendingChars.length}", tag: "StreamingText");
         if (!_hasReceivedFirstChunk && mounted) {
            AppLogger.warning("Stream ended before receiving any content. Calling onDone.", tag: "StreamingText");
            widget.onDone(_fullReceivedText.toString());
         }
      },
      onError: (error, stack) {
        if (mounted) {
          _streamDone = true;
          _charTimer?.cancel();
           AppLogger.error("Stream source error.", error: error, stackTrace: stack, tag: "StreamingText");
          widget.onError(error);
        }
      },
      cancelOnError: true,
    );
  }

  // ✅ MODIFICATION : Renommé en _startCharTimer
  void _startCharTimer() {
     _charTimer?.cancel();
     // Vérifier aussi _hasReceivedFirstChunk ici, même si déjà vérifié avant l'appel
     if (!mounted || !_hasReceivedFirstChunk) return;

     AppLogger.info("Démarrage/Redémarrage du _charTimer.", tag: "StreamingText");
     // ✅ Utiliser widget.characterDisplayDuration
     _charTimer = Timer.periodic(widget.characterDisplayDuration, (timer) {
        if (!mounted) {
           timer.cancel();
           return;
        }

       // Afficher plusieurs caractères à la fois pour la fluidité (ajuster le nombre si besoin)
       int charsToShow = 2;
       bool changed = false;
       while (_pendingChars.isNotEmpty && charsToShow > 0) {
           final char = _pendingChars.removeAt(0); // ✅ Prendre le premier caractère
           _displayedText.write(char); // ✅ Ajouter le caractère
           charsToShow--;
           changed = true;
       }

       if (changed) {
           setState(() {}); // Mettre à jour l'UI
           _scrollToBottom();
       }

       // Vérifier la fin après avoir potentiellement ajouté des caractères
       if (_pendingChars.isEmpty && _streamDone) {
         timer.cancel();
         _charTimer = null;
         if (mounted) {
              AppLogger.info("All chars displayed and stream done. Calling widget.onDone.", tag: "StreamingText");
             widget.onDone(_fullReceivedText.toString());
         }
       }
     });
  }


  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 40), // Garder rapide
          curve: Curves.linear,
        );
      }
    });
  }

  void _unsubscribeFromStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  @override
  void dispose() {
    _unsubscribeFromStream();
    _charTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasReceivedFirstChunk) {
      return Center(
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
                 widget.initialLoadingMessage,
                 textAlign: TextAlign.center,
                 style: widget.style ?? Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                 ),
               ),
             ],
          ),
        ),
      );
    } else {
      return SingleChildScrollView(
        controller: _scrollController,
        child: SelectableText(
          // ✅ Utiliser _displayedText qui est mis à jour caractère par caractère
          _displayedText.toString(),
          style: widget.style,
          textAlign: TextAlign.justify,
        ),
      );
    }
  }
}