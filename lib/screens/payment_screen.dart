import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/case_payment.dart';
import '../models/open_case.dart';
import '../services/api_client.dart';
import '../services/session.dart';
import '../utils/ist.dart';

/// Payment details for a case — the same six fields, dropdown values and
/// validation rules as the portal's payment dialog. Saving writes to the
/// same record, so the portal shows it immediately. Entirely optional:
/// the agent can leave without filling anything.
class PaymentScreen extends StatefulWidget {
  final OpenCase openCase;

  const PaymentScreen({super.key, required this.openCase});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String _status = '';
  String _method = '';

  /// Payment date as an **IST wall clock** — converted to UTC on save.
  DateTime? _date;

  /// While true the date field tracks the current time, so a payment taken
  /// right now is stamped with the moment it's saved. Any manual pick (or a
  /// date already saved on the case) switches it off.
  bool _dateIsLive = true;
  Timer? _clock;

  /// What the portal currently holds for this case, shown as a read-back
  /// summary above the form. Null when nothing is saved yet.
  CasePayment? _saved;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = istNow();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dateIsLive && !_saving && mounted) {
        setState(() => _date = istNow());
      }
    });
    _loadExisting();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final payment = await ApiClient.getPayment(widget.openCase);
      if (!mounted) return;
      if (payment != null) {
        setState(() {
          _saved = payment.isEmpty ? null : payment;
          _status = kPaymentStatuses.contains(payment.status)
              ? payment.status
              : '';
          _method =
              kPaymentMethods.contains(payment.method) ? payment.method : '';
          // A date already on the case wins over the live clock.
          if (payment.date != null) {
            _date = toIstWall(payment.date!);
            _dateIsLive = false;
          }
          _amountController.text =
              payment.amount == null ? '' : _trimAmount(payment.amount!);
          _referenceController.text = payment.reference;
          _notesController.text = payment.notes;
        });
      }
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _trimAmount(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  bool get _needsMethodAndDate => CasePayment.requiresMethodAndDate(_status);

  /// Picks an IST wall-clock date and time, and stops the live clock.
  Future<void> _pickDateTime() async {
    final now = istNow();
    final date = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date ?? now),
    );
    if (!mounted) return;

    setState(() {
      _dateIsLive = false;
      _date = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0,
      );
    });
  }

  void _resumeLiveClock() {
    setState(() {
      _dateIsLive = true;
      _date = istNow();
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());

    if (_status.isEmpty || amount == null || amount <= 0) {
      _showMessage('Payment status and amount are required.');
      return;
    }
    if (_needsMethodAndDate && (_method.isEmpty || _date == null)) {
      _showMessage('Payment method and date are required '
          'unless the status is Pending.');
      return;
    }

    setState(() => _saving = true);
    try {
      final session = await Session.load();
      // Live field: stamp the actual moment of saving.
      final istDate = _dateIsLive ? istNow() : _date;
      await ApiClient.savePayment(
        widget.openCase,
        CasePayment(
          status: _status,
          method: _method,
          reference: _referenceController.text.trim(),
          date: istDate == null ? null : istWallToUtc(istDate),
          amount: amount,
          notes: _notesController.text.trim(),
        ),
        savedBy: session?.agencyName ?? 'Camera App',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment details saved to the portal.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _optionalHint(bool required) => required ? ' *' : ' (optional)';

  static String _formatAmount(double? amount) {
    if (amount == null) return '—';
    final pattern = amount == amount.roundToDouble() ? '#,##0' : '#,##0.00';
    return '₹ ${NumberFormat(pattern, 'en_IN').format(amount)}';
  }

  /// Formats a UTC instant from the server as IST.
  static String _formatInstantIst(DateTime? instant) => instant == null
      ? '—'
      : '${DateFormat('dd/MM/yyyy h:mm a').format(toIstWall(instant))} IST';

  /// Formats an IST wall clock already in IST.
  static String _formatIstWall(DateTime wall) =>
      '${DateFormat('dd/MM/yyyy h:mm:ss a').format(wall)} IST';

  Widget _savedRow(String label, String value, {bool muted = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                  color: muted ? Colors.grey.shade700 : null,
                ),
              ),
            ),
          ],
        ),
      );

  /// Everything currently stored on the case, including who saved it.
  Widget _buildSavedCard(CasePayment saved) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('SAVED PAYMENT DETAILS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.primary,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          _savedRow('Status', saved.status.isEmpty ? '—' : saved.status),
          _savedRow('Method', saved.method.isEmpty ? '—' : saved.method),
          _savedRow('Amount', _formatAmount(saved.amount)),
          _savedRow('Date', _formatInstantIst(saved.date)),
          _savedRow('Reference',
              saved.reference.isEmpty ? '—' : saved.reference),
          _savedRow('Notes', saved.notes.isEmpty ? '—' : saved.notes),
          const Divider(height: 18),
          _savedRow('Saved by',
              (saved.savedBy == null || saved.savedBy!.isEmpty)
                  ? '—'
                  : saved.savedBy!,
              muted: true),
          _savedRow('Saved on', _formatInstantIst(saved.savedAt), muted: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.openCase;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Details'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(c.vehicleNumber,
                style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_saved != null) _buildSavedCard(_saved!),
                  DropdownButtonFormField<String>(
                    initialValue: _status.isEmpty ? null : _status,
                    decoration: const InputDecoration(
                      labelText: 'Payment Status *',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in kPaymentStatuses)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                              _status = v ?? '';
                              // Non-Pending needs a date; default to now so
                              // the agent only changes it when it differs.
                              if (_needsMethodAndDate && _date == null) {
                                _date = DateTime.now();
                              }
                            }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    enabled: !_saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Payment Amount *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _method.isEmpty ? null : _method,
                    decoration: InputDecoration(
                      labelText:
                          'Payment Method${_optionalHint(_needsMethodAndDate)}',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in kPaymentMethods)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged:
                        _saving ? null : (v) => setState(() => _method = v ?? ''),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _saving ? null : _pickDateTime,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Payment Date (IST)'
                            '${_optionalHint(_needsMethodAndDate)}',
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.event),
                        helperText: _dateIsLive
                            ? 'Live — updates until you pick a time or save'
                            : 'Tap to change',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null
                                  ? 'Tap to select'
                                  : _formatIstWall(_date!),
                              style: TextStyle(
                                  color: _date == null ? Colors.grey : null),
                            ),
                          ),
                          if (_dateIsLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('LIVE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green)),
                            )
                          else
                            TextButton(
                              onPressed: _saving ? null : _resumeLiveClock,
                              style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: const Text('Use now',
                                  style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _referenceController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Payment Reference (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    enabled: !_saving,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Payment Notes (optional)',
                      hintText: 'Enter payment related notes here…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    icon: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving…' : 'SAVE TO PORTAL'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
    );
  }
}
