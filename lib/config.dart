// lib/config.dart

import 'package:flutter/foundation.dart';

/// L'ID du modèle d'IA par défaut utilisé pour la génération de chapitres.
const String kDefaultModelId = 'qwen/qwen3-235b-a22b:free';

/// La liste centralisée des "écrivains" (modèles IA) disponibles pour la sélection.
/// Modifiez cette map pour ajouter ou changer les modèles dans toute l'application.
final Map<String, Map<String, String>> kWritersMap = {
  'qwen/qwen3-235b-a22b:free': {
    'name': 'Qwen 3.5B (Recommandé)',
    'description': 'Vous le verez penser et raisonner (en anglais), ce qui peut prendre plus de temps. Le meilleur choix actuellement pour la qualité.',
  },
  'meta-llama/llama-3.3-70b-instruct:free': {
    'name': 'Llama (Phase de test)',
    'description': 'Toujours en phase de test, peut produire des résultats incohérents.',
  },
  'cognitivecomputations/dolphin-mistral-24b-venice-edition:free': {
    'name': 'Venice (Phase de test)',
    'description': 'Toujours en phase de test, peut produire des résultats incohérents.',
  },
};

const String kBaseUrl = kDebugMode
    ? 'http://127.0.0.1:8000'
    // ✅ URL DE PRODUCTION CORRIGÉE
    : 'https://nihon-quest-api.onrender.com';