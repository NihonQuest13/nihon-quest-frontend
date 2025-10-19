// lib/signup_page.dart (CORRIGÉ)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ✅ Import ajouté

// ❌ Suppression de ConsumerStatefulWidget, providers, et ErrorHandler

class SignUpPage extends StatefulWidget { // ✅ Changé en StatefulWidget
  
  // ❌ Suppression de 'onLoginTapped'
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState(); // ✅ Changé en State
}

class _SignUpPageState extends State<SignUpPage> { // ✅ Changé en State
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Fonction _signUp entièrement Corrigée ---
  Future<void> _signUp() async {
    if (!mounted) return;
    
    // Valider le formulaire
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Cacher le clavier
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      // ✅ Utilisation de Supabase directement (comme dans login_page.dart)
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // ✅ Logique de succès DÉPLACÉE ICI
      // S'affiche uniquement si l'inscription réussit
      if (mounted) {
        // ✅ Remplacement de ErrorHandler par ScaffoldMessenger
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Inscription réussie. Votre compte sera validé prochainement."),
            backgroundColor: Colors.green,
          ),
        );
        
        // On redirige vers la page de login après un court délai
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            // ✅ Remplacement de onLoginTapped par Navigator.pop
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(); // Retourne à la page de login
            }
          }
        });
      }

    } on AuthException catch (error) {
      // ✅ Gestion des erreurs Supabase (ex: utilisateur existe déjà)
      if (mounted) {
        // ✅ Remplacement de ErrorHandler par ScaffoldMessenger
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message), // Affiche le message d'erreur réel
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error) {
      // ✅ Gestion des autres erreurs (ex: réseau)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Une erreur inattendue est survenue."),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      // On arrête le chargement dans tous les cas
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  // --- Fin de la fonction corrigée ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ✅ Ajout d'un Scaffold complet (similaire à login_page.dart)
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Bouton retour pour revenir à la page de connexion
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Créer un compte",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: theme.colorScheme.onSurfaceVariant.withAlpha(153)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer un email';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Veuillez entrer un email valide';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant.withAlpha(153)),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer un mot de passe';
                      }
                      if (value.length < 6) {
                        return 'Le mot de passe doit faire au moins 6 caractères';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      minimumSize: const Size(double.infinity, 50),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLoading ? null : _signUp,
                    child: _isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.onPrimary),
                          )
                        : const Text('S\'inscrire'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Déjà un compte ? Se connecter',
                      style: TextStyle(color: theme.colorScheme.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}