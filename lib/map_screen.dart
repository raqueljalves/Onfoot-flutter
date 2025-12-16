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

import 'services/route_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final RouteService _routeService = RouteService();
  final SupabaseClient supabase = Supabase.instance.client;

  static const String _token =
      "pk.eyJ1IjoicmFxdWVsamFsdmVzIiwiYSI6ImNtZ3YyN292YTBhbDMybHNiaGR6bHk2anUifQ.Qn0OuPaYXPC3cX3mgsUBeA";
  static const String _googlePlacesKeyIOS = 'AIzaSyDrK5MiEmC7_3ClRg1LuYd5PTrHvlpDz2A';
  static const String _googlePlacesKeyAndroid = 'AIzaSyCO7ct_ZXQj7quKa796keVOxrhjgkzoyiY';
  MapboxMap? _map;
  Geo.Position? _pos;
  StreamSubscription<Geo.Position>? _positionStream;

  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _userManager;
  PointAnnotation? _userMarker;
  PointAnnotationManager? _stepsManager;

  Uint8List? _footprint;
  Uint8List? _footLeft;
  Uint8List? _footRight;

  final TextEditingController _search = TextEditingController();
  final List<_Suggestion> _suggestions = [];

  Geo.Position? _destination;
  List<Position>? _lastRoutePoints;
  double _remainingKm = 0.0;
  double _remainingMin = 0.0;
  bool _isNavigating = false;
  bool _routePreviewMode = false;
  
  // Off-route detection
  bool _isOffRoute = false;

  @override
  void initState() {
    super.initState();
    _loadFootAssets();
    _initLocation();
  }

  Future<void> _loadFootAssets() async {
    print("🟡 Loading foot assets...");
    
    try {
      _footprint = await _loadAssetImage("assets/footprint.png");
      print("🟢 Loaded footprint.png: ${_footprint?.length} bytes");
    } catch (e) {
      print("🔴 ERROR loading footprint.png: $e");
    }
    
    try {
      _footLeft = await _loadAssetImage("assets/footprints/foot_left.png");
      print("🟢 Loaded foot_left.png: ${_footLeft?.length} bytes");
    } catch (e) {
      print("🔴 ERROR loading foot_left.png: $e");
    }
    
    try {
      _footRight = await _loadAssetImage("assets/footprints/foot_right.png");
      print("🟢 Loaded foot_right.png: ${_footRight?.length} bytes");
    } catch (e) {
      print("🔴 ERROR loading foot_right.png: $e");
    }
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
      _moveTo(_pos!.latitude, _pos!.longitude, zoom: 15);
      _updateUserMarker();
    }

    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _positionStream = Geo.Geolocator.getPositionStream(
      locationSettings: const Geo.LocationSettings(
        accuracy: Geo.LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Geo.Position position) {
      _pos = position;
      _updateUserMarker();

      if (_isNavigating && _destination != null) {
        // Move camera with heading
        final bearing = position.heading >= 0 ? position.heading : 0.0;
        _moveTo(position.latitude, position.longitude, 
                zoom: 18.5, bearing: bearing, pitch: 45);
        _updateRemainingDistance();
        _checkIfOffRoute();
      }
    });
  }

  void _moveTo(double lat, double lon, {double zoom = 15, double bearing = 0, double pitch = 0}) {
    if (_map == null) return;

    _map!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lon, lat)),
        zoom: zoom,
        pitch: pitch,
        bearing: bearing,
      ),
      MapAnimationOptions(duration: 800, startDelay: 0),
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
        iconSize: 1.2,
      ),
    );
  }

  void _updateRemainingDistance() {
    if (_pos == null || _destination == null) return;

    double distanceInMeters = Geo.Geolocator.distanceBetween(
      _pos!.latitude,
      _pos!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    setState(() {
      _remainingKm = distanceInMeters / 1000.0;
      _remainingMin = (_remainingKm / 5.0) * 60.0;
    });

    if (distanceInMeters < 10) {
      _onArrival();
    }
  }

  void _checkIfOffRoute() {
    if (_lastRoutePoints == null || _lastRoutePoints!.isEmpty) return;
    if (_pos == null) return;

    // Only check if moving fast enough (walking speed)
    if (_pos!.speed < 1.0) return; // 1 m/s = 3.6 km/h

    // Find closest point on route
    double minDistance = double.infinity;
    
    for (var point in _lastRoutePoints!) {
      double distance = Geo.Geolocator.distanceBetween(
        _pos!.latitude,
        _pos!.longitude,
        point.lat.toDouble(),
        point.lng.toDouble(),
      );
      
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    // Much larger threshold - walking routes can be 30-50m from centerline
    double threshold = math.max(50.0, _pos!.accuracy * 1.5);

    // Only warn if VERY far off route
    if (minDistance > threshold && !_isOffRoute) {
      setState(() => _isOffRoute = true);
      
      print("⚠️ OFF ROUTE! Distance: ${minDistance.toStringAsFixed(1)}m, Threshold: ${threshold.toStringAsFixed(1)}m");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text("You may be off route. Check the green line."),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (minDistance <= threshold * 0.7 && _isOffRoute) {
      // Need to be well within threshold to clear warning (70% of threshold)
      setState(() => _isOffRoute = false);
      print("✅ Back on route! Distance: ${minDistance.toStringAsFixed(1)}m");
    }
  }

  void _onArrival() {
    WakelockPlus.disable();

    setState(() {
      _isNavigating = false;
      _routePreviewMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🎉 You have arrived at your destination!"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _clearRoute() {
    if (_isNavigating) {
      WakelockPlus.disable();
    }

    setState(() {
      _destination = null;
      _lastRoutePoints = null;
      _remainingKm = 0;
      _remainingMin = 0;
      _isNavigating = false;
      _routePreviewMode = false;
      _isOffRoute = false;
    });

    _lineManager?.deleteAll();
    _stepsManager?.deleteAll();
  }

  void _startNavigation() {
    if (_destination == null || _lastRoutePoints == null) return;

    print("🟢 Starting navigation...");

    setState(() {
      _isNavigating = true;
      _routePreviewMode = false;
    });

    WakelockPlus.enable();

    if (_pos != null) {
      final bearing = _pos!.heading >= 0 ? _pos!.heading : 0.0;
      _moveTo(_pos!.latitude, _pos!.longitude, zoom: 18.5, bearing: bearing, pitch: 45);
    }

    // REDRAW FOOTSTEPS to ensure they're visible during navigation
    print("🟡 Redrawing footsteps for navigation...");
    _drawFootsteps(_lastRoutePoints!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Navigation started! Follow the green route."),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _searchPlaces(String q) async {
    if (q.length < 2) {
      setState(() => _suggestions.clear());
      return;
    }

    print("🔵 Searching for: '$q'");

    // Determine if query looks like POI or address
    final lowerQ = q.toLowerCase();
    final isPOI = _isPOIQuery(lowerQ);

    if (isPOI) {
      print("🟢 Using GOOGLE PLACES for POI search");
      await _searchGooglePlaces(q);
    } else {
      print("🟡 Using MAPBOX for address search");
      await _searchMapbox(q);
    }
  }

  // Detect if query is likely a POI (business/store) vs address
  bool _isPOIQuery(String query) {
    final poiKeywords = [
      'restaurant', 'cafe', 'coffee', 'bar', 'pub',
      'shop', 'store', 'market', 'supermarket', 'grocery',
      'pharmacy', 'hospital', 'clinic', 'doctor',
      'hotel', 'gym', 'bank', 'atm',
      'station', 'train', 'bus', 'metro',
      'museum', 'park', 'cinema', 'theater',
      'albert heijn', 'jumbo', 'lidl', 'aldi', 'ah',
      'mc donald', 'burger king', 'kfc', 'subway'
    ];

    // If query contains POI keywords, use Google Places
    for (var keyword in poiKeywords) {
      if (query.contains(keyword)) return true;
    }

    // If query has numbers followed by street name, likely an address
    if (RegExp(r'^\d+\s+\w+').hasMatch(query)) return false;

    // If short query without numbers, likely searching for POI
    if (query.length <= 15 && !query.contains(RegExp(r'\d'))) return true;

    // Default to address search
    return false;
  }

  Future<void> _searchGooglePlaces(String q) async {
    if (_pos == null) return;

    // Get correct API key for platform
    String apiKey;
    try {
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        apiKey = _googlePlacesKeyIOS;
      } else {
        apiKey = _googlePlacesKeyAndroid;
      }
    } catch (e) {
      apiKey = _googlePlacesKeyAndroid; // Default to Android
    }

    final url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json"
        "?input=${Uri.encodeComponent(q)}"
        "&location=${_pos!.latitude},${_pos!.longitude}"
        "&radius=5000"
        "&key=$apiKey";

    try {
      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) {
        print("🔴 Google Places error: ${res.statusCode}");
        return;
      }

      final data = json.decode(res.body);

      if (data["status"] != "OK" && data["status"] != "ZERO_RESULTS") {
        print("🔴 Google Places API error: ${data['status']}");
        return;
      }

      final List predictions = data["predictions"] ?? [];
      print("🟢 Found ${predictions.length} Google Places results");

      // Get place details for coordinates
      List<_Suggestion> suggestions = [];
      for (var prediction in predictions.take(6)) {
        final placeId = prediction["place_id"];
        final coords = await _getPlaceCoordinates(placeId, apiKey);

        if (coords != null) {
          suggestions.add(
            _Suggestion(
              name: prediction["structured_formatting"]["main_text"] ?? "",
              address: prediction["description"] ?? "",
              lat: (coords["lat"] as num).toDouble(),
              lon: (coords["lng"] as num).toDouble(),
            ),
          );
          print("  📍 ${prediction["structured_formatting"]["main_text"]}");
        }
      }

      setState(() {
        _suggestions.clear();
        _suggestions.addAll(suggestions);
      });

      print("✅ Loaded ${_suggestions.length} Google Places suggestions");
    } catch (e) {
      print("🔴 Google Places exception: $e");
    }
  }

  Future<Map<String, double>?> _getPlaceCoordinates(
      String placeId, String apiKey) async {
    final url =
        "https://maps.googleapis.com/maps/api/place/details/json"
        "?place_id=$placeId"
        "&fields=geometry"
        "&key=$apiKey";

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body);
      if (data["status"] != "OK") return null;

      final location = data["result"]["geometry"]["location"];
      return {
        "lat": (location["lat"] as num).toDouble(),
        "lng": (location["lng"] as num).toDouble(),
      };
    } catch (e) {
      print("🔴 Error getting coordinates: $e");
      return null;
    }
  }

  Future<void> _searchMapbox(String q) async {
    final proximity = _pos != null
        ? "${_pos!.longitude},${_pos!.latitude}"
        : "-9.1393,38.7223";

    final url =
        "https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(q)}.json"
        "?access_token=$_token"
        "&proximity=$proximity"
        "&types=address,place"
        "&limit=6"
        "&language=en";

    try {
      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) {
        print("🔴 Mapbox error: ${res.statusCode}");
        return;
      }

      final data = json.decode(res.body);
      final List features = data["features"] ?? [];

      print("🟢 Found ${features.length} Mapbox results");

      setState(() {
        _suggestions.clear();
        for (var f in features) {
          final c = f["center"];
          if (c is List && c.length >= 2) {
            final name = f["text"] ?? "";
            final address = f["place_name"] ?? "";

            print("  📍 $name - $address");

            _suggestions.add(
              _Suggestion(
                name: name,
                address: address,
                lat: (c[1] as num).toDouble(),
                lon: (c[0] as num).toDouble(),
              ),
            );
          }
        }
      });

      print("✅ Loaded ${_suggestions.length} Mapbox suggestions");
    } catch (e) {
      print("🔴 Mapbox exception: $e");
    }
  }

  Future<void> _onSelectSuggestion(_Suggestion s) async {
    _search.text = s.name;
    setState(() => _suggestions.clear());

    await Future.delayed(const Duration(milliseconds: 200));
    await _createRouteTo(s.lat, s.lon);
  }

  Future<void> _createRouteTo(double destLat, double destLon) async {
    if (_pos == null) return;

    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "${_pos!.longitude},${_pos!.latitude};$destLon,$destLat"
        "?geometries=geojson&steps=true&alternatives=true&access_token=$_token";

    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${res.statusCode}")),
      );
      return;
    }

    final data = json.decode(res.body);
    if (data["routes"] == null || data["routes"].isEmpty) {
      return;
    }

    final routes = data["routes"] as List;
    routes.sort((a, b) => a["distance"].compareTo(b["distance"]));

    final route = routes[0];
    final coords = route["geometry"]["coordinates"] as List;

    final double distanceMeters = (route["distance"] as num).toDouble();
    final double durationSeconds = (route["duration"] as num).toDouble();

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

    try {
      await _routeService.saveRoute(
        fromLat: _pos!.latitude,
        fromLon: _pos!.longitude,
        toLat: destLat,
        toLon: destLon,
        distanceKm: _remainingKm,
      );
    } catch (e) {
      print("⚠️ Could not save to Supabase: $e");
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

    if (points.isEmpty) return;

    _lastRoutePoints = points;

    // Draw route line first
    print("🟡 Drawing route line...");
    await _drawRoute(points);
    print("🟢 Route line drawn!");
    
    // Then draw footsteps on top
    print("🟡 Drawing footsteps on top...");
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
    if (_map == null || pts.isEmpty) return;

    try {
      _lineManager ??= await _map!.annotations.createPolylineAnnotationManager();
      await _lineManager!.deleteAll();

      await _lineManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: pts),
          lineColor: 0xFF00AA55,
          lineWidth: 7.0,
          lineOpacity: 0.9,
        ),
      );
    } catch (e) {
      print("Error drawing route: $e");
    }
  }

  Future<void> _drawFootsteps(List<Position> routePoints) async {
    if (_map == null || routePoints.length < 2) {
      print("🔴 Cannot draw footsteps: map=${_map != null}, points=${routePoints.length}");
      return;
    }
    
    if (_footLeft == null || _footRight == null) {
      print("🔴 Cannot draw footsteps: footLeft=${_footLeft != null}, footRight=${_footRight != null}");
      return;
    }

    print("🟡 Starting to draw footsteps with ${routePoints.length} route points");

    try {
      // Create new manager or clear existing
      if (_stepsManager == null) {
        print("🟡 Creating new footstep manager");
        _stepsManager = await _map!.annotations.createPointAnnotationManager();
      } else {
        print("🟡 Clearing existing footsteps");
        await _stepsManager!.deleteAll();
      }

      bool isLeftFoot = true;
      int footstepCount = 0;
      double totalDistance = 0;
      const double stepDistanceMeters = 10.0; // Place footprint every 10 meters
      double accumulatedDistance = 0;

      // Calculate footsteps based on actual distance
      for (int i = 0; i < routePoints.length - 1; i++) {
        Position current = routePoints[i];
        Position next = routePoints[i + 1];

        // Calculate distance between consecutive points
        double segmentDistance = Geo.Geolocator.distanceBetween(
          current.lat.toDouble(),
          current.lng.toDouble(),
          next.lat.toDouble(),
          next.lng.toDouble(),
        );

        totalDistance += segmentDistance;
        accumulatedDistance += segmentDistance;

        // Place a footstep every 10 meters
        if (accumulatedDistance >= stepDistanceMeters) {
          // Calculate bearing for rotation
          double bearing = _calculateBearing(
            current.lat.toDouble(),
            current.lng.toDouble(),
            next.lat.toDouble(),
            next.lng.toDouble(),
          );

          // Create the footstep
          await _stepsManager!.create(
            PointAnnotationOptions(
              geometry: Point(coordinates: current),
              image: isLeftFoot ? _footLeft! : _footRight!,
              iconSize: 0.35, // Even larger for visibility
              iconRotate: bearing,
              iconOpacity: 1.0, // Full opacity
            ),
          );

          footstepCount++;
          isLeftFoot = !isLeftFoot;
          accumulatedDistance = 0; // Reset counter
        }
      }

      print("🟢 ✅ Successfully drew $footstepCount footsteps along ${totalDistance.toStringAsFixed(0)}m route!");
    } catch (e, stackTrace) {
      print("🔴 ERROR drawing footsteps: $e");
      print("🔴 Stack trace: $stackTrace");
    }
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

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

  @override
  void dispose() {
    _positionStream?.cancel();
    _search.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              _map = m;

              if (_pos != null) {
                _moveTo(_pos!.latitude, _pos!.longitude);
                await _updateUserMarker();
              }

              if (_lastRoutePoints != null) {
                await Future.delayed(const Duration(milliseconds: 300));
                await _drawRoute(_lastRoutePoints!);
                await _drawFootsteps(_lastRoutePoints!);
              }
            },
            onTapListener: _onTap,
          ),

          // OFF-ROUTE WARNING
          if (_isOffRoute && _isNavigating)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "OFF ROUTE! Return to green line",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // DISTANCE/TIME PANEL
          if (_lastRoutePoints != null && (_routePreviewMode || _isNavigating))
            Positioned(
              bottom: _routePreviewMode ? 200 : 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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