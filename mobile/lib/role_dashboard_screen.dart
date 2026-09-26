import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RoleDashboardScreen extends StatelessWidget {
  final String role;
  final User user;
  final Widget child;
  final VoidCallback onSignOut;
  const RoleDashboardScreen({super.key, required this.role, required this.user, required this.child, required this.onSignOut});

  String get title => switch (role) {
    'admin' => 'ALLways Admin',
    'seller' => 'ALLways Seller',
    'delivery_partner' => 'ALLways Delivery',
    'carrier' => 'ALLways Carriers',
    _ => 'ALLways',
  };

  String get subtitle => switch (role) {
    'admin' => 'Operations & management',
    'seller' => 'Your shop workspace',
    'delivery_partner' => 'Deliveries & earnings',
    'carrier' => 'Rides & earnings',
    _ => 'Workspace',
  };

  IconData get icon => switch (role) {
    'admin' => Icons.admin_panel_settings,
    'seller' => Icons.storefront,
    'delivery_partner' => Icons.local_shipping,
    'carrier' => Icons.two_wheeler,
    _ => Icons.dashboard,
  };

  List<_Quick> get quick => switch (role) {
    'admin' => const [
      _Quick('Manage Roles', Icons.manage_accounts),
      _Quick('Orders', Icons.receipt_long),
      _Quick('Delivery Assignment', Icons.assignment_ind),
      _Quick('Notifications', Icons.campaign),
    ],
    'seller' => const [
      _Quick('Products', Icons.inventory_2),
      _Quick('Orders', Icons.receipt_long),
      _Quick('Shop Profile', Icons.storefront),
      _Quick('Offers', Icons.local_offer),
    ],
    'delivery_partner' => const [
      _Quick('Deliveries', Icons.local_shipping),
      _Quick('Earnings', Icons.currency_rupee),
      _Quick('Online Status', Icons.power_settings_new),
      _Quick('Profile', Icons.person),
    ],
    'carrier' => const [
      _Quick('Find Rides', Icons.search),
      _Quick('My Rides', Icons.route),
      _Quick('Earnings', Icons.currency_rupee),
      _Quick('Profile', Icons.person),
    ],
    _ => const [],
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (user.displayName ?? '').trim().isEmpty ? 'ALLways Account' : user.displayName!.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FA),
        elevation: 0,
        titleSpacing: 18,
        title: Row(children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
        actions: [
          IconButton(tooltip: 'Sign out', onPressed: onSignOut, icon: const Icon(Icons.logout_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 29,
                  child: Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(user.email ?? '', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('$subtitle • Profile saved', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                ])),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: quick.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.25),
            itemBuilder: (context, i) => Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(quick[i].icon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(quick[i].title, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Workspace', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Quick {
  final String title;
  final IconData icon;
  const _Quick(this.title, this.icon);
}
