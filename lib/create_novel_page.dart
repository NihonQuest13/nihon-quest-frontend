// lib/create_novel_page.dart (MODIFIÉ POUR LE STREAMING ET CORRIGÉ)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'config.dart';
import 'providers.dart';
import 'services/ai_service.dart';
import 'novel_reader_page.dart';
import 'widgets/streaming_text_widget.dart';
import 'widgets/optimized_common_widgets.dart';
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

    await _generateNovelWithStreamingDialog();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateNovelWithStreamingDialog() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      if (mounted) { // ✅ SÉCURITÉ : Vérification du contexte
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur : Utilisateur non connecté."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // ✅ CORRIGÉ : On récupère le service roadmapServiceProvider
    final roadmapService = ref.read(roadmapServiceProvider);

    final String title = _titleController.text.trim();
    final String specifications = _specificationsController.text.trim();
    final String language = _selectedLanguage;
    final String level = _selectedLevel;
    final String genre = _selectedGenre;
    final String modelId = _selectedModelId;
    
    final Completer<String> textCompleter = Completer<String>();
    String generatedPlan = "";

    try {
      final String planPrompt = roadmapService.getPlanPrompt(
        title: title,
        userPreferences: specifications,
        language: language,
        level: level,
        genre: genre,
        modelId: modelId,
        userId: userId,
      );

      // ✅ CORRIGÉ : Appel direct à la méthode statique de AIService
      final Stream<String> generationStream = AIService.streamChapterFromPrompt(
        prompt: planPrompt,
        modelId: modelId,
        language: language,
      );

      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text("Génération du plan en cours..."),
            content: SizedBox( // ✅ CORRIGÉ : Remplacement de Container par SizedBox
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.6,
              child: SingleChildScrollView(
                // ✅ CORRIGÉ : Renommage de StreamingTextWidget en StreamingTextAnimation
                child: StreamingTextAnimation(
                  stream: generationStream,
                  onDone: (fullText) {
                    textCompleter.complete(fullText);
                    if (Navigator.of(dialogContext).canPop()) {
                       Navigator.of(dialogContext).pop();
                    }
                  },
                  onError: (error) {
                    textCompleter.completeError(error);
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ),
            ),
          );
        },
      );

      generatedPlan = await textCompleter.future;

      if (generatedPlan.trim().isEmpty) {
        throw Exception("La génération du plan a échoué ou a retourné un texte vide.");
      }

      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      showDialog(
        context: context,
        barrierDismissible: false,
        // ✅ CORRIGÉ : Remplacement de LoadingIndicator par LoadingWidget et ajout de `const`
        builder: (context) => const Center(child: LoadingWidget(message: "Finalisation..."),),
      );

      final Novel newNovel = await roadmapService.createNovelFromPlan(
        userId: userId,
        title: title,
        specifications: specifications,
        language: language,
        level: level,
        genre: genre,
        modelId: modelId,
        generatedPlan: generatedPlan,
      );

      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      await AIService.generateNextChapter(newNovel, context, ref);
      
      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      Navigator.of(context).pop();

      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      Navigator.of(context).pop();

      if (!mounted) return; // ✅ SÉCURITÉ : Vérification du contexte
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => NovelReaderPage(
            novelId: newNovel.id,
            vocabularyService: ref.read(vocabularyServiceProvider),
            themeService: themeService,
          ),
        ),
      );

    } catch (e, stackTrace) {
      // ✅ CORRIGÉ : Renommage de logError en error
      AppLogger.error("Échec lors de la création du roman", error: e, stackTrace: stackTrace);
      if (mounted) { // ✅ SÉCURITÉ : Vérification du contexte
        if (Navigator.of(context).canPop()) {
           Navigator.of(context).pop(); // Ferme le loading dialog s'il est ouvert
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la création : ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
