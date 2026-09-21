import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const SreshtSaathiApp());
}

class SreshtSaathiApp extends StatelessWidget {
  const SreshtSaathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SreshtSaathi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Position? currentPosition;
  String status = 'Checking GNSS...';
  String navigationMode = 'Normal GNSS Navigation';

  final MapController mapController = MapController();

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  Future<void> _startLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      setState(() {
        status = 'GNSS / Location Service Disabled';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        status = 'Location Permission Denied';
      });
      return;
    }

    setState(() {
      status = 'GNSS Available';
    });

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      setState(() {
        currentPosition = position;
      });

      mapController.move(
        LatLng(position.latitude, position.longitude),
        16,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final LatLng defaultLocation = currentPosition != null
        ? LatLng(
            currentPosition!.latitude,
            currentPosition!.longitude,
          )
        : const LatLng(37.421998, -122.084000);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SreshtSaathi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: defaultLocation,
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.sresht_saathi',
                ),

                if (currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        ),
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_pin,
                          size: 50,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (currentPosition != null) ...[
                  Text(
                    'Latitude: ${currentPosition!.latitude.toStringAsFixed(6)}',
                  ),
                  Text(
                    'Longitude: ${currentPosition!.longitude.toStringAsFixed(6)}',
                  ),
                  Text(
                    'Accuracy: ${currentPosition!.accuracy.toStringAsFixed(2)} m',
                  ),
                ],

                const SizedBox(height: 8),

                Text(
                  'Mode: $navigationMode',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}