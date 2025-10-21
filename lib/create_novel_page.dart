// lib/create_novel_page.dart (MODIFIÉ POUR CACHER LE PLAN FUTUR)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:japanese_story_app/services/sync_service.dart';
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

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // ✅ CORRECTION : Logique entièrement revue pour enchaîner les dialogues de streaming.
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
      // ✅ MODIFICATION : Changement du titre du dialogue
      final String? rawPlan = await _showStreamingDialog(
        context: context,
        title: "Génération de la trame de l'histoire...", // Titre plus générique
        stream: planStream,
      );

      if (rawPlan == null) {
        _showFeedback("Création annulée.", isError: false);
        return;
      }
      if (rawPlan.trim().isEmpty) {
        throw Exception("La génération de la trame a échoué (résultat vide).");
      }

      // --- Étape 2: Création de l'objet Roman (avec le plan futur caché) ---
      final String cleanedPlan = AIService.cleanAIResponse(rawPlan);
      final Novel newNovel = await roadmapService.createNovelFromPlan(
        userId: userId,
        title: novelDetails['title']!,
        specifications: novelDetails['specifications']!,
        language: novelDetails['language']!,
        level: novelDetails['level']!,
        genre: novelDetails['genre']!,
        modelId: novelDetails['modelId']!,
        generatedPlan: cleanedPlan, // Le plan est stocké mais ne sera pas montré
      );

      // --- Étape 3: Génération du Chapitre 1 ---
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
      );

      if (chapter1FullText == null) {
        _showFeedback("Création annulée.", isError: false);
        await ref.read(novelsProvider.notifier).deleteNovel(newNovel.id); // Nettoyage
        return;
      }
      if (chapter1FullText.trim().isEmpty) {
        throw Exception("La génération du chapitre 1 a échoué (résultat vide).");
      }

      // --- Étape 4: Finalisation & Sauvegarde ---
      final Chapter firstChapter = AIService.extractTitleAndContent(
        chapter1FullText, 0, true, false, AIPrompts.getPromptsFor(newNovel.language),
      );
      await ref.read(novelsProvider.notifier).addChapter(newNovel.id, firstChapter);

      final syncTask = SyncTask(action: 'add', novelId: newNovel.id, content: firstChapter.content, chapterIndex: 0);
      await syncService.addTask(syncTask);

      // --- Étape 5: Navigation ---
      if (!mounted) return;
      _showFeedback("Roman créé avec succès !", isError: false);

      Navigator.of(context).pop(); // Quitte CreateNovelPage
      Navigator.of(context).pushReplacement( // Remplace la page actuelle pour éviter un retour accidentel
        MaterialPageRoute(
          builder: (context) => NovelReaderPage(
            novelId: newNovel.id,
            vocabularyService: ref.read(vocabularyServiceProvider),
            themeService: themeService,
          ),
        ),
      );

    } catch (e, stackTrace) {
      AppLogger.error("Échec lors de la création du roman", error: e, stackTrace: stackTrace);
      if (mounted) {
        _showFeedback("Erreur lors de la création : ${e.toString()}", isError: true);
      }
    }
  }

  // ✅ NOUVELLE FONCTION HELPER pour les dialogues de streaming
  Future<String?> _showStreamingDialog({
    required BuildContext context,
    required String title,
    required Stream<String> stream,
  }) {
    final completer = Completer<String?>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row( // Ajout d'un indicateur visuel
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 16),
              Expanded(child: Text(title)),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.6,
            // ✅ MODIFICATION : Le contenu du stream n'est PAS affiché ici
            child: Center(
              child: Text(
                "L'écrivain prépare l'histoire...",
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            // child: SingleChildScrollView(
            //   child: StreamingTextAnimation(
            //     stream: stream,
            //     onDone: (fullText) {
            //       if (!completer.isCompleted) completer.complete(fullText);
            //       if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
            //     },
            //     onError: (error) {
            //       if (!completer.isCompleted) completer.completeError(error);
            //       if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
            //     },
            //   ),
            // ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!completer.isCompleted) completer.complete(null); // Annulation utilisateur
                if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
              },
              child: const Text("Annuler"),
            )
          ],
        );
      },
    );

    // Écouter le stream en arrière-plan pendant que le dialogue "générique" est affiché
    final streamSubscription = stream.listen(
      (chunk) { /* Ne rien faire avec le chunk ici */ },
      onDone: () {
        // Le stream est terminé, mais on ne sait pas encore le contenu
        // On suppose que AIService gère les erreurs de contenu vide
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      cancelOnError: true,
    );

    // Gérer la complétion du dialogue (quand l'utilisateur annule ou que le stream finit)
    completer.future.then((result) async {
      await streamSubscription.cancel(); // Annuler l'écoute du stream
      if (Navigator.of(context).canPop()) {
         // Assurez-vous que le dialogue est toujours affiché avant de le fermer
         // (peut avoir déjà été fermé par onError/onDone interne au dialogue)
        Navigator.of(context).popUntil((route) => route is! DialogRoute);
      }
    }).catchError((error) async {
       await streamSubscription.cancel();
       if (Navigator.of(context).canPop()) {
         Navigator.of(context).popUntil((route) => route is! DialogRoute);
       }
    });

    // Retourner le futur qui complétera avec le texte complet ou null/erreur
    return completer.future;
  }


  // ✅ NOUVELLE FONCTION HELPER pour les messages
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