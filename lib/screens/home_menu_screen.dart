import 'package:flutter/material.dart';

import '../services/session.dart';
import 'login_screen.dart';
import 'offline_capture_screen.dart';
import 'vehicle_entry_screen.dart';

/// Post-login landing screen: Inspection and Offline Photos.
/// Payments live inside a case (offered after submitting its photos).
class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> {
  String _agencyName = '';

  @override
  void initState() {
    super.initState();
    Session.load().then((s) {
      if (s != null && mounted) setState(() => _agencyName = s.agencyName);
    });
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 32),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _agencyName.isEmpty ? 'Welcome' : 'Welcome, $_agencyName',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            _MenuCard(
              icon: Icons.directions_car,
              title: 'Inspection',
              subtitle: 'Search a vehicle number and take case '
                  'photos & video that sync to the portal',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const VehicleEntryScreen())),
            ),
            const SizedBox(height: 14),
            _MenuCard(
              icon: Icons.photo_camera,
              title: 'Offline Photos',
              subtitle: 'Quick photos & video saved to the gallery only — '
                  'not synced to any case',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OfflineCaptureScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
