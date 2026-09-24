import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const ShresthSaathiApp());
}

// ============================================================
// APP
// ============================================================

class ShresthSaathiApp extends StatelessWidget {
  const ShresthSaathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShresthSaathi',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const NavigationScreen(),
    );
  }
}

// ============================================================
// NAVIGATION SCREEN
// ============================================================

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() =>
      _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  // ============================================================
  // MAP
  // ============================================================

  final MapController mapController = MapController();

  // ============================================================
  // FROM / TO
  // ============================================================

  final TextEditingController fromController =
      TextEditingController();

  final TextEditingController toController =
      TextEditingController();

  LatLng? fromLocation;
  LatLng? toLocation;

  String? fromDisplayName;
  String? toDisplayName;

  bool searchingFrom = true;
  bool isSearching = false;
  bool showSearchResults = false;

  List<Map<String, dynamic>> searchResults = [];

  // ============================================================
  // LOCATION
  // ============================================================

  Position? currentPosition;

  StreamSubscription<Position>? _positionSubscription;

  // ============================================================
  // ROUTE
  // ============================================================

  List<LatLng> routePoints = [];

  double? routeDistance;
  double? routeDuration;

  // ============================================================
  // NAVIGATION
  // ============================================================

  String status = 'Checking GNSS...';

  String navigationMode = 'Normal GNSS Navigation';

  bool isNavigating = false;

  // ============================================================
  // IMU
  // ============================================================

  StreamSubscription<AccelerometerEvent>?
      _accelerometerSubscription;

  StreamSubscription<GyroscopeEvent>?
      _gyroscopeSubscription;

  StreamSubscription<MagnetometerEvent>?
      _magnetometerSubscription;

  AccelerometerEvent? accelerometerData;
  GyroscopeEvent? gyroscopeData;
  MagnetometerEvent? magnetometerData;
  // IMU DATA RECORDING
bool isRecording = false;
int _lastRecordMillis = 0;
DateTime? recordingStartTime;

final List<String> recordedImuData = [];
  // SMOOTHED IMU VALUES
  

double filteredAx = 0.0;
double filteredAy = 0.0;
double filteredAz = 0.0;

double filteredGx = 0.0;
double filteredGy = 0.0;
double filteredGz = 0.0;

double filteredMx = 0.0;
double filteredMy = 0.0;
double filteredMz = 0.0;

static const double sensorAlpha = 0.15;

// DEAD RECKONING STEP DETECTION
double accelMagnitude = 0.0;
double previousAccelMagnitude = 0.0;
DateTime? lastStepTime;
int detectedSteps = 0;

static const double stepThreshold = 10.0;
static const int minStepIntervalMs = 300;

  // ============================================================
  // GNSS LOSS / DEAD RECKONING
  // ============================================================

  bool isGnssLostDemo = false;

  LatLng? estimatedPosition;

  Timer? _deadReckoningTimer;

  int deadReckoningSeconds = 0;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _startLocation();
    _startIMUSensors();
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<void> _startLocation() async {
    final bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return;

      setState(() {
        status = 'GNSS Unavailable';
        navigationMode = 'Location Service Disabled';
      });

      return;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;

      setState(() {
        status = 'GNSS Unavailable';
        navigationMode = 'Location Permission Denied';
      });

      return;
    }

    try {
      final Position position =
          await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      final LatLng location = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        currentPosition = position;

        if (!isGnssLostDemo) {
          status = 'GNSS Available';
          navigationMode = 'Normal GNSS Navigation';
        }
      });

      estimatedPosition = location;

      mapController.move(
        location,
        16,
      );

      _positionSubscription =
          Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen(
        (Position newPosition) {
          if (!mounted) return;

          setState(() {
            currentPosition = newPosition;

            if (!isGnssLostDemo) {
              status = 'GNSS Available';

              navigationMode = isNavigating
                  ? 'Active GNSS Navigation'
                  : 'Normal GNSS Navigation';
            }
          });

          if (!isGnssLostDemo && isNavigating) {
            mapController.move(
              LatLng(
                newPosition.latitude,
                newPosition.longitude,
              ),
              mapController.camera.zoom,
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'GNSS Error';
        navigationMode = 'Location Error';
      });
    }
  }

  // ============================================================
  // IMU
  // ============================================================
Future<void> _startImuRecording() async {
  recordedImuData.clear();
    _lastRecordMillis = 0;

  recordedImuData.add(
    'timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z,latitude,longitude,speed',
  );

  setState(() {
    isRecording = true;
    recordingStartTime = DateTime.now();
  });

  _showMessage('IMU recording started');
}

Future<void> _stopImuRecording() async {
  setState(() {
    isRecording = false;
  });

  final directory = Directory('/storage/emulated/0/Download');

  final file = File(
    '${directory.path}/imu_data_${DateTime.now().millisecondsSinceEpoch}.csv',
  );

  await file.writeAsString(
    recordedImuData.join('\n'),
  );

  _showMessage(
    'IMU data saved: ${file.path} — ${recordedImuData.length - 1} samples',
  );
}
void _recordImuSample() {
  if (!isRecording) return;

  final now = DateTime.now().millisecondsSinceEpoch;

  if (now - _lastRecordMillis < 100) return;

  _lastRecordMillis = now;

  final lat = currentPosition?.latitude ?? '';
  final lon = currentPosition?.longitude ?? '';
  final speed = currentPosition?.speed ?? '';

  recordedImuData.add(
    '$now,'
    '$filteredAx,$filteredAy,$filteredAz,'
    '$filteredGx,$filteredGy,$filteredGz,'
    '$filteredMx,$filteredMy,$filteredMz,'
    '$lat,$lon,$speed',
  );
}
  void _startIMUSensors() {
  _accelerometerSubscription =
      accelerometerEventStream().listen(
    (event) {
      if (!mounted) return;

      filteredAx =
          filteredAx +
              sensorAlpha * (event.x - filteredAx);

      filteredAy =
          filteredAy +
              sensorAlpha * (event.y - filteredAy);

      filteredAz =
          filteredAz +
              sensorAlpha * (event.z - filteredAz);
                  _recordImuSample();
                  accelMagnitude = math.sqrt(
  filteredAx * filteredAx +
      filteredAy * filteredAy +
      filteredAz * filteredAz,
);

final now = DateTime.now();

if (accelMagnitude > stepThreshold &&
    previousAccelMagnitude <= stepThreshold &&
    (lastStepTime == null ||
        now.difference(lastStepTime!).inMilliseconds >
            minStepIntervalMs)) {
  detectedSteps++;
  lastStepTime = now;
}

previousAccelMagnitude = accelMagnitude;

      setState(() {
        accelerometerData = AccelerometerEvent(
          filteredAx,
          filteredAy,
          filteredAz,
          event.timestamp,
        );
      });
    },
  );

  _gyroscopeSubscription =
      gyroscopeEventStream().listen(
    (event) {
      if (!mounted) return;

      filteredGx =
          filteredGx +
              sensorAlpha * (event.x - filteredGx);

      filteredGy =
          filteredGy +
              sensorAlpha * (event.y - filteredGy);

      filteredGz =
          filteredGz +
              sensorAlpha * (event.z - filteredGz);

      setState(() {
        gyroscopeData = GyroscopeEvent(
          filteredGx,
          filteredGy,
          filteredGz,
          event.timestamp,
        );
      });
    },
  );

  _magnetometerSubscription =
      magnetometerEventStream().listen(
    (event) {
      if (!mounted) return;

      filteredMx =
          filteredMx +
              sensorAlpha * (event.x - filteredMx);

      filteredMy =
          filteredMy +
              sensorAlpha * (event.y - filteredMy);

      filteredMz =
          filteredMz +
              sensorAlpha * (event.z - filteredMz);

      setState(() {
        magnetometerData = MagnetometerEvent(
          filteredMx,
          filteredMy,
          filteredMz,
          event.timestamp,
        );
      });
    },
  );
}

  // ============================================================
  // SEARCH
  // ============================================================

  Future<void> _searchLocation() async {
    final TextEditingController controller =
        searchingFrom
            ? fromController
            : toController;

    final String query =
        controller.text.trim();

    if (query.isEmpty) {
      _showMessage(
        searchingFrom
            ? 'Enter starting location'
            : 'Enter destination',
      );

      return;
    }

    setState(() {
      isSearching = true;
      showSearchResults = false;
    });

    try {
      final Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&format=json'
        '&limit=5'
        '&countrycodes=in',
      );

      final http.Response response =
          await http.get(
        uri,
        headers: {
          'User-Agent': 'ShresthSaathi/1.0',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Search failed');
      }

      final dynamic data =
          jsonDecode(response.body);

      if (!mounted) return;

      setState(() {
        searchResults =
            List<Map<String, dynamic>>.from(data);

        isSearching = false;
        showSearchResults = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSearching = false;
      });

      _showMessage(
        'Location search failed',
      );
    }
  }

  // ============================================================
  // SELECT SEARCH RESULT
  // ============================================================

  void _selectSearchResult(
    Map<String, dynamic> result,
  ) {
    final double latitude =
        double.parse(
      result['lat'].toString(),
    );

    final double longitude =
        double.parse(
      result['lon'].toString(),
    );

    final LatLng location =
        LatLng(latitude, longitude);

    final String displayName =
        result['display_name']?.toString() ??
            'Selected location';

    setState(() {
      if (searchingFrom) {
        fromLocation = location;
        fromDisplayName = displayName;
        fromController.text = displayName;
      } else {
        toLocation = location;
        toDisplayName = displayName;
        toController.text = displayName;
      }

      showSearchResults = false;
    });

    mapController.move(
      location,
      15,
    );

    if (fromLocation != null &&
        toLocation != null) {
      _buildRoute();
    }
  }
    Future<void> _saveCurrentRoute() async {
  if (fromLocation == null ||
      toLocation == null ||
      routePoints.isEmpty) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();

  final routeData = {
    'fromName': fromController.text,
    'toName': toController.text,
    'fromLat': fromLocation!.latitude,
    'fromLng': fromLocation!.longitude,
    'toLat': toLocation!.latitude,
    'toLng': toLocation!.longitude,
    'distance': routeDistance ?? 0,
    'duration': routeDuration ?? 0,
    'savedAt': DateTime.now().toIso8601String(),
    'routePoints': routePoints
        .map(
          (point) => {
            'lat': point.latitude,
            'lng': point.longitude,
          },
        )
        .toList(),
  };

  final existingRoutes =
      prefs.getStringList('saved_routes') ?? [];

  existingRoutes.add(jsonEncode(routeData));

  await prefs.setStringList(
    'saved_routes',
    existingRoutes,
  );

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Route automatically saved'),
      duration: Duration(seconds: 2),
    ),
  );
}

  // ============================================================
  // USE CURRENT LOCATION
  // ============================================================

  void _useCurrentAsFrom() {
    if (currentPosition == null) {
      _showMessage(
        'Current location not available',
      );

      return;
    }

    final LatLng location =
        LatLng(
      currentPosition!.latitude,
      currentPosition!.longitude,
    );

    setState(() {
      fromLocation = location;
      fromDisplayName = 'Current Location';
      fromController.text = 'Current Location';
    });

    mapController.move(
      location,
      15,
    );

    if (toLocation != null) {
      _buildRoute();
    }

    _showMessage(
      'Current location selected as From',
    );
  }

  // ============================================================
  // SWAP
  // ============================================================

  void _swapLocations() {
    final LatLng? oldFrom =
        fromLocation;

    final String? oldFromName =
        fromDisplayName;

    final String oldFromText =
        fromController.text;

    setState(() {
      fromLocation = toLocation;
      fromDisplayName = toDisplayName;
      fromController.text = toController.text;

      toLocation = oldFrom;
      toDisplayName = oldFromName;
      toController.text = oldFromText;
    });

    if (fromLocation != null &&
        toLocation != null) {
      _buildRoute();
    }
  }

  // ============================================================
  // ROUTE
  // ============================================================

  Future<void> _buildRoute() async {
    if (fromLocation == null) {
      _showMessage(
        'Please select starting location',
      );

      return;
    }

    if (toLocation == null) {
      _showMessage(
        'Please select destination',
      );

      return;
    }

    final double startLat =
        fromLocation!.latitude;

    final double startLng =
        fromLocation!.longitude;

    final double destinationLat =
        toLocation!.latitude;

    final double destinationLng =
        toLocation!.longitude;

    final String url =
        'https://router.project-osrm.org'
        '/route/v1/driving/'
        '$startLng,$startLat;'
        '$destinationLng,$destinationLat'
        '?overview=full&geometries=geojson';

    try {
      final http.Response response =
          await http.get(
        Uri.parse(url),
      );

      if (response.statusCode != 200) {
        throw Exception('Route failed');
      }

      final dynamic data =
          jsonDecode(response.body);

      if (data['routes'] == null ||
          data['routes'].isEmpty) {
        _showMessage(
          'No route found',
        );

        return;
      }

      final dynamic route =
          data['routes'][0];

      final List<dynamic> coordinates =
          route['geometry']['coordinates'];

      final List<LatLng> points =
          coordinates.map<LatLng>(
        (coordinate) {
          return LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          );
        },
      ).toList();

      if (!mounted) return;

      setState(() {
        routePoints = points;

        routeDistance =
            (route['distance'] as num).toDouble();

        routeDuration =
            (route['duration'] as num).toDouble();
      });
       await _saveCurrentRoute();


      if (points.isNotEmpty) {
        final LatLngBounds bounds =
            LatLngBounds.fromPoints(points);

        mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(100),
          ),
        );
      }
    } catch (e) {
      _showMessage(
        'Unable to calculate route',
      );
    }
  }

  // ============================================================
  // CLEAR ROUTE
  // ============================================================
  Future<void> _showSavedRoutes() async {
  final prefs = await SharedPreferences.getInstance();
  final savedRoutes = prefs.getStringList('saved_routes') ?? [];

  if (!mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(20),
      ),
    ),
    builder: (context) {
      if (savedRoutes.isEmpty) {
        return const SizedBox(
          height: 220,
          child: Center(
            child: Text(
              'No saved routes yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saved Routes',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: savedRoutes.length,
                  itemBuilder: (context, index) {
                    final routeData =
                        jsonDecode(savedRoutes[index])
                            as Map<String, dynamic>;

                    final fromName =
                        routeData['fromName']?.toString() ??
                            'Unknown From';

                    final toName =
                        routeData['toName']?.toString() ??
                            'Unknown Destination';

                    final distance =
                        (routeData['distance'] as num?)
                                ?.toDouble() ??
                            0;

                    final duration =
                        (routeData['duration'] as num?)
                                ?.toDouble() ??
                            0;

                    return Card(
                      margin: const EdgeInsets.only(
                        bottom: 8,
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(
                            Icons.bookmark,
                          ),
                        ),
                        title: Text(
                          toName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${distance >= 1000 ? '${(distance / 1000).toStringAsFixed(1)} km' : '${distance.toStringAsFixed(0)} m'}'
                          ' • ${(duration / 60).round()} min',
                          maxLines: 1,
                        ),
                       trailing: IconButton(
  icon: const Icon(
    Icons.delete_outline,
    color: Colors.red,
  ),
  tooltip: 'Delete route',
  onPressed: () {
    _deleteSavedRoute(index);
  },
),
                        
                        onTap: () {
                          Navigator.pop(context);
                          _loadSavedRoute(routeData);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
void _loadSavedRoute(
  Map<String, dynamic> routeData,
) {
  final double fromLat =
      (routeData['fromLat'] as num).toDouble();

  final double fromLng =
      (routeData['fromLng'] as num).toDouble();

  final double toLat =
      (routeData['toLat'] as num).toDouble();

  final double toLng =
      (routeData['toLng'] as num).toDouble();

  final List<dynamic> savedPoints =
      routeData['routePoints'] as List<dynamic>;

  final List<LatLng> points =
      savedPoints.map<LatLng>((point) {
    return LatLng(
      (point['lat'] as num).toDouble(),
      (point['lng'] as num).toDouble(),
    );
  }).toList();

  setState(() {
    fromLocation = LatLng(
      fromLat,
      fromLng,
    );

    toLocation = LatLng(
      toLat,
      toLng,
    );

    fromController.text =
        routeData['fromName']?.toString() ??
            'Saved Location';

    toController.text =
        routeData['toName']?.toString() ??
            'Saved Destination';

    fromDisplayName =
        fromController.text;

    toDisplayName =
        toController.text;

    routePoints = points;

    routeDistance =
        (routeData['distance'] as num?)
            ?.toDouble();

    routeDuration =
        (routeData['duration'] as num?)
            ?.toDouble();
            
  });

  if (points.isNotEmpty) {
    final bounds =
        LatLngBounds.fromPoints(points);

    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(100),
      ),
    );
  }

  _showMessage(
    'Saved route loaded',
  );
}
Future<void> _deleteSavedRoute(int index) async {
  final prefs = await SharedPreferences.getInstance();

  final savedRoutes =
      prefs.getStringList('saved_routes') ?? [];

  if (index >= 0 && index < savedRoutes.length) {
    savedRoutes.removeAt(index);
    await prefs.setStringList('saved_routes', savedRoutes);

    if (mounted) {
      Navigator.pop(context);
      _showSavedRoutes();
    }
  }
}

  void _clearRoute() {
    setState(() {
      routePoints = [];
      routeDistance = null;
      routeDuration = null;
    });
  }

  // ============================================================
  // MY LOCATION
  // ============================================================

  void _goToCurrentLocation() {
    if (currentPosition == null) {
      _showMessage(
        'Current location not available',
      );

      return;
    }

    final LatLng location =
        LatLng(
      currentPosition!.latitude,
      currentPosition!.longitude,
    );

    mapController.move(
      location,
      16,
    );
  }

  // ============================================================
  // START NAVIGATION
  // ============================================================

  void _startNavigation() {
    if (fromLocation == null ||
        toLocation == null) {
      _showMessage(
        'Select From and To locations first',
      );

      return;
    }

    setState(() {
      isNavigating = true;

      if (!isGnssLostDemo) {
        navigationMode =
            'Active GNSS Navigation';
      }
    });

    _showMessage(
      'Navigation started',
    );
  }

  // ============================================================
  // STOP NAVIGATION
  // ============================================================

  void _stopNavigation() {
    setState(() {
      isNavigating = false;

      if (!isGnssLostDemo) {
        navigationMode =
            'Normal GNSS Navigation';
      }
    });

    _showMessage(
      'Navigation stopped',
    );
  }

  // ============================================================
  // GNSS LOSS
  // ============================================================

  void _toggleGnssLostDemo() {
    if (isGnssLostDemo) {
      _recoverGnss();
    } else {
      _startDeadReckoningDemo();
    }
  }

  // ============================================================
  // DEAD RECKONING DEMO
  // ============================================================

  void _startDeadReckoningDemo() {
  _showMessage('Dead Reckoning started');

  final LatLng start = currentPosition != null
      ? LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        )
      : (fromLocation ??
          const LatLng(
            23.3441,
            85.3096,
          ));

  _deadReckoningTimer?.cancel();

  setState(() {
    isGnssLostDemo = true;
    estimatedPosition = start;
    deadReckoningSeconds = 0;
    status = 'GNSS Lost';
    navigationMode = 'Dead Reckoning Mode';
    isNavigating = true;
  });

  _deadReckoningTimer = Timer.periodic(
    const Duration(milliseconds: 500),
    (timer) {
      if (!mounted || !isGnssLostDemo) {
        timer.cancel();
        return;
      }

      final LatLng current =
          estimatedPosition ?? start;

      deadReckoningSeconds++;

      // IMU activity
      final accel = accelerometerData;

      double activity = 0.0;

      if (accel != null) {
        activity = math.sqrt(
          accel.x * accel.x +
              accel.y * accel.y +
              accel.z * accel.z,
        );
      }

      // Remove approximate gravity.
      final movement =
          (activity - 9.81).abs();

      // Ignore very small sensor noise.
      if (movement < 0.15) {
        setState(() {
          status = 'GNSS Lost → IMU Monitoring';
          navigationMode = 'Dead Reckoning Mode';
        });
        return;
      }

      // Approximate walking displacement.
      final double distance =
          (movement * 0.18).clamp(
        0.3,
        1.2,
      );

      // Use yaw/heading when available.
      const double heading = 0.0;

      const double metersPerDegreeLat =
          111320.0;

      final double metersPerDegreeLon =
          111320.0 *
              math.cos(
                current.latitude *
                    math.pi /
                    180.0,
              );

      final double dx =
          distance * math.cos(heading);

      final double dy =
          distance * math.sin(heading);

      final double nextLat =
          current.latitude +
              dy / metersPerDegreeLat;

      final double nextLon =
          current.longitude +
              dx / metersPerDegreeLon;

      final LatLng nextPosition =
          LatLng(nextLat, nextLon);

      setState(() {
        estimatedPosition =
            nextPosition;

        status =
            'GNSS Lost → Dead Reckoning';

        navigationMode =
            'Estimated Navigation';
      });

      mapController.move(
        nextPosition,
        mapController.camera.zoom,
      );
    },
  );

  _showMessage(
    'GNSS lost — IMU Dead Reckoning active',
  );
}
  // ============================================================
  // GNSS RECOVERY
  // ============================================================

  void _recoverGnss() {
    _deadReckoningTimer?.cancel();

    _deadReckoningTimer = null;

    setState(() {
      isGnssLostDemo = false;

      deadReckoningSeconds = 0;

      status = 'GNSS Available';

      navigationMode = isNavigating
          ? 'Active GNSS Navigation'
          : 'Normal GNSS Navigation';

      if (currentPosition != null) {
        estimatedPosition =
            LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        );
      }
    });

    if (currentPosition != null) {
      mapController.move(
        LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        ),
        mapController.camera.zoom,
      );
    }

    _showMessage(
      'GNSS recovered — navigation re-synchronized',
    );
  }

  // ============================================================
  // CORRECT CIRCULAR BUTTON
  // ============================================================

  Widget _circleMapButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 5,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: 23,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISTANCE
  // ============================================================

  String _formatDistance() {
    if (routeDistance == null) {
      return '--';
    }

    if (routeDistance! >= 1000) {
      return '${(routeDistance! / 1000).toStringAsFixed(2)} km';
    }

    return '${routeDistance!.toStringAsFixed(0)} m';
  }

  // ============================================================
  // DURATION
  // ============================================================

  String _formatDuration() {
    if (routeDuration == null) {
      return '--';
    }

    final int minutes =
        (routeDuration! / 60).round();

    if (minutes < 60) {
      return '$minutes min';
    }

    final int hours =
        minutes ~/ 60;

    final int remainingMinutes =
        minutes % 60;

    return '${hours}h ${remainingMinutes}m';
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
            const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================
  // LOCATION FIELD
  // ============================================================

  Widget _locationField({
    required bool isFrom,
  }) {
    final TextEditingController controller =
        isFrom
            ? fromController
            : toController;

    return Material(
      elevation: 5,
      borderRadius:
          BorderRadius.circular(12),
      child: TextField(
        controller: controller,
        onTap: () {
          setState(() {
            searchingFrom = isFrom;
          });
        },
        onSubmitted: (_) {
          setState(() {
            searchingFrom = isFrom;
          });

          _searchLocation();
        },
        decoration:
            InputDecoration(
          hintText: isFrom
              ? 'From location'
              : 'To destination',
          prefixIcon: Icon(
            isFrom
                ? Icons.trip_origin
                : Icons.location_on,
            color: isFrom
                ? Colors.green
                : Colors.red,
          ),
          suffixIcon:
              isSearching &&
                      searchingFrom == isFrom
                  ? const Padding(
                      padding:
                          EdgeInsets.all(12),
                      child:
                          SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : IconButton(
                      icon:
                          const Icon(
                        Icons.search,
                      ),
                      onPressed: () {
                        setState(() {
                          searchingFrom =
                              isFrom;
                        });

                        _searchLocation();
                      },
                    ),
          filled: true,
          fillColor: Colors.white,
          border:
              OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(12),
            borderSide:
                BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SMALL GNSS + IMU CARD
  // LEFT BOTTOM
  // ============================================================

  Widget _imuAndGnssCard() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(10),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(7),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            // GNSS STATUS
            Text(
  'Steps: $detectedSteps',
  style: const TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
  ),
),
            Row(
              children: [
                Icon(
                  Icons.satellite_alt,
                  size: 13,
                  color:
                      isGnssLostDemo
                          ? Colors.orange
                          : Colors.green,
                ),
                const SizedBox(
                  width: 4,
                ),
                Expanded(
                  child: Text(
                    isGnssLostDemo
                        ? 'GNSS LOST'
                        : 'GNSS AVAILABLE',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 9,
                      color:
                          isGnssLostDemo
                              ? Colors.orange
                              : Colors.green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 2,
            ),

            Text(
              navigationMode,
              style:
                  const TextStyle(
                fontSize: 7,
                color: Colors.grey,
              ),
            ),

            const Divider(
              height: 7,
            ),

            const Text(
              'IMU SENSOR DATA',
              style:
                  TextStyle(
                fontWeight:
                    FontWeight.bold,
                fontSize: 8,
              ),
            ),

            const SizedBox(
              height: 2,
            ),

            Text(
              'A  '
              '${accelerometerData?.x.toStringAsFixed(1) ?? '--'}  '
              '${accelerometerData?.y.toStringAsFixed(1) ?? '--'}  '
              '${accelerometerData?.z.toStringAsFixed(1) ?? '--'}',
              style:
                  const TextStyle(
                fontSize: 7,
              ),
            ),

            Text(
              'G  '
              '${gyroscopeData?.x.toStringAsFixed(1) ?? '--'}  '
              '${gyroscopeData?.y.toStringAsFixed(1) ?? '--'}  '
              '${gyroscopeData?.z.toStringAsFixed(1) ?? '--'}',
              style:
                  const TextStyle(
                fontSize: 7,
              ),
            ),

            Text(
              'M  '
              '${magnetometerData?.x.toStringAsFixed(1) ?? '--'}  '
              '${magnetometerData?.y.toStringAsFixed(1) ?? '--'}  '
              '${magnetometerData?.z.toStringAsFixed(1) ?? '--'}',
              style:
                  const TextStyle(
                fontSize: 7,
              ),
            ),

            const SizedBox(
              height: 4,
            ),
            // IMU RECORDING BUTTON
SizedBox(
  width: double.infinity,
  height: 23,
  child: ElevatedButton.icon(
    onPressed: isRecording
        ? _stopImuRecording
        : _startImuRecording,
    icon: Icon(
      isRecording
          ? Icons.stop
          : Icons.fiber_manual_record,
      size: 12,
    ),
    label: Text(
      isRecording
          ? 'STOP IMU RECORDING'
          : 'START IMU RECORDING',
      style: const TextStyle(
        fontSize: 7,
        fontWeight: FontWeight.bold,
      ),
    ),
    style: ElevatedButton.styleFrom(
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
      ),
    ),
  ),
),

const SizedBox(
  height: 4,
),

            SizedBox(
              width: double.infinity,
              height: 23,
              child:
                  OutlinedButton.icon(
                onPressed:
                    _toggleGnssLostDemo,
                icon: Icon(
                  isGnssLostDemo
                      ? Icons
                          .satellite_alt
                      : Icons
                          .signal_wifi_off,
                  size: 12,
                ),
                label: Text(
                  isGnssLostDemo
                      ? 'GNSS RECOVERY'
                      : 'GNSS LOSS',
                  style:
                      const TextStyle(
                    fontSize: 7,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    OutlinedButton.styleFrom(
                  padding:
                      EdgeInsets.zero,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      9,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final LatLng defaultLocation =
        currentPosition != null
            ? LatLng(
                currentPosition!.latitude,
                currentPosition!.longitude,
              )
            : const LatLng(
                23.3441,
                85.3096,
              );

    return Scaffold(
      body: Stack(
        children: [
          // ======================================================
          // MAP
          // ======================================================

          FlutterMap(
            mapController:
                mapController,
            options: MapOptions(
              initialCenter:
                  defaultLocation,
              initialZoom: 16,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.example.sresht_saathi',
              ),

              // ROUTE
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points:
                          routePoints,
                      strokeWidth: 6,
                      color:
                          Colors.blue,
                    ),
                  ],
                ),

              // CURRENT GNSS LOCATION
              if (currentPosition !=
                      null &&
                  !isGnssLostDemo)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        currentPosition!
                            .latitude,
                        currentPosition!
                            .longitude,
                      ),
                      width: 50,
                      height: 50,
                      child:
                          Container(
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.blue,
                          shape:
                              BoxShape
                                  .circle,
                          border:
                              Border.all(
                            color:
                                Colors.white,
                            width: 4,
                          ),
                        ),
                        child:
                            const Icon(
                          Icons
                              .navigation,
                          color:
                              Colors.white,
                          size: 25,
                        ),
                      ),
                    ),
                  ],
                ),

              // FROM MARKER
              if (fromLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point:
                          fromLocation!,
                      width: 45,
                      height: 45,
                      child:
                          const Icon(
                        Icons
                            .trip_origin,
                        color:
                            Colors.green,
                        size: 34,
                      ),
                    ),
                  ],
                ),

              // TO MARKER
              if (toLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point:
                          toLocation!,
                      width: 45,
                      height: 45,
                      child:
                          const Icon(
                        Icons
                            .location_on,
                        color:
                            Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),

              // DEAD RECKONING ESTIMATED LOCATION
              if (isGnssLostDemo &&
                  estimatedPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point:
                          estimatedPosition!,
                      width: 58,
                      height: 58,
                      child:
                          Container(
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.orange,
                          shape:
                              BoxShape
                                  .circle,
                          border:
                              Border.all(
                            color:
                                Colors.white,
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color:
                                  Colors.black26,
                              blurRadius:
                                  6,
                            ),
                          ],
                        ),
                        child:
                            const Icon(
                          Icons
                              .navigation,
                          color:
                              Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ======================================================
          // SHRESTHSAATHI LOGO
          // ======================================================

          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: Container(
                width: 52,
                height: 52,
                padding:
                    const EdgeInsets.all(2),
                decoration:
                    const BoxDecoration(
                  color: Colors.white,
                  shape:
                      BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black26,
                      blurRadius: 5,
                    ),
                  ],
                ),
                child:
                    ClipOval(
                  child: Image.asset(
                    'assets/shresht_logo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          // ======================================================
          // FROM / TO
          // ======================================================

          Positioned(
            top: 70,
            left: 68,
            right: 12,
            child: Column(
              children: [
                _locationField(
                  isFrom: true,
                ),

                const SizedBox(
                  height: 7,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                          _locationField(
                        isFrom: false,
                      ),
                    ),

                    const SizedBox(
                      width: 5,
                    ),

                    Material(
                      color:
                          Colors.white,
                      elevation: 5,
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                      child:
                          IconButton(
                        tooltip:
                            'Swap locations',
                        onPressed:
                            _swapLocations,
                        icon:
                            const Icon(
                          Icons
                              .swap_vert,
                        ),
                      ),
                    ),
                  ],
                ),

                // SEARCH RESULTS
                if (showSearchResults &&
                    searchResults
                        .isNotEmpty)
                  Container(
                    margin:
                        const EdgeInsets
                            .only(
                      top: 5,
                    ),
                    constraints:
                        const BoxConstraints(
                      maxHeight: 160,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.white,
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color:
                              Colors.black26,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child:
                        ListView.builder(
                      shrinkWrap: true,
                      itemCount:
                          searchResults
                              .length,
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final Map<
                                String,
                                dynamic>
                            result =
                            searchResults[
                                index];

                        return ListTile(
                          dense: true,
                          leading:
                              const Icon(
                            Icons
                                .location_on,
                            color:
                                Colors.blue,
                          ),
                          title:
                              Text(
                            result[
                                        'display_name']
                                    ?.toString() ??
                                'Unknown location',
                            maxLines: 2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                          ),
                          onTap: () {
                            _selectSearchResult(
                              result,
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ======================================================
          // LEFT CIRCULAR CONTROLS
          // ======================================================

          Positioned(
            left: 10,
            top: 200,
            child: SafeArea(
              child: Column(
                children: [
                  // GNSS
                  Material(
                    color:
                        Colors.white,
                    elevation: 5,
                    shape:
                        const CircleBorder(),
                    child:
                        SizedBox(
                      width: 46,
                      height: 46,
                      child:
                          Center(
                        child:
                            Icon(
                          Icons
                              .satellite_alt,
                          color:
                              isGnssLostDemo
                                  ? Colors
                                      .orange
                                  : Colors
                                      .green,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  

                  const SizedBox(
                    height: 7,
                  ),
                 

_circleMapButton(
  icon: Icons.bookmark,
  color: Colors.deepPurple,
  tooltip: 'Saved Routes',
  onPressed: _showSavedRoutes,
),
                  // CURRENT LOCATION
                  _circleMapButton(
                    icon:
                        Icons.my_location,
                    color:
                        Colors.blue,
                    tooltip:
                        'Use Current Location',
                    onPressed:
                        _useCurrentAsFrom,
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  // ZOOM IN
                  _circleMapButton(
                    icon:
                        Icons.add,
                    color:
                        Colors.blue,
                    tooltip:
                        'Zoom In',
                    onPressed: () {
                      final double
                          zoom =
                          mapController
                              .camera
                              .zoom;

                      mapController.move(
                        mapController
                            .camera
                            .center,
                        zoom + 1,
                      );
                    },
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  // ZOOM OUT
                  _circleMapButton(
                    icon:
                        Icons.remove,
                    color:
                        Colors.blue,
                    tooltip:
                        'Zoom Out',
                    onPressed: () {
                      final double
                          zoom =
                          mapController
                              .camera
                              .zoom;

                      mapController.move(
                        mapController
                            .camera
                            .center,
                        zoom - 1,
                      );
                    },
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  // MY LOCATION
                  _circleMapButton(
                    icon:
                        Icons.navigation,
                    color:
                        Colors.indigo,
                    tooltip:
                        'My Location',
                    onPressed:
                        _goToCurrentLocation,
                  ),
                ],
              ),
            ),
          ),

          // ======================================================
          // SMALL GNSS + IMU CARD
          // LEFT BOTTOM
          // ======================================================

          Positioned(
            left: 8,
            bottom: 105,
            child: SafeArea(
              child: SizedBox(
                width: 145,
                child:
                    _imuAndGnssCard(),
              ),
            ),
          ),

          // ======================================================
          // ROUTE INFO
          // ======================================================

          if (routePoints.isNotEmpty)
            Positioned(
              left: 165,
              right: 12,
              bottom: 175,
              child: Card(
                elevation: 5,
                child: Padding(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child:
                      Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text(
                            'Distance',
                            style:
                                TextStyle(
                              fontSize:
                                  9,
                              color:
                                  Colors.grey,
                            ),
                          ),
                          Text(
                            _formatDistance(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                              fontSize:
                                  13,
                            ),
                          ),
                        ],
                      ),

                      Column(
                        children: [
                          const Text(
                            'ETA',
                            style:
                                TextStyle(
                              fontSize:
                                  9,
                              color:
                                  Colors.grey,
                            ),
                          ),
                          Text(
                            _formatDuration(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                              fontSize:
                                  13,
                            ),
                          ),
                        ],
                      ),

                      IconButton(
                        tooltip:
                            'Clear Route',
                        onPressed:
                            _clearRoute,
                        icon:
                            const Icon(
                          Icons.close,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ======================================================
          // ONLY ONE START / STOP NAVIGATION BUTTON
          // ======================================================

          Positioned(
            left: 165,
            right: 12,
            bottom: 48,
            child:
                SizedBox(
              height: 44,
              child:
                  ElevatedButton.icon(
                onPressed:
                    isNavigating
                        ? _stopNavigation
                        : _startNavigation,
                icon: Icon(
                  isNavigating
                      ? Icons.stop
                      : Icons.navigation,
                  size: 17,
                ),
                label: Text(
                  isNavigating
                      ? 'STOP NAVIGATION'
                      : 'START NAVIGATION',
                  style:
                      const TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      isNavigating
                          ? Colors.red
                          : Colors.blue,
                  foregroundColor:
                      Colors.white,
                  elevation: 5,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _positionSubscription?.cancel();

    _accelerometerSubscription?.cancel();

    _gyroscopeSubscription?.cancel();

    _magnetometerSubscription?.cancel();

    _deadReckoningTimer?.cancel();

    fromController.dispose();
    toController.dispose();

    super.dispose();
  }
}