import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

/// Ranked availability: locations with openings first (soonest at top).
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.results, required this.onBook});

  final List<LocationAvailability> results;
  final ValueChanged<LocationAvailability> onBook;

  @override
  Widget build(BuildContext context) {
    final withAvail = results.where((r) => r.hasAvailability).toList();
    final without = results.where((r) => !r.hasAvailability).toList();

    return ListView(
      children: [
        _SectionHeader(
          withAvail.isEmpty
              ? 'No availability in the next window'
              : '${withAvail.length} location(s) with openings',
        ),
        for (final r in withAvail) _AvailabilityTile(r: r, onBook: onBook),
        if (without.isNotEmpty) const _SectionHeader('No openings'),
        for (final r in without) _NoAvailabilityTile(r: r),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8)),
    );
  }
}

class _AvailabilityTile extends StatelessWidget {
  const _AvailabilityTile({required this.r, required this.onBook});
  final LocationAvailability r;
  final ValueChanged<LocationAvailability> onBook;

  @override
  Widget build(BuildContext context) {
    final earliest = r.earliest!;
    final df = DateFormat.MMMEd();
    final extra = r.days.length - 1;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text('${r.days.length}'),
        ),
        title: Text(r.location.shortLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Soonest: ${df.format(earliest)}'
          '${extra > 0 ? '  (+$extra more day${extra == 1 ? '' : 's'})' : ''}'
          '${r.service != null ? '\n${r.service!.name}' : ''}',
        ),
        isThreeLine: r.service != null,
        trailing: FilledButton.tonal(
          onPressed: () => onBook(r),
          child: const Text('Book'),
        ),
        onTap: () => onBook(r),
      ),
    );
  }
}

class _NoAvailabilityTile extends StatelessWidget {
  const _NoAvailabilityTile({required this.r});
  final LocationAvailability r;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.event_busy, size: 20),
      title: Text(r.location.shortLabel,
          style: const TextStyle(color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: r.note != null ? Text(r.note!, style: const TextStyle(fontSize: 12)) : null,
    );
  }
}
