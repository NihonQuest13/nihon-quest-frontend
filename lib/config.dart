// lib/config.dart

import 'package:flutter/foundation.dart';

/// L'ID du modèle d'IA par défaut utilisé pour la génération de chapitres.
const String kDefaultModelId = 'deepseek/deepseek-chat-v3-0324:free';

/// La liste centralisée des "écrivains" (modèles IA) disponibles pour la sélection.
/// Modifiez cette map pour ajouter ou changer les modèles dans toute l'application.
final Map<String, Map<String, String>> kWritersMap = {
  'meituan/longcat-flash-chat:free': {
    'name': 'Longcat (Phase de test)',
    'description': 'Toujours en phase de test, peut produire des résultats incohérents.',
  },
  'z-ai/glm-4.5-air:free': {
    'name': 'Z-ai (Phase de test)',
    'description': 'Toujours en phase de test, peut produire des résultats incohérents.',
  },
  'qwen/qwen3-235b-a22b:free': {
    'name': 'Qwen 3.5B (Phase de test)',
    'description': 'Toujours en phase de test, peut produire des résultats incohérents.',
  },
};

const String kBaseUrl = kDebugMode
    ? 'http://127.0.0.1:8000'
    // ✅ URL DE PRODUCTION CORRIGÉE
    : 'https://nihon-quest-api.onrender.com';