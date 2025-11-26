// lib/screens/route_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_resilience_app/screens/profile_page.dart';
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
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

      // cancel previous profile listener
      await _profileDocSubscription?.cancel();

      if (user != null) {
        _profileDocSubscription = FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              if (snapshot.exists && snapshot.data() != null) {
                final data = snapshot.data() as Map<String, dynamic>;
                setState(() {
                  _currentUserName =
                      data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                  _currentUserPhotoUrl = data['photoUrl'] as String?;
                });
              }
            });
      } else {
        setState(() {
          _currentUserName = null;
          _currentUserPhotoUrl = null;
        });
      }
    });

    _loadRoutePoints();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _profileDocSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRoutePoints() async {
    setState(() {
      _isLoadingRoute = true;
    });

    try {
      // --- MOCK DATA FOR DEMONSTRATION ---
      // These points simulate a route around Bacolod City.
      // In a real application, these would be fetched from Firestore.
      List<LatLng> mockPoints = [
        LatLng(10.6667, 122.95), // Starting point (e.g., near city center)
        LatLng(10.6680, 122.9510), // Move slightly North-East
        LatLng(10.6695, 122.9530), // Further North-East
        LatLng(10.6670, 122.9550), // Move South-East
        LatLng(10.6650, 122.9545), // South
        LatLng(10.6640, 122.9520), // South-West
        LatLng(10.6655, 122.9490), // Back towards starting area
      ];

      // Add more points if you want a longer, more complex mock route
      // For example, if you want to show movement over a full day, you'd have many more points.
      // For a single day's history, we'll use these few to demonstrate the polyline.

      if (mockPoints.isNotEmpty) {
        _mapCenter = mockPoints.first; // Center on the start of the mock route
        // Adjust zoom to fit all mock points
        double minLat = mockPoints
            .map((p) => p.latitude)
            .reduce((a, b) => a < b ? a : b);
        double maxLat = mockPoints
            .map((p) => p.latitude)
            .reduce((a, b) => a > b ? a : b);
        double minLng = mockPoints
            .map((p) => p.longitude)
            .reduce((a, b) => a < b ? a : b);
        double maxLng = mockPoints
            .map((p) => p.longitude)
            .reduce((a, b) => a > b ? a : b);

        // Calculate bounds and center for the mock data
        LatLngBounds bounds = LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        );

        // A simple way to estimate zoom for bounds (FlutterMap's MapController.fitBounds is better for real-time)
        double latDiff = bounds.north - bounds.south;
        double lngDiff = bounds.east - bounds.west;

        if (latDiff == 0 && lngDiff == 0) {
          _mapZoom = 16.0; // Stay zoomed in on a single point
        } else {
          // Approximate zoom level based on the span of coordinates
          // These values are empirical and might need fine-tuning
          _mapZoom = 14.0 - (latDiff.abs() * 50 + lngDiff.abs() * 50);
          if (_mapZoom < 12)
            _mapZoom = 12; // Minimum reasonable zoom for a route
          if (_mapZoom > 17) _mapZoom = 17; // Maximum zoom
          _mapCenter = bounds.center;
        }
      }

      setState(() {
        _routePoints = mockPoints;
      });
      // --- END MOCK DATA ---
    } catch (e) {
      print("Error loading route points (mock data simulation): $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error loading route: $e")));
      }
    } finally {
      setState(() {
        _isLoadingRoute = false;
      });
    }
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
        title: Text(
          '${widget.childName}\'s Route on ${DateFormat('MMM d, yyyy').format(widget.selectedDate)}',
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ProfileAvatar(
              photoPath: _currentUserPhotoUrl,
              displayName: _currentUserName,
              radius: 18,
              onProfileUpdated: (updated) async {
                if (updated == true && _currentUser != null) {
                  final doc = await FirebaseFirestore.instance
                      .collection('guardians')
                      .doc(_currentUser!.uid)
                      .get();
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
                }
              },
            ),
          ),
        ],
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
        child: bodyContent,
      ),
    );
  }
}
