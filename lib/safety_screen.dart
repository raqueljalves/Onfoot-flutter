import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> reports = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadReports();
  }

  Future<void> loadReports() async {
    try {
      final res =
          await supabase.from("safety_reports").select().order("created_at");

      setState(() {
        reports = List<Map<String, dynamic>>.from(res);
        loading = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar reports: $e");
      setState(() => loading = false);
    }
  }

  Future<void> createReport() async {
    final descController = TextEditingController();
    int selectedLevel = 3;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reportar Problema de Segurança"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Nível de risco:"),
            Slider(
              value: selectedLevel.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: "$selectedLevel",
              onChanged: (value) {
                setState(() => selectedLevel = value.toInt());
              },
            ),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "Descreva o problema...",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitReport(
                description: descController.text.trim(),
                riskLevel: selectedLevel,
              );
            },
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReport({
    required String description,
    required int riskLevel,
  }) async {
    try {
      // Pedir localização
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final uid = supabase.auth.currentUser!.id;

      await supabase.from("safety_reports").insert({
        "user_id": uid,
        "lat": pos.latitude,
        "lon": pos.longitude,
        "risk_level": riskLevel,
        "description": description,
        "created_at": DateTime.now().toIso8601String(),
      });

      loadReports();
    } catch (e) {
      debugPrint("Erro ao enviar report: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Relatórios de Segurança"),
        backgroundColor: Colors.red.shade700,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red.shade700,
        onPressed: createReport,
        child: const Icon(Icons.warning_amber_rounded, size: 32),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : reports.isEmpty
              ? const Center(
                  child: Text("Nenhum alerta ainda."),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: reports.length,
                  itemBuilder: (_, i) {
                    final r = reports[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _riskColor(r["risk_level"]),
                          child: Text(
                            r["risk_level"].toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(r["description"] ?? "(Sem descrição)"),
                        subtitle: Text(
                          "Lat: ${r["lat"]}, Lon: ${r["lon"]}\n${r["created_at"] ?? ""}",
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Color _riskColor(int level) {
    switch (level) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      default:
        return Colors.red;
    }
  }
}
