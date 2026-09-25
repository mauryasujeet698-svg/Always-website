import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrderDetailsScreen extends StatelessWidget {
  final String orderId;

  const OrderDetailsScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ORDER DETAILS',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('Help', style: TextStyle(color: Colors.black87)),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data()!;
          final status = (data['status'] ?? 'New Order').toString();
          final items = (data['items'] as List<dynamic>?) ?? const [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Order #$orderId',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                'Placed on ${data['placedAt'] ?? 'Recent'}',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF9E1B46),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER ${status.toUpperCase()}!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your essentials are tracked in realtime',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.delivery_dining,
                      color: Colors.white,
                      size: 48,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildTimeline(status),
              const SizedBox(height: 20),
              const Text(
                'Items in Order',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              ...items.map(
                (it) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (it['name'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text('${it['quantity'] ?? 1}x'),
                  trailing: Text(
                    '₹${it['price'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Total Paid',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Text(
                  '₹${data['totalAmount'] ?? 0}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimeline(String currentStatus) {
    final stages = [
      'New Order',
      'Confirmed',
      'Preparing',
      'Out for delivery',
      'Delivered',
    ];
    int currentIndex = stages.indexOf(currentStatus);
    if (currentIndex == -1) currentIndex = 2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(stages.length, (idx) {
        final isCompleted = idx <= currentIndex;
        return Column(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor:
                  isCompleted ? Colors.blue : Colors.grey.shade300,
              child: Icon(
                Icons.check,
                size: 14,
                color: isCompleted ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stages[idx],
              style: TextStyle(
                fontSize: 9,
                color: isCompleted ? Colors.black87 : Colors.black38,
              ),
            ),
          ],
        );
      }),
    );
  }
}
