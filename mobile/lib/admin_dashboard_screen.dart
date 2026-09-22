import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const String _filterPreferenceKey = 'allways_admin_order_status_filter';
  static const List<String> _statuses = <String>['Pending', 'Preparing', 'Out for delivery', 'Delivered'];

  String _search = '';
  String _statusFilter = 'All';
  bool _loadingPreference = true;

  @override
  void initState() {
    super.initState();
    _loadSavedFilter();
  }

  Future<void> _loadSavedFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFilter = prefs.getString(_filterPreferenceKey);
      if (!mounted) return;
      setState(() {
        if (savedFilter != null && (savedFilter == 'All' || _statuses.contains(savedFilter))) {
          _statusFilter = savedFilter;
        }
        _loadingPreference = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPreference = false);
    }
  }

  Future<void> _saveFilter(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_filterPreferenceKey, value);
    } catch (_) {}
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  String _orderId(Map<String, dynamic> order, String fallback) {
    final id = _stringValue(order['orderId']);
    if (id.isNotEmpty) return id;
    final legacyId = _stringValue(order['id']);
    if (legacyId.isNotEmpty) return legacyId;
    return fallback;
  }

  String _normaliseStatus(dynamic value) {
    final status = _stringValue(value);
    if (status.isEmpty || status == 'New Order') return 'Pending';
    return status;
  }

  String _customerDetails(Map<String, dynamic> order) {
    final lines = <String>[
      if (_stringValue(order['name']).isNotEmpty) _stringValue(order['name']),
      if (_stringValue(order['email']).isNotEmpty) _stringValue(order['email']),
      if (_stringValue(order['phone']).isNotEmpty) _stringValue(order['phone']),
      if (_stringValue(order['address']).isNotEmpty) _stringValue(order['address']),
    ];
    return lines.isEmpty ? 'Customer details unavailable' : lines.join('\n');
  }

  Future<void> _updateStatus(BuildContext context, String orderId, String status) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': status,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #$orderId updated to $status')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update order: $e')),
      );
    }
  }

  Widget _orderCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final order = document.data();
    final id = _orderId(order, document.id);
    final status = _normaliseStatus(order['status']);
    final total = order['total'] ?? order['grandTotal'] ?? order['amount'] ?? 0;
    final selectedStatus = _statuses.contains(status) ? status : 'Pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$id', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(_customerDetails(order), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 10),
            Text('Total: ₹$total', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Status:', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: _statuses.map((status) => DropdownMenuItem<String>(value: status, child: Text(status))).toList(),
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
    if (_loadingPreference) {
      return const Scaffold(
        appBar: AppBar(title: Text('ALLways Admin Dashboard')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ALLways Admin Dashboard')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search Order ID',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by status',
                prefixIcon: Icon(Icons.filter_list),
                border: OutlineInputBorder(),
              ),
              items: <String>['All', ..._statuses]
                  .map((status) => DropdownMenuItem<String>(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
                _saveFilter(value);
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load orders:\n' + snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allOrders = snapshot.data?.docs ?? const [];
                final orders = allOrders.where((document) {
                  final data = document.data();
                  final id = _orderId(data, document.id).toLowerCase();
                  final status = _normaliseStatus(data['status']);
                  final matchesSearch = _search.isEmpty || id.contains(_search);
                  final matchesStatus = _statusFilter == 'All' || status == _statusFilter;
                  return matchesSearch && matchesStatus;
                }).toList();

                if (orders.isEmpty) {
                  return Center(
                    child: Text(allOrders.isEmpty
                        ? 'No orders yet.'
                        : 'No orders match the current filters.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) => _orderCard(context, orders[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
