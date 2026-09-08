import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import 'offline_capture_screen.dart';
import 'photo_checklist_screen.dart';

class VehicleEntryScreen extends StatefulWidget {
  const VehicleEntryScreen({super.key});

  @override
  State<VehicleEntryScreen> createState() => _VehicleEntryScreenState();
}

class _VehicleEntryScreenState extends State<VehicleEntryScreen> {
  final _vehicleController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final vehicleNumber = _vehicleController.text.trim();
    if (vehicleNumber.isEmpty) {
      _showMessage('Enter the vehicle number.');
      return;
    }

    setState(() => _busy = true);
    try {
      final openCase = await ApiClient.findOpenCase(vehicleNumber);
      if (!mounted) return;
      if (openCase == null) {
        _showMessage('No open case found for "$vehicleNumber". '
            'Check the number or ask the office to create the case.');
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhotoChecklistScreen(openCase: openCase)));
    } on AmbiguousBrandException catch (e) {
      await _showAmbiguousBrand(e);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The vehicle has an open case in both companies. Nothing the app can see
  /// says which one the inspector is standing in front of, so it refuses to
  /// guess and offers offline capture instead — a snackbar would be too easy
  /// to miss for something that stops the inspection.
  Future<void> _showAmbiguousBrand(AmbiguousBrandException e) async {
    if (!mounted) return;
    final goOffline = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('Case exists in both companies'),
        content: Text(e.message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Capture offline')),
        ],
      ),
    );
    if (goOffline == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OfflineCaptureScreen()));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 32),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Vehicle Number',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Enter the vehicle registration number to load '
                  'its open inspection case.'),
              const SizedBox(height: 16),
              TextField(
                controller: _vehicleController,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
                  UpperCaseTextFormatter(),
                ],
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'AP07TM2457',
                  // Faint so the example can't be mistaken for a real number.
                  hintStyle: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.25),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _search,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(_busy ? 'Searching…' : 'FIND CASE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
