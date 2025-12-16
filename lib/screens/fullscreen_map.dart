// lib/screens/fullscreen_map.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FullscreenMap extends StatefulWidget {
  final LatLng initialLocation;
  final double initialRadius;
  final String initialZoneName;
  final String? initialSafeZoneId;
  final bool isForAddingOrEditing;
  final List<Map<String, dynamic>>?
  allSafeZones; // These should already be filtered by HomeScreen
  final List<Map<String, dynamic>>? allChildLocations;
  final String userId;

  const FullscreenMap({
    super.key,
    required this.initialLocation,
    required this.initialRadius,
    required this.initialZoneName,
    this.initialSafeZoneId,
    required this.isForAddingOrEditing,
    this.allSafeZones,
    this.allChildLocations,
    required this.userId,
  });

  @override
  State<FullscreenMap> createState() => _FullscreenMapState();
}

class _FullscreenMapState extends State<FullscreenMap> {
  late LatLng _currentLocation;
  late double _currentRadius;
  late String _currentZoneName;
  final MapController _mapController = MapController();
  TextEditingController? _zoneNameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _currentRadius = widget.initialRadius;
    _currentZoneName = widget.initialZoneName;
    _zoneNameController = TextEditingController(text: _currentZoneName);

    // If parent passed child locations (device locations), prefer centering on the device
    if (widget.allChildLocations != null &&
        widget.allChildLocations!.isNotEmpty) {
      try {
        final first = widget.allChildLocations!.first;
        if (first['location'] is LatLng) {
          _currentLocation = first['location'] as LatLng;
        }
      } catch (e) {
        // ignore and fall back to initialLocation
      }

      // Ensure the controller moves after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentLocation, 16.0);
        } catch (e) {
          // swallow errors if controller isn't ready
        }
      });
    } else {
      // Only try to determine current position if adding/editing a zone,
      // and if the initial location is not already explicitly provided (e.g., from an existing zone)
      if (widget.isForAddingOrEditing && widget.initialSafeZoneId == null) {
        _determinePositionAndSetMapCenter();
      }
    }
  }

  @override
  void dispose() {
    _zoneNameController?.dispose();
    super.dispose();
  }

  Future<void> _determinePositionAndSetMapCenter() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Please enable them.'),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permissions are permanently denied, we cannot request permissions.',
          ),
        ),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      // Use a sensible default zoom when centering from device GPS
      try {
        _mapController.move(_currentLocation, 16.0);
      } catch (e) {
        // ignore
      }
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    if (widget.isForAddingOrEditing) {
      setState(() {
        _currentLocation = latLng;
      });
    }
  }

  Future<void> _saveSafeZone() async {
    setState(() {
      _isSaving = true;
    });

    // Ensure zone name is not empty
    if (_currentZoneName.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Safe Zone name cannot be empty.')),
      );
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      final safeZoneData = {
        'name': _currentZoneName,
        'lat': _currentLocation.latitude,
        'lng': _currentLocation.longitude,
        'radius': _currentRadius,
        'createdAt': FieldValue.serverTimestamp(),
        // Ensure isPlaceholder is false for actual data
        'isPlaceholder': false,
      };

      final ref = FirebaseFirestore.instance
          .collection('guardians')
          .doc(widget.userId)
          .collection('geofences');

      if (widget.initialSafeZoneId == null) {
        // Adding new safe zone
        await ref.add(safeZoneData);
      } else {
        // Updating existing safe zone
        await ref.doc(widget.initialSafeZoneId).update(safeZoneData);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Pop with 'true' to indicate success
    } catch (e) {
      print("Error saving safe zone: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving safe zone: $e")));
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isForAddingOrEditing
              ? (widget.initialSafeZoneId == null
                    ? 'Add Safe Zone'
                    : 'Edit Safe Zone')
              : 'Child Location',
        ),
        actions: [
          if (widget.isForAddingOrEditing)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _saveSafeZone,
                  ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 16.0,
              onTap: _onMapTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              maxZoom: 18.0,
              minZoom: 10.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.smart_resilience_app',
                maxZoom: 18,
                tileSize: 256,
                retinaMode: false,
              ),
              // Display existing safe zones (passed from HomeScreen)
              if (widget.allSafeZones != null)
                CircleLayer(
                  circles: widget.allSafeZones!.map((zone) {
                    // Assuming 'location' is already a LatLng object from HomeScreen
                    // And HomeScreen has already filtered out placeholders
                    return CircleMarker(
                      point: zone['location'], // Use the LatLng object directly
                      radius: zone['radius'],
                      color: Colors.blue.withOpacity(0.1),
                      borderColor: Colors.blueAccent,
                      borderStrokeWidth: 2,
                      useRadiusInMeter: true,
                    );
                  }).toList(),
                ),
              // Display child locations (passed from HomeScreen)
              if (widget.allChildLocations != null)
                MarkerLayer(
                  markers: widget.allChildLocations!.map((child) {
                    // Assuming 'location' is already a LatLng object from HomeScreen
                    return Marker(
                      point:
                          child['location'], // Use the LatLng object directly
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: child['color'],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            child['name'][0],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // Display the currently edited/added safe zone
              if (widget.isForAddingOrEditing)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentLocation,
                      radius: _currentRadius,
                      color: Colors.blue.withOpacity(0.2),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                      useRadiusInMeter: true,
                    ),
                  ],
                ),
              // Display the marker for the currently edited/added safe zone
              if (widget.isForAddingOrEditing)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Controls for name and radius when adding/editing
          if (widget.isForAddingOrEditing)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _zoneNameController,
                        decoration: const InputDecoration(
                          labelText: "Safe Zone Name",
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _currentZoneName = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text("Radius:"),
                          Expanded(
                            child: Slider(
                              value: _currentRadius,
                              min: 50,
                              max: 1000,
                              divisions: 19, // 50 to 1000 in steps of 50
                              label: "${_currentRadius.toInt()}m",
                              onChanged: (value) {
                                setState(() {
                                  _currentRadius = value;
                                });
                              },
                            ),
                          ),
                          Text("${_currentRadius.toInt()}m"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
