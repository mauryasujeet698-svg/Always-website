import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class CarrierAndAdminController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveSearchingRides(String riderUid) {
    return _db
        .collection('autoRideRequests')
        .where('status', isEqualTo: 'searching')
        .snapshots();
  }

  Future<bool> acceptRideRequest(
    String rideId,
    String riderUid,
    Map<String, dynamic> riderData,
  ) async {
    final rideRef = _db.collection('autoRideRequests').doc(rideId);
    return _db.runTransaction((transaction) async {
      final snap = await transaction.get(rideRef);
      if (!snap.exists || snap.data()?['status'] != 'searching') {
        return false;
      }

      transaction.update(rideRef, {
        'status': 'accepted',
        'driverUid': riderUid,
        'driverName': riderData['name'] ?? '',
        'driverPhone': riderData['phone'] ?? '',
        'driverVehicleType': riderData['vehicleType'] ?? 'bike',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<void> rejectRideRequest(String rideId, String riderUid) async {
    await _db.collection('autoRideRequests').doc(rideId).update({
      'rejectedBy': FieldValue.arrayUnion([riderUid]),
    });
  }

  Future<void> assignDeliveryPartnerToOrder({
    required String orderId,
    required String carrierUid,
    required String carrierName,
    required String carrierPhone,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'pending_acceptance',
      'carrierUid': carrierUid,
      'carrierName': carrierName,
      'carrierPhone': carrierPhone,
      'assignmentUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> partnerAcceptOrder(String orderId) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'Assigned',
      'partnerAcceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> partnerRejectOrder(String orderId) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'unassigned',
      'carrierUid': null,
      'carrierName': null,
      'carrierPhone': null,
    });
  }

  static Future<void> triggerPhoneCall(String phoneNumber) async {
    if (phoneNumber.trim().isEmpty) return;
    final Uri uri = Uri(scheme: 'tel', path: phoneNumber.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
