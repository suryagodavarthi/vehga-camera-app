import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import 'photo_checklist_screen.dart';

class VehicleEntryScreen extends StatefulWidget {
  const VehicleEntryScreen({super.key});

  @override
  State<VehicleEntryScreen> createState() => _VehicleEntryScreenState();
}

class _VehicleEntryScreenState extends State<VehicleEntryScreen> {
  final _vehicleController = TextEditingController();
  final _uniqueIdController = TextEditingController();
  final _uniqueIdFocus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _vehicleController.dispose();
    _uniqueIdController.dispose();
    _uniqueIdFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final vehicleNumber = _vehicleController.text.trim();
    final uniqueId = _uniqueIdController.text.trim();
    if (vehicleNumber.isEmpty) {
      _showMessage('Enter the vehicle number.');
      return;
    }
    if (uniqueId.isEmpty) {
      _showMessage('Enter the case Unique ID.');
      _uniqueIdFocus.requestFocus();
      return;
    }

    setState(() => _busy = true);
    try {
      final openCase = await ApiClient.findOpenCase(vehicleNumber, uniqueId);
      if (!mounted) return;
      if (openCase == null) {
        _showMessage('No open case found for "$vehicleNumber". '
            'Check the number or ask the office to create the case.');
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhotoChecklistScreen(openCase: openCase)));
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Faint so the examples can't be mistaken for real values.
    final faintHint = TextStyle(
      color: Colors.grey.withValues(alpha: 0.25),
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    );
    const entryStyle =
        TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2);

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
              const Text('Enter the vehicle registration number and the '
                  'case Unique ID given by the office.'),
              const SizedBox(height: 16),
              TextField(
                controller: _vehicleController,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
                  UpperCaseTextFormatter(),
                ],
                style: entryStyle,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'AP07TM2457',
                  hintStyle: faintHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _uniqueIdFocus.requestFocus(),
              ),
              const SizedBox(height: 24),
              Text('Unique ID', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _uniqueIdController,
                focusNode: _uniqueIdFocus,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
                  UpperCaseTextFormatter(),
                ],
                style: entryStyle,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'VG-123456-A',
                  hintStyle: faintHint,
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
