import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/ui/book_room_view_model.dart';

/// The search's results, as items of the screen's list (so long results
/// scroll with the form): progress while checking, rooms that couldn't be
/// checked, then the free rooms, those that fit the weekly hours first.
List<Widget> roomResults(
  BuildContext context, {
  required BookRoomState state,
  required WeeklyQuota? quota,
  required VoidCallback onSearch,
  required ValueChanged<List<Room>> onCheckAgain,
  required ValueChanged<String> onFilter,
  required ValueChanged<RoomWithSlots> onBook,
}) {
  final s = state;
  if (s.error != null) {
    return [
      MessageView(
        compact: true,
        tone: Tone.danger,
        icon: s.errorIsSession ? Icons.lock_clock : Icons.cloud_off,
        title: s.errorIsSession ? "Couldn't sign you in" : "Couldn't load rooms",
        message: s.error,
        action: FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
    ];
  }

  final rooms = s.rooms;
  if (rooms == null) return [];
  final theme = Theme.of(context);

  // While checking: progress, with free rooms listed below as they arrive.
  final progress = s.searching
      ? <Widget>[
          Text(
            s.total == 0 ? 'Getting the room list…' : 'Checked ${s.checked} of ${s.total} rooms…',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: s.total == 0 ? null : s.checked / s.total),
          ),
          const SizedBox(height: 16),
        ]
      : const <Widget>[];

  // Rooms that couldn't be checked even after a retry.
  final failedNote = !s.searching && s.failed.isNotEmpty
      ? <Widget>[
          StatusBanner(
            tone: Tone.warning,
            icon: Icons.warning_amber_rounded,
            title: "${s.failed.length} ${s.failed.length == 1 ? 'room' : 'rooms'} couldn't be checked",
            action: TextButton(onPressed: () => onCheckAgain(List.of(s.failed)), child: const Text('Check again')),
          ),
          const SizedBox(height: 12),
        ]
      : const <Widget>[];

  if (rooms.isEmpty) {
    if (s.searching || s.failed.isNotEmpty) return [...progress, ...failedNote];
    if (s.stopped) {
      return [
        MessageView(
          compact: true,
          icon: Icons.stop_circle_outlined,
          title: 'Search stopped',
          message: 'Checked ${s.checked} of ${s.total} rooms, none free so far.',
          action:
              FilledButton.icon(onPressed: onSearch, icon: const Icon(Icons.search), label: const Text('Search again')),
        ),
      ];
    }
    return [
      const MessageView(
        compact: true,
        icon: Icons.meeting_room_outlined,
        title: 'No rooms free for this slot',
        message: 'Try a shorter time, a different start time or another day.',
      ),
    ];
  }

  // Only discussion and meeting rooms count against the weekly hours.
  bool fits(RoomWithSlots r) =>
      quota == null || !quotaRoomTypes.contains(r.room.quotaType) || quota.fits(r.room.quotaType, s.duration);

  final q = s.filter.toLowerCase();
  final shown = (q.isEmpty
      ? [...rooms]
      : rooms.where((r) => '${r.room.rsrcName} ${r.room.rsrcTypName}'.toLowerCase().contains(q)).toList())
    // Rooms you can still book come first.
    ..sort((a, b) => (fits(a) ? 0 : 1).compareTo(fits(b) ? 0 : 1));
  return [
    ...progress,
    ...failedNote,
    Text(
      '${rooms.length} ${rooms.length == 1 ? 'room' : 'rooms'} free'
      '${s.searching ? ' so far' : s.stopped ? ' (stopped after ${s.checked} of ${s.total})' : ''}',
      style: theme.textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    if (rooms.length > 5) ...[
      TextField(
        decoration: const InputDecoration(
          hintText: 'Filter by room name',
          prefixIcon: Icon(Icons.filter_list),
          isDense: true,
        ),
        onChanged: onFilter,
      ),
      const SizedBox(height: 12),
    ],
    if (shown.isEmpty)
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No rooms match "${s.filter}".', textAlign: TextAlign.center),
      ),
    for (final rm in shown) RoomTile(room: rm, canBook: fits(rm), quota: quota, onBook: () => onBook(rm)),
  ];
}

/// A free room. Rooms past the weekly hours left show why and can't be
/// booked.
class RoomTile extends StatelessWidget {
  final RoomWithSlots room;
  final bool canBook;
  final WeeklyQuota? quota;
  final VoidCallback onBook;

  const RoomTile({super.key, required this.room, required this.canBook, required this.quota, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rm = room;
    final quota = this.quota;
    final type = rm.room.quotaType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: canBook,
          onTap: onBook,
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          leading: const Icon(Icons.meeting_room_outlined),
          title: Text(rm.room.rsrcName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([
                if (rm.room.rsrcTypName.isNotEmpty) rm.room.rsrcTypName,
                if (rm.room.capacity > 0) 'Seats ${rm.room.capacity}',
              ].join(' · ')),
              if (!canBook && quota != null)
                Text(
                  'Weekly limit: ${formatHours(quota.remaining(type))} of ${roomTypeLabel(type).toLowerCase()} left',
                  style: TextStyle(color: scheme.error),
                ),
            ],
          ),
          trailing: FilledButton.tonal(
            onPressed: canBook ? onBook : null,
            child: const Text('Book'),
          ),
        ),
      ),
    );
  }
}
