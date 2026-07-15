import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../config.dart';
import '../models/enums.dart';
import '../models/models.dart';
import '../scanner/monitor_service.dart';
import '../scanner/scanner.dart';
import 'results_view.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.services});
  final Services services;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  bool _loadingSetup = true;
  bool _scanning = false;
  String? _error;

  List<Patient> _patients = const [];
  Patient? _patient;

  List<PresentingIssue> _issues = const [];
  PresentingIssue? _issue;

  Modality _modality = Modality.inPerson;
  int _months = 1; // default 1, max 6

  List<ClinicLocation> _locations = const [];
  final Set<String> _selectedLocationIds = {};

  ScanProgress? _progress;
  List<LocationAvailability>? _results;

  // Background monitor runs as a foreground service (survives backgrounding),
  // not an in-app timer.
  ScanRequest? _lastRequest;
  bool _monitoring = false;
  int _monitorMinutes = 15;

  bool get _hasAvailability => _results?.any((r) => r.hasAvailability) ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
    _refreshMonitoringState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The service may have found a slot and stopped itself while we were away.
    if (state == AppLifecycleState.resumed) _refreshMonitoringState();
  }

  Future<void> _refreshMonitoringState() async {
    final running = await AppointmentMonitor.isRunning;
    if (mounted && running != _monitoring) setState(() => _monitoring = running);
  }

  Future<void> _setup() async {
    setState(() {
      _loadingSetup = true;
      _error = null;
    });
    try {
      final patients = await widget.services.bootstrap.loadPatients();
      if (patients.isEmpty) {
        throw Exception('No patient charts found on this account.');
      }
      _patients = patients;
      _patient = patients.first;
      await _loadForPatient();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loadingSetup = false);
    }
  }

  /// Load the location list (for the toggles) and the appointment-type options.
  Future<void> _loadForPatient() async {
    final chartId = _patient!.chartId;
    final locations = await widget.services.booking.locations(chartId);
    if (locations.isEmpty) {
      throw Exception('No bookable locations for this patient.');
    }
    _locations = locations;
    _selectedLocationIds
      ..clear()
      ..addAll(locations.map((l) => l.id)); // default: everything selected

    final issues = await widget.services.booking.presentingIssues(chartId, locations.first.id);
    _issues = issues;
    _issue = issues.firstWhere(
      (i) => i.name.toLowerCase().contains('medical visit'),
      orElse: () => issues.first,
    );
    if (mounted) setState(() {});
  }

  Future<void> _runScan() async {
    if (_patient == null || _issue == null || _selectedLocationIds.isEmpty) return;
    _stopMonitoring();
    final req = ScanRequest(
      patient: _patient!,
      issueName: _issue!.name,
      modality: _modality,
      monthsAhead: _months,
      includeLocationIds: _selectedLocationIds.toSet(),
    );
    _lastRequest = req;
    setState(() {
      _scanning = true;
      _error = null;
      _results = null;
      _progress = null;
    });
    try {
      final results = await widget.services.scanner.scan(
        req,
        onProgress: (p) => setState(() => _progress = p),
      );
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _startMonitoring() async {
    final req = _lastRequest;
    if (req == null) return;
    try {
      await AppointmentMonitor.start(req, Duration(minutes: _monitorMinutes));
      if (mounted) setState(() => _monitoring = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t start background watch: $e')),
        );
      }
    }
  }

  void _stopMonitoring() {
    if (_monitoring) AppointmentMonitor.stop();
    if (_monitoring && mounted) setState(() => _monitoring = false);
  }

  Future<void> _openBooking(LocationAvailability r) async {
    final url = Uri.parse(EbbConfig.appOrigin).replace(
      pathSegments: [_patient!.accountId, 'booking', 'new-appointment'],
    );
    final earliest = r.earliest;
    final when = earliest == null ? '' : ' — try ${DateFormat.yMMMMd().format(earliest)}';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Opening booking for ${r.location.shortLabel}$when'),
      ));
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _newSearch() {
    _stopMonitoring();
    setState(() {
      _results = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find an appointment'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () {
              _stopMonitoring();
              widget.services.auth.signOut();
            },
          ),
        ],
      ),
      // SafeArea keeps the bottom bar (e.g. "Start watching") clear of the
      // Android navigation bar under edge-to-edge (targetSdk 35+).
      body: SafeArea(
        child: _loadingSetup
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && _results == null)
                ? _ErrorView(message: _error!, onRetry: _setup)
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Options form before a search; results afterwards.
    if (_results == null && !_scanning) {
      return SingleChildScrollView(
        child: _Options(
          patients: _patients,
          patient: _patient,
          onPatient: (p) async {
            setState(() => _patient = p);
            try {
              await _loadForPatient();
            } catch (e) {
              setState(() => _error = '$e');
            }
          },
          issues: _issues,
          issue: _issue,
          onIssue: (i) => setState(() => _issue = i),
          modality: _modality,
          onModality: (m) => setState(() => _modality = m),
          months: _months,
          onMonths: (m) => setState(() => _months = m),
          locations: _locations,
          selectedIds: _selectedLocationIds,
          onToggleLocation: (id, on) => setState(() {
            on ? _selectedLocationIds.add(id) : _selectedLocationIds.remove(id);
          }),
          onSelectAll: (all) => setState(() {
            _selectedLocationIds.clear();
            if (all) _selectedLocationIds.addAll(_locations.map((l) => l.id));
          }),
          onScan: _runScan,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${_issue?.name ?? ''} · ${_selectedLocationIds.length} location(s) · $_months mo',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _scanning ? null : _newSearch,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('New search'),
              ),
            ],
          ),
        ),
        if (_scanning) _ProgressBar(progress: _progress),
        const Divider(height: 1),
        Expanded(
          child: _results == null
              ? const Center(child: Text('Scanning…'))
              : ResultsView(results: _results!, onBook: _openBooking),
        ),
        if (_results != null && !_scanning && !_hasAvailability)
          _MonitorBar(
            monitoring: _monitoring,
            minutes: _monitorMinutes,
            onMinutes: (m) => setState(() => _monitorMinutes = m),
            onStart: _startMonitoring,
            onStop: _stopMonitoring,
          ),
      ],
    );
  }
}

class _MonitorBar extends StatelessWidget {
  const _MonitorBar({
    required this.monitoring,
    required this.minutes,
    required this.onMinutes,
    required this.onStart,
    required this.onStop,
  });

  final bool monitoring;
  final int minutes;
  final ValueChanged<int> onMinutes;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: monitoring
            ? Row(
                children: [
                  const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'Watching every $minutes min — you\'ll get a notification when a slot opens.'),
                  ),
                  TextButton(onPressed: onStop, child: const Text('Stop')),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('No openings right now. Keep checking in the background?'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Every'),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: minutes,
                        items: const [5, 15, 30, 60]
                            .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                            .toList(),
                        onChanged: (m) => m == null ? null : onMinutes(m),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('Start watching'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({
    required this.patients,
    required this.patient,
    required this.onPatient,
    required this.issues,
    required this.issue,
    required this.onIssue,
    required this.modality,
    required this.onModality,
    required this.months,
    required this.onMonths,
    required this.locations,
    required this.selectedIds,
    required this.onToggleLocation,
    required this.onSelectAll,
    required this.onScan,
  });

  final List<Patient> patients;
  final Patient? patient;
  final ValueChanged<Patient> onPatient;
  final List<PresentingIssue> issues;
  final PresentingIssue? issue;
  final ValueChanged<PresentingIssue> onIssue;
  final Modality modality;
  final ValueChanged<Modality> onModality;
  final int months;
  final ValueChanged<int> onMonths;
  final List<ClinicLocation> locations;
  final Set<String> selectedIds;
  final void Function(String id, bool on) onToggleLocation;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (patients.length > 1) ...[
            DropdownButtonFormField<Patient>(
              initialValue: patient,
              decoration: const InputDecoration(labelText: 'Patient', border: OutlineInputBorder()),
              items: [
                for (final p in patients) DropdownMenuItem(value: p, child: Text(p.fullName)),
              ],
              onChanged: (p) => p == null ? null : onPatient(p),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<PresentingIssue>(
            key: ValueKey('issue-${patient?.chartId}-${issues.length}'),
            initialValue: issue,
            decoration: const InputDecoration(
                labelText: 'Appointment type', border: OutlineInputBorder()),
            items: [
              for (final i in issues)
                DropdownMenuItem(value: i, child: Text(i.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (i) => i == null ? null : onIssue(i),
          ),
          const SizedBox(height: 12),
          SegmentedButton<Modality>(
            segments: const [
              ButtonSegment(value: Modality.inPerson, label: Text('In-person'), icon: Icon(Icons.person)),
              ButtonSegment(value: Modality.virtual, label: Text('Virtual'), icon: Icon(Icons.videocam)),
            ],
            selected: {modality},
            onSelectionChanged: (s) => onModality(s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Months ahead:'),
              Expanded(
                child: Slider(
                  value: months.toDouble(),
                  min: 1,
                  max: 6,
                  divisions: 5,
                  label: '$months',
                  onChanged: (v) => onMonths(v.round()),
                ),
              ),
              Text('$months', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Locations (${selectedIds.length}/${locations.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              Row(children: [
                TextButton(onPressed: () => onSelectAll(true), child: const Text('All')),
                TextButton(onPressed: () => onSelectAll(false), child: const Text('None')),
              ]),
            ],
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final loc in locations)
                    SwitchListTile(
                      dense: true,
                      title: Text(loc.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: (loc.city != null && loc.city!.trim().isNotEmpty)
                          ? Text(loc.city!.trim())
                          : null,
                      value: selectedIds.contains(loc.id),
                      onChanged: (v) => onToggleLocation(loc.id, v),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: selectedIds.isEmpty ? null : onScan,
            icon: const Icon(Icons.search),
            label: Text(selectedIds.isEmpty
                ? 'Select at least one location'
                : 'Search ${selectedIds.length} location${selectedIds.length == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({this.progress});
  final ScanProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: p == null || p.total == 0 ? null : p.fraction),
          if (p != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${p.completed}/${p.total} · ${p.currentLocation}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
