import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  LatLng? geofenceCenter;
  double geofenceRadius = 100; // meters

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      geofenceCenter = latlng;
    });

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Set Geofence Radius',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    min: 50,
                    max: 1000,
                    divisions: 19,
                    label: '${geofenceRadius.round()} m',
                    value: geofenceRadius,
                    onChanged: (value) {
                      setModalState(() => geofenceRadius = value);
                      setState(() => geofenceRadius = value);
                    },
                  ),
                  Text('${geofenceRadius.round()} meters'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Geofence set!")),
                      );
                    },
                    child: const Text("Save Geofence"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Geofence')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter:
              geofenceCenter ??
              LatLng(10.3157, 123.8854), // default to Cebu City
          initialZoom: 15.0,
          onTap: _onMapTap,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.smart_resilience_app',
          ),
          if (geofenceCenter != null)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: geofenceCenter!,
                  color: Colors.blue.withOpacity(0.3),
                  borderStrokeWidth: 2,
                  borderColor: Colors.blue,
                  useRadiusInMeter: true,
                  radius: geofenceRadius,
                ),
              ],
            ),
          if (geofenceCenter != null)
            MarkerLayer(
              markers: [
                Marker(
                  width: 60,
                  height: 60,
                  point: geofenceCenter!,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
