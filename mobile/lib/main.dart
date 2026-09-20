import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AllwaysApp());
}

class AllwaysApp extends StatelessWidget {
  const AllwaysApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ALLways',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black)),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('products').snapshots();
    return Scaffold(
      appBar: AppBar(
        title: const Text('ALLways', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: () => _showSignIn(context), icon: const Icon(Icons.person_outline))],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await FirebaseFirestore.instance.collection('products').get(); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Deliver to', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            const Row(children: [
              Icon(Icons.location_on_outlined, size: 20),
              SizedBox(width: 6),
              Expanded(child: Text('Choose your delivery location at checkout', style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: Colors.black),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ALLways local', style: TextStyle(color: Colors.white70, fontSize: 13)),
                SizedBox(height: 8),
                Text('Everything you need, closer to home.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Shop local essentials. Simple ordering.', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            const SizedBox(height: 22),
            const Text('Categories', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: const [
              _CategoryChip(icon: Icons.shopping_basket_outlined, label: 'Groceries'),
              _CategoryChip(icon: Icons.local_drink_outlined, label: 'Dairy'),
              _CategoryChip(icon: Icons.fastfood_outlined, label: 'Food'),
              _CategoryChip(icon: Icons.devices_outlined, label: 'Electronics'),
            ]),
            const SizedBox(height: 24),
            const Text('Items', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
                if (snapshot.hasError) return _InfoCard(message: 'Firebase connection needs to be configured.', detail: snapshot.error.toString());
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) return const _InfoCard(message: 'No items available yet.', detail: 'Items added to the shared Firebase inventory will appear here.');
                return Column(children: docs.map((doc) {
                  final data = doc.data();
                  final name = (data['name'] ?? data['title'] ?? 'Item').toString();
                  final price = data['price'];
                  final available = data['available'] ?? data['isAvailable'] ?? true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(price == null ? 'Price not set' : '₹$price'),
                      trailing: available == true ? const Icon(Icons.check_circle_outline) : const Text('Unavailable'),
                    ),
                  );
                }).toList());
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: const NavigationBar(selectedIndex: 0, destinations: [
        NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'Shop'),
        NavigationDestination(icon: Icon(Icons.directions_car_outlined), label: 'Travel'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
      ]),
    );
  }

  void _showSignIn(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: currentUser == null
          ? const Text('Customer sign-in will use the existing ALLways Firebase Authentication.', style: TextStyle(fontSize: 16))
          : Text('Signed in as ' + (currentUser.email ?? currentUser.uid)),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon; final String label;
  const _CategoryChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class _InfoCard extends StatelessWidget {
  final String message; final String detail;
  const _InfoCard({required this.message, required this.detail});
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(detail, style: const TextStyle(color: Colors.grey)),
    ]),
  ));
}
