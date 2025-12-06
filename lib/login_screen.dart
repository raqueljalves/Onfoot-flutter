import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool loading = false;

  // ===============================
  // LOGIN GOOGLE
  // ===============================
  Future<void> _loginGoogle() async {
    setState(() => loading = true);

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: "io.supabase.onfoot://login-callback/",
      );
      // AuthGate detecta login automaticamente
    } catch (e) {
      _showError("Erro ao entrar com Google.");
    }

    setState(() => loading = false);
  }

  // ===============================
  // LOGIN APPLE (somente iPhone)
  // ===============================
  Future<void> _loginApple() async {
    setState(() => loading = true);

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: "io.supabase.onfoot://login-callback/",
      );
    } catch (e) {
      _showError("Erro ao entrar com Apple.");
    }

    setState(() => loading = false);
    if (Theme.of(context).platform == TargetPlatform.iOS) 

  }

  // ===============================
  // HELPERS
  // ===============================
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8D6A3),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset("assets/icon/icon.png", height: 120),

              const SizedBox(height: 32),

              const Text(
                "Welcome to OnFoot",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 40),

              // ==========================================
              // BOTÃO GOOGLE
              // ==========================================
              ElevatedButton.icon(
                onPressed: loading ? null : _loginGoogle,
                icon: Image.asset("assets/google.png", height: 24),
                label: const Text(
                  "Entrar com Google",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),

              const SizedBox(height: 16),

              // ==========================================
              // BOTÃO APPLE
              // ==========================================
              ElevatedButton.icon(
                onPressed: loading ? null : _loginApple,
                icon: const Icon(Icons.apple),
                label: const Text(
                  "Entrar com Apple",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),

              const SizedBox(height: 32),

              if (loading) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
