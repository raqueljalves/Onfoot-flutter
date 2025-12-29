import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        profile = response;
        isLoading = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar perfil: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      
      if (!mounted) return;
      
      Navigator.of(context).pushReplacementNamed('/auth');
    } catch (e) {
      print('❌ Erro ao fazer logout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao fazer logout')),
      );
    }
  }

  Widget _stat(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF9CAF88),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/home');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Perfil'),
          backgroundColor: const Color(0xFF9CAF88),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/home');
            },
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    
                    // Avatar
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: profile?["avatar_url"] != null
                          ? NetworkImage(profile!["avatar_url"])
                          : null,
                      child: profile?["avatar_url"] == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Nome
                    Text(
                      profile?["name"] ?? "Sem nome",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Email
                    Text(
                      user?.email ?? "",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Estatísticas
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _stat("Cidades", profile?["cities"] ?? 0),
                        _stat("Países", profile?["countries"] ?? 0),
                        _stat("Score", profile?["score"] ?? 0),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    const Divider(),
                    
                    // Opções
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Terminar sessão'),
                      onTap: _handleSignOut,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}