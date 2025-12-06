import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final supabase = Supabase.instance.client;

  // Buscar perfil do utilizador atual
  Future<Map<String, dynamic>?> getProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final res = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    return res;
  }

  // Atualizar nome ou avatar
  Future<void> updateProfile({
    String? name,
    String? avatarUrl,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('profiles').update({
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    }).eq('id', user.id);
  }

  // Atualizar score (por exemplo, após viagem)
  Future<void> updateTravelStats({
    int? cities,
    int? countries,
    int? score,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('profiles').update({
      if (cities != null) 'cities': cities,
      if (countries != null) 'countries': countries,
      if (score != null) 'score': score,
    }).eq('id', user.id);
  }
}
