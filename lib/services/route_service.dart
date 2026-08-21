import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

class RouteService {
  static final SupabaseClient supabase = Supabase.instance.client;

  /// Salva rota no Supabase. Devolve o id da linha criada (uuid ou int,
  /// conforme o schema), ou null se o utilizador não estiver autenticado.
  Future<dynamic> saveRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required double distanceKm,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await supabase.from("routes").insert({
      "user_id": userId,
      "from_lat": fromLat,
      "from_lon": fromLon,
      "to_lat": toLat,
      "to_lon": toLon,
      "distance_km": distanceKm,
      "created_at": DateTime.now().toIso8601String(),
    }).select().single();

    return row['id'];
  }

  /// Atualiza o resultado de uma viagem (chegou bem / parou / problema).
  /// Falha silenciosamente se a coluna ainda não existir no Supabase.
  Future<void> updateRouteStatus(dynamic routeId, String status, String? note) async {
    try {
      await supabase.from('routes').update({
        'status': status,
        'feedback_note': note,
      }).eq('id', routeId);
    } catch (e) {
      print('⚠️ Could not update route status: $e');
    }
  }

  /// Calcula distância entre dois pontos (Haversine)
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // raio da terra em KM
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // distancia em km
  }

  double _degToRad(double degree) {
    return degree * (pi / 180.0);
  }
}

