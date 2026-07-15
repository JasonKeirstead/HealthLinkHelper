import 'dart:async';

import '../api/booking_repository.dart';
import '../models/enums.dart';
import '../models/models.dart';

/// What to scan for.
class ScanRequest {
  const ScanRequest({
    required this.patient,
    required this.issueName,
    this.modality = Modality.inPerson,
    this.monthsAhead = 1,
    this.includeLocationIds,
    this.concurrency = 4,
  });

  final Patient patient;

  /// Presenting-issue name to match per location (case-insensitive substring),
  /// e.g. "Medical Visit".
  final String issueName;
  final Modality modality;
  final int monthsAhead;

  /// Only scan these location ids. Null = scan every location.
  final Set<String>? includeLocationIds;
  final int concurrency;
}

class ScanProgress {
  const ScanProgress(this.completed, this.total, this.currentLocation);
  final int completed;
  final int total;
  final String currentLocation;
  double get fraction => total == 0 ? 0 : completed / total;
}

/// Sweeps every location for the requested type over the next N months and
/// reports where/when there is availability. Read-only.
class AvailabilityScanner {
  AvailabilityScanner(this._repo);
  final BookingRepository _repo;

  Future<List<LocationAvailability>> scan(
    ScanRequest req, {
    void Function(ScanProgress)? onProgress,
  }) async {
    final chartId = req.patient.chartId;
    final windows = _monthWindows(req.monthsAhead);
    final all = await _repo.locations(chartId);
    final include = req.includeLocationIds;
    final locations =
        include == null ? all : all.where((l) => include.contains(l.id)).toList();

    var completed = 0;
    final results = await _pooled<ClinicLocation, LocationAvailability>(
      locations,
      req.concurrency,
      (loc) async {
        final r = await _scanLocation(chartId, loc, req, windows);
        completed++;
        onProgress?.call(ScanProgress(completed, locations.length, loc.shortLabel));
        return r;
      },
    );

    results.sort(_bySoonest);
    return results;
  }

  Future<LocationAvailability> _scanLocation(
    String chartId,
    ClinicLocation loc,
    ScanRequest req,
    List<(DateTime, DateTime)> windows,
  ) async {
    try {
      final issues = await _repo.presentingIssues(chartId, loc.id);
      final issue = _firstMatch(issues.map((i) => i.name).toList(), req.issueName);
      if (issue == null) {
        return LocationAvailability(location: loc, note: 'Type not offered here');
      }
      final issueId = issues.firstWhere((i) => i.name == issue).id;

      final services = await _repo.services(chartId, loc.id, issueId, req.modality.bookingType);
      final service = _pickService(services, req.modality);
      if (service == null) {
        return LocationAvailability(location: loc, note: 'No matching service');
      }

      final days = <DateTime>{};
      // Query each month window concurrently within the location.
      final perMonth = await Future.wait(windows.map((w) => _repo.availableDays(
            chartId: chartId,
            locationId: loc.id,
            serviceId: service.id,
            bookingType: req.modality.bookingType,
            from: w.$1,
            until: w.$2,
          )));
      for (final list in perMonth) {
        for (final d in list) {
          days.add(DateTime(d.year, d.month, d.day));
        }
      }

      return LocationAvailability(location: loc, service: service, days: days.toList());
    } catch (e) {
      return LocationAvailability(location: loc, note: 'Error: $e');
    }
  }

  /// Prefer a service matching the modality; for in-person avoid telephone ones.
  Service? _pickService(List<Service> services, Modality modality) {
    if (services.isEmpty) return null;
    if (modality == Modality.inPerson) {
      final nonPhone = services.where((s) => !s.isTelephone).toList();
      if (nonPhone.isNotEmpty) return nonPhone.first;
    }
    return services.first;
  }

  String? _firstMatch(List<String> names, String needle) {
    final n = needle.toLowerCase();
    for (final name in names) {
      if (name.toLowerCase().contains(n)) return name;
    }
    return null;
  }

  static int _bySoonest(LocationAvailability a, LocationAvailability b) {
    if (a.hasAvailability && b.hasAvailability) {
      return a.earliest!.compareTo(b.earliest!);
    }
    if (a.hasAvailability) return -1;
    if (b.hasAvailability) return 1;
    return a.location.shortLabel.compareTo(b.location.shortLabel);
  }

  /// Month-boundary windows starting from the current month.
  static List<(DateTime, DateTime)> _monthWindows(int months) {
    final now = DateTime.now();
    return List.generate(months, (i) {
      final start = DateTime(now.year, now.month + i, 1);
      final end = DateTime(now.year, now.month + i + 1, 0);
      return (start, end);
    });
  }

  /// Run [task] over [items] with at most [limit] in flight, preserving order.
  static Future<List<R>> _pooled<T, R>(
    List<T> items,
    int limit,
    Future<R> Function(T) task,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        results[i] = await task(items[i]);
      }
    }

    final workers = List.generate(
      limit.clamp(1, items.isEmpty ? 1 : items.length),
      (_) => worker(),
    );
    await Future.wait(workers);
    return results.cast<R>();
  }
}
