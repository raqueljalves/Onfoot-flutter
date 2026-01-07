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
      
      if (response == null) return null;
      
      // ✅ FIX: Handle both List and Map responses
      // Supabase RPC can return either a single object or an array
      if (response is List) {
        // If it's a list, get the first element
        if (response.isEmpty) return null;
        final firstItem = response.first;
        if (firstItem is Map<String, dynamic>) {
          return firstItem;
        }
        // Convert to Map if needed
        return Map<String, dynamic>.from(firstItem as Map);
      } else if (response is Map) {
        // If it's already a map, convert it properly
        return Map<String, dynamic>.from(response);
      }
      
      print('⚠️ Unexpected response type: ${response.runtimeType}');
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