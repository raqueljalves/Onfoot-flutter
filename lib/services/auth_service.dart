import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Get current user
  User? get currentUser => _supabase.auth.currentUser;
  
  // Check if signed in
  bool get isSignedIn => currentUser != null;
  
  // Sign in with Google
  Future<AuthResponse?> signInWithGoogle() async {
    try {
      // Web client ID for Android (from Google Cloud Console)
      const webClientId = '622737814142-fbh7ninou8nm76m7ks6e2cq0rul8ct7v.apps.googleusercontent.com';
      
      // iOS client ID
      const iosClientId = 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: iosClientId,
        serverClientId: webClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw 'No Access Token or ID Token found.';
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Create profile if first time
      await _createProfileIfNeeded(response.user!);

      return response;
    } catch (e) {
      print('🔴 Google Sign In Error: $e');
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
    await GoogleSignIn().signOut();
  }
  
  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}