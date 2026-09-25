import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool _allwaysNotifications = true;
  bool _orderUpdates = true;
  bool _deliveryUpdates = true;
  bool _travelUpdates = true;
  bool _offersPromotions = false;
  bool _announcements = false;
  String _selectedTab = 'All';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _allwaysNotifications = prefs.getBool('notif_master') ?? true;
      _orderUpdates = prefs.getBool('notif_orders') ?? true;
      _deliveryUpdates = prefs.getBool('notif_delivery') ?? true;
      _travelUpdates = prefs.getBool('notif_travel') ?? true;
      _offersPromotions = prefs.getBool('notif_offers') ?? false;
      _announcements = prefs.getBool('notif_announcements') ?? false;
    });
  }

  Future<void> _setPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('customers').doc(user.uid).set({
        'notification_preferences': {key: value},
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Stay updated with your ALLways activity',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildToggleCard(
            title: 'ALLways notifications',
            subtitle: 'Central app alerts and updates',
            icon: Icons.notifications_none,
            value: _allwaysNotifications,
            onChanged: (v) {
              setState(() => _allwaysNotifications = v);
              _setPreference('notif_master', v);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'ORDER & DELIVERY',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFCECEF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildTile(
                  'Order updates',
                  'From confirmation to delivery completion',
                  Icons.receipt_long,
                  _orderUpdates,
                  (v) {
                    setState(() => _orderUpdates = v);
                    _setPreference('notif_orders', v);
                  },
                ),
                const Divider(height: 1, color: Colors.black12),
                _buildTile(
                  'Delivery updates',
                  'Partner alerts and tracking status',
                  Icons.local_shipping_outlined,
                  _deliveryUpdates,
                  (v) {
                    setState(() => _deliveryUpdates = v);
                    _setPreference('notif_delivery', v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'TRAVEL & OFFERS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFCECEF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildTile(
                  'Travel & Ride Updates',
                  'Ride & booking updates',
                  Icons.two_wheeler,
                  _travelUpdates,
                  (v) {
                    setState(() => _travelUpdates = v);
                    _setPreference('notif_travel', v);
                  },
                ),
                const Divider(height: 1, color: Colors.black12),
                _buildTile(
                  'Offers & Promotions',
                  'Exclusive deals and reward news',
                  Icons.sell_outlined,
                  _offersPromotions,
                  (v) {
                    setState(() => _offersPromotions = v);
                    _setPreference('notif_offers', v);
                  },
                ),
                const Divider(height: 1, color: Colors.black12),
                _buildTile(
                  'ALLways Announcements',
                  'Important service news and critical alerts',
                  Icons.campaign_outlined,
                  _announcements,
                  (v) {
                    setState(() => _announcements = v);
                    _setPreference('notif_announcements', v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'NOTIFICATION HISTORY',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Orders', 'Delivery', 'Travel', 'Offers'].map((tab) {
                final isSelected = _selectedTab == tab;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: isSelected,
                    selectedColor: const Color(0xFFB06A78),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                    onSelected: (val) => setState(() => _selectedTab = tab),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (user != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('customers')
                  .doc(user.uid)
                  .collection('notifications')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No notifications yet.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data!.docs.where((d) {
                  if (_selectedTab == 'All') return true;
                  return (d.data()['category'] ?? '')
                          .toString()
                          .toLowerCase() ==
                      _selectedTab.toLowerCase();
                }).toList();

                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No notifications in this category.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = docs[i].data();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF202026),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFF2C2C36),
                            child: Icon(
                              Icons.notifications_active,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['title'] ?? 'Notification',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  item['body'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCECEF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE8D0D5),
            child: Icon(icon, color: const Color(0xFF7A434E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF7A434E),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE8D0D5),
        child: Icon(icon, color: const Color(0xFF7A434E), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.black54, fontSize: 11),
      ),
      trailing: Switch(
        value: value,
        activeColor: const Color(0xFF7A434E),
        onChanged: onChanged,
      ),
    );
  }
}
