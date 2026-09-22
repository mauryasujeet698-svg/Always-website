import 'package:flutter/material.dart';

class TravelTeaserScreen extends StatelessWidget {
  const TravelTeaserScreen({super.key});

  Widget _feature({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF311B92), Color(0xFFE91E63)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.travel_explore, color: Colors.white, size: 42),
                  SizedBox(height: 18),
                  Text(
                    'ALLways Mobility — Coming Soon to Pratapgarh',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Local travel, rentals and smarter routes — all in one place.',
                    style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _feature(
              icon: Icons.directions_car,
              title: 'Vehicle Rental',
              subtitle: 'Flexible two-wheeler and four-wheeler rentals.',
            ),
            _feature(
              icon: Icons.people_alt,
              title: 'Ride Sharing',
              subtitle: 'Reliable shared commuting connecting local hubs.',
            ),
            _feature(
              icon: Icons.route,
              title: 'Live Route Tracking',
              subtitle: 'Real-time tracking for Chandika Dham to Pratapgarh.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('We will notify you when Travel launches!'),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_none),
              label: const Text('Notify Me When Live'),
            ),
          ],
        ),
      ),
    );
  }
}
