import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'dart:async';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  Timer? _authTimeout;

  @override
  void initState() {
    super.initState();
    
    // 👂 Ouvir quando o utilizador volta do Google
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      
      print('🔔 Auth event: $event');
      
      if (event == AuthChangeEvent.signedIn && session != null) {
        print('✅ Login bem-sucedido: ${session.user.email}');
        
        // Para o loading
        if (mounted) {
          setState(() => _isLoading = false);
        }

        // Navegar para o mapa
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/map');
        }
      } else if (event == AuthChangeEvent.signedOut) {
        print('❌ Utilizador deslogado');
        // Para o loading se houver erro
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);


    // Timeout de 10 segundos
    _authTimeout = Timer(Duration(seconds: 10), () {
      if (_isLoading) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login timeout - tenta novamente')),
       );
      }
    });

    try {
      print('🟡 A iniciar login com Google...');

      await _authService.signInWithGoogle();

      print('✅ Janela de login aberta');

      // NÃO navegamos aqui! O listener faz isso quando o login terminar

    } catch (e) {
      print('❌ Login failed: $e');


      if (!mounted) return;

      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
   
      setState(() => _isLoading = false);
      
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF9CAF88), // ✅ COR CORRETA
              Color(0xFF7A9070),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo - Pegada
                  Image.asset(
                    'assets/footprint.png', // ✅ USA TUA PEGADA
                    width: 100,
                    height: 100,
                    color: Colors.white,
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Title
                  const Text(
                    'OnFoot',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Walk Safe, Walk Smart',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Welcome message
                  const Text(
                    'Welcome!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sign in to start your safe walking journey',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Google Sign In Button
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : ElevatedButton.icon(
                          onPressed: _handleGoogleSignIn,
                          icon: const Icon(Icons.login, color: Color(0xFF9CAF88)), 
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9CAF88),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF9CAF88),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 5,
                          ),
                        ),
                  const SizedBox(height: 60),

                  // Features
                  _buildFeature(
                    Icons.navigation,
                    'Smart pedestrian navigation',
                  ),
                  const SizedBox(height: 16),
                  _buildFeature(
                    Icons.security,
                    'Real-time safety alerts',
                  ),
                  const SizedBox(height: 16),
                  _buildFeature(
                    Icons.people,
                    'Community-powered routes',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}