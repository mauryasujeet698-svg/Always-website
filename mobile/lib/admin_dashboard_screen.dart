import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  static const List<String> _statuses = <String>[
    'Pending',
    'Preparing',
    'Out for delivery',
    'Delivered',
  ];

  Future<void> _updateStatus(BuildContext context, String orderId, String status) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': status,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #$orderId updated to $status')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update order: $e')),
        );
      }
    }
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  String _customerDetails(Map<String, dynamic> order) {
    final name = _stringValue(order['name']);
    final email = _stringValue(order['email']);
    final phone = _stringValue(order['phone']);
    final address = _stringValue(order['address']);
    final lines = <String>[
      if (name.isNotEmpty) name,
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
      if (address.isNotEmpty) address,
    ];
    return lines.isEmpty ? 'Customer details unavailable' : lines.join('\n');
  }

  Widget _orderCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final order = document.data();
    final orderId = _stringValue(order['orderId']).isNotEmpty
        ? _stringValue(order['orderId'])
        : (_stringValue(order['id']).isNotEmpty ? _stringValue(order['id']) : document.id);
    final status = _stringValue(order['status']).isNotEmpty ? _stringValue(order['status']) : 'Pending';
    final total = order['total'] ?? order['grandTotal'] ?? order['amount'] ?? 0;
    final selectedStatus = _statuses.contains(status) ? status : _statuses.first;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$orderId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(_customerDetails(order), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 10),
            Text('Total: ₹$total', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Status:', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: _statuses.map((value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    onChanged: (value) {
                      if (value == null || value == status) return;
                      _updateStatus(context, document.id, value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ALLways Admin Dashboard')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Could not load orders: ${snapshot.error}')));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data?.docs ?? const [];
          if (orders.isEmpty) return const Center(child: Text('No orders yet.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) => _orderCard(context, orders[index]),
          );
        },
      ),
    );
  }
}
