// lib/signup_page.dart (CORRIGÉ AVEC signUp data et SANS upsert)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/app_logger.dart'; // Assurez-vous que l'import est correct

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // ... (contrôleurs et variables d'état inchangés) ...
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController(); // Prénom
  final _lastNameController = TextEditingController();  // Nom
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  // --- Fonction _signUp avec data dans signUp ---
  Future<void> _signUp() async {
    if (!mounted) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      // 1. INSCRIPTION AUTH - ⭐ MODIFICATION: Passer les données ici
      final authResponse = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          // Passer first_name et last_name comme métadonnées utilisateur
          data: {
            'first_name': _firstNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            // Vous pouvez ajouter d'autres métadonnées ici si nécessaire
          });

      // Le trigger 'handle_new_user' s'exécute automatiquement ici
      // et (après modification SQL) insérera id, email, first_name, last_name.

      if (authResponse.user == null) {
        // Gérer le cas où l'utilisateur n'est pas retourné (confirmation requise, etc.)
        if (mounted) {
           // Si la confirmation est activée, signUp réussit mais user peut être null
           // Vérifiez les paramètres de votre projet Supabase Auth
           final requiresConfirmation = authResponse.session == null;
           if (requiresConfirmation) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Inscription réussie ! Veuillez vérifier votre email pour confirmer votre compte."),
                  backgroundColor: Colors.orangeAccent, // Couleur différente pour confirmation
                ),
              );
              // Rediriger vers login quand même, l'utilisateur doit confirmer
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                }
              });
              // Ne pas lancer d'erreur ici si la confirmation est juste requise
              return; // Sortir de la fonction
           } else {
             // Si pas de confirmation requise et user est null, c'est une vraie erreur
             throw const AuthException("Erreur inattendue : utilisateur non retourné après inscription.");
           }
        }
      }
      // final userId = authResponse.user!.id; // On n'a plus besoin de l'ID ici

      // 2. ⭐ SUPPRESSION de l'appel .upsert() ou .update()
      // L'insertion/mise à jour est entièrement gérée par le trigger maintenant.

      // 3. SUCCÈS (Si confirmation non requise ou déjà faite)
      if (mounted && authResponse.user != null) { // Vérifier que user n'est pas null
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Inscription réussie ! Votre compte sera validé prochainement par un administrateur."),
            backgroundColor: Colors.green,
          ),
        );

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }

    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur d'authentification: ${error.message}"),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } on PostgrestException catch (error) {
      // Normalement, on ne devrait plus avoir d'erreur Postgrest ici
      if (mounted) {
        AppLogger.error("Erreur Postgrest inattendue lors de l'inscription (trigger?)", error: error, tag: "SignUpPage");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Erreur base de données lors de l'inscription."),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (mounted) {
        AppLogger.error("Erreur inattendue lors de l'inscription", error: error, stackTrace: stackTrace, tag: "SignUpPage");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Une erreur inattendue est survenue."),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  // --- Fin de la fonction corrigée ---

  // ... (build method inchangé) ...
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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

                  // Champ Prénom (first_name)
                  TextFormField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'Prénom',
                      prefixIcon: Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant.withAlpha(153)),
                    ),
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words, // Première lettre en majuscule
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer votre prénom';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 20),

                  // Champ Nom (last_name)
                  TextFormField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant.withAlpha(153)),
                    ),
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Veuillez entrer votre nom';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 20),

                  // Champ Email
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
                      // Regex simple pour format email
                      if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) {
                         return 'Veuillez entrer un email valide';
                      }
                      return null;
                    },
                    enabled: !_isLoading,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 20),

                  // Champ Mot de passe
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