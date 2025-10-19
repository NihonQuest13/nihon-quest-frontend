// lib/auth_guard.dart (CORRIGÉ)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_page.dart'; 
import 'login_page.dart';
import 'providers.dart'; 
import 'widgets/splash_screen.dart'; 

class AuthGuard extends ConsumerStatefulWidget {
  const AuthGuard({super.key});

  @override
  ConsumerState<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends ConsumerState<AuthGuard> {
  bool _isLoading = true;
  bool _isApproved = false;
  StreamSubscription<AuthState>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    _checkAuth();
    
    // Écoute les changements d'état (login, logout)
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _checkUserStatus();
      } else {
        // Déconnexion détectée
        if (mounted) {
          setState(() {
            _isApproved = false;
            _isLoading = false;
          });
        }
      }
    });
  }
  
  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    final session = Supabase.instance.client.auth.currentSession;
    
    if (session != null) {
      await _checkUserStatus();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isApproved = false;
        });
      }
    }
  }

  Future<void> _checkUserStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() { _isApproved = false; _isLoading = false; });
        return;
      }

      // 1. Lire le statut du profil
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select('status')
          .eq('id', user.id)
          .maybeSingle();

      String? status = profileData?['status'];

      // 2. Logique de décision
      if (status == 'approved') {
        if (mounted) setState(() { _isApproved = true; _isLoading = false; });
      } else {
        // Statut non 'approved', déconnexion immédiate
        await Supabase.instance.client.auth.signOut();
        
        if (mounted) {
          String message;
          if (profileData == null) {
            message = 'Profil introuvable. Veuillez vous réinscrire.';
          } else if (status == 'pending') {
            message = 'Votre compte est en attente d\'approbation.';
          } else {
            message = 'Votre demande d\'inscription a été refusée.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: status == 'pending' ? Colors.orange : Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          
          setState(() {
            _isApproved = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de la vérification du statut: $e');
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        setState(() { _isApproved = false; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashScreen();
    }

    if (_isApproved) {
      // ⛔️ On n'a plus besoin de lire les services ici
      // final vocabularyService = ref.watch(vocabularyServiceProvider);
      
      // ✅ On appelle le constructeur const de HomePage (sans paramètres)
      return const HomePage(); 
    } else {
      // Utilisateur non connecté
      return const LoginPage();
    }
  }
}