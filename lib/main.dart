// lib/main.dart (MODIFIÉ ET CORRIGÉ)
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_page.dart';
import 'login_page.dart';
import 'providers.dart';
import 'services/vocabulary_service.dart';
import 'utils/app_theme.dart';
import 'widgets/splash_screen.dart';

import 'auth_guard.dart'; // Import du nouveau garde

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // --- INITIALISATION DE SUPABASE ---
  await Supabase.initialize(
    url: 'https://kiokpxrwljcrpmkartys.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtpb2tweHJ3bGpjcnBta2FydHlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA3MDc3NzYsImV4cCI6MjA3NjI4Mzc3Nn0.QjEyNWhx5p104vNYMOBwImW_Q9MRJK6rCHFr6-UD9l0',
  );
  // --- FIN DE L'INITIALISATION ---

  await initializeDateFormatting('fr_FR', null);
  await themeService.loadTheme();

  final prefs = await SharedPreferences.getInstance();
  final vocabularyService = VocabularyService(prefs: prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MyApp(
        vocabularyService: vocabularyService,
      ),
    ),
  );
}

class MyApp extends ConsumerWidget {
  final VocabularyService vocabularyService;

  const MyApp({
    super.key,
    required this.vocabularyService,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeServiceProvider);

    return MaterialApp(
      title: 'Nihon Quest',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AuthGuard(), 
      debugShowCheckedModeBanner: false,
    );
  }
}

// ⛔️ LE PROVIDER EST SUPPRIMÉ D'ICI
// final vocabularyServiceProvider = Provider<VocabularyService>((ref) {
//   final prefs = ref.watch(sharedPreferencesProvider);
//   return VocabularyService(prefs: prefs);
// });