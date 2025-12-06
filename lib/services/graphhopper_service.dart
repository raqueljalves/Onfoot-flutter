import 'dart:convert';
import 'package:http/http.dart' as http;

class GraphHopperService {
  static const String _apiKey = "800477a2-ef2c-46e0-a1ee-02b4d09536a8";

  // Função para obter rota a pé
  static Future<Map<String, dynamic>?> getWalkingRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final url =
        "https://graphhopper.com/api/1/route?"
        "point=$startLat,$startLng&point=$endLat,$endLng"
        "&vehicle=foot"
        "&locale=en"
        "&points_encoded=false"
        "&key=$_apiKey";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data["paths"] != null && data["paths"].isNotEmpty) {
        return data["paths"][0];
      }
    }

    return null;
  }
}
