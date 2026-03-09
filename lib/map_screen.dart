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
import 'services/safety_service.dart';  // ✅ NOVO IMPORT
import 'widgets/city_confirmation_dialog.dart';
import '../services/preferences_service.dart';

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

  // ✅ NOVO: Safety Reports
  final SafetyService _safetyService = SafetyService();
  List<SafetyReport> _nearbyReports = [];
  PointAnnotationManager? _safetyMarkersManager;
  DateTime? _lastReportsRefresh;
  Uint8List? _dangerIcon;
  Uint8List? _constructionIcon;
  Uint8List? _lightingIcon;

  @override
  void initState() {
    super.initState();
    // Carrega última localização
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
    _loadSafetyIcons();  // ✅ NOVO
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

  // ✅ Carregar ícones de safety com símbolos
  Future<void> _loadSafetyIcons() async {
    _dangerIcon = await _createIconWithSymbol(Icons.local_police, Colors.red, 40);
    _constructionIcon = await _createIconWithSymbol(Icons.construction, Colors.orange, 40);
    _lightingIcon = await _createIconWithSymbol(Icons.lightbulb_outline, Colors.amber, 40);
    print('✅ Safety icons loaded');
  }

  // ✅ Criar ícone com símbolo
  Future<Uint8List> _createIconWithSymbol(IconData icon, Color color, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Fundo branco circular com sombra
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
    
    // Sombra
    canvas.drawCircle(center + const Offset(1, 2), radius, shadowPaint);
    
    // Fundo branco
    canvas.drawCircle(center, radius, bgPaint);
    
    // Borda colorida
    canvas.drawCircle(center, radius, borderPaint);
    
    // Desenhar ícone
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

  // ✅ NOVO: Carregar reports próximos
  Future<void> _loadNearbyReports() async {
    if (_pos == null) return;
    
    // Só atualiza a cada 2 minutos
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

  // ✅ NOVO: Desenhar markers de safety no mapa
  Future<void> _drawSafetyMarkers() async {
    if (_map == null) return;
    
    try {
      // Criar manager se não existir
      _safetyMarkersManager ??= await _map!.annotations.createPointAnnotationManager();
      
      // Limpar markers antigos
      await _safetyMarkersManager!.deleteAll();
      
      // Adicionar novos markers
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
            iconSize: 1.0,
          ),
        );
      }
      
      print('🗺️ Drew ${_nearbyReports.length} safety markers');
    } catch (e) {
      print('🔴 Error drawing safety markers: $e');
    }
  }

  // ✅ NOVO: Mostrar detalhes do report
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
      _loadNearbyReports();  // ✅ NOVO: Atualizar reports
      _pos = position;
      _updateUserMarker();

      if (_isNavigating && _destination != null) {
        // Registrar caminho percorrido e desenhar pegadas
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
            
            // Adicionar pegada a cada 3 metros
            if (distance >= 3) {
              _walkedPath.add(currentPos);
              _lastWalkedPosition = _pos;
              _drawFootsteps(_walkedPath);
            }
          }
        }

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
  if (_map == null || _pos == null) return;

  _userManager ??= await _map!.annotations.createPointAnnotationManager();

  if (_userMarker != null) {
    await _userManager!.delete(_userMarker!);
  }

  // ✅ NOVO: Buscar emoji do user
  final userEmoji = await _getUserEmoji();

  _userMarker = await _userManager!.create(
    PointAnnotationOptions(
      geometry: Point(
        coordinates: Position(_pos!.longitude, _pos!.latitude),
      ),
      image: await _createEmojiMarker(userEmoji),  // ✅ Emoji!
      iconSize: 1.5,  // ✅ Tamanho maior
    ),
  );
}
  
  // ✅ NOVO: Buscar emoji do perfil
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

// ✅ NOVO: Criar imagem do emoji
Future<Uint8List> _createEmojiMarker(String emoji) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = 64.0;
  
  // Sombra
  final shadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.3)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
  canvas.drawCircle(Offset(size/2, size/2 + 2), size/2.5, shadowPaint);
  
  // Fundo branco circular
  final bgPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(size/2, size/2), size/2.5, bgPaint);
  
  // Borda verde
  final borderPaint = Paint()
    ..color = Color(0xFF00AA55)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  canvas.drawCircle(Offset(size/2, size/2), size/2.5, borderPaint);
  
  // Emoji
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

  // ===================================================================
  // PROFESSIONAL PEDESTRIAN NAVIGATION
  // ===================================================================
  
  /// Calculate shortest distance from point to polyline (route)
  double _distanceToPolyline(Geo.Position point, List<Position> polyline) {
    if (polyline.isEmpty) return double.infinity;
    
    double minDistance = double.infinity;
    
    // Check distance to each segment of the polyline
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
  
  /// Calculate distance from point to line segment
  double _distanceToSegment(
    double px, double py,  // Point
    double x1, double y1,  // Segment start
    double x2, double y2,  // Segment end
  ) {
    // Convert to meters for accurate calculation
    final segmentLength = Geo.Geolocator.distanceBetween(y1, x1, y2, x2);
    
    if (segmentLength == 0) {
      // Segment is a point
      return Geo.Geolocator.distanceBetween(py, px, y1, x1);
    }
    
    // Calculate projection parameter
    final dx = x2 - x1;
    final dy = y2 - y1;
    final t = math.max(0, math.min(1, 
      ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    ));
    
    // Find closest point on segment
    final closestX = x1 + t * dx;
    final closestY = y1 + t * dy;
    
    // Return distance to closest point
    return Geo.Geolocator.distanceBetween(py, px, closestY, closestX);
  }
  
  /// Smart off-route detection with tolerance
  void _checkIfOffRoute() {
    if (_lastRoutePoints == null || _lastRoutePoints!.isEmpty) return;
    if (_pos == null) return;

    // Only check if moving (avoid GPS drift when stationary)
    if (_pos!.speed < 0.8) {
      // Reset off-route timer when stationary
      _offRouteStartTime = null;
      _divergenceStartTime = null;
      return;
    }

    // Check distance from route line
    double distanceFromRoute = _distanceToPolyline(_pos!, _lastRoutePoints!);

    // Calculate if user is making progress toward destination
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
    
      progress = distanceBefore - distanceNow; // Positive = getting closer
    }

    // Track recent progress
    _recentProgress.add(progress);
    if (_recentProgress.length > 10) _recentProgress.removeAt(0);
  
    double avgProgress = _recentProgress.isEmpty ? 0 : 
      _recentProgress.reduce((a, b) => a + b) / _recentProgress.length;

    print("📊 Distance from route: ${distanceFromRoute.toStringAsFixed(1)}m, Progress: ${avgProgress.toStringAsFixed(1)}m/s");

    // DECISION LOGIC

    // 1. Close to route AND making progress? ON ROUTE
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

    // 2. Poor GPS? UNCERTAIN (stay silent)
    if (_pos!.accuracy > 20) {
      print("🤔 UNCERTAIN: Poor GPS accuracy (${_pos!.accuracy.toStringAsFixed(0)}m)");
      _previousPos = _pos;
      return;
    }

    // 3. FAR from route (>50m)? Trigger off-route
    if (distanceFromRoute > 50) {
      if (_divergenceStartTime == null) {
        _divergenceStartTime = DateTime.now();
        print("⚠️ OFF-ROUTE detected: ${distanceFromRoute.toStringAsFixed(1)}m from route");
      } else {
        Duration divergenceDuration = DateTime.now().difference(_divergenceStartTime!);
      
        // Wait 8 seconds to confirm (shorter than before)
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
  
  /// Handle off-route: Silent intelligent re-routing
  Future<void> _handleOffRoute() async {
    if (_destination == null || _pos == null) return;
    
    setState(() => _isOffRoute = true);
    
    print("🔄 Attempting silent re-routing...");
    print("📍 Current position: ${_pos!.latitude}, ${_pos!.longitude}");
    print("🎯 Destination: ${_destination!.latitude}, ${_destination!.longitude}");
    
    // Calculate new route from current position
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
      
      // Compare with remaining distance on original route
      final currentRemainingDistance = _remainingKm * 1000;
      
      print("📊 Route comparison:");
      print("  Original remaining: ${currentRemainingDistance.toStringAsFixed(0)}m");
      print("  New route: ${newDistance.toStringAsFixed(0)}m");
      
      // Accept new route if it's equal or better (within 10% margin)
      if (newDistance <= currentRemainingDistance * 1.1) {
        print("✅ ACCEPTING NEW ROUTE (better or similar)");
        
        // Extract new route points
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
        
        // Update route
        _lastRoutePoints = points;
        _remainingKm = newDistance / 1000.0;
        _remainingMin = newDuration / 60.0;

        print("🎨 Redrawing route...");
        // Redraw route
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
                // Force accept new route
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

    // Determine if query looks like POI or address
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

    await PreferencesService.addRecentSearch(s.name);

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

  // Desenhar pegadas APENAS no caminho percorrido
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

      // Percorrer todo o caminho percorrido
      for (int i = 0; i < walkedPath.length; i++) {
        Position current = walkedPath[i];
        Position? next = i + 1 < walkedPath.length ? walkedPath[i + 1] : null;

        double bearing = 0;
        if (next != null) {
          bearing = _calculateBearing(
            current.lat.toDouble(),
            current.lng.toDouble(),
            next.lat.toDouble(),
            next.lng.toDouble(),
          );
        }

        // Colocar pegada
        await _stepsManager!.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: current),
            image: isLeftFoot ? _footLeft! : _footRight!,
            iconSize: 2.0,
            iconRotate: bearing,
            iconOpacity: 1.0,
            iconAnchor: IconAnchor.CENTER,
            iconColor: "#FFD700"
          ),
        );

        footstepCount++;
        isLeftFoot = !isLeftFoot; // Alternar esquerda/direita
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

    // ✅ NOVO: Verificar se clicou perto de um safety report
    final touchCoord = ctx.point.coordinates;
    for (var report in _nearbyReports) {
      final distance = Geo.Geolocator.distanceBetween(
        touchCoord.lat.toDouble(),
        touchCoord.lng.toDouble(),
        report.latitude,
        report.longitude,
      );
      
      // Se clicou a menos de 50 metros de um report
      if (distance < 50) {
        _showReportDetails(report);
        return;
      }
    }

    // Comportamento original
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
    _safetyMarkersManager?.deleteAll();  // ✅ NOVO

    // Guarda localização ao fechar
    if (_pos != null) {
      PreferencesService.saveLastLocation(
        _pos!.latitude,
        _pos!.longitude,
     );
     print('💾 Localização guardada ao fechar app');
   }

    super.dispose();
  }
  
  // ✅ MÉTODOS DOS BOTÕES DE CATEGORIA (adicionar ANTES do @override Widget build)

  Widget _buildCategoryButtons() {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryButton(icon: '☕', label: 'Cafés', query: 'coffee shop'),
          _CategoryButton(icon: '🍽️', label: 'Food', query: 'restaurant'),
          _CategoryButton(icon: '💊', label: 'Pharmacy', query: 'pharmacy'),
          _CategoryButton(icon: '🏪', label: 'Stores', query: 'supermarket'),
          _CategoryButton(icon: '🏥', label: 'Hospital', query: 'hospital'),
        ],
      ),
    );
  }

  Widget _CategoryButton({required String icon, required String label, required String query}) {
    return GestureDetector(
      onTap: () {
        _search.text = query;
        _searchPlaces(query);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F3DF),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
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

                // ✅ NOVO: Carregar safety reports quando o mapa é criado
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
          ),
          // SEARCH BAR + SUGGESTIONS
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Column(
              children: [
                _buildCategoryButtons(),  // ✅ ADICIONAR ESTA LINHA!
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
      // Barra de pesquisa (original)
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
      
      // Pesquisas recentes
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
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
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
                  'CLEAR',
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
        
        // Lista de pesquisas
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
    // Só verifica a cada 5 minutos
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

      // ✅ Verificar se já confirmou esta cidade
      final alreadyConfirmed = await _cityService.hasConfirmedCity(cityId);
      if (alreadyConfirmed) {
        print('✅ City already confirmed: ${city['name']}');
        _currentCityId = cityId;
        return;
      }

      // Cidade nova (não confirmada)?
      if (cityId != _currentCityId) {
        _currentCityId = cityId;

        // Mostra o pop-up
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
          _addLog('📍 Cidade confirmada: ${city['name']}');

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${city['name']} confirmada!'),
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

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_police, color: Colors.red),
              title: const Text('Dangerous Area'),
              onTap: () {
                _createReport('dangerous_area');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.construction, color: Colors.orange),
              title: const Text('Construction Site'),
              onTap: () {
                _createReport('construction');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline, color: Colors.yellow),
              title: const Text('Poor Lighting'),
              onTap: () {
                _createReport('poor_lighting');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createReport(String type) async {
    print('🟡 Tentando criar report...');
    print('📍 Localização atual: $_pos');
    print('👤 User ID: ${Supabase.instance.client.auth.currentUser?.id}');
  
    if (_pos == null) {
      print('❌ Localização não disponível!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting location...')),
     );
     return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
  
    if (userId == null) {
      print('❌ User não está autenticado!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: not authenticated')),
      );
      return;
    }

    try {
      print('🔵 A inserir no Supabase...');
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
          })
          .select();

      print('✅ Response do Supabase: $response');

      // ✅ NOVO: Recarregar reports após criar um novo
      _lastReportsRefresh = null;  // Forçar refresh
      await _loadNearbyReports();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Report created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ ERRO COMPLETO: $e');
      print('❌ Tipo do erro: ${e.runtimeType}');
    
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