import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileController controller = ProfileController();
  Map<String, dynamic>? profile;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await controller.loadProfile();
      setState(() {
        profile = data;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      debugPrint("Erro ao carregar perfil: $e");
    }
  }

  /// Editar Nome
  void _editName() {
    final textController =
        TextEditingController(text: profile?["name"] ?? "");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Editar Nome"),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Escreve o teu nome",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isEmpty) return;

              await controller.updateName(newName);
              if (mounted) Navigator.pop(context);
              _load();
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  /// Alterar Avatar
  Future<void> _changeAvatar() async {
    final url = await controller.updateAvatar();
    if (url != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return const Scaffold(
        body: Center(
          child: Text("Não foi possível carregar o perfil."),
        ),
      );
    }

    final user = Supabase.instance.client.auth.currentUser!;
    final avatar = profile!["avatar_url"];
    final name = profile!["name"] ?? "Sem nome";
    final cities = profile!["cities"] ?? 0;
    final countries = profile!["countries"] ?? 0;
    final score = profile!["score"] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Perfil"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _changeAvatar,
              child: CircleAvatar(
                radius: 60,
                backgroundImage: avatar != null
                    ? NetworkImage(avatar)
                    : const AssetImage("assets/profile/default_avatar.png")
                        as ImageProvider,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 4),

            Text(
              user.email ?? "",
              style: const TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 32),

            // Estatísticas
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat("Cidades", cities),
                _stat("Países", countries),
                _stat("Score", score),
              ],
            ),

            const SizedBox(height: 40),

            // Editar Nome
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.green),
              title: const Text("Editar Nome"),
              onTap: _editName,
            ),

            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Terminar Sessão"),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, "/login");
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String title, int value) {
    return Column(
      children: [
        Text(
          "$value",
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(title),
      ],
    );
  }
}
