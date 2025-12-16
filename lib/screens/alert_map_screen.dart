// lib/screens/alert_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AlertMapScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String alertStatus; // 'entry', 'exit', 'panic', etc.
  final String deviceId;
  final String? childName; // NEW: Optional child name
  final DateTime timestamp;
  final List<Map<String, dynamic>>? otherAlerts; // Other alerts to display
  final Function(String deviceId, int timestamp)?
  onAlertViewed; // NEW: Callback when alert is viewed

  const AlertMapScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.alertStatus,
    required this.deviceId,
    this.childName,
    required this.timestamp,
    this.otherAlerts,
    this.onAlertViewed,
  });

  @override
  State<AlertMapScreen> createState() => _AlertMapScreenState();
}

class _AlertMapScreenState extends State<AlertMapScreen> {
  late LatLng _alertLocation;
  final MapController _mapController = MapController();
  double _currentZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _alertLocation = LatLng(widget.lat, widget.lng);

    // NEW: Mark alert as viewed when map screen is opened
    if (widget.onAlertViewed != null) {
      widget.onAlertViewed!(
        widget.deviceId,
        widget.timestamp.millisecondsSinceEpoch,
      );
    }

    // Center map on alert location after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(_alertLocation, 16.0);
      } catch (e) {
        // swallow errors if controller isn't ready
      }
    });
  }

  // Get color based on alert status
  Color _getStatusColor() {
    switch (widget.alertStatus.toLowerCase()) {
      case 'entry':
        return Colors.green;
      case 'exit':
        return Colors.orange;
      case 'panic':
      case 'sos':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  // Get icon based on alert status
  IconData _getStatusIcon() {
    switch (widget.alertStatus.toLowerCase()) {
      case 'entry':
        return Icons.login;
      case 'exit':
        return Icons.logout;
      case 'panic':
      case 'sos':
        return Icons.warning_rounded;
      default:
        return Icons.location_on;
    }
  }

  // Get status label
  String _getStatusLabel() {
    switch (widget.alertStatus.toLowerCase()) {
      case 'entry':
        return 'Geofence Entry';
      case 'exit':
        return 'Geofence Exit';
      case 'panic':
      case 'sos':
        return 'Panic Alert';
      default:
        return 'Alert';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_getStatusLabel()} - ${widget.childName ?? widget.deviceId}',
        ),
        elevation: 0,
        backgroundColor: _getStatusColor(),
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _alertLocation,
              initialZoom: 16.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              maxZoom: 18.0,
              minZoom: 10.0,
            ),
            children: [
              // OpenStreetMap tiles
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.smart_resilience_app',
                maxZoom: 18,
                tileSize: 256,
                retinaMode: false,
              ),
              // Display other alerts if provided
              if (widget.otherAlerts != null && widget.otherAlerts!.isNotEmpty)
                MarkerLayer(
                  markers: widget.otherAlerts!
                      .where((alert) {
                        // Don't display the main alert marker twice
                        return !(alert['lat'] == widget.lat &&
                            alert['lng'] == widget.lng);
                      })
                      .map((alert) {
                        final alertLat = (alert['lat'] as num).toDouble();
                        final alertLng = (alert['lng'] as num).toDouble();
                        final alertStatus =
                            (alert['status'] as String? ?? 'unknown')
                                .toLowerCase();

                        Color markerColor = Colors.blue;
                        if (alertStatus == 'entry') {
                          markerColor = Colors.green;
                        } else if (alertStatus == 'exit') {
                          markerColor = Colors.orange;
                        } else if (alertStatus == 'panic' ||
                            alertStatus == 'sos') {
                          markerColor = Colors.red;
                        }

                        return Marker(
                          point: LatLng(alertLat, alertLng),
                          width: 40,
                          height: 40,
                          child: GestureDetector(
                            onTap: () {
                              _mapController.move(
                                LatLng(alertLat, alertLng),
                                16.0,
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: markerColor.withOpacity(0.8),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  alertStatus == 'entry'
                                      ? Icons.login
                                      : alertStatus == 'exit'
                                      ? Icons.logout
                                      : Icons.warning_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              // Main alert marker (current alert)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _alertLocation,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getStatusColor().withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _getStatusColor().withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _getStatusIcon(),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Alert details card at the bottom
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    top: BorderSide(color: _getStatusColor(), width: 4),
                  ),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getStatusIcon(),
                            color: _getStatusColor(),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusLabel(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Device: ${widget.childName ?? widget.deviceId}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${widget.lat.toStringAsFixed(6)}, ${widget.lng.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.timestamp.toString(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getStatusColor(),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Close Map',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Zoom controls (optional)
          Positioned(
            bottom: 140,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  onPressed: () {
                    setState(() {
                      _currentZoom = (_currentZoom + 1).clamp(10.0, 18.0);
                    });
                    _mapController.move(_alertLocation, _currentZoom);
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  onPressed: () {
                    setState(() {
                      _currentZoom = (_currentZoom - 1).clamp(10.0, 18.0);
                    });
                    _mapController.move(_alertLocation, _currentZoom);
                  },
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.remove, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
