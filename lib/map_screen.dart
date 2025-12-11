import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as Geo;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:math' show cos, sin, pi;

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
  StreamSubscription<Geo.Position>? _positionStream;

  // Annotations
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _userManager;
  PointAnnotation? _userMarker;
  PointAnnotationManager? _stepsManager;
  PointAnnotationManager? _destinationManager;

  // Icons
  Uint8List? _footprint;
  Uint8List? _footLeft;
  Uint8List? _footRight;

  // Search
  final TextEditingController _search = TextEditingController();
  final List<_Suggestion> _suggestions = [];

  // ADD THIS LINE:
  Geo.Position? _destination;  //Make sure this is Geo.Position
  
  // Route data
  List<Position>? _lastRoutePoints = [];
  double _remainingKm = 0.0;
  double _remainingMin = 0.0;
  bool _isNavigating = false;
  bool _routePreviewMode = false;

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
    _footprint = await _loadAssetImage("assets/footprint.png");
    _footLeft = await _loadAssetImage("assets/footprints/foot_left.png");
    _footRight = await _loadAssetImage("assets/footprints/foot_right.png");
  }

  Future<Uint8List> _loadAssetImage(String path) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 24,
      targetHeight: 24,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  // ===================================================================
  // LOCALIZAÇÃO COM UPDATES EM TEMPO REAL
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

    if (!mounted) return;
    setState(() {});

    if (_map != null && _pos != null) {
      _moveTo(_pos!.latitude, _pos!.longitude);
      _updateUserMarker();
    }

    // START LISTENING TO LOCATION UPDATES
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _positionStream = Geo.Geolocator.getPositionStream(
      locationSettings: const Geo.LocationSettings(
        accuracy: Geo.LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Geo.Position position) {
      print("🔵 Location updated: ${position.latitude}, ${position.longitude}");
   
      _pos = position;
      _updateUserMarker();

      // If navigating, move camera to follow user and update distance/time
      if (_isNavigating && _destination != null) {
        print("🟢 Navigating - moving camera to user position");
        _moveTo(_pos!.latitude, _pos!.longitude); // THIS MOVES THE CAMERA
        _updateRemainingDistance();
     }
   });
 }

  void _moveTo(double lat, double lon) {
  if (_map == null) return;

  print("🔵 Moving camera to: $lat, $lon");

  _map!.flyTo(
    CameraOptions(
      center: Point(coordinates: Position(lon, lat)),
      zoom: 17.0,  // Good zoom level for walking navigation
      pitch: 0,
      bearing: 0,
    ),
    MapAnimationOptions(
      duration: 1000,  // 1 second smooth animation
      startDelay: 0,
    ),
  );
}

  Future<void> _updateUserMarker() async {
    if (_map == null || _pos == null || _footprint == null) return;

    _userManager ??= await _map!.annotations.createPointAnnotationManager();

    if (_userMarker != null) {
      await _userManager!.delete(_userMarker!);
    }

    _userMarker = await _userManager!.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(_pos!.longitude, _pos!.latitude),
        ),
        image: _footprint!,
        iconSize: 1.0,
      ),
    );
  }

  // ===================================================================
  // CALCULATE REMAINING DISTANCE IN REAL-TIME
  // ===================================================================
void _updateRemainingDistance() {
  if (_pos == null || _destination == null) return;

  // Calculate distance in METERS
  double distanceInMeters = Geo.Geolocator.distanceBetween(
    _pos!.latitude,
    _pos!.longitude,
    _destination!.latitude,  // now this will work!
    _destination!.longitude, // now this will work!
  );

  print("🔵 Distance in meters: $distanceInMeters");

  setState(() {
    // Convert meters to kilometers
    _remainingKm = distanceInMeters / 1000.0;
    
    // Calculate time (assuming 5 km/h walking speed)
    _remainingMin = (_remainingKm / 5.0) * 60.0;
    
    print("🟢 Distance: ${_remainingKm.toStringAsFixed(2)} km");
    print("🟢 Time: ${_remainingMin.toStringAsFixed(0)} min");
  });

  // Check if arrived (within 10 meters)
  if (distanceInMeters < 10) {
    _onArrival();
  }
}

void _onArrival() {
  // Turn off screen lock when navigation ends
  WakelockPlus.disable();
  print("🟢 Screen lock restored");

  setState(() {
    _isNavigating = false;
    _routePreviewMode = false;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("You have arrived at your destination!"),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 3),
    ),
  );
} 

void _clearRoute() {
  // Turn off screen lock when clearing route
  if (_isNavigating) {
    WakelockPlus.disable();
  }

  setState(() {
    _destination = null;
    _lastRoutePoints = [];
    _remainingKm = 0;
    _remainingMin = 0;
    _isNavigating = false;
    _routePreviewMode = false;
  });

  // Remove route line
  if (_lineManager != null) {
    _map?.annotations.removeAnnotationManager(_lineManager!);
    _lineManager = null;
  }
  
  // Remove footsteps
  if (_stepsManager != null) {
    _map?.annotations.removeAnnotationManager(_stepsManager!);
    _stepsManager = null;
  }

  // Remove destination marker
  if (_destinationManager != null) {
    _map?.annotations.removeAnnotationManager(_destinationManager!);
    _destinationManager = null;
  }

  print("🔴 Route cleared");
}
  // ===================================================================
// START NAVIGATION
// ===================================================================
void _startNavigation() {
  if (_destination == null || _lastRoutePoints == null) return;
  
  setState(() {
    _isNavigating = true;
    _routePreviewMode = false;
  });
  
 // Keep screen on during navigation
  WakelockPlus.enable();
  print("🟢 Screen will stay on during navigation");

  // Move camera back to user's current location
  if (_pos != null) {
    _moveTo(_pos!.latitude, _pos!.longitude);
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Navigation started! Follow the green route."),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 2),
    ),
  );
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
        "&types=address,poi"
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

    await Future.delayed(const Duration(milliseconds: 200));
    
    await _createRouteTo(s.lat, s.lon);
  }

  // ===================================================================
  // ROTA + PEGADAS COM NAVEGAÇÃO
  // ===================================================================
  Future<void> _createRouteTo(double destLat, double destLon) async {
    if (_pos == null) {
      print("🔴 ERROR: _pos is null");
      return;
    }

    print("🔵 Creating route from (${_pos!.latitude}, ${_pos!.longitude}) to ($destLat, $destLon)");

    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "${_pos!.longitude},${_pos!.latitude};$destLon,$destLat"
        "?geometries=geojson&steps=true&alternatives=true&access_token=$_token";

    print("🔵 Fetching route...");

    final res = await http.get(Uri.parse(url));
    print("🔵 Response status: ${res.statusCode}");

    if (res.statusCode != 200) {
      print("🔴 ERROR: Bad response ${res.statusCode}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${res.statusCode}")),
      );
      return;
    }

    final data = json.decode(res.body);
    if (data["routes"] == null || data["routes"].isEmpty) {
      print("🔴 No routes found");
      return;
    }

    // Sort routes by distance (shortest first)
    final routes = data["routes"] as List;
    routes.sort((a, b) => a["distance"].compareTo(b["distance"]));

    // Use the shortest route (often includes shortcuts)
    final route = routes[0];
    final coords = route["geometry"]["coordinates"] as List;
  

    print("🟢 Route found!");
    final double distanceMeters = (route["distance"] as num).toDouble();
    final double durationSeconds = (route["duration"] as num).toDouble();

    print("🟢 Distance: ${distanceMeters}m, Duration: ${durationSeconds}s");

    _remainingKm = distanceMeters / 1000.0;
    _remainingMin = durationSeconds / 60.0;
    _destination = Geo.Position(
      latitude: destLat,
      longitude: destLon,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    // Save to Supabase
    try {
      await _routeService.saveRoute(
        fromLat: _pos!.latitude,
        fromLon: _pos!.longitude,
        toLat: destLat,
        toLon: destLon,
        distanceKm: _remainingKm,
      );
      print("🟢 Route saved to Supabase");
    } catch (e) {
      print("⚠️ Warning: Could not save to Supabase: $e");
    }

    if (coords == null || coords.isEmpty) {
      print("🔴 ERROR: No geometry coordinates");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not read geometry.")),
      );
      return;
    }

    final List<Position> points = [];
    for (var c in coords) {
      if (c is List && c.length >= 2) {
        points.add(Position(
          (c[0] as num).toDouble(),
          (c[1] as num).toDouble(),
        ));
      }
    }

    print("🟢 Route has ${points.length} points");

    if (points.isEmpty) {
      print("🔴 ERROR: No valid points extracted");
      return;
    }

    _lastRoutePoints = points;

    // Draw route and footsteps
    print("🟡 Starting to draw route...");
    await _drawRoute(points);
    print("🟢 Route drawn!");
    
    print("🟡 Starting to draw footsteps...");
    await _drawFootsteps(points);
    print("🟢 Footsteps drawn!");

    // Set to preview mode (not navigating yet)
    _routePreviewMode = true;
    _isNavigating = false;

    if (!mounted) return;
    setState(() {});

    print("🟢 UI updated - route preview mode active");

    // Move camera to show full route
    _fitRouteBounds(points);
  }

  void _fitRouteBounds(List<Position> points) {
    if (_map == null || points.isEmpty) return;

    double minLat = points[0].lat.toDouble();
    double maxLat = points[0].lat.toDouble();
    double minLng = points[0].lng.toDouble();
    double maxLng = points[0].lng.toDouble();

    for (var p in points) {
      final lat = p.lat.toDouble();
      final lng = p.lng.toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    _map?.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(centerLng, centerLat)),
        zoom: 14,
      ),
    );
  }

  Future<void> _drawRoute(List<Position> pts) async {
    if (_map == null) {
      print("🔴 ERROR: _map is null in _drawRoute");
      return;
    }

    if (pts.isEmpty) {
      print("🔴 ERROR: pts is empty in _drawRoute");
      return;
    }

    print("🟡 Drawing route with ${pts.length} points");

    try {
      // Create manager if needed
      if (_lineManager == null) {
        print("🟡 Creating polyline annotation manager...");
        _lineManager = await _map!.annotations.createPolylineAnnotationManager();
        print("🟢 Polyline manager created");
      }

      // Clear existing lines
      print("🟡 Clearing existing lines...");
      await _lineManager!.deleteAll();
      print("🟢 Existing lines cleared");

      // Create the route line
      print("🟡 Creating polyline annotation...");
      final annotation = await _lineManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: pts),
          lineColor: 0xFF00AA55, // Your original green color
          lineWidth: 6.0,
          lineOpacity: 0.8,
        ),
      );

      print("🟢 ✅ Route line created successfully! ID: ${annotation.id}");
    } catch (e, stackTrace) {
      print("🔴 ERROR drawing route: $e");
      print("🔴 Stack trace: $stackTrace");
    }
  }
  Future<void> _drawFootsteps(List<Position> routePoints) async {
    if (_map == null || routePoints.length < 2) return;

    try {
      print("🔵 Starting to draw footsteps...");
    
      // Remove old footsteps if they exist
      if (_stepsManager != null) {
        await _map!.annotations.removeAnnotationManager(_stepsManager!);
        _stepsManager = null;
        print("🟢 Old footsteps removed");} 

      // Create new footstep manager
     _stepsManager = await _map!.annotations.createPointAnnotationManager();

     List<PointAnnotationOptions> footsteps = [];
     bool isLeftFoot = true;
     const double stepDistance = 20.0; // One footprint every 20 meters
     double accumulatedDistance = 0.0;

     for (int i = 0; i < routePoints.length - 1; i++) {
       Position current = routePoints[i];
       Position next = routePoints[i + 1];

       double segmentDistance = Geo.Geolocator.distanceBetween(
         current.lat.toDouble(),
         current.lng.toDouble(),
         next.lat.toDouble(),
         next.lng.toDouble(),
       );

       double bearing = Geo.Geolocator.bearingBetween(
         current.lat.toDouble(),
         current.lng.toDouble(),
         next.lat.toDouble(),
         next.lng.toDouble(),
       );

       while (accumulatedDistance < segmentDistance) {
         double ratio = accumulatedDistance / segmentDistance;
         double lat = current.lat + (next.lat - current.lat) * ratio;
         double lng = current.lng + (next.lng - current.lng) * ratio;

         // Offset perpendicular to the route (left or right)
         double offsetDistance = 0.00001; // Small offset
         double perpendicularBearing = bearing + (isLeftFoot ? -90 : 90);
        
         double offsetLat = lat + offsetDistance * cos(perpendicularBearing * pi / 180);
         double offsetLng = lng + offsetDistance * sin(perpendicularBearing * pi / 180);

         // Create a simple circle marker (no image needed!)
         footsteps.add(
           PointAnnotationOptions(
             geometry: Point(coordinates: Position(offsetLng, offsetLat)),
             iconColor: 0xFF6AA57A, // Green color matching your theme
             iconSize: 0.5,
           ),
         );

         isLeftFoot = !isLeftFoot;
         accumulatedDistance += stepDistance;
       }

       accumulatedDistance -= segmentDistance;
     }

     if (footsteps.isNotEmpty) {
       await _stepsManager!.createMulti(footsteps);
       print("🟢 Drew ${footsteps.length} footstep markers along the route");
     }

   } catch (e, stackTrace) {
     print("🔴 Error drawing footsteps: $e");
     print("🔴 Stack trace: $stackTrace");
   }
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

    if (!mounted) return;

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
            Icon(Icons.warning, size: 34, color: _riskColor(risk)),
            const SizedBox(height: 8),
            Text("Risk Level: $risk",
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
  // LIFECYCLE + UI
  // ===================================================================
  @override
  void dispose() {
    _positionStream?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  // Wait for location before showing map
  if (_pos == null) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Colors.green),
      ),
    );
  }

  final Point center = Point(
    coordinates: Position(_pos!.longitude, _pos!.latitude),
  );

  return Scaffold(
    body: Stack(
      children: [
        MapWidget(
          styleUri: MapboxStyles.SATELLITE_STREETS,
          cameraOptions: CameraOptions(center: center, zoom: 15),
          onMapCreated: (m) async {
            print("🟢 Map created!");
            _map = m;

            if (_pos != null) {
              _moveTo(_pos!.latitude, _pos!.longitude);
              await _updateUserMarker();
            }

            if (_lastRoutePoints != null) {
              print("🟡 Redrawing existing route...");
              await Future.delayed(const Duration(milliseconds: 300));
              await _drawRoute(_lastRoutePoints!);
              await _drawFootsteps(_lastRoutePoints!);
              print("🟢 Route redrawn");
            }
          },
          onTapListener: _onTap,
        ),

        // DISTANCE/TIME PANEL
        if (_lastRoutePoints != null && (_routePreviewMode || _isNavigating))
          Positioned(
            bottom: _routePreviewMode ? 200 : 120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xAAE6F2DD),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_walk,
                        color: Color(0xFF6AA57A), size: 28),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "${_remainingKm.toStringAsFixed(2)} km",
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          "${_remainingMin.toStringAsFixed(0)} min ${_isNavigating ? 'remaining' : 'walk'}",
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

        // START WALK BUTTON
        if (_routePreviewMode && !_isNavigating && _lastRoutePoints != null)
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  "Start Walk",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6AA57A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                ),
              ),
            ),
          ),

        // SEARCH BAR + SUGGESTIONS
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: Column(
            children: [
              _buildSearchBar(),
              if (_suggestions.isNotEmpty) _buildSuggestions(),
            ],
          ),
        ),

        // CLEAR ROUTE BUTTON
        if (_lastRoutePoints != null)
          Positioned(
            bottom: 40,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFFBA4A4A),
              onPressed: _clearRoute,
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
      ],
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
            leading: const Icon(Icons.place, color: Color(0xFF6AA57A)),
            title: Text(
              s.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(s.address),
            onTap: () => _onSelectSuggestion(s),
          );
        },
      ),
    );
  }
}

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