import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'providers/event_provider.dart';

// Screens
import 'map_screen.dart';
import 'home_screen.dart';
import 'safety_screen.dart';
import 'profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

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
      routes: {
        '/': (_) => const MapScreen(),     // abre direto no mapa
        '/home': (_) => const HomeScreen(),
        '/map': (_) => const MapScreen(),
        '/safety': (_) => const SafetyScreen(),
        '/profile': (_) => const ProfileScreen(),
      },

      initialRoute: '/',   // sem login
    );
  }
}

