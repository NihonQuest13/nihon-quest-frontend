// lib/config.dart

import 'package:flutter/foundation.dart';

/// L'ID du modèle d'IA par défaut utilisé pour la génération de chapitres.
const String kDefaultModelId = 'deepseek/deepseek-r1-0528:free';

/// La liste centralisée des "écrivains" (modèles IA) disponibles pour la sélection.
/// Modifiez cette map pour ajouter ou changer les modèles dans toute l'application.
final Map<String, Map<String, String>> kWritersMap = {
  'deepseek/deepseek-r1-0528:free': {
    'name': 'Deepseek (Par défaut - Test)',
    'description': 'Rapide, cohérent et excellent pour la narration. (Recommandé)',
  },
  // Exemple si vous vouliez en ajouter un autre :
  // 'mistralai/mistral-7b-instruct:free': {
  //   'name': 'Mistral 7B',
  //   'description': 'Un modèle 7B rapide et populaire, alternative gratuite.',
  // },
};

const String kBaseUrl = kDebugMode
    ? 'http://127.0.0.1:8000'
    : 'https://nihon-quest-backend.onrender.com';