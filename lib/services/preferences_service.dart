import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static SharedPreferences? _prefs;
  
  // Inicializar (chamar no main.dart)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // ========== ÚLTIMA LOCALIZAÇÃO ==========
  static Future<void> saveLastLocation(double lat, double lng) async {
    await _prefs!.setDouble('last_lat', lat);
    await _prefs!.setDouble('last_lng', lng);
    print('💾 Localização guardada: $lat, $lng');
  }
  
  static Map<String, double>? getLastLocation() {
    final lat = _prefs!.getDouble('last_lat');
    final lng = _prefs!.getDouble('last_lng');
    
    if (lat == null || lng == null) {
      print('📍 Sem localização guardada');
      return null;
    }
    
    print('📍 Localização carregada: $lat, $lng');
    return {'lat': lat, 'lng': lng};
  }
  
  // ========== PESQUISAS RECENTES ==========
  static Future<void> addRecentSearch(String query) async {
    List<String> recent = _prefs!.getStringList('recent_searches') ?? [];
    
    // Remove duplicados
    recent.remove(query);
    
    // Adiciona no topo
    recent.insert(0, query);
    
    // Mantém só últimas 5
    if (recent.length > 5) {
      recent = recent.sublist(0, 5);
    }
    
    await _prefs!.setStringList('recent_searches', recent);
    print('🔍 Pesquisa guardada: $query');
  }
  
  static List<String> getRecentSearches() {
    return _prefs!.getStringList('recent_searches') ?? [];
  }
  
  static Future<void> clearRecentSearches() async {
    await _prefs!.remove('recent_searches');
  }
  
  // ========== ESTILO DO MAPA ==========
  static Future<void> setMapStyle(String style) async {
    await _prefs!.setString('map_style', style);
    print('🗺️ Map style guardado: $style');
  }
  
  static String getMapStyle() {
    return _prefs!.getString('map_style') ?? 'satellite';
  }
  
  // ========== TUTORIAL ==========
  static Future<void> setTutorialCompleted() async {
    await _prefs!.setBool('tutorial_completed', true);
  }
  
  static bool shouldShowTutorial() {
    return !(_prefs!.getBool('tutorial_completed') ?? false);
  }
}