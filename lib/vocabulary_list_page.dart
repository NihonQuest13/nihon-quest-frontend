// lib/vocabulary_list_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/vocabulary_service.dart';

class VocabularyListPage extends StatefulWidget {
  final VocabularyService vocabularyService;

  const VocabularyListPage({super.key, required this.vocabularyService});

  @override
  State<VocabularyListPage> createState() => _VocabularyListPageState();
}

class _VocabularyListPageState extends State<VocabularyListPage> {
  List<VocabularyEntry> _vocabularyList = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadVocabularyList();
  }

  Future<void> _loadVocabularyList() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final loadedList = await widget.vocabularyService.loadVocabulary();
      if (mounted) {
        setState(() {
          _vocabularyList = loadedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement vocabulaire: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        _showFeedback("Erreur lors du chargement du vocabulaire.", isError: true);
      }
    }
  }

  Future<void> _exportToAnkiTsv() async {
    if (_vocabularyList.isEmpty) {
      _showFeedback('La liste de vocabulaire est vide.', isError: true);
      return;
    }
    setState(() => _isProcessing = true);

    try {
      final buffer = StringBuffer();
      for (final entry in _vocabularyList) {
        final word = entry.word.replaceAll('\t', ' ').replaceAll('\n', ' ');
        final reading = entry.reading.replaceAll('\t', ' ').replaceAll('\n', ' ');
        final translation = entry.translation.replaceAll('\t', ' ').replaceAll('\n', ' ');
        buffer.writeln('$word\t$reading\t$translation');
      }
      final tsvData = buffer.toString();

      const fileName = 'vocabulaire_global.tsv';
      
      if (kIsWeb) {
        // L'export TSV sur le web nécessite une autre approche (téléchargement via un lien)
        _showFeedback("L'export TSV pour le web sera bientôt disponible.", isError: false);
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le fichier TSV pour Anki:',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['tsv'],
        );

        if (outputFile != null) {
          if (!outputFile.toLowerCase().endsWith('.tsv')) { outputFile += '.tsv'; }
          final file = File(outputFile);
          await file.writeAsString(tsvData, flush: true);
          _showFeedback('Vocabulaire exporté pour Anki (TSV)');
        } else {
          _showFeedback('Exportation annulée.', isError: false);
        }
      }
    } catch (e) {
      _showFeedback('Erreur lors de l\'export TSV: $e', isError: true);
    } finally {
      if(mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportToExcel() async {
    if (_vocabularyList.isEmpty) {
      _showFeedback('La liste de vocabulaire est vide.', isError: true);
      return;
    }
    setState(() => _isProcessing = true);

    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Vocabulaire Global'];

      // --- CORRECTION FINALE : on retire 'const' ---
      final header = [
        TextCellValue('Mot'),
        TextCellValue('Lecture (Hiragana)'),
        TextCellValue('Traduction (Français)')
      ];
      sheetObject.appendRow(header);

      for (final entry in _vocabularyList) {
        final row = [
          TextCellValue(entry.word),
          TextCellValue(entry.reading),
          TextCellValue(entry.translation),
        ];
        sheetObject.appendRow(row);
      }

      const fileName = 'vocabulaire_global.xlsx';
      
      if (kIsWeb) {
        excel.save(fileName: fileName);
        _showFeedback('Téléchargement Excel démarré.');
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le fichier Excel (.xlsx):',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (outputFile != null) {
           if (!outputFile.toLowerCase().endsWith('.xlsx')) { outputFile += '.xlsx'; }
          List<int>? fileBytes = excel.save();
          if (fileBytes != null) {
            final file = File(outputFile);
            await file.writeAsBytes(fileBytes, flush: true);
            _showFeedback('Vocabulaire exporté vers Excel (.xlsx)');
          } else { throw Exception("Impossible de générer les bytes Excel."); }
        } else {
          _showFeedback('Exportation annulée.', isError: false);
        }
      }
    } catch (e) {
      _showFeedback('Erreur lors de l\'export Excel: $e', isError: true);
    } finally {
      if(mounted) setState(() => _isProcessing = false);
    }
  }

   Future<void> _deleteEntry(VocabularyEntry entryToDelete) async {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Confirmer la suppression'),
                content: Text('Supprimer définitivement le mot "${entryToDelete.word}" du vocabulaire global ?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                  TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Supprimer')),
                ],
              ));

      if (confirm != true || !mounted) return;

      setState(() => _isProcessing = true);
      try {
         final success = await widget.vocabularyService.removeEntry(entryToDelete);
         if(success && mounted) {
            setState(() {
               _vocabularyList.remove(entryToDelete);
            });
             _showFeedback('Mot "${entryToDelete.word}" supprimé.');
         } else if (!success && mounted) {
            _showFeedback('Erreur lors de la suppression.', isError: true);
         }
      } catch (e) {
          _showFeedback('Erreur lors de la suppression: $e', isError: true);
      } finally {
         if(mounted) setState(() => _isProcessing = false);
      }
   }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar( content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.green, ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isEmpty = _vocabularyList.isEmpty;
    final DateFormat dateFormat = DateFormat('dd/MM/yy HH:mm', 'fr_FR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vocabulaire Global'),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.file_download_outlined,
              color: isEmpty || _isLoading || _isProcessing ? theme.disabledColor : null,
            ),
            tooltip: 'Exporter le vocabulaire',
            enabled: !_isLoading && !isEmpty && !_isProcessing,
            onSelected: (String choice) {
              if (choice == 'anki') { _exportToAnkiTsv(); }
              else if (choice == 'excel') { _exportToExcel(); }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>( value: 'anki', child: ListTile( leading: Icon(Icons.library_books_outlined), title: Text('Exporter pour Anki (TSV)'), ), ),
              const PopupMenuItem<String>( value: 'excel', child: ListTile( leading: Icon(Icons.table_chart_outlined), title: Text('Exporter vers Excel (.xlsx)'), ), ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isProcessing
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Traitement en cours..."),
                    ],
                  ),
                )
              : isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          'Aucun mot n\'a été enregistré dans le vocabulaire global.',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                     onRefresh: _loadVocabularyList,
                     child: ListView.separated(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _vocabularyList.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = _vocabularyList[index];
                          return ListTile(
                            title: SelectableText(
                              entry.word,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            subtitle: SelectableText(
                              '${entry.reading}  /  ${entry.translation}\nEnregistré le: ${dateFormat.format(entry.createdAt.toLocal())}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                            ),
                            isThreeLine: true,
                            dense: false,
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.grey[400], size: 20,),
                              tooltip: 'Supprimer ce mot',
                              onPressed: _isProcessing ? null : () => _deleteEntry(entry),
                            ),
                          );
                        },
                      ),
                   ),
    );
  }
}