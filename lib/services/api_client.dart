import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/case_payment.dart';
import '../models/open_case.dart';
import 'session.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// The vehicle has an open case in both Vehga and Pronto, so the app cannot
/// tell which company this inspection belongs to. Capture offline and let the
/// office attach the photos to the right case.
class AmbiguousBrandException extends ApiException {
  final String vehicleNumber;

  AmbiguousBrandException(this.vehicleNumber)
      : super('$vehicleNumber has an open case in both Vehga and Pronto, so '
            'this app cannot tell which one these photos belong to.\n\n'
            'Please capture offline — the office will attach the photos to '
            'the correct case.');
}

class ApiClient {
  /// Header naming the company a request belongs to, mirroring the portal's
  /// `X-Brand`. Sent on every call made against a known case, so the backend
  /// files the work under that case's company rather than defaulting to Vehga.
  static const _brandHeader = 'X-Brand';

  static Map<String, String> _headers(OpenCase c, {bool json = false}) => {
        _brandHeader: c.brand,
        if (json) 'Content-Type': 'application/json',
      };

  /// POST /users/login — validates agency credentials.
  /// Returns the user's display name on success.
  static Future<String> login(String userId, String password) async {
    final base = await Session.apiBaseUrl();
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$base/users/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw ApiException(
          'Could not reach the server. Check your internet connection.');
    }

    if (res.statusCode == 401) {
      throw ApiException('Invalid user id or password.');
    }
    if (res.statusCode != 200) {
      throw ApiException('Login failed (HTTP ${res.statusCode}).');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['name'] ?? body['Name'] ?? userId).toString();
  }

  /// GET /valuations/workflows/open — finds the open case whose vehicle
  /// number matches [vehicleNumber] (ignoring spaces/dashes/case), and with it
  /// the company that case belongs to.
  ///
  /// This is the one call that deliberately sends no `X-Brand`. The app has no
  /// brand until a case is found, so the lookup has to see both companies'
  /// cases to work out which one this vehicle belongs to — scoping it would
  /// defeat the detection it exists to perform.
  ///
  /// Throws [AmbiguousBrandException] when the vehicle has an open case in
  /// both companies. That is legitimate (the same vehicle can be inspected for
  /// both), but nothing here can tell which one the inspector is standing in
  /// front of, and guessing would file the whole inspection under the wrong
  /// company. The AVO captures offline instead.
  static Future<OpenCase?> findOpenCase(String vehicleNumber) async {
    final base = await Session.apiBaseUrl();
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('$base/valuations/workflows/open'))
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw ApiException(
          'Could not reach the server. Check your internet connection.');
    }

    if (res.statusCode != 200) {
      throw ApiException('Case lookup failed (HTTP ${res.statusCode}).');
    }

    final wanted = normalizeVehicleNumber(vehicleNumber);
    final data = jsonDecode(res.body);
    if (data is! List) return null;

    final matches = <OpenCase>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final c = OpenCase.fromJson(item);
      if (c.valuationId.isEmpty) continue;
      if (normalizeVehicleNumber(c.vehicleNumber) == wanted) matches.add(c);
    }

    if (matches.isEmpty) return null;

    // Two cases under one company is not ambiguous — the brand is still
    // certain — so only a split across companies is refused.
    final brands = matches.map((c) => c.brand).toSet();
    if (brands.length > 1) throw AmbiguousBrandException(vehicleNumber);

    return matches.first;
  }

  /// GET /valuations/{id}/photos — URLs of everything already uploaded for
  /// this case (photos and the video, merged in one map by the backend).
  /// Errors return an empty map so the checklist still opens offline.
  static Future<Map<String, String>> getUploadedMedia(OpenCase c) async {
    try {
      final base = await Session.apiBaseUrl();
      final res = await http
          .get(
              Uri.parse('$base/valuations/${c.valuationId}/photos'
                  '?vehicleNumber=${Uri.encodeQueryComponent(c.vehicleNumber)}'
                  '&applicantContact=${Uri.encodeQueryComponent(c.applicantContact)}'),
              headers: _headers(c))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return {};
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return {};
      return {
        for (final e in data.entries)
          if (e.value != null && e.value.toString().isNotEmpty)
            e.key: e.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  /// GET /valuations/{id}/photos/custom — previously uploaded custom photos.
  static Future<List<UploadedCustomPhoto>> getUploadedCustomPhotos(
      OpenCase c) async {
    try {
      final base = await Session.apiBaseUrl();
      final res = await http
          .get(
              Uri.parse('$base/valuations/${c.valuationId}/photos/custom'
                  '?vehicleNumber=${Uri.encodeQueryComponent(c.vehicleNumber)}'
                  '&applicantContact=${Uri.encodeQueryComponent(c.applicantContact)}'),
              headers: _headers(c))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data is! List) return [];
      return [
        for (final item in data)
          if (item is Map<String, dynamic> &&
              (item['photoUrl'] ?? item['PhotoUrl']) != null)
            UploadedCustomPhoto(
              (item['name'] ?? item['Name'] ?? 'Photo').toString(),
              (item['photoUrl'] ?? item['PhotoUrl']).toString(),
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// GET /payments/{valuationId} — existing payment for the case.
  /// Returns null when nothing has been saved yet (backend answers 404).
  static Future<CasePayment?> getPayment(OpenCase c) async {
    final base = await Session.apiBaseUrl();
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('$base/payments/${c.valuationId}'),
              headers: _headers(c))
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw ApiException(
          'Could not reach the server. Check your internet connection.');
    }

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw ApiException('Could not load payment (HTTP ${res.statusCode}).');
    }

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return null;
    return CasePayment.fromJson(data);
  }

  /// PUT /payments — saves payment details onto the case, the same endpoint
  /// and record the portal's payment dialog uses.
  static Future<void> savePayment(
    OpenCase c,
    CasePayment payment, {
    required String savedBy,
  }) async {
    final base = await Session.apiBaseUrl();
    final http.Response res;
    try {
      res = await http
          .put(
            Uri.parse('$base/payments'),
            headers: _headers(c, json: true),
            body: jsonEncode({
              'valuationId': c.valuationId,
              'vehicleNumber': c.vehicleNumber,
              'applicantContact': c.applicantContact,
              'paymentStatus': payment.status,
              'paymentMethod': payment.method,
              'paymentReference': payment.reference,
              'paymentDate': payment.date?.toUtc().toIso8601String(),
              'paymentAmount': payment.amount,
              'paymentNotes': payment.notes,
              'savedBy': savedBy,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw ApiException(
          'Could not reach the server. Check your internet connection.');
    }

    if (res.statusCode != 200) {
      throw ApiException('Saving payment failed (HTTP ${res.statusCode}).');
    }
  }

  /// PUT /valuations/{id}/photos — multipart upload of captured photos.
  /// [photos] maps the backend field name (e.g. "FrontLeftSide") to a file.
  /// [customPhotos], if given, are uploaded alongside as freely-named extras
  /// (backend field `CustomImageFiles` + a `CustomImagesMetadata` JSON blob).
  static Future<void> uploadPhotos(
    OpenCase openCase,
    Map<String, File> photos, {
    List<CustomPhotoCapture> customPhotos = const [],
    void Function(String photoType)? onProgress,
  }) async {
    if (photos.isEmpty && customPhotos.isEmpty) {
      throw ApiException('No photos to upload.');
    }

    final base = await Session.apiBaseUrl();
    final uri = Uri.parse('$base/valuations/${openCase.valuationId}/photos');

    final request = http.MultipartRequest('PUT', uri)
      ..headers.addAll(_headers(openCase))
      ..fields['ValuationId'] = openCase.valuationId
      ..fields['VehicleNumber'] = openCase.vehicleNumber
      ..fields['ApplicantContact'] = openCase.applicantContact;

    for (final entry in photos.entries) {
      onProgress?.call(entry.key);
      request.files.add(await http.MultipartFile.fromPath(
        entry.key,
        entry.value.path,
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    if (customPhotos.isNotEmpty) {
      final now = DateTime.now().toIso8601String();
      final metadata = <Map<String, dynamic>>[];
      for (var i = 0; i < customPhotos.length; i++) {
        onProgress?.call(customPhotos[i].name);
        request.files.add(await http.MultipartFile.fromPath(
          'CustomImageFiles',
          customPhotos[i].file.path,
          contentType: MediaType('image', 'jpeg'),
        ));
        metadata.add({'Index': i, 'Name': customPhotos[i].name, 'Date': now});
      }
      request.fields['CustomImagesMetadata'] = jsonEncode(metadata);
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(minutes: 10));
    } on Exception {
      throw ApiException('Upload failed. Check your internet connection.');
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw ApiException(
          'Upload failed (HTTP ${streamed.statusCode}). $body');
    }
  }

  /// PUT /valuations/{id}/photos with only the VehicleVideo field.
  /// Uploaded separately from photos so a large video can't fail the photo
  /// sync and can be retried on its own. [onProgress] reports 0.0–1.0.
  static Future<void> uploadVideo(
    OpenCase openCase,
    File video, {
    void Function(double fraction)? onProgress,
  }) async {
    final base = await Session.apiBaseUrl();
    final uri = Uri.parse('$base/valuations/${openCase.valuationId}/photos');

    final request = _ProgressMultipartRequest('PUT', uri, onProgress)
      ..headers.addAll(_headers(openCase))
      ..fields['ValuationId'] = openCase.valuationId
      ..fields['VehicleNumber'] = openCase.vehicleNumber
      ..fields['ApplicantContact'] = openCase.applicantContact;

    request.files.add(await http.MultipartFile.fromPath(
      'VehicleVideo',
      video.path,
      contentType: MediaType('video', 'mp4'),
    ));

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(minutes: 15));
    } on Exception {
      throw ApiException(
          'Video upload failed. Check your internet connection.');
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw ApiException(
          'Video upload failed (HTTP ${streamed.statusCode}). $body');
    }
  }
}

/// MultipartRequest that reports how many bytes have been handed to the
/// network layer, for upload progress display.
class _ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(double fraction)? onProgress;

  _ProgressMultipartRequest(super.method, super.url, this.onProgress);

  @override
  http.ByteStream finalize() {
    final inner = super.finalize();
    final report = onProgress;
    if (report == null) return inner;

    final total = contentLength;
    var sent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        if (total > 0) report((sent / total).clamp(0.0, 1.0));
        sink.add(chunk);
      },
    );
    return http.ByteStream(inner.transform(transformer));
  }
}

/// A photo captured for the "Additional Photos" flow — freely named by the
/// inspector rather than matching a fixed [PhotoSlot].
class CustomPhotoCapture {
  final String name;
  final File file;
  const CustomPhotoCapture(this.name, this.file);
}

/// A custom photo already uploaded to the case, as returned by the backend.
class UploadedCustomPhoto {
  final String name;
  final String url;
  const UploadedCustomPhoto(this.name, this.url);
}
