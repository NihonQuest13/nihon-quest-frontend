// lib/create_novel_page.dart (MODIFIÉ POUR LA TRAME PERSONNALISÉE EXCLUSIVE)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'config.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/ai_prompts.dart';
import 'services/sync_service.dart';
import 'novel_reader_page.dart';
import 'widgets/streaming_text_widget.dart';
import 'utils/app_logger.dart';

class CreateNovelPage extends ConsumerStatefulWidget {
  const CreateNovelPage({super.key});

  @override
  CreateNovelPageState createState() => CreateNovelPageState();
}

class CreateNovelPageState extends ConsumerState<CreateNovelPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _specificationsController = TextEditingController();
  final TextEditingController _futureOutlineController = TextEditingController();

  bool _isLoading = false;

  String _selectedLanguage = 'Japonais';
  late String _selectedLevel;
  String _selectedGenre = 'Fantasy';
  String _selectedModelId = kDefaultModelId;
  bool _isDynamicOutline = true;

  final Map<String, List<String>> _languageLevels = {
    'Anglais': ['A1 (Beginner)', 'A2 (Elementary)', 'B1 (Intermediate)', 'B2 (Advanced)', 'C1 (Proficient)', 'C2 (Mastery)', 'Native'],
    'Coréen': ['TOPIK 1-2 (Débutant)', 'TOPIK 3-4 (Intermédiaire)', 'TOPIK 5-6 (Avancé)', 'Natif'],
    'Espagnol': ['A1 (Principiante)', 'A2 (Elemental)', 'B1 (Intermedio)', 'B2 (Avanzado)', 'C1 (Experto)', 'C2 (Maestría)', 'Nativo'],
    'Français': ['A1 (Débutant)', 'A2 (Élémentaire)', 'B1 (Intermédiaire)', 'B2 (Avancé)', 'C1 (Expert)', 'C2 (Maîtrise)', 'Natif'],
    'Italien': ['A1 (Principiante)', 'A2 (Elementare)', 'B1 (Intermedio)', 'B2 (Avanzado)', 'C1 (Esperto)', 'C2 (Padronanza)', 'Nativo'],
    'Japonais': ['N5', 'N4', 'N3', 'N2', 'N1', 'Natif']
  };

  final List<String> _genres = const [
    'Aventure', 'Fantasy', 'Historique', 'Horreur', 'Mystère', 'Philosophie', 'Poésie', 'Romance', 'Science-fiction', 'Slice of Life', 'Smut', 'Thriller', 'Western', 'Autre'
  ];

  late List<String> _currentLevels;

  @override
  void initState() {
    super.initState();
    _currentLevels = _languageLevels[_selectedLanguage]!;
    _selectedLevel = _currentLevels[2]; // Default to N3/Intermediate
  }

  @override
  void dispose() {
    _titleController.dispose();
    _specificationsController.dispose();
    _futureOutlineController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isLoading) {
      return;
    }
    setState(() => _isLoading = true);
    await _handleNovelCreationFlow();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleNovelCreationFlow() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _showFeedback("Erreur : Utilisateur non connecté.", isError: true);
      return;
    }

    final roadmapService = ref.read(roadmapServiceProvider);
    final syncService = ref.read(syncServiceProvider);
    
    // Si la trame n'est pas dynamique, on prend ce que l'utilisateur a écrit.
    final userProvidedOutline = !_isDynamicOutline ? _futureOutlineController.text.trim() : null;
    String? finalFutureOutline;

    try {
      // --- Étape 1: Déterminer le Plan Directeur (Futur) ---
      if (userProvidedOutline != null) {
        // L'utilisateur a fourni son propre plan (ou a laissé le champ vide).
        finalFutureOutline = userProvidedOutline.isNotEmpty ? userProvidedOutline : null;
        AppLogger.info("Utilisation du plan directeur fourni par l'utilisateur (longueur: ${finalFutureOutline?.length ?? 0}).", tag: "CreateNovelPage");
      } else { // Implique que _isDynamicOutline est true
        // L'utilisateur veut une trame évolutive -> l'IA génère
        AppLogger.info("Début Étape 1: Génération du Plan Directeur par l'IA", tag: "CreateNovelPage");
        final planPrompt = roadmapService.getPlanPrompt(
          title: _titleController.text.trim(),
          userPreferences: _specificationsController.text.trim(),
          language: _selectedLanguage,
          level: _selectedLevel,
          genre: _selectedGenre,
          modelId: _selectedModelId,
          userId: userId,
        );
        final planStream = AIService.streamChapterFromPrompt(
          prompt: planPrompt, modelId: _selectedModelId, language: _selectedLanguage,
        );

        if (!mounted) return;
        final rawPlan = await _showStreamingDialog(
          context: context, title: "Génération de la trame de l'histoire...", stream: planStream, showStreamContent: false,
        );

        if (rawPlan == null || rawPlan.trim().isEmpty) {
          _showFeedback("La création a été annulée ou a échoué.", isError: true);
          return;
        }
        finalFutureOutline = AIService.cleanAIResponse(rawPlan);
        AppLogger.success("Étape 1 terminée: Plan Directeur généré par l'IA.", tag: "CreateNovelPage");
      }
      
      // --- Étape 2: Création de l'objet Roman ---
      AppLogger.info("Début Étape 2: Création de l'objet Roman", tag: "CreateNovelPage");
      final newNovel = Novel(
        user_id: userId,
        title: _titleController.text.trim(),
        specifications: _specificationsController.text.trim(),
        language: _selectedLanguage,
        level: _selectedLevel,
        genre: _selectedGenre,
        modelId: _selectedModelId,
        createdAt: DateTime.now(),
        futureOutline: finalFutureOutline,
        isDynamicOutline: _isDynamicOutline,
        roadMap: "Le roman vient de commencer.",
      );
      await ref.read(novelsProvider.notifier).addNovel(newNovel);
      AppLogger.success("Étape 2 terminée: Objet Novel créé (ID: ${newNovel.id}).", tag: "CreateNovelPage");

      // --- Étape 3: Génération du Chapitre 1 ---
      AppLogger.info("Début Étape 3: Génération Chapitre 1", tag: "CreateNovelPage");
      final chapter1Prompt = await AIService.preparePrompt(novel: newNovel, isFirstChapter: true);
      final chapter1Stream = AIService.streamChapterFromPrompt(
        prompt: chapter1Prompt, modelId: newNovel.modelId, language: newNovel.language,
      );

      if (!mounted) return;
      final chapter1FullText = await _showStreamingDialog(
        context: context, title: "Génération du Chapitre 1...", stream: chapter1Stream, showStreamContent: true,
      );

      if (chapter1FullText == null || chapter1FullText.trim().isEmpty) {
        _showFeedback("Création annulée.", isError: false);
        await ref.read(novelsProvider.notifier).deleteNovel(newNovel.id);
        return;
      }
      AppLogger.success("Étape 3 terminée: Chapitre 1 généré.", tag: "CreateNovelPage");

      // --- Étape 4: Finalisation & Sauvegarde ---
      AppLogger.info("Début Étape 4: Finalisation et Sauvegarde", tag: "CreateNovelPage");
      final firstChapter = AIService.extractTitleAndContent(
        chapter1FullText, 0, true, false, AIPrompts.getPromptsFor(newNovel.language),
      );
      await ref.read(novelsProvider.notifier).addChapter(newNovel.id, firstChapter);
      
      final syncTask = SyncTask(action: 'add', novelId: newNovel.id, content: firstChapter.content, chapterIndex: 0);
      await syncService.addTask(syncTask);
      AppLogger.success("Étape 4 terminée.", tag: "CreateNovelPage");

      // --- Étape 5: Navigation ---
      if (!mounted) return;
      _showFeedback("Roman créé avec succès !", isError: false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => NovelReaderPage(
            novelId: newNovel.id,
            vocabularyService: ref.read(vocabularyServiceProvider),
            themeService: themeService,
          ),
        ),
      );

    } catch (e, stackTrace) {
      AppLogger.error("Échec global création roman", error: e, stackTrace: stackTrace, tag: "CreateNovelPage");
      if (mounted) {
        _showFeedback("Erreur lors de la création : ${e.toString()}", isError: true);
      }
    }
  }

  Future<String?> _showStreamingDialog({
    required BuildContext context,
    required String title,
    required Stream<String> stream,
    bool showStreamContent = false,
  }) async {
    final completer = Completer<String?>();
    final buffer = StringBuffer();
    StreamSubscription? streamSubscription;
    bool isCompleting = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!showStreamContent) {
           if (streamSubscription == null) {
              streamSubscription = stream.listen(
                (chunk) => buffer.write(chunk),
                onDone: () {
                  if (!isCompleting && !completer.isCompleted) {
                    isCompleting = true;
                    if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                    completer.complete(buffer.toString());
                  }
                },
                onError: (error, stack) {
                  if (!isCompleting && !completer.isCompleted) {
                    isCompleting = true;
                    if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                    completer.completeError(error);
                  }
                },
                cancelOnError: true,
              );
           }
        }

        return PopScope(
           canPop: false,
           child: AlertDialog(
             title: Row(children: [ const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)), const SizedBox(width: 16), Expanded(child: Text(title)), ],),
             content: SizedBox(
               width: MediaQuery.of(context).size.width * 0.8,
               height: MediaQuery.of(context).size.height * 0.6,
               child: showStreamContent
                 ? SingleChildScrollView(
                     child: StreamingTextAnimation(
                       stream: stream,
                       style: Theme.of(context).textTheme.bodyMedium,
                       onDone: (fullText) {
                         if (!isCompleting && !completer.isCompleted) {
                            isCompleting = true;
                            completer.complete(fullText);
                         }
                       },
                       onError: (error) {
                          if (!isCompleting && !completer.isCompleted) {
                            isCompleting = true;
                            completer.completeError(error);
                          }
                       },
                     ),
                   )
                 : Center( child: Text( "L'écrivain prépare le fil rouge de l'histoire...", style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center,), ),
             ),
             actions: [
               TextButton(
                 onPressed: () {
                   streamSubscription?.cancel();
                   if (!isCompleting && !completer.isCompleted) {
                      isCompleting = true;
                       if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                      completer.complete(null);
                   }
                 },
                 child: const Text("Annuler"),
               )
             ],
           ),
        );
      },
    );

     completer.future.whenComplete(() {
        streamSubscription?.cancel();
         if (Navigator.of(context).canPop()) {
            Navigator.of(context).popUntil((route) => route is! DialogRoute);
         }
     });

    return completer.future;
  }

  void _showFeedback(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer un nouveau roman'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration( labelText: 'Titre du roman', prefixIcon: Icon(Icons.title), hintText: 'Ex: Chroniques de l\'Aube Écarlate',),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Veuillez entrer un titre' : null,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedModelId,
              decoration: const InputDecoration( labelText: 'Écrivain', prefixIcon: Icon(Icons.edit_note_rounded),),
              items: kWritersMap.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text( entry.value['name']!, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis,),
                      Text( entry.value['description']!, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis,),
                    ],
                  ),
                );
              }).toList(),
              selectedItemBuilder: (BuildContext context) {
                return kWritersMap.values.map<Widget>((item) {
                  return Align( alignment: Alignment.centerLeft, child: Text(item['name']!, overflow: TextOverflow.ellipsis),);
                }).toList();
              },
              onChanged: (String? newValue) {
                if (newValue != null) setState(() => _selectedModelId = newValue);
              },
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedLanguage,
                    decoration: const InputDecoration(labelText: 'Langue', prefixIcon: Icon(Icons.language)),
                    items: _languageLevels.keys.map((String value) { return DropdownMenuItem<String>(value: value, child: Text(value)); }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedLanguage = newValue;
                          _currentLevels = _languageLevels[newValue]!;
                          _selectedLevel = _currentLevels.length > 2 ? _currentLevels[2] : _currentLevels.first;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _selectedLevel,
                    decoration: const InputDecoration(labelText: 'Niveau', prefixIcon: Icon(Icons.leaderboard_outlined)),
                    items: _currentLevels.map((String value) { return DropdownMenuItem<String>(value: value, child: Text(value)); }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) setState(() => _selectedLevel = newValue);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedGenre,
              decoration: const InputDecoration(labelText: 'Genre', prefixIcon: Icon(Icons.category_outlined)),
              items: _genres.map((String value) { return DropdownMenuItem<String>(value: value, child: Text(value)); }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) setState(() => _selectedGenre = newValue);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _specificationsController,
              decoration: const InputDecoration( labelText: 'Spécifications / Thèmes', prefixIcon: Icon(Icons.lightbulb_outline), hintText: 'Ex: lieu précis, description des personnages, éléments de l\'intrigue...',),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 20),
            
            CheckboxListTile(
              title: const Text("Trame évolutive (gérée par l'IA)"),
              subtitle: const Text("Laissez l'IA imaginer et faire évoluer l'histoire pour vous."),
              value: _isDynamicOutline,
              onChanged: (bool? value) {
                setState(() {
                  _isDynamicOutline = value ?? true;
                  if (_isDynamicOutline) {
                    _futureOutlineController.clear();
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            
            // ✅ CHAMP CONDITIONNEL AVEC ANIMATION
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                // Effet de fondu et de glissement vertical
                return SizeTransition(
                  sizeFactor: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: !_isDynamicOutline
                  ? TextFormField(
                      key: const ValueKey('futureOutlineField'), // Clé pour l'animation
                      controller: _futureOutlineController,
                      decoration: const InputDecoration(
                        labelText: 'Écrivez votre propre trame',
                        prefixIcon: Icon(Icons.timeline_outlined),
                        hintText: 'Décrivez les grandes lignes des prochains chapitres sous forme de sommaire...',
                      ),
                      minLines: 3,
                      maxLines: 8,
                    )
                  : const SizedBox.shrink(key: ValueKey('emptyOutline')), // Widget vide quand la case est cochée
            ),
            const SizedBox(height: 32),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom( minimumSize: const Size(double.infinity, 50),),
              icon: _isLoading
                  ? Container( width: 24, height: 24, padding: const EdgeInsets.all(2.0), child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white) )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? 'Création en cours...' : 'Commencer l\'aventure'),
              onPressed: _isLoading ? null : _submitForm,
            ),
          ],
        ),
      ),
    );
  }
}

