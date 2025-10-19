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
  'alibaba/tongyi-deepresearch-30b-a3b:free': {
    'name': 'Alibaba (Par défaut - Test)',
    'description': 'Rapide, cohérent et excellent pour la narration. (Recommandé)',
  },
};

const String kBaseUrl = kDebugMode
    ? 'http://127.0.0.1:8000'
    // ✅ URL DE PRODUCTION CORRIGÉE
    : 'https://nihon-quest-api.onrender.com';