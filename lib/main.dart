import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'providers/event_provider.dart';
import 'services/preferences_service.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'map_screen.dart';
import 'home_screen.dart';
import 'safety_screen.dart';
import 'profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

   // ✅ ADICIONA ISTO - Inicializar shared preferences
  await PreferencesService.init();
  print('✅ Preferences inicializadas');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  // ✅ LISTENER para Auth
  // Nota: o supabase_flutter já trata os deep links do OAuth internamente
  // (via SupabaseAuth), incluindo o link inicial em cold start. Não é
  // preciso (nem seguro) processar o URI manualmente aqui — isso causava
  // processamento duplicado do mesmo token e mascarava erros reais de login.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    print('🔔 Global Auth event: ${data.event}');
    if (data.session != null) {
      print('✅ Session captured: ${data.session!.user.email}');
    }
  }, onError: (error) {
    print('❌ Global Auth error: $error');
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EventProvider()),
      ],
      child: const OnFootApp(),
    ),
  );
}

class OnFootApp extends StatelessWidget {
  const OnFootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "OnFoot",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF9CAF88), // ✅ COR CORRETA
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9CAF88),
          primary: const Color(0xFF9CAF88),
          secondary: const Color(0xFF7A9070), 
        ),
      ),
      routes: {
        '/': (_) => const SplashScreen(),      // ✅ Verifica login primeiro
        '/auth': (_) => const AuthScreen(),    // ✅ Tela de login/signup
        '/home': (_) => const HomeScreen(),
        '/map': (_) => const MapScreen(),
        '/safety': (_) => const SafetyScreen(),
        '/profile': (_) => const ProfileScreen(),
      },
      initialRoute: '/',
    );
  }
}