import 'package:flutter_test/flutter_test.dart';
import 'package:healthlink_scanner/src/api/api_client.dart';
import 'package:healthlink_scanner/src/api/booking_repository.dart';
import 'package:healthlink_scanner/src/models/enums.dart';
import 'package:healthlink_scanner/src/models/models.dart';
import 'package:healthlink_scanner/src/scanner/scanner.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
Map<String, dynamic> _booking(Map<String, dynamic> booking) => {
      'currentUser': {
        'chart': {'booking': booking}
      }
    };
Map<String, dynamic> _conn(List<Map<String, dynamic>> nodes) => {
      'edges': [for (final n in nodes) {'node': n}]
    };

/// Fake backend mirroring the real API shapes for four NB locations.
class FakeBackend implements GraphQLExecutor {
  static final firstOfMonth = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }();

  @override
  Future<Map<String, dynamic>> query(String op, String query, Map<String, dynamic> v) async {
    switch (op) {
      case 'getLocations':
        return _booking({
          'locations': _conn([
            {'id': 'campbellton', 'name': 'Campbellton Clinic', 'city': 'Campbellton', 'province': 'NB'},
            {'id': 'bouctouche', 'name': 'Bouctouche Clinic', 'city': 'Bouctouche', 'province': 'NB'},
            {'id': 'fredericton', 'name': 'Fredericton Clinic', 'city': 'Fredericton', 'province': 'NB'},
            {'id': 'novisit', 'name': 'Virtual Refill', 'city': 'Zzz', 'province': 'NB'},
          ])
        });
      case 'getPresentingIssues':
        final loc = v['locationId'];
        final issues = loc == 'novisit'
            ? [{'id': 'refill', 'name': 'Medication Refill'}]
            : [{'id': 'mv-$loc', 'name': 'Medical Visit'}];
        return _booking({'presentingIssues': _conn(issues.cast<Map<String, dynamic>>())});
      case 'getTypes':
        return _booking({
          'services': _conn([
            {'id': 'svc', 'name': 'Medical Visit (EN)'}
          ])
        });
      case 'getAvailableDays':
        final loc = v['locationId'];
        final from = DateTime.parse(v['from'] as String);
        List<String> days;
        if (loc == 'campbellton') {
          days = [_ymd(from)]; // one day in every month window
        } else if (loc == 'bouctouche' && from == FakeBackend.firstOfMonth) {
          days = [_ymd(from.add(const Duration(days: 10)))]; // one day, first month only
        } else {
          days = const [];
        }
        return _booking({'availableDays': days});
      default:
        return _booking({});
    }
  }
}

void main() {
  test('scan ranks locations with availability soonest-first', () async {
    final scanner = AvailabilityScanner(BookingRepository(FakeBackend()));
    final results = await scanner.scan(const ScanRequest(
      patient: Patient(accountId: 'A', chartId: 'C', fullName: 'Test'),
      issueName: 'Medical Visit',
      monthsAhead: 6,
    ));

    expect(results.length, 4);

    // Campbellton (earliest = 1st of current month) ranks before Bouctouche (11th).
    expect(results[0].location.id, 'campbellton');
    expect(results[1].location.id, 'bouctouche');

    final campbellton = results[0];
    expect(campbellton.hasAvailability, isTrue);
    expect(campbellton.days.length, 6); // one open day per month window
    expect(campbellton.service?.name, 'Medical Visit (EN)');

    // Fredericton offers the type but has no open days.
    final fredericton = results.firstWhere((r) => r.location.id == 'fredericton');
    expect(fredericton.hasAvailability, isFalse);
    expect(fredericton.note, isNull);

    // Location that doesn't offer the type is annotated, not crashed.
    final novisit = results.firstWhere((r) => r.location.id == 'novisit');
    expect(novisit.hasAvailability, isFalse);
    expect(novisit.note, 'Type not offered here');
  });

  test('bookingType maps to wire values', () {
    expect(Modality.inPerson.bookingType.wire, 'PHYSICAL');
    expect(Modality.inPerson.visitType.wire, 'IN_PERSON');
    expect(Modality.virtual.bookingType.wire, 'VIRTUAL');
  });
}
