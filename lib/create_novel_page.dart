// lib/create_novel_page.dart (CORRIGÉ)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ✅ AJOUT DE L'IMPORT

import 'models.dart';
import 'config.dart';

// --- THIS IS THE NEW, CORRECT WIDGET ---
class CreateNovelPage extends ConsumerStatefulWidget {
  const CreateNovelPage({super.key});

  @override
  CreateNovelPageState createState() => CreateNovelPageState();
}

class CreateNovelPageState extends ConsumerState<CreateNovelPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _specificationsController = TextEditingController();

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
    'Italien': ['A1 (Principiante)', 'A2 (Elementare)', 'B1 (Intermedio)', 'B2 (Avanzato)', 'C1 (Esperto)', 'C2 (Padronanza)', 'Nativo'],
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

  // --- ⬇️ CORRECTION PRINCIPALE ICI ⬇️ ---
  void _createNovel() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // ✅ RÉCUPÉRER L'USER ID ACTUEL
    final userId = Supabase.instance.client.auth.currentUser?.id;

    // Sécurité : vérifier si l'utilisateur est bien connecté
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erreur : Utilisateur non connecté. Reconnexion..."),
          backgroundColor: Colors.red,
        ),
      );
      // Optionnel : déconnecter pour forcer le retour au login
      // Supabase.instance.client.auth.signOut();
      return;
    }

    final newNovel = Novel(
      user_id: userId, // ✅ AJOUT DU CHAMP user_id
      title: _titleController.text.trim(),
      level: _selectedLevel,
      genre: _selectedGenre,
      specifications: _specificationsController.text.trim(),
      language: _selectedLanguage,
      modelId: _selectedModelId,
      createdAt: DateTime.now(),
      summaries: [], // ✅ Initialiser avec une liste vide
    );

    // Return the newly created novel to the HomePage
    Navigator.pop(context, newNovel);
  }
  // --- ⬆️ FIN DE LA CORRECTION ⬆️ ---

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
            // Title
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

            // Writer selection
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

            // Language and Level
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

            // Genre
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

            // Specifications
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

            // Submit Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Commencer l\'aventure'),
              onPressed: _createNovel,
            ),
          ],
        ),
      ),
    );
  }
}