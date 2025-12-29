import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart' as Geo;

class CityDetectionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _currentCityId;
  
  Future<Map<String, dynamic>?> detectCity(double lat, double lon) async {
    try {
      final response = await _supabase.rpc('find_nearest_city', params: {
        'user_lat': lat,
        'user_lon': lon,
        'max_distance_km': 50,
      });
      
      if (response != null) {
        return response as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('🔴 City detection error: $e');
      return null;
    }
  }
  
  Future<void> saveUserCity(String cityId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      await _supabase.from('user_cities').upsert({
        'user_id': userId,
        'city_id': cityId,
        'last_visit': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,city_id');
      
      print('✅ City saved to user profile');
    } catch (e) {
      print('⚠️ Error saving city: $e');
    }
  }
}