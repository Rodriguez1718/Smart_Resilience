import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_resilience_app/screens/fullscreen_map.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  LatLng? geofenceCenter;
  LatLng? deviceLocation;
  double geofenceRadius = 100; // meters
  bool _isLoading = true;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initializeDeviceLocation();
  }

  /// Get the device's current location
  Future<void> _initializeDeviceLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to set geofence'),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        deviceLocation = LatLng(position.latitude, position.longitude);
        geofenceCenter = deviceLocation; // Lock geofence to device location
        _isLoading = false;
      });

      print(
        '[GeofenceScreen] Device location: ${deviceLocation?.latitude}, ${deviceLocation?.longitude}',
      );
    } catch (e) {
      print('[GeofenceScreen] Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Safe Zone'), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : deviceLocation == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Unable to get device location'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initializeDeviceLocation,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: deviceLocation!,
                    initialZoom: 15.0,
                    // Lock map center to device location, disable tap
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.smart_resilience_app',
                    ),
                    // Geofence circle
                    if (geofenceCenter != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: geofenceCenter!,
                            color: Colors.blue.withOpacity(0.2),
                            borderStrokeWidth: 2,
                            borderColor: Colors.blue,
                            useRadiusInMeter: true,
                            radius: geofenceRadius,
                          ),
                        ],
                      ),
                    // Device location marker (at center of geofence)
                    if (deviceLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 60,
                            height: 60,
                            point: deviceLocation!,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.my_location,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // Bottom sheet for radius control
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Safe Zone Radius',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Adjust the radius to define the safe zone around the device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Slider(
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          label: '${geofenceRadius.round()} m',
                          value: geofenceRadius,
                          activeColor: Colors.green,
                          inactiveColor: Colors.grey[300],
                          onChanged: (value) {
                            setState(() => geofenceRadius = value);
                          },
                        ),
                        Center(
                          child: Text(
                            '${geofenceRadius.round()} meters',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              // Navigate to FullscreenMap to save the safe zone
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FullscreenMap(
                                    initialLocation: deviceLocation!,
                                    initialRadius: geofenceRadius,
                                    initialZoneName: 'New Safe Zone',
                                    isForAddingOrEditing: true,
                                    userId:
                                        'user_placeholder', // TODO: Get from auth
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Save Safe Zone',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
