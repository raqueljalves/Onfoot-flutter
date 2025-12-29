import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Get current user
  User? get currentUser => _supabase.auth.currentUser;
  
  // Check if signed in
  bool get isSignedIn => currentUser != null;
  
  // Sign in with Google (usando Supabase OAuth nativo)
  Future<bool> signInWithGoogle() async {
    try {
      print('🟡 Starting Google Sign-In via Supabase...');
      print('📱 Using redirect: io.supabase.onfootapp://login');

      final response = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google, 
        redirectTo: 'io.supabase.onfootapp://login',  //✅ FORÇA este URL!
      );
      
      print('✅ Google Sign-In initiated: $response');
      return response;

    } catch (e) {
      print('❌ Error during sign-in: $e');
      rethrow;
    }
  }

  // Create profile on first sign in
  Future<void> _createProfileIfNeeded(User user) async {
    try {
      final existing = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existing == null) {
        await _supabase.from('profiles').insert({
          'id': user.id,
          'username': user.email?.split('@')[0] ?? 'user',
          'avatar_url': user.userMetadata?['avatar_url'],
          'total_reports': 0,
        });
        print('✅ Profile created for ${user.email}');
      }
    } catch (e) {
      print('⚠️ Profile creation error: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
  
  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}