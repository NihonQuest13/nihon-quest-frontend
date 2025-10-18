// lib/edit_novel_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'config.dart'; // ✅ AJOUT DE L'IMPORT

// --- Les constantes locales sont SUPPRIMÉES ---

class EditNovelPage extends ConsumerStatefulWidget {
  final Novel novel;
  const EditNovelPage({super.key, required this.novel});

  @override
  EditNovelPageState createState() => EditNovelPageState();
}

class EditNovelPageState extends ConsumerState<EditNovelPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _specificationsController = TextEditingController();
  bool _isSaving = false;
  
  // Les valeurs initiales sont prises du roman
  late String _selectedLanguage;
  late String _selectedLevel;
  late String _selectedGenre;
  late String _selectedModelId;

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
    final novel = widget.novel;
    
    // Initialisation des contrôleurs et variables avec les données du roman
    _titleController.text = novel.title;
    _specificationsController.text = novel.specifications;
    
    _selectedLanguage = novel.language;
    // On doit s'assurer que la clé de langue existe, sinon on prend la première clé par défaut (Français)
    _currentLevels = _languageLevels[novel.language] ?? _languageLevels['Français']!;

    // On vérifie que le niveau existe bien dans la liste courante
    _selectedLevel = _currentLevels.contains(novel.level) ? novel.level : _currentLevels.first;
    
    // On vérifie que le genre existe bien dans la liste courante
    _selectedGenre = _genres.contains(novel.genre) ? novel.genre : _genres.first;
    
    // On utilise le modelId existant ou le par défaut
    _selectedModelId = kWritersMap.keys.contains(novel.modelId) ? novel.modelId! : kDefaultModelId; // ✅ MODIFIÉ
  }

  @override
  void dispose() {
    _titleController.dispose();
    _specificationsController.dispose();
    super.dispose();
  }

  Future<void> _updateNovel() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
       return;
    }
    setState(() { _isSaving = true; });

    final novel = widget.novel;
    
    // Mise à jour des propriétés du roman
    novel.title = _titleController.text.trim();
    novel.level = _selectedLevel;
    novel.genre = _selectedGenre;
    novel.specifications = _specificationsController.text.trim();
    novel.modelId = _selectedModelId;
    novel.updatedAt = DateTime.now();

    // La langue ne peut pas être changée ici (elle est bloquée dans l'UI)
    
    try {
      await ref.read(novelsProvider.notifier).updateNovel(novel);
      if (mounted) {
        _showFeedback('Roman "${novel.title}" mis à jour avec succès !');
        // On revient à la page précédente (HomePage)
        Navigator.pop(context);
      }
    } catch (e) {
       if (mounted) {
        _showFeedback("Erreur lors de la mise à jour : ${e.toString()}", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  
  void _showFeedback(String message, {bool isError = false, int duration = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        duration: Duration(seconds: duration),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final novel = widget.novel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le roman'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            Center(
              child: Container(
                width: 120,
                height: 180,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline.withAlpha((255 * 0.5).round()), width: 1),
                ),
                // Affiche l'image de couverture si elle est disponible (dans ce contexte, elle vient d'une URL)
                child: novel.coverImagePath != null && novel.coverImagePath!.startsWith('http')
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(novel.coverImagePath!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.menu_book, size: 40, color: theme.colorScheme.secondary),
                        const SizedBox(height: 8),
                        Text("Couverture\nexistante", textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                      ],
                    ),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titre du roman',
                prefixIcon: Icon(Icons.title),
                hintText: 'Ex: Chroniques de l\'Aube Écarlate',
              ),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Veuillez entrer un titre' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedModelId,
              decoration: const InputDecoration(
                labelText: 'Écrivain',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              items: kWritersMap.entries.map((entry) { // ✅ MODIFIÉ
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
                return kWritersMap.values.map<Widget>((item) { // ✅ MODIFIÉ
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item['name']!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList();
              },
              onChanged: _isSaving ? null : (String? newValue) {
                if (newValue != null && mounted) {
                  setState(() {
                    _selectedModelId = newValue;
                  });
                }
              },
              validator: (value) => value == null ? 'Veuillez sélectionner un écrivain' : null,
            ),
            const SizedBox(height: 20),
            // La langue est bloquée ici car son changement pourrait causer des problèmes critiques
            AbsorbPointer(
              absorbing: true,
              child: DropdownButtonFormField<String>(
                value: _selectedLanguage,
                decoration: InputDecoration(
                  labelText: 'Langue du roman (Ne peut pas être modifiée)',
                  prefixIcon: const Icon(Icons.language),
                  // Style visuel pour indiquer que le champ est désactivé
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
                ),
                items: _languageLevels.keys.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  );
                }).toList(),
                onChanged: null,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedLevel,
              decoration: const InputDecoration(
                labelText: 'Niveau de langue',
                prefixIcon: Icon(Icons.leaderboard_outlined),
              ),
              items: _currentLevels.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: _isSaving ? null : (String? newValue) {
                if (newValue != null && mounted) {
                  setState(() {
                    _selectedLevel = newValue;
                  });
                }
              },
              validator: (value) => value == null ? 'Veuillez sélectionner un niveau' : null,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedGenre,
              decoration: const InputDecoration(
                labelText: 'Genre',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _genres.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: _isSaving ? null : (String? newValue) {
                 if (newValue != null && mounted) {
                  setState(() {
                    _selectedGenre = newValue;
                  });
                }
              },
              validator: (value) => value == null ? 'Veuillez sélectionner un genre' : null,
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
              maxLines: null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: _isSaving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator( color: theme.colorScheme.onPrimary, strokeWidth: 2.5 ) )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Sauvegarde en cours...' : 'Sauvegarder les modifications'),
              onPressed: _isSaving ? null : _updateNovel,
            ),
          ],
        ),
      ),
    );
  }
}