import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembered search options, persisted across app restarts.
class ScanPrefs {
  const ScanPrefs({
    this.selectedLocationIds,
    this.months,
    this.modalityIndex,
    this.issueName,
    this.alarmOnFound,
  });

  final Set<String>? selectedLocationIds;
  final int? months;
  final int? modalityIndex;
  final String? issueName;
  final bool? alarmOnFound;

  Map<String, dynamic> toJson() => {
        'locs': selectedLocationIds?.toList(),
        'months': months,
        'modality': modalityIndex,
        'issue': issueName,
        'alarm': alarmOnFound,
      };

  factory ScanPrefs.fromJson(Map<String, dynamic> j) => ScanPrefs(
        selectedLocationIds: (j['locs'] as List?)?.map((e) => e as String).toSet(),
        months: j['months'] as int?,
        modalityIndex: j['modality'] as int?,
        issueName: j['issue'] as String?,
        alarmOnFound: j['alarm'] as bool?,
      );
}

class ScanPrefsStore {
  ScanPrefsStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'scan_prefs_v1';

  Future<ScanPrefs> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const ScanPrefs();
    try {
      return ScanPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ScanPrefs();
    }
  }

  Future<void> save(ScanPrefs prefs) =>
      _storage.write(key: _key, value: jsonEncode(prefs.toJson()));
}
