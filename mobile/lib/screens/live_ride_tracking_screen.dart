import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../controllers/carrier_and_admin_controller.dart';

class LiveRideTrackingScreen extends StatefulWidget {
  final String rideId;
  final bool isRider;

  const LiveRideTrackingScreen({
    super.key,
    required this.rideId,
    this.isRider = false,
  });

  @override
  State<LiveRideTrackingScreen> createState() => _LiveRideTrackingScreenState();
}

class _LiveRideTrackingScreenState extends State<LiveRideTrackingScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  LatLng? _driverLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  double _markerRotation = 0.0;
  String _contactPhone = '';
  String _rideStatus = 'searching';

  @override
  void initState() {
    super.initState();
    _initRideStream();
  }

  void _initRideStream() {
    FirebaseFirestore.instance
        .collection('autoRideRequests')
        .doc(widget.rideId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      setState(() {
        _rideStatus = (data['status'] ?? 'searching').toString();
        _contactPhone = widget.isRider
            ? (data['customerPhone'] ?? '').toString()
            : (data['driverPhone'] ?? '').toString();

        if (data['pickupLat'] is num && data['pickupLng'] is num) {
          _pickupLocation = LatLng(
            (data['pickupLat'] as num).toDouble(),
            (data['pickupLng'] as num).toDouble(),
          );
        }
        if (data['destLat'] is num && data['destLng'] is num) {
          _destinationLocation = LatLng(
            (data['destLat'] as num).toDouble(),
            (data['destLng'] as num).toDouble(),
          );
        }

        if (data['driverLat'] is num && data['driverLng'] is num) {
          final newLoc = LatLng(
            (data['driverLat'] as num).toDouble(),
            (data['driverLng'] as num).toDouble(),
          );
          if (_driverLocation != null) {
            _markerRotation = _getBearing(_driverLocation!, newLoc);
          }
          _driverLocation = newLoc;
        }
      });

      if (_routePoints.isEmpty &&
          _pickupLocation != null &&
          _destinationLocation != null) {
        _loadOSRMRoute(_pickupLocation!, _destinationLocation!);
      }
    });
  }

  double _getBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lng1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lng2 = end.longitude * math.pi / 180;
    final dLon = lng2 - lng1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _loadOSRMRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );
    try {
      final res = await http.get(url);
      if (!mounted || res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return;
      final coordinates = routes[0]['geometry']['coordinates'] as List;
      setState(() {
        _routePoints = coordinates
            .whereType<List>()
            .where((c) => c.length >= 2)
            .map((c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final center = _pickupLocation ?? const LatLng(25.9123, 81.9876);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E24),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Live ride tracking',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.allways.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.5,
                      color: Colors.black87,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_pickupLocation != null)
                    Marker(
                      point: _pickupLocation!,
                      width: 32,
                      height: 32,
                      child: const Icon(
                        Icons.radio_button_checked,
                        color: Colors.green,
                        size: 28,
                      ),
                    ),
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 32,
                      height: 32,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                  if (_driverLocation != null)
                    Marker(
                      point: _driverLocation!,
                      width: 50,
                      height: 50,
                      child: Transform.rotate(
                        angle: _markerRotation * (math.pi / 180),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF673AB7),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: const Icon(
                            Icons.two_wheeler,
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
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEF),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 12),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live ride tracking',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Partner location is updating live',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.my_location, color: Colors.black87),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF26262E),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10),
                ],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF673AB7),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isRider ? 'Customer' : 'Ride Partner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Status: $_rideStatus',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        CarrierAndAdminController.triggerPhoneCall(_contactPhone),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 20,
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
