import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Address lines stamped onto every photo:
/// street, area, village/town/city, state.
class WatermarkLocation {
  final String? street;
  final String? area;
  final String? city;
  final String? state;
  final double latitude;
  final double longitude;

  WatermarkLocation({
    this.street,
    this.area,
    this.city,
    this.state,
    required this.latitude,
    required this.longitude,
  });

  /// Address lines, skipping whatever the geocoder could not resolve.
  /// Falls back to raw coordinates so the stamp is never empty.
  List<String> get lines {
    final result = [street, area, city, state]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    if (result.isEmpty) {
      result.add('${latitude.toStringAsFixed(5)}, '
          '${longitude.toStringAsFixed(5)}');
    }
    return result;
  }
}

class LocationService {
  static WatermarkLocation? _cached;
  static DateTime? _cachedAt;

  /// Current position reverse-geocoded to street/area/city/state.
  /// Cached for 3 minutes so repeated captures don't wait for a GPS fix.
  static Future<WatermarkLocation> get() async {
    final cached = _cached;
    if (cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 3)) {
      return cached;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location (GPS) is turned off. Please enable it.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to stamp photos.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    String? street, area, city, state;
    try {
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        street = _firstNonEmpty([p.street, p.thoroughfare, p.name]);
        area = _firstNonEmpty([p.subLocality]);
        city = _firstNonEmpty([p.locality, p.subAdministrativeArea]);
        state = _firstNonEmpty([p.administrativeArea]);
      }
    } catch (_) {
      // Geocoder unavailable: WatermarkLocation falls back to coordinates.
    }

    final loc = WatermarkLocation(
      street: street,
      area: area,
      city: city,
      state: state,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _cached = loc;
    _cachedAt = DateTime.now();
    return loc;
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
