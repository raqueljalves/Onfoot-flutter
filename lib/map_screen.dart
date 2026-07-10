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
import 'services/city_detection_service.dart';
import 'services/safety_service.dart';
import 'widgets/city_confirmation_dialog.dart';
import '../services/preferences_service.dart';
import 'services/auth_service.dart';

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
  static const String _googlePlacesKeyIOS = 'AIzaSyDPz05cdqsN7XJhBTCinQ4Bof_NZ8YzZG4';
  static const String _googlePlacesKeyAndroid = 'AIzaSyDyqOIinfKxtDeJld06ltiO8y3B83vXeM0';
  MapboxMap? _map;
  Geo.Position? _pos;
  StreamSubscription<Geo.Position>? _positionStream;

  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _userManager;
  PointAnnotation? _userMarker;
  PointAnnotationManager? _stepsManager;

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

  final CityDetectionService _cityService = CityDetectionService();
  String? _currentCityId;
  DateTime? _lastCityCheck;
  
  // Off-route detection
  bool _isOffRoute = false;
  DateTime? _offRouteStartTime;
  Geo.Position? _lastKnownGoodPosition;
  DateTime? _uncertainStartTime;
  DateTime? _divergenceStartTime;
  List<double> _recentProgress = [];
  Geo.Position? _previousPos;

  // Variáveis para caminho percorrido
  List<Position> _walkedPath = [];
  Geo.Position? _lastWalkedPosition;

  // Explore Around Me
  bool _showingCategoryPins = false;
  String? _activeCategoryType;
  PointAnnotationManager? _categoryPinsManager;
  List<Map<String, dynamic>> _categoryPlaces = [];  // Dados dos lugares para tap

  // Transit Routes
  bool _isTransitMode = false;
  List<Map<String, dynamic>> _transitLegs = [];  // legs da rota transit
  double _transitKm = 0.0;
  double _transitMin = 0.0;
  double _walkKm = 0.0;  // distância walk-only para comparação
  double _walkMin = 0.0;

  // Safety Reports
  final SafetyService _safetyService = SafetyService();
  List<SafetyReport> _nearbyReports = [];
  PointAnnotationManager? _safetyMarkersManager;
  DateTime? _lastReportsRefresh;
  Uint8List? _dangerIcon;
  Uint8List? _constructionIcon;
  Uint8List? _lightingIcon;
  Uint8List? _harassmentIcon;
  Uint8List? _isolatedIcon;
  Uint8List? _safeSpotIcon;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // O login com Google conclui-se de forma assíncrona (troca do token
    // pode chegar depois do ecrã do mapa já estar visível, sobretudo se a
    // app foi para background durante o OAuth). Sem isto, _isLoggedIn só
    // refletia o estado na próxima interação que desse rebuild ao ecrã.
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() {});
    }, onError: (error) {
      print('❌ Auth error: $error');
    });
    final lastLoc = PreferencesService.getLastLocation();
    if (lastLoc != null) {
      print('📍 Usando última localização guardada');
      _pos = Geo.Position(
        latitude: lastLoc['lat']!,
        longitude: lastLoc['lng']!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    
      if (mounted) setState(() {});
    
      if (_map != null) {
        _moveTo(lastLoc['lat']!, lastLoc['lng']!);
      }
    }
    _loadFootAssets();
    _loadSafetyIcons();
    _initLocation();
  }

  Future<void> _loadFootAssets() async {
    print("🟡 Loading foot assets...");
    
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

  Future<void> _loadSafetyIcons() async {
    _dangerIcon = await _createIconWithSymbol(Icons.local_police, Colors.red, 40);
    _constructionIcon = await _createIconWithSymbol(Icons.construction, Colors.orange, 40);
    _lightingIcon = await _createIconWithSymbol(Icons.lightbulb_outline, Colors.amber, 40);
    _harassmentIcon = await _createIconWithSymbol(Icons.sentiment_very_dissatisfied, Colors.purple, 40);
    _isolatedIcon = await _createIconWithSymbol(Icons.person_off, Colors.blueGrey, 40);
    _safeSpotIcon = await _createIconWithSymbol(Icons.check_circle, Colors.green, 40);
    print('✅ Safety icons loaded');
  }

  Future<Uint8List> _createIconWithSymbol(IconData icon, Color color, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - 3;
    
    canvas.drawCircle(center + const Offset(1, 2), radius, shadowPaint);
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawCircle(center, radius, borderPaint);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  Future<void> _loadNearbyReports() async {
    if (_pos == null) return;
    
    if (_lastReportsRefresh != null &&
        DateTime.now().difference(_lastReportsRefresh!).inMinutes < 2) {
      return;
    }
    
    _lastReportsRefresh = DateTime.now();
    
    try {
      print('📍 Loading nearby safety reports...');
      
      final reports = await _safetyService.getNearbyReports(
        lat: _pos!.latitude,
        lon: _pos!.longitude,
        radiusKm: 5.0,
      );
      
      print('✅ Found ${reports.length} nearby reports');
      
      setState(() {
        _nearbyReports = reports;
      });
      
      await _drawSafetyMarkers();
    } catch (e) {
      print('🔴 Error loading reports: $e');
    }
  }

  Future<void> _drawSafetyMarkers() async {
    if (_map == null) return;
    
    try {
      _safetyMarkersManager ??= await _map!.annotations.createPointAnnotationManager();
      
      await _safetyMarkersManager!.deleteAll();
      
      for (var report in _nearbyReports) {
        Uint8List? icon;
        
        switch (report.type) {
          case 'dangerous_area':
            icon = _dangerIcon;
            break;
          case 'construction':
            icon = _constructionIcon;
            break;
          case 'poor_lighting':
            icon = _lightingIcon;
            break;
          case 'harassment':
            icon = _harassmentIcon;
            break;
          case 'isolated_area':
            icon = _isolatedIcon;
            break;
          case 'safe_spot':
            icon = _safeSpotIcon;
            break;
          default:
            icon = _dangerIcon;
        }
        
        if (icon == null) continue;
        
        await _safetyMarkersManager!.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(report.longitude, report.latitude),
            ),
            image: icon,
            iconSize: 2.0,
          ),
        );
      }
      
      print('🗺️ Drew ${_nearbyReports.length} safety markers');
    } catch (e) {
      print('🔴 Error drawing safety markers: $e');
    }
  }

  void _showReportDetails(SafetyReport report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(report.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    report.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.typeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        report.distanceKm != null
                            ? '${(report.distanceKm! * 1000).toStringAsFixed(0)}m away'
                            : 'Nearby',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (report.description != null) ...[
              const SizedBox(height: 16),
              Text(
                report.description!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  _formatTimeAgo(report.createdAt),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                Row(
                  children: [
                    Icon(Icons.thumb_up, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('${report.upvotes}'),
                    const SizedBox(width: 16),
                    Icon(Icons.thumb_down, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('${report.downvotes}'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  Future<Uint8List> _loadAssetImage(String path) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 32,
      targetHeight: 32,
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
      _checkCityChange(position);
      _loadNearbyReports();
      _pos = position;
      _updateUserMarker();

      if (_isNavigating && _destination != null) {
        if (_pos != null) {
          final currentPos = Position(_pos!.longitude, _pos!.latitude);
          
          if (_lastWalkedPosition == null) {
            _walkedPath.add(currentPos);
            _lastWalkedPosition = _pos;
            _drawFootsteps(_walkedPath);
          } else {
            double distance = Geo.Geolocator.distanceBetween(
              _lastWalkedPosition!.latitude,
              _lastWalkedPosition!.longitude,
              _pos!.latitude,
              _pos!.longitude,
            );
            
            if (distance >= 3) {
              _walkedPath.add(currentPos);
              _lastWalkedPosition = _pos;
              _drawFootsteps(_walkedPath);
            }
          }
        }

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
    if (_map == null || _pos == null) return;

    _userManager ??= await _map!.annotations.createPointAnnotationManager();

    if (_userMarker != null) {
      try {
        await _userManager!.delete(_userMarker!);
      } catch (e) {
        // Annotation might not be on map yet, safe to ignore
      }
    }

    final userEmoji = await _getUserEmoji();

    _userMarker = await _userManager!.create(
      PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(_pos!.longitude, _pos!.latitude),
        ),
        image: await _createEmojiMarker(userEmoji),
        iconSize: 1.5,
      ),
    );
  }
  
  Future<String> _getUserEmoji() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return '🚶‍♀️';
      
      final response = await supabase
        .from('profiles')
        .select('selected_emoji')
        .eq('id', userId)
        .maybeSingle();
      
      return response?['selected_emoji'] ?? '🚶‍♀️';
    } catch (e) {
      print('⚠️ Error loading emoji: $e');
      return '🚶‍♀️';
    }
  }

  Future<Uint8List> _createEmojiMarker(String emoji) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = 64.0;
    
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(size/2, size/2 + 2), size/2.5, shadowPaint);
    
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size/2, size/2), size/2.5, bgPaint);
    
    final borderPaint = Paint()
      ..color = Color(0xFF00AA55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset(size/2, size/2), size/2.5, borderPaint);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.6),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
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

  double _distanceToPolyline(Geo.Position point, List<Position> polyline) {
    if (polyline.isEmpty) return double.infinity;
    
    double minDistance = double.infinity;
    
    for (int i = 0; i < polyline.length - 1; i++) {
      final segmentStart = polyline[i];
      final segmentEnd = polyline[i + 1];
      
      final distance = _distanceToSegment(
        point.latitude, point.longitude,
        segmentStart.lat.toDouble(), segmentStart.lng.toDouble(),
        segmentEnd.lat.toDouble(), segmentEnd.lng.toDouble(),
      );
      
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    
    return minDistance;
  }
  
  double _distanceToSegment(
    double px, double py,
    double x1, double y1,
    double x2, double y2,
  ) {
    final segmentLength = Geo.Geolocator.distanceBetween(y1, x1, y2, x2);
    
    if (segmentLength == 0) {
      return Geo.Geolocator.distanceBetween(py, px, y1, x1);
    }
    
    final dx = x2 - x1;
    final dy = y2 - y1;
    final t = math.max(0, math.min(1, 
      ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    ));
    
    final closestX = x1 + t * dx;
    final closestY = y1 + t * dy;
    
    return Geo.Geolocator.distanceBetween(py, px, closestY, closestX);
  }
  
  void _checkIfOffRoute() {
    if (_lastRoutePoints == null || _lastRoutePoints!.isEmpty) return;
    if (_pos == null) return;

    if (_pos!.speed < 0.8) {
      _offRouteStartTime = null;
      _divergenceStartTime = null;
      return;
    }

    double distanceFromRoute = _distanceToPolyline(_pos!, _lastRoutePoints!);

    double progress = 0;
    if (_previousPos != null && _destination != null) {
      double distanceBefore = Geo.Geolocator.distanceBetween(
        _previousPos!.latitude, _previousPos!.longitude,
        _destination!.latitude, _destination!.longitude,
      );
    
      double distanceNow = Geo.Geolocator.distanceBetween(
        _pos!.latitude, _pos!.longitude,
        _destination!.latitude, _destination!.longitude,
      );
    
      progress = distanceBefore - distanceNow;
    }

    _recentProgress.add(progress);
    if (_recentProgress.length > 10) _recentProgress.removeAt(0);
  
    double avgProgress = _recentProgress.isEmpty ? 0 : 
      _recentProgress.reduce((a, b) => a + b) / _recentProgress.length;

    print("📊 Distance from route: ${distanceFromRoute.toStringAsFixed(1)}m, Progress: ${avgProgress.toStringAsFixed(1)}m/s");

    if (distanceFromRoute < 25 && avgProgress > -2) {
      if (_isOffRoute) {
        setState(() => _isOffRoute = false);
        print("✅ Back on route");
      }
      _offRouteStartTime = null;
      _divergenceStartTime = null;
      _previousPos = _pos;
      return;
    }

    if (_pos!.accuracy > 20) {
      print("🤔 UNCERTAIN: Poor GPS accuracy (${_pos!.accuracy.toStringAsFixed(0)}m)");
      _previousPos = _pos;
      return;
    }

    if (distanceFromRoute > 50) {
      if (_divergenceStartTime == null) {
        _divergenceStartTime = DateTime.now();
        print("⚠️ OFF-ROUTE detected: ${distanceFromRoute.toStringAsFixed(1)}m from route");
      } else {
        Duration divergenceDuration = DateTime.now().difference(_divergenceStartTime!);
      
        if (divergenceDuration.inSeconds > 8 && !_isOffRoute) {
          print("🔴 CONFIRMED OFF-ROUTE after ${divergenceDuration.inSeconds}s (distance: ${distanceFromRoute.toStringAsFixed(1)}m)");
          _handleOffRoute();
        }
      }
    } else {
      _divergenceStartTime = null;
    }

    _previousPos = _pos;
  }
  
  Future<void> _handleOffRoute() async {
    if (_destination == null || _pos == null) return;
    
    setState(() => _isOffRoute = true);
    
    print("🔄 Attempting silent re-routing...");
    print("📍 Current position: ${_pos!.latitude}, ${_pos!.longitude}");
    print("🎯 Destination: ${_destination!.latitude}, ${_destination!.longitude}");
    
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/walking/"
        "${_pos!.longitude},${_pos!.latitude};"
        "${_destination!.longitude},${_destination!.latitude}"
        "?geometries=geojson&steps=true&alternatives=true&access_token=$_token";

    try {
      print("🌐 Making API request...");
      final res = await http.get(Uri.parse(url));
      
      print("📡 API Response status: ${res.statusCode}");
      
      if (res.statusCode != 200) {
        print("🔴 API request failed with status: ${res.statusCode}");
        return;
      }

      final data = json.decode(res.body);
      if (data["routes"] == null || data["routes"].isEmpty) {
        print("🔴 No routes found in API response");
        return;
      }

      final routes = data["routes"] as List;
      routes.sort((a, b) => a["distance"].compareTo(b["distance"]));
      
      final newRoute = routes[0];
      final newDistance = (newRoute["distance"] as num).toDouble();
      final newDuration = (newRoute["duration"] as num).toDouble();
      
      final currentRemainingDistance = _remainingKm * 1000;
      
      print("📊 Route comparison:");
      print("  Original remaining: ${currentRemainingDistance.toStringAsFixed(0)}m");
      print("  New route: ${newDistance.toStringAsFixed(0)}m");
      
      if (newDistance <= currentRemainingDistance * 1.1) {
        print("✅ ACCEPTING NEW ROUTE (better or similar)");
        
        final coords = newRoute["geometry"]["coordinates"] as List;
        final List<Position> points = [];
        for (var c in coords) {
          if (c is List && c.length >= 2) {
            points.add(Position(
              (c[0] as num).toDouble(),
              (c[1] as num).toDouble(),
            ));
          }
        }
        
        _lastRoutePoints = points;
        _remainingKm = newDistance / 1000.0;
        _remainingMin = newDuration / 60.0;

        print("🎨 Redrawing route...");
        await _drawRoute(points);
        print("✅ Route redrawn successfully!");
        
        setState(() => _isOffRoute = false);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✨ Route updated to match your path"),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        print("⚠️ New route is longer, suggesting return");
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("📍 Suggested: Return to green route for shorter path"),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: "Recalculate",
              textColor: Colors.white,
              onPressed: () async {
                final coords = newRoute["geometry"]["coordinates"] as List;
                final List<Position> points = [];
                for (var c in coords) {
                  if (c is List && c.length >= 2) {
                    points.add(Position(
                      (c[0] as num).toDouble(),
                      (c[1] as num).toDouble(),
                    ));
                  }
                }
                
                _lastRoutePoints = points;
                _remainingKm = newDistance / 1000.0;
                _remainingMin = newDuration / 60.0;
                
                await _drawRoute(points);
                
                setState(() => _isOffRoute = false);
              },
            ),
          ),
        );
      }
    } catch (e) {
      print("🔴 Re-routing failed with exception: $e");
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
      _walkedPath.clear();
      _lastWalkedPosition = null;
      _isTransitMode = false;
      _transitLegs.clear();
      _transitKm = 0;
      _transitMin = 0;
      _walkKm = 0;
      _walkMin = 0;
    });

    _lineManager?.deleteAll();
    _stepsManager?.deleteAll();
  }

  void _startNavigation() {
    if (_destination == null || _lastRoutePoints == null) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    print("🟢 Starting navigation...");

    setState(() {
      _isNavigating = true;
      _routePreviewMode = false;
      _walkedPath.clear();
      _lastWalkedPosition = null;
    });

    WakelockPlus.enable();

    if (_pos != null) {
      final bearing = _pos!.heading >= 0 ? _pos!.heading : 0.0;
      _moveTo(_pos!.latitude, _pos!.longitude, zoom: 18.5, bearing: bearing, pitch: 45);
    }

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
      print("⏭️ Query too short: '$q' (${q.length} chars)");
      setState(() => _suggestions.clear());
      return;
    }

    print("🔵 Searching for: '$q' (${q.length} chars)");

    final lowerQ = q.toLowerCase();
    final isPOI = _isPOIQuery(lowerQ);

    print("🔍 Query type: ${isPOI ? 'POI (Google Places)' : 'Address (Mapbox)'}");

    if (isPOI) {
      print("🟢 Using GOOGLE PLACES for POI search");
      await _searchGooglePlaces(q);
    } else {
      print("🟡 Using MAPBOX for address search");
      await _searchMapbox(q);
    }
  }

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

    for (var keyword in poiKeywords) {
      if (query.contains(keyword)) return true;
    }

    if (RegExp(r'^\d+\s+\w+').hasMatch(query)) return false;

    if (query.length <= 15 && !query.contains(RegExp(r'\d'))) return true;

    return false;
  }

  Future<void> _searchGooglePlaces(String q) async {
    if (_pos == null) return;

    String apiKey;
    try {
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        apiKey = _googlePlacesKeyIOS;
      } else {
        apiKey = _googlePlacesKeyAndroid;
      }
    } catch (e) {
      apiKey = _googlePlacesKeyAndroid;
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
    // Fechar teclado
    FocusScope.of(context).unfocus();
    
    _search.text = s.name;
    setState(() => _suggestions.clear());

    await PreferencesService.addRecentSearch(s.name);

    await Future.delayed(const Duration(milliseconds: 200));
    await _createRouteTo(s.lat, s.lon);
  }

  Future<void> _createRouteTo(double destLat, double destLon) async {
    if (_pos == null) return;

    // Reset transit mode
    _isTransitMode = false;
    _transitLegs.clear();

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

    // Guardar distância walk para comparação com transit
    _walkKm = _remainingKm;
    _walkMin = _remainingMin;

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

    if (_isLoggedIn) {
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

    print("🟡 Drawing route line...");
    await _drawRoute(points);
    print("🟢 Route line drawn!");

    _routePreviewMode = true;
    _isNavigating = false;
    
    if (!mounted) return;
    setState(() {});

    print("🟢 UI updated - route preview mode active");

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

  Future<void> _drawFootsteps(List<Position> walkedPath) async {
    if (_map == null || walkedPath.length < 2) {
      return;
    }
    
    if (_footLeft == null || _footRight == null) {
      return;
    }

    try {
      if (_stepsManager == null) {
        _stepsManager = await _map!.annotations.createPointAnnotationManager();
      } else {
        await _stepsManager!.deleteAll();
      }

      bool isLeftFoot = true;
      int footstepCount = 0;

      // ✅ LIMITAR a últimas 50 pegadas (performance) + excluir posição atual (não tapar emoji)
      final pathToShow = walkedPath.length > 50
        ? walkedPath.sublist(walkedPath.length - 50)
        : walkedPath;

      for (int i = 0; i < pathToShow.length - 1; i++) {
        Position current = pathToShow[i];
        Position? next = i + 1 < pathToShow.length ? pathToShow[i + 1] : null;

        double bearing = 0;
        if (next != null) {
          bearing = _calculateBearing(
            current.lat.toDouble(),
            current.lng.toDouble(),
            next.lat.toDouble(),
            next.lng.toDouble(),
          );
        }

        await _stepsManager!.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: current),
            image: isLeftFoot ? _footLeft! : _footRight!,
            iconSize: 3.0,
            iconRotate: bearing,
            iconOpacity: 1.0,
            iconAnchor: IconAnchor.CENTER,
          ),
        );

        footstepCount++;
        isLeftFoot = !isLeftFoot;
      }

      print("🟢 Drew $footstepCount footsteps on walked path!");
    } catch (e) {
      print("🔴 ERROR drawing footsteps: $e");
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

    // Verificar se clicou perto de um safety report
    final touchCoord = ctx.point.coordinates;
    for (var report in _nearbyReports) {
      final distance = Geo.Geolocator.distanceBetween(
        touchCoord.lat.toDouble(),
        touchCoord.lng.toDouble(),
        report.latitude,
        report.longitude,
      );
      
      if (distance < 50) {
        _showReportDetails(report);
        return;
      }
    }

    // Verificar se clicou perto de um pin de categoria
    if (_showingCategoryPins && _categoryPlaces.isNotEmpty) {
      Map<String, dynamic>? closestPlace;
      double closestDistance = double.infinity;
      
      for (var place in _categoryPlaces) {
        final distance = Geo.Geolocator.distanceBetween(
          touchCoord.lat.toDouble(),
          touchCoord.lng.toDouble(),
          place['lat'],
          place['lng'],
        );
        
        if (distance < closestDistance) {
          closestDistance = distance;
          closestPlace = place;
        }
      }
      
      // Se clicou a menos de 80 metros de um lugar
      if (closestPlace != null && closestDistance < 80) {
        _showPlaceDetails(closestPlace);
        return;
      }
    }

    // Query risk layer (wrapped in try-catch to prevent crash)
    try {
      final screenPoint = ctx.touchPosition;
      final results = await _map!.queryRenderedFeatures(
        RenderedQueryGeometry(
          type: Type.SCREEN_COORDINATE,
          value: jsonEncode({
            "x": screenPoint.x,
            "y": screenPoint.y,
          }),
        ),
        RenderedQueryOptions(layerIds: ["risk-layer"]),
      );

      if (results.isEmpty) return;

      final f = results.first?.queriedFeature.feature;
      if (f == null) return;

      final Map<String, dynamic> jsonData = jsonDecode(jsonEncode(f));
      final risk = jsonData["properties"]?["risk"] ?? 1;

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
    } catch (e) {
      // Silently ignore queryRenderedFeatures errors
      // This happens with some Mapbox Flutter versions
      print("⚠️ queryRenderedFeatures error (safe to ignore): $e");
    }
  }

  Color _riskColor(dynamic r) {
    final v = r is num ? r.toInt() : int.tryParse("$r") ?? 1;
    return [Colors.green, Colors.yellow, Colors.orange, Colors.red]
        [(v - 1).clamp(0, 3)];
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _positionStream?.cancel();
    _search.dispose();
    WakelockPlus.disable();
    _safetyMarkersManager?.deleteAll();
    _categoryPinsManager?.deleteAll();  // Limpar pins de categoria

    if (_pos != null) {
      PreferencesService.saveLastLocation(
        _pos!.latitude,
        _pos!.longitude,
     );
     print('💾 location saved');
   }

    super.dispose();
  }

  // ============================================================
  // GUEST MODE HELPERS
  // ============================================================

  bool get _isLoggedIn => supabase.auth.currentUser != null;

  Future<bool> _requireLogin(String feature) async {
    if (_isLoggedIn) return true;

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => _LoginSheet(feature: feature),
    );

    return result == true;
  }

  // ✅ MÉTODOS DOS BOTÕES DE CATEGORIA (adicionar ANTES do @override Widget build)

  // ============================================================
  // TRANSIT ROUTES (Tarefa 5)
  // ============================================================

  Future<void> _createTransitRoute(double destLat, double destLon) async {
    if (_pos == null) return;

    String apiKey;
    try {
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        apiKey = _googlePlacesKeyIOS;
      } else {
        apiKey = _googlePlacesKeyAndroid;
      }
    } catch (e) {
      apiKey = _googlePlacesKeyAndroid;
    }

    final url = "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${_pos!.latitude},${_pos!.longitude}"
        "&destination=$destLat,$destLon"
        "&mode=transit"
        "&alternatives=true"
        "&key=$apiKey";

    try {
      print("🚌 Fetching transit route...");
      print("🚌 URL: $url");
      final res = await http.get(Uri.parse(url));

      print("🚌 HTTP status: ${res.statusCode}");
      print("🚌 Response body (first 500 chars): ${res.body.substring(0, res.body.length > 500 ? 500 : res.body.length)}");

      if (res.statusCode != 200) {
        print("🔴 Google Directions error: ${res.statusCode}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transit route not available'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final data = json.decode(res.body);

      if (data["status"] != "OK") {
        print("🔴 Google Directions status: ${data['status']}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No transit routes found: ${data["status"]}'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final routes = data["routes"] as List;
      if (routes.isEmpty) return;

      // Usar primeira rota (melhor)
      final route = routes[0];
      final legs = route["legs"] as List;
      final leg = legs[0]; // Single origin-destination

      final double totalMeters = (leg["distance"]["value"] as num).toDouble();
      final double totalSeconds = (leg["duration"]["value"] as num).toDouble();

      _transitKm = totalMeters / 1000.0;
      _transitMin = totalSeconds / 60.0;

      // Extrair steps (cada step é walking ou transit)
      final steps = leg["steps"] as List;
      _transitLegs.clear();

      List<Position> allPoints = [];

      for (var step in steps) {
        final travelMode = step["travel_mode"] as String; // WALKING ou TRANSIT
        final polyline = step["polyline"]["points"] as String;
        final points = _decodePolyline(polyline);

        String transitInfo = '';
        String transitShortName = '';
        String vehicleType = '';

        if (travelMode == "TRANSIT" && step["transit_details"] != null) {
          final transit = step["transit_details"];
          final line = transit["line"];
          transitShortName = line["short_name"] ?? line["name"] ?? '';
          vehicleType = line["vehicle"]?["type"] ?? '';
          final departureStop = transit["departure_stop"]?["name"] ?? '';
          final arrivalStop = transit["arrival_stop"]?["name"] ?? '';
          final numStops = transit["num_stops"] ?? 0;
          transitInfo = '$transitShortName: $departureStop → $arrivalStop ($numStops stops)';
        }

        _transitLegs.add({
          'mode': travelMode,
          'points': points,
          'distance': (step["distance"]["value"] as num).toDouble(),
          'duration': (step["duration"]["value"] as num).toDouble(),
          'instructions': step["html_instructions"] ?? '',
          'transit_info': transitInfo,
          'transit_short_name': transitShortName,
          'vehicle_type': vehicleType,
        });

        allPoints.addAll(points);
      }

      print("🚌 Transit route: ${_transitLegs.length} legs, ${_transitKm.toStringAsFixed(1)}km, ${_transitMin.toStringAsFixed(0)}min");

      // Guardar pontos para bounds
      _lastRoutePoints = allPoints;

      // Desenhar rota multi-cor
      await _drawTransitRoute();

      setState(() {
        _isTransitMode = true;
        _remainingKm = _transitKm;
        _remainingMin = _transitMin;
        _routePreviewMode = true;
        _isNavigating = false;
      });

      _fitRouteBounds(allPoints);

    } catch (e) {
      print("🔴 Transit route error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error loading transit route'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Decode Google's encoded polyline
  List<Position> _decodePolyline(String encoded) {
    List<Position> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(Position(lng / 1E5, lat / 1E5));
    }

    return points;
  }

  /// Draw transit route with different colors per leg
  Future<void> _drawTransitRoute() async {
    if (_map == null) return;

    try {
      _lineManager ??= await _map!.annotations.createPolylineAnnotationManager();
      await _lineManager!.deleteAll();

      for (var leg in _transitLegs) {
        final List<Position> points = leg['points'];
        final String mode = leg['mode'];

        if (points.length < 2) continue;

        // Verde para walking, azul para transit
        final int color = mode == 'TRANSIT' ? 0xFF2196F3 : 0xFF00AA55;
        final double width = mode == 'TRANSIT' ? 8.0 : 5.0;

        await _lineManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: points),
            lineColor: color,
            lineWidth: width,
            lineOpacity: 0.9,
          ),
        );
      }

      print("🎨 Drew ${_transitLegs.length} transit route segments");
    } catch (e) {
      print("🔴 Error drawing transit route: $e");
    }
  }

  /// Switch between walk and transit mode
  Future<void> _toggleTransitMode() async {
    if (_destination == null) return;

    if (_isTransitMode) {
      // Switch to walk-only
      setState(() => _isTransitMode = false);
      _remainingKm = _walkKm;
      _remainingMin = _walkMin;

      // Redraw walking route
      final url =
          "https://api.mapbox.com/directions/v5/mapbox/walking/"
          "${_pos!.longitude},${_pos!.latitude};"
          "${_destination!.longitude},${_destination!.latitude}"
          "?geometries=geojson&steps=true&access_token=$_token";

      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final routes = data["routes"] as List;
          if (routes.isNotEmpty) {
            routes.sort((a, b) => a["distance"].compareTo(b["distance"]));
            final coords = routes[0]["geometry"]["coordinates"] as List;
            final List<Position> points = [];
            for (var c in coords) {
              if (c is List && c.length >= 2) {
                points.add(Position(
                  (c[0] as num).toDouble(),
                  (c[1] as num).toDouble(),
                ));
              }
            }
            _lastRoutePoints = points;
            await _drawRoute(points);
            _fitRouteBounds(points);
          }
        }
      } catch (e) {
        print("🔴 Error switching to walk: $e");
      }

      setState(() {});
    } else {
      // Switch to transit
      await _createTransitRoute(
        _destination!.latitude,
        _destination!.longitude,
      );
    }
  }

  // ============================================================
  // PLACE DETAILS MODAL (tap em pin de categoria)
  // ============================================================

  void _showPlaceDetails(Map<String, dynamic> place) {
    final name = place['name'] ?? 'Unknown';
    final address = place['address'] ?? '';
    final rating = place['rating'] ?? '';
    final isOpen = place['isOpen'];
    final category = place['category'] ?? '';
    final lat = place['lat'] as double;
    final lng = place['lng'] as double;
    
    // Calcular distância
    double distanceMeters = 0;
    if (_pos != null) {
      distanceMeters = Geo.Geolocator.distanceBetween(
        _pos!.latitude, _pos!.longitude, lat, lng,
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Nome e info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (address.isNotEmpty)
                        Text(
                          address,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Distância
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6AA57A).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              distanceMeters < 1000
                                  ? '${distanceMeters.toStringAsFixed(0)}m'
                                  : '${(distanceMeters / 1000).toStringAsFixed(1)}km',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6AA57A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Rating
                          if (rating.isNotEmpty) ...[
                            const Icon(Icons.star, size: 16, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(rating, style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                          ],
                          // Open/Closed
                          if (isOpen != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOpen
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isOpen ? 'Open' : 'Closed',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isOpen ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Botão Walk Here
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Fecha modal
                  _clearCategoryPins(); // Limpa pins
                  _createRouteTo(lat, lng); // Cria rota
                },
                icon: const Icon(Icons.directions_walk, size: 24),
                label: Text(
                  'Walk here (${distanceMeters < 1000 ? '${distanceMeters.toStringAsFixed(0)}m' : '${(distanceMeters / 1000).toStringAsFixed(1)}km'})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6AA57A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EXPLORE AROUND ME (Tarefa 2)
  // ============================================================

  void _showExploreModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Título
            const Text(
              'Around Me',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Categorias
            _buildCategoryTile('☕', 'Cafés', 'café'),
            _buildCategoryTile('🍽️', 'Restaurants', 'restaurant'),
            _buildCategoryTile('💊', 'Pharmacies', 'pharmacy'),
            _buildCategoryTile('🏪', 'Supermarkets', 'supermarket'),
            _buildCategoryTile('🏥', 'Hospitals', 'hospital'),
            _buildCategoryTile('🏛️', 'Attractions', 'tourist_attraction'),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(String emoji, String label, String query) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 32)),
      title: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        Navigator.pop(context); // Fecha modal
        _searchAndShowCategoryPins(query, label);
      },
    );
  }

  Future<void> _searchAndShowCategoryPins(String query, String categoryLabel) async {
    if (_pos == null) {
      print('🔴 Explore: _pos is null!');
      return;
    }
    
    print('🔍 Explore: Searching $categoryLabel ($query) near ${_pos!.latitude},${_pos!.longitude}');
    
    setState(() {
      _showingCategoryPins = true;
      _activeCategoryType = categoryLabel;
    });
    
    // Limpar pins anteriores
    if (_categoryPinsManager != null) {
      await _categoryPinsManager!.deleteAll();
    }
    
    // Buscar lugares via Google Places
    String apiKey;
    try {
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        apiKey = _googlePlacesKeyIOS;
      } else {
        apiKey = _googlePlacesKeyAndroid;
      }
    } catch (e) {
      apiKey = _googlePlacesKeyAndroid;
    }
    
    final url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
        "?location=${_pos!.latitude},${_pos!.longitude}"
        "&radius=1000"
        "&type=$query"
        "&key=$apiKey";
    
    print('🌐 Explore URL: $url');
    
    try {
      final res = await http.get(Uri.parse(url));
      
      print('📡 Explore response: ${res.statusCode}');
      
      if (res.statusCode != 200) {
        print('🔴 Explore: HTTP error ${res.statusCode}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching $categoryLabel: ${res.statusCode}')),
        );
        return;
      }
      
      final data = json.decode(res.body);
      print('📡 Explore API status: ${data["status"]}');
      
      final List results = data["results"] ?? [];
      
      if (results.isEmpty) {
        print('🔴 Explore: No results found');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No $categoryLabel found nearby')),
        );
        return;
      }
      
      print('✅ Explore: Found ${results.length} $categoryLabel');
      
      // Criar pins no mapa
      await _drawCategoryPins(results, categoryLabel);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Showing ${results.length} $categoryLabel nearby'),
          backgroundColor: const Color(0xFF6AA57A),
          action: SnackBarAction(
            label: 'Clear',
            textColor: Colors.white,
            onPressed: _clearCategoryPins,
          ),
        ),
      );
      
    } catch (e) {
      print('Error searching category: $e');
    }
  }

  Future<void> _drawCategoryPins(List results, String categoryLabel) async {
    if (_map == null) return;
    
    // Guardar dados dos lugares para tap
    _categoryPlaces.clear();
    
    try {
      _categoryPinsManager ??= await _map!.annotations.createPointAnnotationManager();
      await _categoryPinsManager!.deleteAll();
      
      // Escolher cor por categoria
      Color pinColor;
      switch (categoryLabel) {
        case 'Cafés':
          pinColor = const Color(0xFF8B4513); // Marrom
          break;
        case 'Restaurants':
          pinColor = const Color(0xFFFF5722); // Laranja
          break;
        case 'Pharmacies':
          pinColor = const Color(0xFF4CAF50); // Verde
          break;
        case 'Supermarkets':
          pinColor = const Color(0xFF2196F3); // Azul
          break;
        case 'Hospitals':
          pinColor = const Color(0xFFE53935); // Vermelho
          break;
        default:
          pinColor = const Color(0xFF9C27B0); // Roxo
      }
      
      // Criar pin colorido
      final pinIcon = await _createColoredPin(pinColor);
      
      for (var place in results.take(15)) { // Máximo 15 pins
        final lat = place['geometry']['location']['lat'];
        final lng = place['geometry']['location']['lng'];
        final name = place['name'] ?? 'Unknown';
        final address = place['vicinity'] ?? '';
        final rating = place['rating']?.toString() ?? '';
        final isOpen = place['opening_hours']?['open_now'];
        
        // Guardar dados para tap
        _categoryPlaces.add({
          'name': name,
          'address': address,
          'lat': (lat as num).toDouble(),
          'lng': (lng as num).toDouble(),
          'rating': rating,
          'isOpen': isOpen,
          'category': categoryLabel,
        });
        
        await _categoryPinsManager!.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: Position(lng, lat)),
            image: pinIcon,
            iconSize: 1.2,
          ),
        );
      }
      
      print('📍 Saved ${_categoryPlaces.length} places for tap detection');
      
    } catch (e) {
      print('Error drawing pins: $e');
    }
  }

  Future<Uint8List> _createColoredPin(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = 48.0;
    
    // Pin shape (teardrop)
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);
    
    final path = Path();
    path.addOval(Rect.fromCircle(center: Offset(size/2, size/3), radius: size/3));
    path.moveTo(size/2, size/3 + size/3);
    path.lineTo(size/2 - 8, size - 8);
    path.lineTo(size/2, size);
    path.lineTo(size/2 + 8, size - 8);
    path.close();
    
    canvas.drawPath(path.shift(const Offset(2, 2)), shadowPaint);
    canvas.drawPath(path, paint);
    
    // Borda branca
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, borderPaint);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  void _clearCategoryPins() {
    setState(() {
      _showingCategoryPins = false;
      _activeCategoryType = null;
      _categoryPlaces.clear();
    });
    _categoryPinsManager?.deleteAll();
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

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/home');
        return false;
      },
      child: Scaffold(
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
                }

                await _loadNearbyReports();
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
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isTransitMode ? Icons.directions_transit : Icons.directions_walk,
                            color: _isTransitMode ? const Color(0xFF2196F3) : const Color(0xFF6AA57A),
                            size: 28,
                          ),
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
                                "${_remainingMin.toStringAsFixed(0)} min ${_isNavigating ? 'remaining' : (_isTransitMode ? 'transit + walk' : 'walk')}",
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Transit legs info
                      if (_isTransitMode && _transitLegs.isNotEmpty && _routePreviewMode) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...(_transitLegs.where((l) => l['mode'] == 'TRANSIT').map((leg) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    leg['transit_short_name'] != '' 
                                      ? leg['transit_short_name'] 
                                      : leg['vehicle_type'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    leg['transit_info'],
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                      ],
                      // Toggle walk/transit (só na preview)
                      if (_routePreviewMode && !_isNavigating && _destination != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _toggleTransitMode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isTransitMode 
                                ? const Color(0xFF00AA55).withOpacity(0.2) 
                                : const Color(0xFF2196F3).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isTransitMode ? Icons.directions_walk : Icons.directions_transit,
                                  size: 18,
                                  color: _isTransitMode 
                                    ? const Color(0xFF00AA55) 
                                    : const Color(0xFF2196F3),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isTransitMode 
                                    ? 'Switch to Walk (${_walkMin.toStringAsFixed(0)} min)' 
                                    : 'Switch to Transit',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _isTransitMode 
                                      ? const Color(0xFF00AA55) 
                                      : const Color(0xFF2196F3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Botão flutuante para reportar problemas
          Positioned(
            bottom: 100,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'report',
              onPressed: () => _showReportDialog(context),
              backgroundColor: Colors.red,
              child: const Icon(Icons.warning, color: Colors.white),
            ),
          ),

          // BOTÃO EXPLORE AROUND ME
          if (!_isNavigating && !_routePreviewMode)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _showExploreModal,
                  icon: const Icon(Icons.explore, size: 28),
                  label: const Text(
                    'Explore Around Me',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6AA57A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 8,
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

          // ✅ TAREFA 1: SEARCH BAR (sem category buttons!) + top: 60
          Positioned(
            top: 60,
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
    ),
  );
}

  Widget _buildSearchBar() {
  return Column(
    children: [
      Container(
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
      ),
      
      if (_search.text.isEmpty && _suggestions.isEmpty)
        _buildRecentSearches(),
    ],
  );
}

  Widget _buildRecentSearches() {
  final recent = PreferencesService.getRecentSearches();
  
  if (recent.isEmpty) return const SizedBox.shrink();
  
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'recent searches',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await PreferencesService.clearRecentSearches();
                  setState(() {});
                },
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6AA57A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        ...recent.map((search) => ListTile(
          dense: true,
          leading: const Icon(Icons.history, color: Colors.grey, size: 20),
          title: Text(search),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          onTap: () {
            _search.text = search;
            _searchPlaces(search);
          },
        )).toList(),
      ],
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

  Future<void> _checkCityChange(Geo.Position position) async {
    if (!_isLoggedIn) return;

    if (_lastCityCheck != null &&
        DateTime.now().difference(_lastCityCheck!).inMinutes < 5) {
      return;
    }

    _lastCityCheck = DateTime.now();

    try {
      final city = await _cityService.detectCity(
        position.latitude,
        position.longitude,
      );

      if (city == null) return;

      final cityId = city['id'] as String;

      final alreadyConfirmed = await _cityService.hasConfirmedCity(cityId);
      if (alreadyConfirmed) {
        print('✅ City already confirmed: ${city['name']}');
        _currentCityId = cityId;
        return;
      }

      if (cityId != _currentCityId) {
        _currentCityId = cityId;

        if (!mounted) return;

        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => CityConfirmationDialog(
            cityName: city['name'] as String,
            country: city['country'] as String,
            flag: _getFlag(city['country'] as String),
            onConfirm: () => Navigator.pop(context, true),
            onCancel: () => Navigator.pop(context, false),
          ),
        );

        if (confirm == true) {
          await _cityService.saveUserCity(cityId);
          _addLog('📍 City Confirmed: ${city['name']}');

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${city['name']} confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('⚠️ City check error: $e');
    }
  }

  String _getFlag(String country) {
    final flags = {
      'Netherlands': '🇳🇱',
      'Italy': '🇮🇹',
      'Brazil': '🇧🇷',
      'Portugal': '🇵🇹',
      'USA': '🇺🇸',
      'Spain': '🇪🇸',
      'France': '🇫🇷',
      'Germany': '🇩🇪',
      'United Kingdom': '🇬🇧',
    };
    return flags[country] ?? '🌍';
  }

  void _addLog(String message) {
    debugPrint(message);
  }

  void _showReportDialog(BuildContext context) async {
    final loggedIn = await _requireLogin('report safety issues');
    if (!loggedIn) return;

    String? selectedType;
    final descController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final reportOptions = [
            {'type': 'dangerous_area', 'label': 'Dangerous Area', 'icon': Icons.local_police, 'color': Colors.red},
            {'type': 'harassment', 'label': 'Harassment / Unsafe', 'icon': Icons.sentiment_very_dissatisfied, 'color': Colors.purple},
            {'type': 'isolated_area', 'label': 'Isolated Area', 'icon': Icons.person_off, 'color': Colors.blueGrey},
            {'type': 'poor_lighting', 'label': 'Poor Lighting', 'icon': Icons.lightbulb_outline, 'color': Colors.amber},
            {'type': 'construction', 'label': 'Construction / Obstacle', 'icon': Icons.construction, 'color': Colors.orange},
            {'type': 'safe_spot', 'label': 'Safe Spot', 'icon': Icons.check_circle, 'color': Colors.green},
          ];

          return Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Text('What is happening here?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...reportOptions.map((opt) {
                  final isSelected = selectedType == opt['type'];
                  final color = opt['color'] as Color;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedType = opt['type'] as String),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.15) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.grey[200]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(opt['icon'] as IconData, color: color, size: 22),
                          const SizedBox(width: 12),
                          Text(opt['label'] as String, style: TextStyle(fontSize: 15, color: isSelected ? color : Colors.black87, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    hintText: 'Optional description (e.g. dark street near the park)',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[300]!)),
                  ),
                  maxLines: 2,
                  maxLength: 120,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedType == null
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _createReport(selectedType!, description: descController.text.trim().isEmpty ? null : descController.text.trim());
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9CAF88),
                      disabledBackgroundColor: Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Submit', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    descController.dispose();
  }

  Future<void> _createReport(String type, {String? description}) async {
    print('🟡 Trying to create report...');
    print('📍 Current location: $_pos');
    print('👤 User ID: ${Supabase.instance.client.auth.currentUser?.id}');
  
    if (_pos == null) {
      print('❌ Location not available!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting location...')),
     );
     return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
  
    if (userId == null) {
      print('❌ User not authenticated!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: not authenticated')),
      );
      return;
    }

    try {
      print('🔵 Inserting into Supabase...');
      print('   Type: $type');
      print('   Lat: ${_pos!.latitude}');
      print('   Lon: ${_pos!.longitude}');
      print('   User ID: $userId');
    
      final response = await Supabase.instance.client
          .from('safety_reports')
          .insert({
            'type': type,
            'latitude': _pos!.latitude,
            'longitude': _pos!.longitude,
            'user_id': userId,
            'created_at': DateTime.now().toIso8601String(),
            if (description != null) 'description': description,
          })
          .select();

      print('✅ Response do Supabase: $response');

      _lastReportsRefresh = null;
      await _loadNearbyReports();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Report created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Error: $e');
      print('❌ Error type: ${e.runtimeType}');
    
      if (!mounted) return;
    
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
} 

class _LoginSheet extends StatefulWidget {
  final String feature;
  const _LoginSheet({required this.feature});

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  bool _loading = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        Navigator.pop(context, true);
      }
    }, onError: (error) {
      // Sem isto, uma falha no callback OAuth deixava o spinner a girar
      // para sempre dentro da sheet, sem qualquer feedback.
      print('❌ Login error: $error');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await AuthService().signInWithGoogle();
    } catch (e) {
      print('❌ Login error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Icon(Icons.account_circle, size: 56, color: Color(0xFF9CAF88)),
          const SizedBox(height: 16),
          const Text(
            'Sign in required',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to ${widget.feature}',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9CAF88)))
                : ElevatedButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login, size: 20),
                    label: const Text(
                      'Continue with Google',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9CAF88),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Not now',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
        ],
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