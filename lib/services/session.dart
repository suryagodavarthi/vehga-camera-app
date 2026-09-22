import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Persisted agency session + server URL override.
class Session {
  static const _kAgencyId = 'agencyId';
  static const _kAgencyName = 'agencyName';
  static const _kApiBaseUrl = 'apiBaseUrl';
  static const _kRetiredUrlsCleared = 'retiredApiBaseUrlsCleared';

  final String agencyId;
  final String agencyName;

  Session({required this.agencyId, required this.agencyName});

  static Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kAgencyId);
    if (id == null || id.isEmpty) return null;
    return Session(
      agencyId: id,
      agencyName: prefs.getString(_kAgencyName) ?? id,
    );
  }

  static Future<void> save(String agencyId, String agencyName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgencyId, agencyId);
    await prefs.setString(_kAgencyName, agencyName);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAgencyId);
    await prefs.remove(_kAgencyName);
  }

  static Future<String> apiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // Once per install of this build: a saved address equal to an old default is a
    // leftover from "Reset to default", not a choice, so follow the new default.
    // Addresses typed in afterwards (a staging server, say) are kept.
    if (!(prefs.getBool(_kRetiredUrlsCleared) ?? false)) {
      if (kRetiredApiBaseUrls.contains(prefs.getString(_kApiBaseUrl))) {
        await prefs.remove(_kApiBaseUrl);
      }
      await prefs.setBool(_kRetiredUrlsCleared, true);
    }
    final url = prefs.getString(_kApiBaseUrl);
    if (url == null || url.isEmpty) return kDefaultApiBaseUrl;
    return url;
  }

  static Future<void> setApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    var cleaned = url.trim();
    if (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    await prefs.setString(_kApiBaseUrl, cleaned);
  }
}
