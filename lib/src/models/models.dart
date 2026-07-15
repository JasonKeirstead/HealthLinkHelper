import 'enums.dart';

/// Parse a number that the API may return as a num OR a string.
double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// A patient chart to book for (self or a dependent), scoped to an account.
class Patient {
  const Patient({
    required this.accountId,
    required this.chartId,
    required this.fullName,
  });

  final String accountId;
  final String chartId;
  final String fullName;

  @override
  String toString() => '$fullName ($chartId @ $accountId)';
}

/// A bookable clinic location.
class ClinicLocation {
  const ClinicLocation({
    required this.id,
    required this.name,
    this.city,
    this.province,
    this.streetAddress1,
    this.postalCode,
    this.timezone,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String? city;
  final String? province;
  final String? streetAddress1;
  final String? postalCode;
  final String? timezone;
  final double? latitude;
  final double? longitude;

  String get displayName => name.trim();

  String get shortLabel {
    final c = city?.trim();
    return (c == null || c.isEmpty) ? displayName : c;
  }

  factory ClinicLocation.fromJson(Map<String, dynamic> j) => ClinicLocation(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        city: j['city'] as String?,
        province: j['province'] as String?,
        streetAddress1: j['streetAddress1'] as String?,
        postalCode: j['postalCode'] as String?,
        timezone: j['timezone'] as String?,
        latitude: _asDouble(j['latitude']),
        longitude: _asDouble(j['longitude']),
      );
}

/// A "reason for visit" category.
class PresentingIssue {
  const PresentingIssue({required this.id, required this.name});
  final String id;
  final String name;

  factory PresentingIssue.fromJson(Map<String, dynamic> j) =>
      PresentingIssue(id: j['id'] as String, name: (j['name'] as String?) ?? '');
}

/// An appointment "type" (service). Belongs to a location + presenting issue.
class Service {
  const Service({required this.id, required this.name});
  final String id;
  final String name;

  bool get isTelephone =>
      RegExp(r'telephone|t[ée]l[ée]phone', caseSensitive: false).hasMatch(name);

  VisitType visitTypeFor(Modality modality) {
    if (modality == Modality.inPerson) return VisitType.inPerson;
    return isTelephone ? VisitType.phone : VisitType.virtual;
  }

  factory Service.fromJson(Map<String, dynamic> j) =>
      Service(id: j['id'] as String, name: (j['name'] as String?) ?? '');
}

/// A concrete bookable time slot on a given day.
class TimeSlot {
  const TimeSlot({required this.from, required this.until, this.providerId});
  final DateTime from;
  final DateTime until;
  final String? providerId;

  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
        from: DateTime.parse(j['from'] as String),
        until: DateTime.parse(j['until'] as String),
        providerId: (j['providerUser'] as Map<String, dynamic>?)?['id'] as String?,
      );
}

/// Availability found at one location for the requested type over the window.
class LocationAvailability {
  LocationAvailability({
    required this.location,
    this.service,
    List<DateTime>? days,
    this.note,
  }) : days = (days ?? [])..sort();

  final ClinicLocation location;
  final Service? service;

  /// Distinct days (date-only, local) that have at least one open slot.
  final List<DateTime> days;

  /// Non-empty when the location could not be scanned (e.g. type not offered).
  final String? note;

  bool get hasAvailability => days.isNotEmpty;
  DateTime? get earliest => days.isEmpty ? null : days.first;
}
