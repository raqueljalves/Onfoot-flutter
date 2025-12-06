import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as Geo;
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/route_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Services
  final RouteService _routeService = RouteService();
  final SupabaseClient supabase = Supabase.instance.client;

  // Mapbox token
  static const String _token =
      "pk.eyJ1IjoicmFxdWVsamFsdmVzIiwiYSI6ImNtZ3YyN292YTBhbDMybHNiaGR6bHk2anUifQ.Qn0OuPaYXPC3cX3mgsUBeA";

  // Map & location
  MapboxMap? _map;
  Geo.Position? _pos;

  // Annotations
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _userManager;
  PointAnnotation? _userMarker;
  PointAnnotationManager? _stepsManager;

  // Icons
  Uint8List? _footprint;
  Uint8List? _footLeft;
  Uint8List? _footRight;

  // Search
  final TextEditingController _search = TextEditingController();
  final List<_Suggestion> _suggestions = [];

  // Route data
  List<Position>? _lastRoutePoints;

  // Navigation mode
  bool _navigating = false;
  double _remainingKm = 0.0;
  double _remainingMin = 0.0;

  @override
  void initState() {
    super.initState();
    _loadFootAssets();
    _initLocation();
  }

  // ===================================================================
  // ICONS
  // ===================================================================
  Future<void> _loadFootAssets() async {
    _footprint = await loadAssetImage("assets/footprint.png");
    _footLeft = await loadAssetImage("assets/footprints/foot_left.png");
    _footRight = await loadAssetImage("assets/footprints/foot_right.png");
  }

  Future<Uint8List> loadAssetImage(String path) async {
    final ByteData bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 24,
      targetHeight: 24,
    );
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  // ===================================================================
  // LOCALIZAÇÃO
  // ===================================================================
  Future<void> _initLocation() async {
    var perm = await Geo.Geolocator.checkPermission();
    if (perm == Geo.LocationPermission.denied) {
      perm = await Geo.Geolocator.requestPermission();
    }
    if (perm == Geo.LocationPermission.denied ||
        perm == Geo.LocationPermission.deniedForever) {
      return;
    }

    _pos = await Geo.Geolocator.getCurrentPosition(
      desiredAccuracy: Geo.LocationAccuracy.best,
    );

    setState(() {});

    if (_map != null && _pos != null) {
      _moveTo(_pos!.latitude, _pos!.longitude);
      _updateUserMarker();
    }
  }

  void _moveTo(double lat, double lon) {
    _map?.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(lon, lat)),
        zoom: 15,
      ),
    );
  }

  Future<void> _updateUserMarker() async {
    if (_map == null || _pos == null || _footprint == null) return;

    _userManager ??=
        await _map!.annotations.createPointAnnotationManager();

    if (_userMarker != null) {
      await _userManager!.delete(_userMarker!);
    }

    final marker = await _userManager!.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(_pos!.longitude, _pos!.latitude),
        ),
        image: _footprint!,
        iconSize: 1.0, // mesmo tamanho das pegadas
      ),
    );

    _userMarker = marker;
  }

  // ===================================================================
  // AUTOCOMPLETE
  // ===================================================================
  Future<void> _searchPlaces(String q) async {
    if (q.length < 3) {
      setState(() => _suggestions.clear());
      return;
    }

    final proximity = _pos != null
        ? "&proximity=${_pos!.longitude},${_pos!.latitude}"
        : "";

    final url =
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json"
        "?autocomplete=true"
        "&fuzzyMatch=false"
        "&types=address"
        "&limit=6"
        "$proximity"
        "&access_token=$_token";

    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return;

    final data = json.decode(res.body);
    final List features = data["features"] ?? [];

    setState(() {
      _suggestions.clear();
      for (var f in features) {
        final c = f["center"];
        if (c is List && c.length == 2) {
          _suggestions.add(
            _Suggestion(
              name: f["text"] ?? "",
              address: f["place_name"] ?? "",
              lat: (c[1] as num).toDouble(),
              lon: (c[0] as num).toDouble(),
            ),
          );
        }
      }
    });
  }

  Future<void> _onSelectSuggestion(_Suggestion s) async {
    _search.text = s.name;
    setState(() => _suggestions.clear());

    _moveTo(s.lat, s.lon);
    await _createRouteTo(s.lat, s.lon);
  }

  // ===================================================================
  // ROTA + PEGADAS
  // ===================================================================
  Future<void> _createRouteTo(double destLat, double destLon) async {
    if (_pos == null) return;

    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "${_pos!.longitude},${_pos!.latitude};$destLon,$destLat"
        "?geometries=geojson&access_token=$_token";

    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return;

    final data = json.decode(res.body);

    // Rota principal
    final route = data["routes"][0];

    // Distância e duração reais da rota
    final double distanceMeters = (route["distance"] as num).toDouble();
    final double durationSeconds = (route["duration"] as num).toDouble();

    _remainingKm = distanceMeters / 1000.0;
    _remainingMin = durationSeconds / 60.0;

    setState(() {});

    // Geometria da rota
    final coords = route["geometry"]["coordinates"];
    final List<Position> points = coords.map<Position>((c) {
      return Position(
        (c[0] as num).toDouble(),
        (c[1] as num).toDouble(),
      );
    }).toList();

    _lastRoutePoints = points;

    await _drawRoute(points);
    await _drawFootsteps(points);
  }

  Future<void> _drawRoute(List<Position> pts) async {
    if (_map == null) return;

    _lineManager ??=
        await _map!.annotations.createPolylineAnnotationManager();

    await _lineManager!.deleteAll();

    await _lineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: pts),
        lineColor: 0xFF00AA55,
        lineWidth: 5,
        lineOpacity: 1.0,
      ),
    );
  }

  Future<void> _drawFootsteps(List<Position> pts) async {
    if (_map == null || _footLeft == null || _footRight == null) return;

    _stepsManager ??=
        await _map!.annotations.createPointAnnotationManager();

    await _stepsManager!.deleteAll();

    bool left = true;

    // um passo a cada 4 pontos
    for (int i = 0; i < pts.length - 1; i += 4) {
      final a = pts[i];
      final b = pts[i + 1];

      final dx = b.lng - a.lng;
      final dy = b.lat - a.lat;
      final angleDeg = math.atan2(dy, dx) * 180 / math.pi;

      final img = left ? _footLeft! : _footRight!;
      left = !left;

      await _stepsManager!.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(a.lng, a.lat)),
          image: img,
          iconSize: 0.14,
          iconRotate: angleDeg,
        ),
      );
    }
  }

  // ===================================================================
  // ROUTE BUTTON
  // ===================================================================
  void _startRoute() {
    if (_lastRoutePoints == null || _lastRoutePoints!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No route available")),
      );
      return;
    }

    _drawRoute(_lastRoutePoints!);
    _drawFootsteps(_lastRoutePoints!);
  }

  // ===================================================================
  // FOLLOW MODE
  // ===================================================================
  void _startNavigation() {
    if (_pos == null) return;

    setState(() => _navigating = true);

    Geo.Geolocator.getPositionStream(
      locationSettings: const Geo.LocationSettings(
        accuracy: Geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((newPos) {
      print("🔵 GPS UPDATE: ${newPos.latitude}, ${newPos.longitude}");

      if (!_navigating) return;

      _pos = newPos;
      _updateUserMarker();

      _map?.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(newPos.longitude, newPos.latitude),
          ),
          zoom: 16,
          bearing: newPos.heading,
        ),
        MapAnimationOptions(duration: 1000),
      );
    });
  }

  void _stopNavigation() {
    setState(() => _navigating = false);
  }

  // ===================================================================
  // RISK POPUP
  // ===================================================================
  Future<void> _onTap(MapContentGestureContext ctx) async {
    if (_map == null) return;

    final results = await _map!.queryRenderedFeatures(
      RenderedQueryGeometry(
        type: Type.SCREEN_COORDINATE,
        value: jsonEncode(ctx.touchPosition.encode()),
      ),
      RenderedQueryOptions(layerIds: ["risk-layer"]),
    );

    if (results.isEmpty) return;

    final f = results.first?.queriedFeature.feature;
    if (f == null) return;

    final Map<String, dynamic> json = jsonDecode(jsonEncode(f));
    final risk = json["properties"]?["risk"] ?? 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFEAF5E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning,
                size: 34, color: _riskColor(risk)),
            const SizedBox(height: 8),
            Text("Risk Level: $risk",
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              "This location has a safety report.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _riskColor(dynamic r) {
    final v = r is num ? r.toInt() : int.tryParse("$r") ?? 1;
    return [Colors.green, Colors.yellow, Colors.orange, Colors.red]
        [(v - 1).clamp(0, 3)];
  }

  // ===================================================================
  // UI
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    final Point center = _pos == null
        ? Point(coordinates: Position(-9.1393, 38.7223))
        : Point(
            coordinates: Position(_pos!.longitude, _pos!.latitude),
          );

    return Scaffold(
      body: SlidingUpPanel(
        minHeight: 60,
        maxHeight: 350,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(22)),
        panel: _buildHomePanel(context),
        body: Stack(
          children: [
            MapWidget(
              styleUri: MapboxStyles.SATELLITE_STREETS,
              cameraOptions: CameraOptions(center: center, zoom: 15),
              onMapCreated: (m) {
                _map = m;

                Future.delayed(const Duration(milliseconds: 200), () {
                  if (_lastRoutePoints != null) {
                    _drawRoute(_lastRoutePoints!);
                    _drawFootsteps(_lastRoutePoints!);
                  }
                });
              },
              onTapListener: _onTap,
            ),

            // SEARCH BAR
            if (!_navigating)
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    _buildSearchBar(),
                    if (_suggestions.isNotEmpty)
                      _buildSuggestions(),
                  ],
                ),
              ),

            // START ROUTE
            if (!_navigating)
              Positioned(
                bottom: 120,
                right: 16,
                child: FloatingActionButton.extended(
                  backgroundColor: Colors.blueAccent,
                  onPressed: _startRoute,
                  label: const Text("Start Route"),
                  icon: const Icon(Icons.route),
                ),
              ),

            // START WALK
            if (!_navigating)
              Positioned(
                bottom: 40,
                right: 16,
                child: FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF70A77F),
                  onPressed: _startNavigation,
                  label: const Text("Start Walk"),
                  icon: const Icon(Icons.directions_walk),
                ),
              ),

            // NAVIGATION PANEL
            if (_navigating) _buildNavPanel(),

            // STOP NAVIGATION
            if (_navigating)
              Positioned(
                bottom: 40,
                left: 16,
                right: 16,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBA4A4A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: _stopNavigation,
                  child: const Text(
                    "Stop Navigation",
                    style: TextStyle(
                        fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // NAVIGATION PANEL
  Widget _buildNavPanel() {
    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xAAE6F2DD),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_walk,
                  color: Color(0xFF6AA57A)),
              const SizedBox(width: 10),
              Text(
                "${_remainingKm.toStringAsFixed(2)} km",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(width: 20),
              Text(
                "${_remainingMin.toStringAsFixed(0)} min",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // SEARCH BAR
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8F3DF),
            Color(0xFFCFE8C6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _search,
        onChanged: _searchPlaces,
        decoration: const InputDecoration(
          icon: Icon(Icons.search, color: Color(0xFF6AA57A)),
          hintText: "Search destination…",
          border: InputBorder.none,
        ),
      ),
    );
  }

  // SUGGESTIONS
  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          return ListTile(
            leading:
                const Icon(Icons.place, color: Color(0xFF6AA57A)),
            title: Text(
              s.name,
              style:
                  const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(s.address),
            onTap: () => _onSelectSuggestion(s),
          );
        },
      ),
    );
  }

  // HOME PANEL
  Widget _buildHomePanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            "OnFoot Menu",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          _menuItem(
            icon: Icons.map_outlined,
            color: Colors.green,
            title: "Map",
            subtitle: "Navigate safely",
            onTap: () {
              Navigator.pop(context);
            },
          ),

          _menuItem(
            icon: Icons.shield_outlined,
            color: Colors.orange,
            title: "Safety",
            subtitle: "Emergency tools",
            onTap: () {
              Navigator.pushNamed(context, '/safety');
            },
          ),

          _menuItem(
            icon: Icons.person_outline,
            color: Colors.blueGrey,
            title: "Profile",
            subtitle: "Your account",
            onTap: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
        ],
      ),
    );
  }

  // MENU ITEM
  Widget _menuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

// ================================================================
// MODEL
// ================================================================
class _Suggestion {
  final String name;
  final String address;
  final double lat;
  final double lon;

  _Suggestion({
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
  });
}
