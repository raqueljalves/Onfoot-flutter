import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyService {
  final supabase = Supabase.instance.client;

  /// Enviar novo relatório de segurança
  Future<void> submitReport({
    required double lat,
    required double lon,
    required String type, // dangerous_area, construction, poor_lighting
    String? description,
  }) async {
    await supabase.from("safety_reports").insert({
      "user_id": supabase.auth.currentUser!.id,
      "latitude": lat,
      "longitude": lon,
      "type": type,
      "description": description,
      "created_at": DateTime.now().toIso8601String(),
    });
  }

  /// Buscar todos os relatórios do user atual
  Future<List<Map<String, dynamic>>> getMyReports() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from("safety_reports")
        .select()
        .eq('user_id', userId)
        .order("created_at", ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// ✅ NEW: Buscar reports próximos à localização atual
  /// Usa a função RPC do Supabase para cálculo de distância
  Future<List<SafetyReport>> getNearbyReports({
    required double lat,
    required double lon,
    double radiusKm = 5.0,
  }) async {
    try {
      final response = await supabase.rpc('get_nearby_safety_reports', params: {
        'user_lat': lat,
        'user_lon': lon,
        'radius_km': radiusKm,
      });

      if (response == null) return [];

      final List<dynamic> data = response is List ? response : [response];
      
      return data.map((item) => SafetyReport.fromMap(item)).toList();
    } catch (e) {
      print('🔴 Error fetching nearby reports: $e');
      
      // Fallback: buscar todos e filtrar localmente
      return await _getNearbyReportsFallback(lat, lon, radiusKm);
    }
  }

  /// Fallback se a função RPC não existir
  Future<List<SafetyReport>> _getNearbyReportsFallback(
    double lat, 
    double lon, 
    double radiusKm
  ) async {
    try {
      // Buscar todos os reports ativos
      final res = await supabase
          .from("safety_reports")
          .select()
          .order("created_at", ascending: false)
          .limit(100);

      final List<SafetyReport> reports = [];
      
      for (var item in res) {
        final report = SafetyReport.fromMap(item);
        final distance = _calculateDistance(
          lat, lon, 
          report.latitude, report.longitude
        );
        
        if (distance <= radiusKm) {
          report.distanceKm = distance;
          reports.add(report);
        }
      }
      
      // Ordenar por distância
      reports.sort((a, b) => 
        (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0)
      );
      
      return reports;
    } catch (e) {
      print('🔴 Fallback also failed: $e');
      return [];
    }
  }

  /// Calcular distância entre dois pontos (Haversine)
  double _calculateDistance(
    double lat1, double lon1, 
    double lat2, double lon2
  ) {
    const R = 6371.0; // Raio da Terra em km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return R * c;
  }

  double _toRadians(double degree) => degree * (math.pi / 180);

  /// Apagar um report
  Future<void> deleteReport(String reportId) async {
    await supabase
        .from("safety_reports")
        .delete()
        .eq('id', reportId);
  }

  /// Upvote num report
  Future<void> upvoteReport(String reportId) async {
    await supabase.rpc('increment_upvote', params: {'report_id': reportId});
  }

  /// Downvote num report
  Future<void> downvoteReport(String reportId) async {
    await supabase.rpc('increment_downvote', params: {'report_id': reportId});
  }
}


/// Model para Safety Report
class SafetyReport {
  final String id;
  final String type;
  final double latitude;
  final double longitude;
  final String? description;
  final int upvotes;
  final int downvotes;
  final DateTime createdAt;
  double? distanceKm;

  SafetyReport({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description,
    this.upvotes = 0,
    this.downvotes = 0,
    required this.createdAt,
    this.distanceKm,
  });

  factory SafetyReport.fromMap(Map<String, dynamic> map) {
    return SafetyReport(
      id: map['id'] as String,
      type: map['type'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      description: map['description'] as String?,
      upvotes: map['upvotes'] as int? ?? 0,
      downvotes: map['downvotes'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      distanceKm: map['distance_km'] != null 
          ? (map['distance_km'] as num).toDouble() 
          : null,
    );
  }

  /// Ícone baseado no tipo
  String get icon {
    switch (type) {
      case 'dangerous_area':
        return '🚨';
      case 'construction':
        return '🚧';
      case 'poor_lighting':
        return '💡';
      case 'harassment':
        return '🆘';
      case 'isolated_area':
        return '👥';
      case 'safe_spot':
        return '✅';
      default:
        return '⚠️';
    }
  }

  /// Cor baseada no tipo (ARGB format for Mapbox)
  int get color {
    switch (type) {
      case 'dangerous_area':
        return 0xFFFF0000; // Vermelho
      case 'construction':
        return 0xFFFF9800; // Laranja
      case 'poor_lighting':
        return 0xFFFFEB3B; // Amarelo
      case 'harassment':
        return 0xFF9C27B0; // Roxo
      case 'isolated_area':
        return 0xFF607D8B; // Cinzento azulado
      case 'safe_spot':
        return 0xFF4CAF50; // Verde
      default:
        return 0xFFFF5722; // Laranja escuro
    }
  }

  /// Nome legível do tipo
  String get typeName {
    switch (type) {
      case 'dangerous_area':
        return 'Dangerous Area';
      case 'construction':
        return 'Construction';
      case 'poor_lighting':
        return 'Poor Lighting';
      case 'harassment':
        return 'Harassment / Unsafe';
      case 'isolated_area':
        return 'Isolated Area';
      case 'safe_spot':
        return 'Safe Spot';
      default:
        return 'Warning';
    }
  }
}