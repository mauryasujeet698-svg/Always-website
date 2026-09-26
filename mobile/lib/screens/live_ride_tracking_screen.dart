import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = const [];
  LatLng? _driverLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  double _markerRotation = 0.0;
  String _contactPhone = '';
  String _rideStatus = 'searching';
  bool _cameraFitted = false;

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

      LatLng? newPickup;
      LatLng? newDestination;
      LatLng? newDriver;

      if (data['pickupLat'] is num && data['pickupLng'] is num) {
        newPickup = LatLng(
          (data['pickupLat'] as num).toDouble(),
          (data['pickupLng'] as num).toDouble(),
        );
      }
      if (data['destLat'] is num && data['destLng'] is num) {
        newDestination = LatLng(
          (data['destLat'] as num).toDouble(),
          (data['destLng'] as num).toDouble(),
        );
      }
      if (data['driverLat'] is num && data['driverLng'] is num) {
        newDriver = LatLng(
          (data['driverLat'] as num).toDouble(),
          (data['driverLng'] as num).toDouble(),
        );
      }

      setState(() {
        _rideStatus = (data['status'] ?? 'searching').toString();
        _contactPhone = widget.isRider
            ? (data['customerPhone'] ?? '').toString()
            : (data['driverPhone'] ?? '').toString();

        _pickupLocation = newPickup;
        _destinationLocation = newDestination;

        if (newDriver != null) {
          if (_driverLocation != null) {
            _markerRotation = _getBearing(_driverLocation!, newDriver);
          }
          _driverLocation = newDriver;
        }
      });

      if (newPickup != null &&
          newDestination != null &&
          (_routePoints.isEmpty ||
              _pickupLocation != newPickup ||
              _destinationLocation != newDestination)) {
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

      final geometry = routes.first['geometry'];
      final coordinates = geometry is Map ? geometry['coordinates'] : null;
      if (coordinates is! List) return;

      final points = coordinates
          .whereType<List>()
          .where((c) => c.length >= 2)
          .map(
            (c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() => _routePoints = points);
      _fitCameraIfReady();
    } catch (_) {
      // Keep the existing screen usable if the free public OSRM endpoint
      // temporarily fails.
    }
  }

  Future<void> _fitCameraIfReady() async {
    if (_mapController == null) return;

    final points = <LatLng>[
      if (_pickupLocation != null) _pickupLocation!,
      if (_destinationLocation != null) _destinationLocation!,
      if (_driverLocation != null) _driverLocation!,
    ];

    if (points.isEmpty) return;

    if (points.length == 1) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 14.5),
        ),
      );
      return;
    }

    if (_cameraFitted && _driverLocation != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _driverLocation!, zoom: 15),
        ),
      );
      return;
    }

    final lats = points.map((p) => p.latitude).toList();
    final lngs = points.map((p) => p.longitude).toList();

    final bounds = LatLngBounds(
      southwest: LatLng(
        lats.reduce(math.min),
        lngs.reduce(math.min),
      ),
      northeast: LatLng(
        lats.reduce(math.max),
        lngs.reduce(math.max),
      ),
    );

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 70),
      );
      _cameraFitted = true;
    } catch (_) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 14),
        ),
      );
    }
  }

  Set<Marker> _markers() {
    return {
      if (_pickupLocation != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      if (_destinationLocation != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      if (_driverLocation != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLocation!,
          rotation: _markerRotation,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          infoWindow: const InfoWindow(title: 'Ride partner'),
        ),
    };
  }

  Set<Polyline> _polylines() {
    if (_routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('osrm_route'),
        points: _routePoints,
        width: 5,
        color: Colors.deepPurple,
        geodesic: false,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final center =
        _pickupLocation ?? const LatLng(25.9123, 81.9876);

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
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: center,
              zoom: 14.5,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitCameraIfReady();
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            markers: _markers(),
            polylines: _polylines(),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
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
                        CarrierAndAdminController.triggerPhoneCall(
                      _contactPhone,
                    ),
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
