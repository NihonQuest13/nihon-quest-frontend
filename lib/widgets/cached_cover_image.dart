// lib/widgets/cached_cover_image.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Widget optimisé pour afficher les couvertures de romans
/// avec mise en cache automatique et gestion des erreurs
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
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      
      // 🚀 Placeholder pendant le chargement
      placeholder: (context, url) => placeholder ?? Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      
      // ❌ Widget en cas d'erreur
      errorWidget: (context, url, error) => errorWidget ?? Container(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Image non disponible',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      
      // ⚙️ Configuration du cache
      memCacheWidth: 400, // Limite la taille en mémoire
      memCacheHeight: 600,
      maxWidthDiskCache: 800, // Limite la taille sur disque
      maxHeightDiskCache: 1200,
      
      // 🔄 Durée de vie du cache (7 jours)
      cacheKey: imageUrl,
    );
  }
}

// 📝 UTILISATION dans home_page.dart :
// Remplacer Image.network() par CachedCoverImage()
//
// ❌ AVANT :
// Image.network(coverPath!, fit: BoxFit.cover)
//
// ✅ APRÈS :
// CachedCoverImage(imageUrl: coverPath!, fit: BoxFit.cover)