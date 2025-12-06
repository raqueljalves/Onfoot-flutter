import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyService {
  final supabase = Supabase.instance.client;

  /// Enviar novo relatório de segurança
  Future<void> submitReport({
    required double lat,
    required double lon,
    required String level, // baixo, medio, alto
    required String description,
  }) async {
    await supabase.from("safety_reports").insert({
      "user_id": supabase.auth.currentUser!.id,
      "lat": lat,
      "lon": lon,
      "level": level,
      "description": description,
      "created_at": DateTime.now().toIso8601String(),
    });
  }

  /// Buscar todos os relatórios para gerar heatmap
  Future<List<Map<String, dynamic>>> getReports() async {
    final res = await supabase
        .from("safety_reports")
        .select()
        .order("created_at", ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }
}
