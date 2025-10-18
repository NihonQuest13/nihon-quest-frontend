import 'dart:async';
import 'package:flutter/material.dart';

// AMÉLIORATION : Le widget est maintenant plus robuste et sa documentation est plus claire.
class StreamingTextAnimation extends StatefulWidget {
  /// Le flux de données textuelles à afficher.
  final Stream<String> stream;

  /// Le style à appliquer au texte.
  final TextStyle? style;

  /// Callback exécuté lorsque le flux est terminé avec succès.
  /// Renvoie le texte complet qui a été reçu.
  final Function(String) onDone;

  /// Callback exécuté si une erreur se produit sur le flux.
  final Function(Object) onError;

  const StreamingTextAnimation({
    super.key,
    required this.stream,
    required this.onDone,
    required this.onError,
    this.style,
  });

  @override
  StreamingTextAnimationState createState() => StreamingTextAnimationState();
}

class StreamingTextAnimationState extends State<StreamingTextAnimation> {
  final StringBuffer _fullText = StringBuffer();
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // On s'abonne au flux de données dès que le widget est initialisé.
    _subscribeToStream();
  }

  @override
  void didUpdateWidget(StreamingTextAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // AMÉLIORATION : Si le flux change (ce qui est rare mais possible),
    // on se désabonne de l'ancien et on s'abonne au nouveau pour éviter les fuites.
    if (widget.stream != oldWidget.stream) {
      _unsubscribe();
      _subscribeToStream();
    }
  }

  void _subscribeToStream() {
    _subscription = widget.stream.listen(
      (chunk) {
        // On ajoute chaque morceau de texte reçu.
        if (mounted) {
          setState(() {
            _fullText.write(chunk);
          });
          // On fait défiler automatiquement vers le bas pour que l'utilisateur voie le texte arriver.
          _scrollToBottom();
        }
      },
      onDone: () {
        // Le flux est terminé, on appelle le callback de succès.
        if (mounted) {
          widget.onDone(_fullText.toString());
        }
      },
      onError: (error) {
        // Une erreur est survenue, on appelle le callback d'erreur.
        if (mounted) {
          widget.onError(error);
        }
      },
      // Important : le flux sera automatiquement annulé en cas d'erreur.
      cancelOnError: true,
    );
  }

  void _scrollToBottom() {
    // On attend un très court instant que l'interface se mette à jour avec le nouveau texte
    // avant de calculer la position maximale de défilement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // AMÉLIORATION : La logique de désabonnement est isolée dans sa propre méthode pour plus de clarté.
  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    // On s'assure de bien se désabonner et de libérer les ressources
    // lorsque le widget est retiré de l'écran. C'est crucial pour éviter les bugs.
    _unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Le widget d'affichage est un simple texte sélectionnable qui se met à jour
    // au fur et à mesure que les données arrivent.
    return SingleChildScrollView(
      controller: _scrollController,
      child: SelectableText(
        _fullText.toString(),
        style: widget.style,
        textAlign: TextAlign.justify,
      ),
    );
  }
}