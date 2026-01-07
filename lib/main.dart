import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

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

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit, 
    ),
  );

  // ✅ LISTENER para Auth
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    print('🔔 Global Auth event: ${data.event}');
    if (data.session != null) {
      print('✅ Session captured: ${data.session!.user.email}');
    }
  });

  // ✅ LISTENER para Deep Links
  final appLinks = AppLinks();

  // ✅ Escuta deep links enquanto a app está aberta
  appLinks.uriLinkStream.listen((uri) {
    print('📱 ========== DEEP LINK RECEBIDO! ==========' );
    print('📱 URI completo: $uri');
    print('📱 Scheme: ${uri.scheme}');
    print('📱 Host: ${uri.host}');
    print('📱 Path: ${uri.path}');
    print('📱 Fragment: ${uri.fragment}');
    print('📱 Query params: ${uri.queryParameters}');
    print('📱 =====================================');

    // ✅ PROCESSA O FRAGMENT MANUALMENTE!
    if (uri.fragment.isNotEmpty) {
      print('🔑 Fragment encontrado! A processar tokens...');
    
      // Parse o fragment como se fossem query params
      final fragmentParams = Uri.splitQueryString(uri.fragment);
    
      if (fragmentParams.containsKey('access_token')) {
        print('✅ Access token encontrado no fragment!');
        print('🔄 A processar sessão via Supabase...');
      
        // Reconstrói o URI com os params no lugar certo
        final fixedUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
          queryParameters: fragmentParams,
        );
      
        print('🔧 URI corrigido: $fixedUri');
      
        // FORÇA o Supabase a processar manualmente
        Supabase.instance.client.auth.getSessionFromUrl(fixedUri).then((response) {
          print('✅ Sessão recuperada com sucesso!');
          print('👤 User: ${response.session?.user.email}');
        }).catchError((error) {
          print('❌ Erro ao processar sessão: $error');
        });
      }
    }
  }, onError: (err) {
    print('❌ ERRO no deep link: $err');
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