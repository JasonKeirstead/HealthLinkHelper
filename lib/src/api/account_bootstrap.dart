import '../models/models.dart';
import 'api_client.dart';
import 'graphql_ops.dart';

/// Resolves the (accountId, chartId, name) patients bookable by the signed-in
/// user via `currentUser.charts.nodes` — replacing any hardcoded IDs. A user may
/// have several charts (self across multiple accounts/clinics, plus dependents).
class AccountBootstrap {
  AccountBootstrap(this._api);
  final GraphQLExecutor _api;

  Future<List<Patient>> loadPatients() async {
    final data = await _api.query('connectedCharts', Ops.connectedCharts, const {});
    final nodes = ((data['currentUser']?['charts']?['nodes']) as List?) ?? const [];

    final patients = <Patient>[];
    final seen = <String>{}; // dedupe by accountId|chartId
    for (final n in nodes) {
      final node = n as Map<String, dynamic>;
      if (node['patientArchived'] == true) continue;
      final chartId = node['id'] as String?;
      final accountId = (node['account'] as Map<String, dynamic>?)?['id'] as String?;
      if (chartId == null || accountId == null) continue;
      if (!seen.add('$accountId|$chartId')) continue;

      final profile = node['profile'] as Map<String, dynamic>?;
      final name = (profile?['fullName'] as String?)?.trim();
      patients.add(Patient(
        accountId: accountId,
        chartId: chartId,
        fullName: (name != null && name.isNotEmpty) ? name : 'Patient $chartId',
      ));
    }
    return patients;
  }
}
