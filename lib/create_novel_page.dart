// lib/create_novel_page.dart (CORRIGÉ - Erreur "Stream has already been listened to")
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:japanese_story_app/services/sync_service.dart'; // Assurez-vous que le chemin est correct
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'config.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'services/ai_prompts.dart';
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

  bool _isLoading = false;

  // --- Default values for a new novel ---
  String _selectedLanguage = 'Japonais';
  late String _selectedLevel;
  String _selectedGenre = 'Fantasy';
  String _selectedModelId = kDefaultModelId;

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
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isLoading) {
      return;
    }

    setState(() => _isLoading = true);

    await _handleNovelCreationFlow();

    // S'assurer que le widget est toujours monté avant de modifier l'état
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

    final novelDetails = {
      'title': _titleController.text.trim(),
      'specifications': _specificationsController.text.trim(),
      'language': _selectedLanguage,
      'level': _selectedLevel,
      'genre': _selectedGenre,
      'modelId': _selectedModelId,
      'userId': userId,
    };

    try {
      // --- Étape 1: Génération du Plan Directeur (Futur) ---
      AppLogger.info("Début Étape 1: Génération Plan Directeur", tag: "CreateNovelPage");
      final String planPrompt = roadmapService.getPlanPrompt(
        title: novelDetails['title']!,
        userPreferences: novelDetails['specifications']!,
        language: novelDetails['language']!,
        level: novelDetails['level']!,
        genre: novelDetails['genre']!,
        modelId: novelDetails['modelId']!,
        userId: userId,
      );
      final Stream<String> planStream = AIService.streamChapterFromPrompt(
        prompt: planPrompt,
        modelId: novelDetails['modelId']!,
        language: novelDetails['language']!,
      );

      if (!mounted) return;
      final String? rawPlan = await _showStreamingDialog(
        context: context,
        title: "Génération de la trame de l'histoire...",
        stream: planStream,
        showStreamContent: false, // Ne pas montrer le stream du plan
      );

      if (rawPlan == null) {
        AppLogger.warning("Génération du plan annulée ou échouée (rawPlan is null).", tag: "CreateNovelPage");
        _showFeedback("Création annulée.", isError: false);
        return;
      }
      if (rawPlan.trim().isEmpty) {
        AppLogger.error("La génération du plan a échoué (résultat vide).", tag: "CreateNovelPage");
        throw Exception("La génération de la trame a échoué (résultat vide).");
      }
       AppLogger.success("Étape 1 terminée: Plan Directeur généré (longueur: ${rawPlan.length}).", tag: "CreateNovelPage");


      // --- Étape 2: Création de l'objet Roman ---
       AppLogger.info("Début Étape 2: Création de l'objet Roman", tag: "CreateNovelPage");
      final String cleanedPlan = AIService.cleanAIResponse(rawPlan);
      final Novel newNovel = await roadmapService.createNovelFromPlan(
        userId: userId,
        title: novelDetails['title']!,
        specifications: novelDetails['specifications']!,
        language: novelDetails['language']!,
        level: novelDetails['level']!,
        genre: novelDetails['genre']!,
        modelId: novelDetails['modelId']!,
        generatedPlan: cleanedPlan,
      );
      AppLogger.success("Étape 2 terminée: Objet Novel créé (ID: ${newNovel.id}).", tag: "CreateNovelPage");


      // --- Étape 3: Génération du Chapitre 1 ---
      AppLogger.info("Début Étape 3: Génération Chapitre 1", tag: "CreateNovelPage");
      final String chapter1Prompt = await AIService.preparePrompt(novel: newNovel, isFirstChapter: true);
      final Stream<String> chapter1Stream = AIService.streamChapterFromPrompt(
        prompt: chapter1Prompt,
        modelId: newNovel.modelId,
        language: newNovel.language,
      );

      if (!mounted) return;
      final String? chapter1FullText = await _showStreamingDialog(
        context: context,
        title: "Génération du Chapitre 1...",
        stream: chapter1Stream,
        showStreamContent: true, // Afficher le stream
      );

      if (chapter1FullText == null) {
         AppLogger.warning("Génération du chapitre 1 annulée ou échouée (chapter1FullText is null).", tag: "CreateNovelPage");
        _showFeedback("Création annulée.", isError: false);
        try {
           await ref.read(novelsProvider.notifier).deleteNovel(newNovel.id);
           AppLogger.info("Nettoyage: Roman ${newNovel.id} supprimé.", tag: "CreateNovelPage");
        } catch (deleteError) {
           AppLogger.error("Erreur nettoyage roman ${newNovel.id}", error: deleteError, tag: "CreateNovelPage");
        }
        return;
      }
      if (chapter1FullText.trim().isEmpty) {
         AppLogger.error("Génération chapitre 1 échouée (vide).", tag: "CreateNovelPage");
         try {
           await ref.read(novelsProvider.notifier).deleteNovel(newNovel.id);
            AppLogger.info("Nettoyage: Roman ${newNovel.id} supprimé.", tag: "CreateNovelPage");
         } catch (deleteError) {
             AppLogger.error("Erreur nettoyage roman ${newNovel.id}", error: deleteError, tag: "CreateNovelPage");
         }
        throw Exception("La génération du chapitre 1 a échoué (résultat vide).");
      }
      AppLogger.success("Étape 3 terminée: Chapitre 1 généré (longueur: ${chapter1FullText.length}).", tag: "CreateNovelPage");


      // --- Étape 4: Finalisation & Sauvegarde ---
      AppLogger.info("Début Étape 4: Finalisation et Sauvegarde", tag: "CreateNovelPage");
      final Chapter firstChapter = AIService.extractTitleAndContent(
        chapter1FullText, 0, true, false, AIPrompts.getPromptsFor(newNovel.language),
      );
      await ref.read(novelsProvider.notifier).addChapter(newNovel.id, firstChapter);
      AppLogger.info("Chapitre 1 ajouté via provider.", tag: "CreateNovelPage");


      final syncTask = SyncTask(action: 'add', novelId: newNovel.id, content: firstChapter.content, chapterIndex: 0);
      await syncService.addTask(syncTask);
      AppLogger.info("Tâche synchro 'add' ajoutée.", tag: "CreateNovelPage");
      AppLogger.success("Étape 4 terminée.", tag: "CreateNovelPage");


      // --- Étape 5: Navigation ---
      AppLogger.info("Début Étape 5: Navigation", tag: "CreateNovelPage");
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
       AppLogger.success("Étape 5 terminée.", tag: "CreateNovelPage");


    } catch (e, stackTrace) {
      AppLogger.error("Échec global création roman", error: e, stackTrace: stackTrace, tag: "CreateNovelPage");
      if (mounted) {
        _showFeedback("Erreur lors de la création : ${e.toString()}", isError: true);
      }
       if (mounted && _isLoading) {
           setState(() => _isLoading = false);
       }
    }
  }

  // ✅ CORRECTION : Gestion de l'écouteur unique
  Future<String?> _showStreamingDialog({
    required BuildContext context,
    required String title,
    required Stream<String> stream,
    bool showStreamContent = false,
  }) async {
    final completer = Completer<String?>();
    final buffer = StringBuffer();
    StreamSubscription? streamSubscription; // Seulement si showStreamContent = false
    bool isCompleting = false; // Pour éviter double complétion

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // --- Logique d'écoute conditionnelle ---
        if (!showStreamContent) {
          // Si on ne montre PAS le stream, on l'écoute ici pour accumuler le buffer
           // S'assurer de ne pas ré-écouter si le dialogue se reconstruit
           if (streamSubscription == null) {
              streamSubscription = stream.listen(
                (chunk) {
                  buffer.write(chunk);
                },
                onDone: () {
                  AppLogger.info("Stream (caché) terminé (onDone) pour '$title'", tag: "CreateNovelPage._showStreamingDialog");
                  if (!isCompleting && !completer.isCompleted) {
                    isCompleting = true;
                    if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                    completer.complete(buffer.toString());
                  }
                },
                onError: (error, stack) {
                  AppLogger.error("Erreur sur stream (caché) pour '$title'", error: error, stackTrace: stack, tag: "CreateNovelPage._showStreamingDialog");
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
        // Si showStreamContent est true, on NE LANCE PAS d'écouteur ici.
        // StreamingTextAnimation le fera.

        return PopScope(
           canPop: false,
           child: AlertDialog(
             title: Row(
               children: [
                 const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                 const SizedBox(width: 16),
                 Expanded(child: Text(title)),
               ],
             ),
             content: SizedBox(
               width: MediaQuery.of(context).size.width * 0.8,
               height: MediaQuery.of(context).size.height * 0.6,
               child: showStreamContent
                 ? SingleChildScrollView(
                     child: StreamingTextAnimation(
                       // On passe le stream DIRECTEMENT
                       stream: stream,
                       style: Theme.of(context).textTheme.bodyMedium,
                       // Les callbacks gèrent la complétion et la fermeture
                       onDone: (fullText) {
                         AppLogger.info("StreamingTextAnimation (montré) terminé (onDone) pour '$title'", tag: "CreateNovelPage._showStreamingDialog");
                         if (!isCompleting && !completer.isCompleted) {
                            isCompleting = true;
                            // Pas besoin de fermer le dialogue ici, whenComplete le fera
                            completer.complete(fullText);
                         }
                       },
                       onError: (error) {
                          AppLogger.error("Erreur StreamingTextAnimation (montré) pour '$title'", error: error, tag: "CreateNovelPage._showStreamingDialog");
                          if (!isCompleting && !completer.isCompleted) {
                            isCompleting = true;
                            // Pas besoin de fermer le dialogue ici, whenComplete le fera
                            completer.completeError(error);
                          }
                       },
                     ),
                   )
                 : Center(
                     child: Text(
                       "L'écrivain prépare le fil rouge de l'histoire... \n(cette opération peut prendre quelques minutes)",
                       style: Theme.of(context).textTheme.bodyMedium,
                       textAlign: TextAlign.center,
                     ),
                   ),
             ),
             actions: [
               TextButton(
                 onPressed: () {
                   AppLogger.warning("Annulation manuelle pour '$title'", tag: "CreateNovelPage._showStreamingDialog");
                   // Annuler l'écouteur externe s'il existe
                   streamSubscription?.cancel();
                   if (!isCompleting && !completer.isCompleted) {
                      isCompleting = true;
                       if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                      completer.complete(null); // Annulation
                   }
                 },
                 child: const Text("Annuler"),
               )
             ],
           ),
        );
      },
    );

    // Nettoyage après la complétion du Future (succès, erreur ou annulation)
     completer.future.whenComplete(() {
        streamSubscription?.cancel(); // Annuler l'écouteur externe si besoin
         // Fermer le dialogue s'il est encore ouvert (sécurité)
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

  // --- build() reste inchangé ---
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
              decoration: const InputDecoration(
                labelText: 'Titre du roman',
                prefixIcon: Icon(Icons.title),
                hintText: 'Ex: Chroniques de l\'Aube Écarlate',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Veuillez entrer un titre' : null,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedModelId,
              decoration: const InputDecoration(
                labelText: 'Écrivain',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              items: kWritersMap.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        entry.value['name']!,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        entry.value['description']!,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
              selectedItemBuilder: (BuildContext context) {
                return kWritersMap.values.map<Widget>((item) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(item['name']!, overflow: TextOverflow.ellipsis),
                  );
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
                    items: _languageLevels.keys.map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
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
                    items: _currentLevels.map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
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
              items: _genres.map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) setState(() => _selectedGenre = newValue);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _specificationsController,
              decoration: const InputDecoration(
                labelText: 'Spécifications / Thèmes',
                prefixIcon: Icon(Icons.lightbulb_outline),
                hintText: 'Ex: lieu précis, description des personnages, éléments de l\'intrigue...',
              ),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: _isLoading
                  ? Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white)
                    )
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