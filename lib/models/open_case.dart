const String kBrandVehga = 'vehga';
const String kBrandPronto = 'pronto';

/// Display name for a brand key, for the few places the app names a company.
String brandLabel(String brand) =>
    brand == kBrandPronto ? 'Pronto Moto' : 'Vehga';

/// Maps whatever the backend sent to a known brand key.
///
/// Mirrors BrandContext.Normalise on the server: null, blank and unrecognised
/// all mean Vehga, because every case created before multi-brand has no brand
/// and belongs to Vehga. An unknown value must not become a third company that
/// no listing would ever show.
String normalizeBrand(Object? raw) {
  final v = raw?.toString().trim().toLowerCase();
  if (v == null || v.isEmpty) return kBrandVehga;
  return v == kBrandPronto ? kBrandPronto : kBrandVehga;
}

/// One open valuation case as returned by GET /valuations/workflows/open.
class OpenCase {
  final String valuationId;
  final String vehicleNumber;
  final String applicantContact;
  final String? applicantName;
  final String? status;
  final String? workflow;
  final int workflowStepOrder;

  /// Company the case was created under: "vehga" or "pronto".
  ///
  /// The app has no brand of its own — this is the only thing that decides
  /// which company a capture is filed under, and it comes from the case
  /// itself, so it cannot disagree with the portal. Cases created before
  /// multi-brand carry no brand at all, which the backend defines as Vehga.
  final String brand;

  /// The case's Unique ID as the portal shows it, e.g. "VG-519499-K".
  ///
  /// Not part of the open-cases listing — that comes from the Workflows table,
  /// and the reference lives on the Cosmos document — so it is null until
  /// [ApiClient.findOpenCase] has fetched it and matched it to what the
  /// inspector typed.
  final String? referenceNumber;

  OpenCase({
    required this.valuationId,
    required this.vehicleNumber,
    required this.applicantContact,
    this.applicantName,
    this.status,
    this.workflow,
    this.workflowStepOrder = 0,
    this.brand = kBrandVehga,
    this.referenceNumber,
  });

  OpenCase withReference(String referenceNumber) => OpenCase(
        valuationId: valuationId,
        vehicleNumber: vehicleNumber,
        applicantContact: applicantContact,
        applicantName: applicantName,
        status: status,
        workflow: workflow,
        workflowStepOrder: workflowStepOrder,
        brand: brand,
        referenceNumber: referenceNumber,
      );

  factory OpenCase.fromJson(Map<String, dynamic> json) {
    String read(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null) return v.toString();
      }
      return '';
    }

    return OpenCase(
      valuationId: read(['valuationId', 'ValuationId']),
      vehicleNumber: read(['vehicleNumber', 'VehicleNumber']),
      applicantContact: read(['applicantContact', 'ApplicantContact']),
      applicantName: json['applicantName']?.toString() ??
          json['ApplicantName']?.toString(),
      status: json['status']?.toString() ?? json['Status']?.toString(),
      workflow: json['workflow']?.toString() ?? json['Workflow']?.toString(),
      workflowStepOrder: int.tryParse(
              (json['workflowStepOrder'] ?? json['WorkflowStepOrder'] ?? '0')
                  .toString()) ??
          0,
      brand: normalizeBrand(json['brand'] ?? json['Brand']),
    );
  }
}

/// Uppercases and strips everything but letters/digits so
/// "AP07 TM 2457", "ap07-tm-2457" and "AP07TM2457" all match.
String normalizeVehicleNumber(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Same treatment for the Unique ID, so "vg 519499 k", "VG519499K" and
/// "VG-519499-K" all match.
String normalizeReference(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
