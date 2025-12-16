// lib/screens/route_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart'; // For date formatting

class RouteMapScreen extends StatefulWidget {
  final String userId;
  final String childId;
  final String childName;
  final DateTime selectedDate;

  const RouteMapScreen({
    super.key,
    required this.userId,
    required this.childId,
    required this.childName,
    required this.selectedDate,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  User? _currentUser;
  String? _currentUserName;
  String? _currentUserPhotoUrl;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;
  StreamSubscription<DatabaseEvent>? _historySubscription;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = true;
  LatLng _mapCenter = LatLng(10.6667, 122.95); // Default to Bacolod
  double _mapZoom = 14.0;

  @override
  void initState() {
    super.initState();
    // Start listening to auth/profile changes so the app bar avatar stays in sync
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (!mounted) return;
      _currentUser = user;

      // cancel previous subscriptions
      await _profileDocSubscription?.cancel();
      await _historySubscription?.cancel();

      if (user != null) {
        // keep profile avatar/name in sync
        _profileDocSubscription = FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
              if (!mounted) return;
              if (doc.exists && doc.data() != null) {
                final data = doc.data() as Map<String, dynamic>;
                setState(() {
                  _currentUserName =
                      data['fullName'] ??
                      _currentUser!.phoneNumber ??
                      'Guardian';
                  _currentUserPhotoUrl = data['photoUrl'] as String?;
                });
              }
            });

        setState(() => _isLoadingRoute = true);

        try {
          final db = FirebaseDatabase.instance;
          final ref = db.ref('history/${widget.childId}');

          // Cancel previous subscription if any
          await _historySubscription?.cancel();

          _historySubscription = ref.onValue.listen((DatabaseEvent event) {
            if (!mounted) return;

            final snapshot = event.snapshot;
            final value = snapshot.value;

            List<Map<String, dynamic>> entries = [];

            if (value != null) {
              if (value is Map) {
                value.forEach((key, v) {
                  Map<String, dynamic>? entry;
                  if (v is Map)
                    entry = Map<String, dynamic>.from(v);
                  else if (v is String) {
                    try {
                      final decoded = jsonDecode(v);
                      if (decoded is Map)
                        entry = Map<String, dynamic>.from(decoded);
                    } catch (_) {}
                  }
                  if (entry != null) {
                    entry['__key'] = key;
                    entries.add(entry);
                  }
                });
              } else if (value is List) {
                for (var v in value) {
                  if (v is Map)
                    entries.add(Map<String, dynamic>.from(v));
                  else if (v is String) {
                    try {
                      final decoded = jsonDecode(v);
                      if (decoded is Map)
                        entries.add(Map<String, dynamic>.from(decoded));
                    } catch (_) {}
                  }
                }
              }
            }

            // Normalize & filter by date, allow lat/lng or lat/lon
            List<Map<String, dynamic>> datedPoints = [];
            for (var e in entries) {
              final tsRaw = e['timestamp'];
              int ts = 0;
              if (tsRaw is int)
                ts = tsRaw;
              else if (tsRaw is String)
                ts = int.tryParse(tsRaw) ?? 0;
              if (ts > 0 && ts < 10000000000) ts = ts * 1000;
              if (ts <= 0) continue;

              final dt = DateTime.fromMillisecondsSinceEpoch(ts);
              if (dt.year == widget.selectedDate.year &&
                  dt.month == widget.selectedDate.month &&
                  dt.day == widget.selectedDate.day) {
                double lat = 0.0;
                double lng = 0.0;
                // possible key variants
                final latKeys = ['lat', 'latitude', 'Lat', 'LAT'];
                final lngKeys = ['lng', 'lon', 'longitude', 'Lon', 'LON'];
                for (var k in latKeys) {
                  if (e.containsKey(k)) {
                    lat = double.tryParse(e[k]?.toString() ?? '') ?? lat;
                    break;
                  }
                }
                for (var k in lngKeys) {
                  if (e.containsKey(k)) {
                    lng = double.tryParse(e[k]?.toString() ?? '') ?? lng;
                    break;
                  }
                }

                if (lat != 0.0 || lng != 0.0) {
                  datedPoints.add({'ts': ts, 'lat': lat, 'lng': lng});
                }
              }
            }

            // Sort & convert
            datedPoints.sort(
              (a, b) => (a['ts'] as int).compareTo(b['ts'] as int),
            );
            final points = datedPoints
                .map((p) => LatLng((p['lat'] as double), (p['lng'] as double)))
                .toList();

            // compute center/zoom similar to previous logic
            LatLng mapCenter = _mapCenter;
            double mapZoom = _mapZoom;
            if (points.isNotEmpty) {
              mapCenter = points.first;
              double minLat = points
                  .map((p) => p.latitude)
                  .reduce((a, b) => a < b ? a : b);
              double maxLat = points
                  .map((p) => p.latitude)
                  .reduce((a, b) => a > b ? a : b);
              double minLng = points
                  .map((p) => p.longitude)
                  .reduce((a, b) => a < b ? a : b);
              double maxLng = points
                  .map((p) => p.longitude)
                  .reduce((a, b) => a > b ? a : b);
              LatLngBounds bounds = LatLngBounds(
                LatLng(minLat, minLng),
                LatLng(maxLat, maxLng),
              );
              double latDiff = bounds.north - bounds.south;
              double lngDiff = bounds.east - bounds.west;
              if (latDiff == 0 && lngDiff == 0) {
                mapZoom = 16.0;
              } else {
                mapZoom = 14.0 - (latDiff.abs() * 50 + lngDiff.abs() * 50);
                if (mapZoom < 12) mapZoom = 12;
                if (mapZoom > 17) mapZoom = 17;
                mapCenter = bounds.center;
              }
            }

            setState(() {
              _routePoints = points;
              _mapCenter = mapCenter;
              _mapZoom = mapZoom;
              _isLoadingRoute = false;
            });
          });
        } catch (e) {
          print("Error loading route points from RTDB: $e");
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Error loading route: $e")));
          }
          setState(() => _isLoadingRoute = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _profileDocSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the body in a static gradient container (same as HomeScreen)
    final Widget bodyContent = _isLoadingRoute
        ? const Center(child: CircularProgressIndicator())
        : _routePoints.isEmpty
        ? const Center(child: Text('No route data available for this day.'))
        : FlutterMap(
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: _mapZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.smart_resilience_app',
              ),
              // Draw the polyline for the route
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: Colors.blue,
                  ),
                ],
              ),
              // Markers for start and end points
              MarkerLayer(
                markers: [
                  // Start point marker
                  if (_routePoints.isNotEmpty)
                    Marker(
                      point: _routePoints.first,
                      width: 80,
                      height: 80,
                      child: Column(
                        children: [
                          const Icon(Icons.flag, color: Colors.green, size: 30),
                          Text(
                            'Start',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  // End point marker (if different from start)
                  if (_routePoints.length > 1)
                    Marker(
                      point: _routePoints.last,
                      width: 80,
                      height: 80,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 30,
                          ),
                          Text(
                            'End',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Route'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.shade100,
              Colors.blue.shade100,
              Colors.green.shade50,
            ],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMMM d, yyyy').format(widget.selectedDate),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: bodyContent),
          ],
        ),
      ),
    );
  }
}
