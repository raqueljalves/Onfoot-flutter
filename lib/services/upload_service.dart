import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class UploadService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<String?> uploadAvatar(File file, String userId) async {
    final path = "avatars/$userId-${DateTime.now().millisecondsSinceEpoch}.jpg";

    // Faz upload
    await supabase.storage.from("avatars").upload(path, file);

    // Gera URL pública
    final url = supabase.storage.from("avatars").getPublicUrl(path);

    return url;
  }
}
