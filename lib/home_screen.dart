import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'profile_screen.dart'; 
import 'safety_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FCE8), // topo
              Color(0xFFDCE8D2), // fundo
            ],
          ),
        ),
        width: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // LOGO (Pegada)
              Image.asset(
                "assets/footprint.png",
                width: 70,
                height: 70,
              ),

              const SizedBox(height: 10),

              // NOME DA APP
              const Text(
                "OnFoot",
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F2F2F),
                ),
              ),

              const SizedBox(height: 8),

              // SLOGAN
              const Text(
                "Your safety companion app",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 50),

              // BOTÃO MAP
              _MenuButton(
                color: Color(0xFF77A96C),
                icon: Icons.map_outlined,
                title: "Map",
                subtitle: "Navigate safely",
                onTap: () {
                  Navigator.pushNamed(context, '/map');
                },
              ),

              const SizedBox(height: 25),

              // BOTÃO SAFETY
              _MenuButton(
                color: Color(0xFFE2725B),
                icon: Icons.shield_outlined,
                title: "Safety",
                subtitle: "Emergency features",
                onTap: () {
                  Navigator.pushNamed(context, '/safety');
                },
              ),

              const SizedBox(height: 25),

              // BOTÃO PROFILE
              _MenuButton(
                color: Color(0xFF6D747D),
                icon: Icons.person_outline,
                title: "Profile",
                subtitle: "Your settings",
                onTap: () {
                  Navigator.pushNamed(context, '/profile');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuButton({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
