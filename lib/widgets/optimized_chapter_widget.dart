// lib/widgets/optimized_chapter_widget.dart
import 'package:flutter/material.dart';
import '../models.dart';

/// Widget optimisé pour afficher un chapitre
/// Utilise RepaintBoundary pour isoler les repeints
/// et const constructors quand possible
class OptimizedChapterWidget extends StatefulWidget {
  final Chapter chapter;
  final int index;
  final TextStyle baseStyle;
  final Function(String) onTextSelection;
  final ScrollController? scrollController;

  const OptimizedChapterWidget({
    super.key,
    required this.chapter,
    required this.index,
    required this.baseStyle,
    required this.onTextSelection,
    this.scrollController,
  });

  @override
  State<OptimizedChapterWidget> createState() => _OptimizedChapterWidgetState();
}

class _OptimizedChapterWidgetState extends State<OptimizedChapterWidget> 
    with AutomaticKeepAliveClientMixin {
  
  // ✅ Garde le widget en vie quand on change de page
  // Évite de reconstruire le chapitre à chaque fois
  @override
  bool get wantKeepAlive => true;

  // ✅ Cache pour les TextSpans formatés
  List<TextSpan>? _cachedSpans;
  
  @override
  void initState() {
    super.initState();
    _buildCachedSpans();
  }

  @override
  void didUpdateWidget(OptimizedChapterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ✅ Reconstruit le cache uniquement si le contenu change
    if (oldWidget.chapter.content != widget.chapter.content ||
        oldWidget.baseStyle != widget.baseStyle) {
      _buildCachedSpans();
    }
  }

  void _buildCachedSpans() {
    _cachedSpans = _formatText(widget.chapter.content, widget.baseStyle);
  }

  List<TextSpan> _formatText(String text, TextStyle baseStyle) {
    // Nettoyage du texte
    String processedText = text
        .replaceAll('—', ', ')
        .replaceAll(',,', ',');

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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Important pour AutomaticKeepAliveClientMixin
    
    final theme = Theme.of(context);
    final titleStyle = widget.baseStyle.copyWith(
      fontSize: widget.baseStyle.fontSize != null 
          ? widget.baseStyle.fontSize! + 4 
          : null,
      fontWeight: FontWeight.w800,
      height: 1.8,
      color: widget.baseStyle.color?.withAlpha((255 * 0.9).round()),
    );

    // ✅ RepaintBoundary isole ce widget des repeints du parent
    return RepaintBoundary(
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(
            20.0,
            MediaQuery.of(context).padding.top + kToolbarHeight + 24.0,
            20.0,
            120.0,
          ),
          child: SelectableText.rich(
            TextSpan(
              children: [
                // Titre
                ..._formatText("${widget.chapter.title}\n\n", titleStyle),
                // Contenu (depuis le cache)
                ..._cachedSpans!,
              ],
            ),
            textAlign: TextAlign.justify,
            onSelectionChanged: (selection, cause) {
              final fullText = "${widget.chapter.title}\n\n${widget.chapter.content}";
              
              if (selection.isValid && 
                  !selection.isCollapsed && 
                  (cause == SelectionChangedCause.longPress || 
                   cause == SelectionChangedCause.drag || 
                   cause == SelectionChangedCause.doubleTap)) {
                
                String selectedText = '';
                try {
                  if (selection.start >= 0 && 
                      selection.end <= fullText.length && 
                      selection.start < selection.end) {
                    selectedText = fullText
                        .substring(selection.start, selection.end)
                        .trim();
                  }
                } catch (e) {
                  debugPrint("Erreur substring: $e");
                  selectedText = '';
                }

                bool isValidForLookup = selectedText.isNotEmpty &&
                    selectedText != widget.chapter.title.trim() &&
                    selectedText.length <= 50 &&
                    !selectedText.contains('\n');
                
                if (isValidForLookup) {
                  widget.onTextSelection(selectedText);
                }
              }
            },
            cursorColor: theme.colorScheme.primary,
            selectionControls: MaterialTextSelectionControls(),
          ),
        ),
      ),
    );
  }
}

// 📝 UTILISATION dans novel_reader_page.dart :
//
// OptimizedChapterWidget(
//   chapter: chapter,
//   index: index,
//   baseStyle: _getBaseTextStyle(),
//   scrollController: _scrollControllers[index],
//   onTextSelection: (text) => _triggerReadingAndTranslation(text),
// )