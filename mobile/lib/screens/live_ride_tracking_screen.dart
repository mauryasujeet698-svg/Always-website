import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../controllers/carrier_and_admin_controller.dart';

class LiveRideTrackingScreen extends StatefulWidget {
  final String rideId;
  final bool isRider;
  const LiveRideTrackingScreen({super.key, required this.rideId, this.isRider = false});
  @override State<LiveRideTrackingScreen> createState() => _LiveRideTrackingScreenState();
}

class _LiveRideTrackingScreenState extends State<LiveRideTrackingScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = const [];
  LatLng? _driverLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  double _markerRotation = 0.0;
  String _contactPhone = '';
  String _rideStatus = 'searching';
  bool _cameraFitted = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initRideStream();
  }

  void _initRideStream() {
    FirebaseFirestore.instance.collection('autoRideRequests').doc(widget.rideId).snapshots().listen((doc) {
      if (!mounted || !doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      LatLng? newPickup;
      LatLng? newDestination;
      LatLng? newDriver;

      if (data['pickupLat'] is num && data['pickupLng'] is num) {
        newPickup = LatLng((data['pickupLat'] as num).toDouble(), (data['pickupLng'] as num).toDouble());
      }
      if (data['destLat'] is num && data['destLng'] is num) {
        newDestination = LatLng((data['destLat'] as num).toDouble(), (data['destLng'] as num).toDouble());
      }
      if (data['driverLat'] is num && data['driverLng'] is num) {
        newDriver = LatLng((data['driverLat'] as num).toDouble(), (data['driverLng'] as num).toDouble());
      }

      final routeChanged = _pickupLocation?.latitude != newPickup?.latitude ||
          _pickupLocation?.longitude != newPickup?.longitude ||
          _destinationLocation?.latitude != newDestination?.latitude ||
          _destinationLocation?.longitude != newDestination?.longitude;

      setState(() {
        _rideStatus = (data['status'] ?? 'searching').toString();
        _contactPhone = widget.isRider ? (data['customerPhone'] ?? '').toString() : (data['driverPhone'] ?? '').toString();
        _pickupLocation = newPickup;
        _destinationLocation = newDestination;
        if (newDriver != null) {
          if (_driverLocation != null) _markerRotation = _getBearing(_driverLocation!, newDriver);
          _driverLocation = newDriver;
        }
      });

      if (newPickup != null && newDestination != null && (_routePoints.isEmpty || routeChanged)) {
        _loadOSRMRoute(newPickup, newDestination);
      }
      _fitCameraIfReady();
    });
  }

  double _getBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lng1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lng2 = end.longitude * math.pi / 180;
    final dLon = lng2 - lng1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _loadOSRMRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );
    try {
      final res = await http.get(url);
      if (!mounted || res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return;
      final geometry = routes.first['geometry'];
      final coordinates = geometry is Map ? geometry['coordinates'] : null;
      if (coordinates is! List) return;
      final points = coordinates.whereType<List>().where((c) => c.length >= 2).map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      if (!mounted) return;
      setState(() => _routePoints = points);
      _fitCameraIfReady();
    } catch (_) {}
  }

  void _fitCameraIfReady() {
    if (!_mapReady) return;
    final points = <LatLng>[
      if (_pickupLocation != null) _pickupLocation!,
      if (_destinationLocation != null) _destinationLocation!,
      if (_driverLocation != null) _driverLocation!,
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14.5);
      return;
    }
    if (_cameraFitted && _driverLocation != null) {
      _mapController.move(_driverLocation!, 15);
      return;
    }
    try {
      _mapController.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(70)));
      _cameraFitted = true;
    } catch (_) {
      _mapController.move(points.first, 14);
    }
  }

  Widget _circleMarker({required Color color, required IconData icon, double size = 58}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }

  List<Marker> _markers() => [
    if (_pickupLocation != null)
      Marker(point: _pickupLocation!, width: 62, height: 62, child: _circleMarker(color: Colors.green, icon: Icons.check)),
    if (_driverLocation != null)
      Marker(
        point: _driverLocation!,
        width: 62,
        height: 62,
        child: Transform.rotate(
          angle: _markerRotation * math.pi / 180,
          child: _circleMarker(color: const Color(0xFF673AB7), icon: Icons.two_wheeler),
        ),
      ),
    if (_destinationLocation != null)
      Marker(point: _destinationLocation!, width: 62, height: 62, child: _circleMarker(color: Colors.red, icon: Icons.flag)),
  ];

  @override
  Widget build(BuildContext context) {
    final center = _pickupLocation ?? const LatLng(25.9123, 81.9876);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F6F0),
        elevation: 0,
        title: const Text('Live ride tracking', style: TextStyle(color: Colors.black, fontSize: 18)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.5,
              onMapReady: () {
                _mapReady = true;
                _fitCameraIfReady();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                maxZoom: 19,
                userAgentPackageName: 'com.allways.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _routePoints, color: const Color(0xFF673AB7), strokeWidth: 5),
                  ],
                ),
              MarkerLayer(markers: _markers()),
            ],
          ),
          Positioned(
            top: 12, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEF),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 12),
                  SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Live ride tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Partner location is updating live', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ])),
                  Icon(Icons.my_location, color: Colors.black87),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEF),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler, color: Colors.black87, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(child: Text(
                    'Green pickup • Red destination • Purple moving bike',
                    style: TextStyle(color: Colors.black87, fontSize: 14),
                  )),
                  TextButton(
                    onPressed: () => CarrierAndAdminController.triggerPhoneCall(_contactPhone),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E5A73))),
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
