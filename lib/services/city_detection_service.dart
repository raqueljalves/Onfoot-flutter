import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CityDetectionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // ✅ Carregar cidade confirmada do cache local
  Future<String?> getConfirmedCityId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('confirmed_city_id');
  }
  
  // ✅ Guardar cidade confirmada localmente
  Future<void> _saveConfirmedCityLocally(String cityId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('confirmed_city_id', cityId);
    print('💾 City ID saved locally: $cityId');
  }
  
  Future<Map<String, dynamic>?> detectCity(double lat, double lon) async {
    try {
      final response = await _supabase.rpc('find_nearest_city', params: {
        'user_lat': lat,
        'user_lon': lon,
        'max_distance_km': 50,
      });
      
      if (response == null) return null;
      
      // Handle both List and Map responses
      if (response is List) {
        if (response.isEmpty) return null;
        final firstItem = response.first;
        if (firstItem is Map<String, dynamic>) {
          return firstItem;
        }
        return Map<String, dynamic>.from(firstItem as Map);
      } else if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      
      print('⚠️ Unexpected response type: ${response.runtimeType}');
      return null;
    } catch (e) {
      print('🔴 City detection error: $e');
      return null;
    }
  }
  
  // ✅ Verificar se já confirmou esta cidade
  Future<bool> hasConfirmedCity(String cityId) async {
    final confirmedId = await getConfirmedCityId();
    return confirmedId == cityId;
  }
  
  Future<void> saveUserCity(String cityId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      // ✅ SEMPRE guardar localmente primeiro
      await _saveConfirmedCityLocally(cityId);
      
      if (userId == null) {
        print('⚠️ No user logged in, saved only locally');
        return;
      }
      
      // Guardar no Supabase
      await _supabase.from('user_cities').upsert({
        'user_id': userId,
        'city_id': cityId,
        'last_visit': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,city_id');
      
      print('✅ City saved to Supabase and locally');
    } catch (e) {
      print('⚠️ Error saving city to Supabase: $e (but saved locally)');
    }
  }
  
  // ✅ Limpar cidade confirmada (útil para testes)
  Future<void> clearConfirmedCity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('confirmed_city_id');
    print('🗑️ Confirmed city cleared');
  }
}