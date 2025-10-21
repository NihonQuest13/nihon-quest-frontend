// lib/widgets/cached_cover_image.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Widget optimisé pour afficher les couvertures avec mise en cache
class CachedCoverImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover, // Fit par défaut
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CachedNetworkImage(
      imageUrl: imageUrl, // URL de l'image
      width: width,      // Largeur optionnelle
      height: height,     // Hauteur optionnelle
      fit: fit,          // Comment l'image doit s'adapter

      // Widget affiché pendant le chargement
      placeholder: (context, url) => placeholder ?? Center(
        child: SizedBox(
          width: 30, // Taille de l'indicateur
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.5, // Épaisseur
            color: theme.colorScheme.primary.withOpacity(0.7), // Couleur thème
          ),
        ),
      ),

      // Widget affiché en cas d'erreur de chargement
      errorWidget: (context, url, error) => errorWidget ?? Container(
        // Fond légèrement grisé pour indiquer une erreur
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon( // Icône d'image cassée
              Icons.broken_image_outlined,
              size: 40, // Taille de l'icône
              color: theme.colorScheme.error.withOpacity(0.7), // Couleur d'erreur
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text( // Message d'erreur
                'Image\nindisponible',
                style: theme.textTheme.labelSmall?.copyWith( // Petite police
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),

      // Options de performance du cache (ajuster si nécessaire)
      memCacheWidth: 400, // Limite taille en mémoire (pixels)
      memCacheHeight: 600,
      maxWidthDiskCache: 800, // Limite taille sur disque (pixels)
      maxHeightDiskCache: 1200,

      // Optionnel: Clé de cache unique (l'URL est souvent suffisante)
      // cacheKey: imageUrl,

      // Optionnel: Animation de fondu à l'apparition
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
    );
  }
}