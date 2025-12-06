import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';

class ProfileController {
  final userService = UserService();
  final uploadService = UploadService();
  final SupabaseClient supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> loadProfile() async {
    return await userService.getProfile();
  }

  Future<void> updateName(String newName) async {
    await userService.updateProfile(name: newName);
  }

  Future<String?> updateAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;

    final file = File(image.path);

    final userId = supabase.auth.currentUser!.id;

    final url = await uploadService.uploadAvatar(file, userId);

    if (url != null) {
      await userService.updateProfile(avatarUrl: url);
    }

    return url;
  }
}
