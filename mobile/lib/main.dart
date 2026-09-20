import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const inventoryEndpoint =
    'https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec';

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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        ),
        home: const HomeScreen(),
      );
}

class Product {
  final String id;
  final String name;
  final String category;
  final String icon;
  final String description;
  final String brand;
  final num price;
  final num stock;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.description,
    required this.brand,
    required this.price,
    required this.stock,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    num number(dynamic value) {
      if (value is num) return value;
      return num.tryParse(value?.toString() ?? '') ?? 0;
    }

    return Product(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Item').toString(),
      category: (json['category'] ?? json['cat'] ?? 'Other').toString(),
      icon: (json['icon'] ?? '🛍️').toString(),
      description: (json['description'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      price: number(json['price']),
      stock: number(json['stock']),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> products = [];
  bool loading = true;
  String? error;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    loadInventory();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadInventory(silent: true);
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadInventory({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final uri = Uri.parse(
        inventoryEndpoint + '?_=' + DateTime.now().millisecondsSinceEpoch.toString(),
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Inventory server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map<String, dynamic>
          ? (decoded['products'] ?? decoded)
          : decoded;

      if (raw is! List) {
        throw Exception('Inventory response format is not supported');
      }

      final next = raw
          .whereType<Map>()
          .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (mounted) {
        setState(() {
          products = next;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      'All',
      ...products.map((p) => p.category),
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ALLways', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: () => _showSignIn(context),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadInventory,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Deliver to', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            const Row(children: [
              Icon(Icons.location_on_outlined, size: 20),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Choose your delivery location at checkout',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.black,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ALLways local', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 8),
                  Text(
                    'Everything you need, closer to home.',
                    style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text('Shop local essentials. Simple ordering.', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('Categories', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((category) {
                return Chip(
                  avatar: Icon(category == 'All' ? Icons.apps : Icons.category_outlined, size: 18),
                  label: Text(category),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('Items', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                ),
                if (!loading)
                  Text(
                    products.length.toString() + ' available',
                    style: const TextStyle(color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              _InfoCard(message: 'Could not load the live inventory.', detail: error!)
            else if (products.isEmpty)
              const _InfoCard(
                message: 'No items available yet.',
                detail: 'Items added to the shared ALLways inventory will appear here.',
              )
            else
              ...products.map(
                (product) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(product.icon.isEmpty ? '🛍️' : product.icon)),
                    title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(product.category + ' • ₹' + product.price.toString()),
                    trailing: product.stock > 0
                        ? const Icon(Icons.check_circle_outline)
                        : const Text('Unavailable'),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: [
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'Shop'),
          NavigationDestination(icon: Icon(Icons.directions_car_outlined), label: 'Travel'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
        ],
      ),
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
            ? const Text(
                'Customer sign-in will use the existing ALLways Firebase Authentication.',
                style: TextStyle(fontSize: 16),
              )
            : Text('Signed in as ' + (currentUser.email ?? currentUser.uid)),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String message;
  final String detail;
  const _InfoCard({required this.message, required this.detail});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(detail, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}
