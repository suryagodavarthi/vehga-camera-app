/// Payment details for a case — mirrors the backend PaymentDto and the
/// portal's payment dialog field-for-field.
class CasePayment {
  final String status;
  final String method;
  final String reference;
  final DateTime? date;
  final double? amount;
  final String notes;
  final String? savedBy;
  final DateTime? savedAt;

  const CasePayment({
    this.status = '',
    this.method = '',
    this.reference = '',
    this.date,
    this.amount,
    this.notes = '',
    this.savedBy,
    this.savedAt,
  });

  factory CasePayment.fromJson(Map<String, dynamic> json) {
    String str(String lower, String upper) =>
        (json[lower] ?? json[upper] ?? '').toString();

    // Kept as a UTC instant; screens convert to IST for display.
    DateTime? parseDate(String lower, String upper) {
      final raw = json[lower] ?? json[upper];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString())?.toUtc();
    }

    final rawAmount = json['paymentAmount'] ?? json['PaymentAmount'];

    return CasePayment(
      status: str('paymentStatus', 'PaymentStatus'),
      method: str('paymentMethod', 'PaymentMethod'),
      reference: str('paymentReference', 'PaymentReference'),
      date: parseDate('paymentDate', 'PaymentDate'),
      amount:
          rawAmount == null ? null : double.tryParse(rawAmount.toString()),
      notes: str('paymentNotes', 'PaymentNotes'),
      savedBy: (json['savedBy'] ?? json['SavedBy'])?.toString(),
      savedAt: parseDate('savedAt', 'SavedAt'),
    );
  }

  bool get isEmpty => status.isEmpty && amount == null;

  /// Method and date are only required when the payment isn't Pending —
  /// same rule the portal enforces.
  static bool requiresMethodAndDate(String status) => status != 'Pending';
}

const List<String> kPaymentStatuses = ['Completed', 'Pending', 'Credit'];
const List<String> kPaymentMethods = ['Online', 'Cash', 'UPI', 'Card'];
