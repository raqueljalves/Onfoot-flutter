import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class EmergencyInfo {
  final String country;
  final String number;

  const EmergencyInfo({required this.country, required this.number});
}

class EmergencyService {
  static const String _mapboxToken =
      "pk.eyJ1IjoicmFxdWVsamFsdmVzIiwiYSI6ImNtc2l0bGVjYzBkb3kyeXNmcmQ0cTJocm0ifQ.Atv3-ZZv3H3-vyiYJC2JXw";

  static const String defaultNumber = '112';

  // Country name as returned by Mapbox's country-level reverse geocoding -> emergency number.
  static const Map<String, String> _emergencyNumbers = {
    // Europe (EU + UK, Switzerland, Norway) - 112 works across the EU
    'Austria': '112', 'Belgium': '112', 'Bulgaria': '112', 'Croatia': '112',
    'Cyprus': '112', 'Czechia': '112', 'Czech Republic': '112', 'Denmark': '112',
    'Estonia': '112', 'Finland': '112', 'France': '112', 'Germany': '112',
    'Greece': '112', 'Hungary': '112', 'Ireland': '112', 'Italy': '112',
    'Latvia': '112', 'Lithuania': '112', 'Luxembourg': '112', 'Malta': '112',
    'Netherlands': '112', 'Poland': '112', 'Portugal': '112', 'Romania': '112',
    'Slovakia': '112', 'Slovenia': '112', 'Spain': '112', 'Sweden': '112',
    'United Kingdom': '112', 'Switzerland': '112', 'Norway': '112',
    // North America
    'United States': '911', 'United States of America': '911',
    'Canada': '911', 'Mexico': '911',
    // Oceania
    'Australia': '000', 'New Zealand': '111',
    // Asia
    'Japan': '110', 'China': '110', 'South Korea': '112', 'India': '112',
    // South America
    'Brazil': '190',
  };

  String? _cachedCountry;
  String? _cachedNumber;
  double? _cachedLat;
  double? _cachedLng;

  /// Detects the country at (lat, lng) via Mapbox reverse geocoding and
  /// returns its emergency number. Caches the result and skips the API call
  /// if called again close (~10km) to the last checked position.
  Future<EmergencyInfo> getEmergencyNumber(double lat, double lng) async {
    if (_cachedCountry != null &&
        _cachedNumber != null &&
        _cachedLat != null &&
        _cachedLng != null &&
        _distanceKm(_cachedLat!, _cachedLng!, lat, lng) < 10) {
      return EmergencyInfo(country: _cachedCountry!, number: _cachedNumber!);
    }

    try {
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?types=country&access_token=$_mapboxToken',
      );

      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final country = features.first['text'] as String? ?? '';
          final number = _emergencyNumbers[country] ?? defaultNumber;

          _cachedCountry = country;
          _cachedNumber = number;
          _cachedLat = lat;
          _cachedLng = lng;

          return EmergencyInfo(country: country, number: number);
        }
      }
    } catch (e) {
      print('🔴 Emergency country lookup failed: $e');
    }

    // Reverse geocoding failed - fall back to whatever we had cached before,
    // or the universal default so SOS never has no number to call.
    return EmergencyInfo(
      country: _cachedCountry ?? '',
      number: _cachedNumber ?? defaultNumber,
    );
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
}
