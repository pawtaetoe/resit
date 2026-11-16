import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';

/// The start time: a field that opens a sheet of times at the bottom of the
/// screen, within thumb reach, instead of a long menu near the top.
class StartTimeField extends StatelessWidget {
  /// The start times on offer, and the picked one (minutes since midnight).
  final List<int> options;
  final int startMin;
  final bool enabled;

  /// Called with a newly picked time.
  final ValueChanged<int> onChanged;

  const StartTimeField({
    super.key,
    required this.options,
    required this.startMin,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Text('No more slots today. Pick another day.');
    }
    final current = options.contains(startMin) ? startMin : options.first;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: enabled ? () => _pick(context, current) : null,
      icon: const Icon(Icons.access_time),
      label: Row(
        children: [
          Expanded(child: Text(hhmm(current), style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Start time', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.page),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in options)
                    ChoiceChip(
                      label: Text(hhmm(m)),
                      selected: m == current,
                      onSelected: (_) => Navigator.pop(context, m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != current) onChanged(picked);
  }
}
