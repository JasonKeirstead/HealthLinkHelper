import '../models/enums.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'graphql_ops.dart';

/// Typed wrappers over the booking GraphQL operations.
class BookingRepository {
  BookingRepository(this._api);
  final GraphQLExecutor _api;

  List<Map<String, dynamic>> _edges(Map<String, dynamic>? connection) {
    final edges = connection?['edges'];
    if (edges is! List) return const [];
    return edges
        .map((e) => (e as Map<String, dynamic>)['node'] as Map<String, dynamic>)
        .toList();
  }

  Map<String, dynamic> _booking(Map<String, dynamic> data) =>
      (data['currentUser']['chart']['booking']) as Map<String, dynamic>;

  Future<List<ClinicLocation>> locations(String chartId) async {
    final data = await _api.query('getLocations', Ops.getLocations, {
      'chartId': chartId,
      'bookingType': BookingType.nonGroup.wire,
      'name': '',
      'pagination': {'first': 100},
    });
    return _edges(_booking(data)['locations'] as Map<String, dynamic>?)
        .map(ClinicLocation.fromJson)
        .toList();
  }

  Future<List<PresentingIssue>> presentingIssues(String chartId, String locationId) async {
    final data = await _api.query('getPresentingIssues', Ops.getPresentingIssues, {
      'chartId': chartId,
      'locationId': locationId,
      'name': '',
      'bookingType': BookingType.nonGroup.wire,
    });
    return _edges(_booking(data)['presentingIssues'] as Map<String, dynamic>?)
        .map(PresentingIssue.fromJson)
        .toList();
  }

  Future<List<Service>> services(
    String chartId,
    String locationId,
    String presentingIssueId,
    BookingType bookingType,
  ) async {
    final data = await _api.query('getTypes', Ops.getTypes, {
      'chartId': chartId,
      'locationId': locationId,
      'presentingIssueId': presentingIssueId,
      'bookingType': bookingType.wire,
    });
    return _edges(_booking(data)['services'] as Map<String, dynamic>?)
        .map(Service.fromJson)
        .toList();
  }

  /// Days with availability in [from, until]. Values are `YYYY-MM-DD` strings.
  Future<List<DateTime>> availableDays({
    required String chartId,
    required String locationId,
    required String serviceId,
    required BookingType bookingType,
    required DateTime from,
    required DateTime until,
    String? providerId,
  }) async {
    final data = await _api.query('getAvailableDays', Ops.getAvailableDays, {
      'chartId': chartId,
      'bookingType': bookingType.wire,
      'locationId': locationId,
      'serviceId': serviceId,
      'providerId': providerId,
      'from': _localIso(from),
      'until': _localIso(until, endOfDay: true),
    });
    final days = _booking(data)['availableDays'];
    if (days is! List) return const [];
    return days.map((d) => DateTime.parse(d as String)).toList();
  }

  Future<List<TimeSlot>> timeSlots({
    required String chartId,
    required String locationId,
    required String serviceId,
    required BookingType bookingType,
    required DateTime date,
    String? providerId,
  }) async {
    final data = await _api.query('getTimeSlots', Ops.getTimeSlots, {
      'chartId': chartId,
      'bookingType': bookingType.wire,
      'locationId': locationId,
      'serviceId': serviceId,
      'providerId': providerId,
      'date': _localIso(date),
    });
    final slots = _booking(data)['timeSlots'];
    if (slots is! List) return const [];
    return slots
        .map((s) => TimeSlot.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// `DateTimeWithTimezone` on the wire is a local ISO string without offset.
  static String _localIso(DateTime d, {bool endOfDay = false}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = endOfDay ? '23:59:59.000' : '00:00:00.000';
    return '${d.year}-${two(d.month)}-${two(d.day)}T$t';
  }
}
