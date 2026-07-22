import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The most recent appointment the background watch (or a scan) turned up.
///
/// Persisted so the app screen can show "what was last found, and where" even
/// after the finding happened in the background service isolate.
class LastFound {
  const LastFound({
    required this.locationName,
    this.city,
    required this.earliest,
    required this.foundAt,
    this.bookingUrl,
  });

  /// Full clinic name (not just the city).
  final String locationName;
  final String? city;

  /// Soonest open day that was found.
  final DateTime earliest;

  /// When the app recorded this find.
  final DateTime foundAt;

  /// TH Connect booking hand-off URL, if known.
  final String? bookingUrl;

  Map<String, dynamic> toJson() => {
        'name': locationName,
        'city': city,
        'earliest': earliest.toIso8601String(),
        'foundAt': foundAt.toIso8601String(),
        'url': bookingUrl,
      };

  static LastFound? fromJson(Map<String, dynamic> j) {
    final earliest = DateTime.tryParse(j['earliest'] as String? ?? '');
    final foundAt = DateTime.tryParse(j['foundAt'] as String? ?? '');
    final name = j['name'] as String?;
    if (earliest == null || foundAt == null || name == null) return null;
    return LastFound(
      locationName: name,
      city: j['city'] as String?,
      earliest: earliest,
      foundAt: foundAt,
      bookingUrl: j['url'] as String?,
    );
  }
}

class LastFoundStore {
  LastFoundStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'last_found_v1';

  Future<void> save(LastFound found) =>
      _storage.write(key: _key, value: jsonEncode(found.toJson()));

  Future<LastFound?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return LastFound.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}
