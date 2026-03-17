import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/emoji_selector_screen.dart';  // ✅ ADICIONAR IMPORT

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;
  String userEmoji = '🚶‍♀️';  // ✅ ADICIONAR VARIÁVEL

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
        userEmoji = response['selected_emoji'] ?? '🚶‍♀️';  // ✅ CARREGAR EMOJI
        isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading profile: $e');
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
        const SnackBar(content: Text('Error logging out. Please try again.')),
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
          title: const Text('Profile'),
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
                      profile?["name"] ?? "No Name",
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
                        _stat("Cities", profile?["cities"] ?? 0),
                        _stat("Countries", profile?["countries"] ?? 0),
                        _stat("Score", profile?["score"] ?? 0),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    const Divider(),
                    
                    // ✅ EMOJI SELECTOR (CORRIGIDO!)
                    ListTile(
                      leading: const Icon(Icons.emoji_emotions, color: Color(0xFF9CAF88)),
                      title: const Text('Choose Walking Emoji'),
                      trailing: Text(userEmoji, style: const TextStyle(fontSize: 32)),
                      onTap: () async {
                        final selected = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(builder: (_) => EmojiSelectorScreen()),
                        );
                        
                        if (selected != null) {
                          try {
                            // Salvar no Supabase
                            await Supabase.instance.client
                              .from('profiles')
                              .update({'selected_emoji': selected})
                              .eq('id', Supabase.instance.client.auth.currentUser!.id);
                            
                            setState(() => userEmoji = selected);
                            
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Emoji changed to $selected'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            print('Error saving emoji: $e');
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error saving emoji'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    
                    const Divider(),
                    
                    // ✅ LOGOUT (CORRIGIDO - SEPARADO!)
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Logout'),
                      onTap: _handleSignOut,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}