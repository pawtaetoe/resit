import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/ui/book_room_view_model.dart';
import 'package:resit/features/room_booking/ui/manage_booking_screen.dart';
import 'package:resit/features/room_booking/ui/quota_card.dart';
import 'package:resit/core/widgets/desktop.dart';

/// Book a room: pick a day, a start time and a length, then choose from the
/// rooms free for the whole slot.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Each screen has its own search, even with two open at once.
    return AuthGate(
      title: 'Book a room',
      builder: (_) => ProviderScope(overrides: [bookRoomProvider], child: const _BookRoomView()),
    );
  }
}

class _BookRoomView extends ConsumerStatefulWidget {
  const _BookRoomView();

  @override
  ConsumerState<_BookRoomView> createState() => _BookRoomViewState();
}

class _BookRoomViewState extends ConsumerState<_BookRoomView> {
  final _resultsKey = GlobalKey();

  BookRoomViewModel get _vm => ref.read(bookRoomProvider.notifier);

  Future<void> _search({List<Room>? only}) => _vm.search(only: only, onShowResults: _revealResults);

  /// The search button is at the bottom but results appear under the form,
  /// so scroll them into view.
  void _revealResults() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _book(RoomWithSlots room) async {
    final s = ref.read(bookRoomProvider);
    final summary = s.slotSummary;
    final type = room.room.quotaType;
    final quota = weeklyQuotaFor(ref, s.date);
    final quotaNote = quota == null || !quotaRoomTypes.contains(type)
        ? null
        : 'Uses ${formatHours(s.duration)} of your weekly ${roomTypeLabel(type).toLowerCase()} hours. '
            '${formatHours(quota.remaining(type) - s.duration)} left after this.';
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmBookingSheet(room: room, date: s.apiDate, slotSummary: summary, quotaNote: quotaNote),
    );
    if (booked != true || !mounted) return;

    _vm.booked(room);
    HapticFeedback.mediumImpact();
    showSuccess(
      context,
      'Booked ${room.room.rsrcName} for $summary.',
      action: SnackBarAction(
        label: 'My bookings',
        // Back to the tabs first, so there's never a second My bookings
        // underneath (e.g. when Book a room was opened from My bookings).
        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ManageBookingScreen()),
          (route) => route.isFirst,
        ),
      ),
    );
  }

  /// Most hours left for any room type in the selected week (null = unknown).
  int? _maxLeft(WeeklyQuota? quota) =>
      quota == null ? null : quotaRoomTypes.map(quota.remaining).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bookRoomProvider);
    final quota = weeklyQuotaFor(ref, s.date);
    // Other room types (e.g. lecture rooms) have no weekly allowance, so the
    // hours left only limit the length when just DR/MR are being searched.
    final maxLeft = s.onlyQuotaTypes ? _maxLeft(quota) : null;
    final overQuota = maxLeft != null && s.duration > maxLeft;

    return AppScaffold(
      appBar: thumbAppBar('Book a room'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 32),
        children: [
          _label(context, 'Day'),
          _buildDayPicker(s),
          const SizedBox(height: 20),
          _label(context, 'Start time'),
          _buildStartPicker(s),
          const SizedBox(height: 20),
          _label(context, 'How long'),
          _buildDurationPicker(s, maxLeft),
          if (overQuota) ...[
            const SizedBox(height: 8),
            StatusBanner(
              tone: Tone.warning,
              icon: Icons.hourglass_bottom,
              title: maxLeft == 0 ? 'No booking hours left this week' : 'Only ${formatHours(maxLeft)} left this week',
              message: maxLeft == 0 ? 'Pick a day in another week.' : 'Pick a shorter time.',
            ),
          ],
          const SizedBox(height: 20),
          _buildTypeSection(s),
          const SizedBox(height: 16),
          QuotaSummary(day: s.date),
          const SizedBox(height: 24),
          SizedBox(key: _resultsKey),
          ..._buildResults(s, quota),
        ],
      ),
      // The chosen slot and the search button stay under the thumb while
      // the options scroll above.
      bottomNavigationBar: ThumbBar(
        caption: Text(s.slotSummary),
        // While searching, the button stops the search (rooms found so far
        // stay listed).
        child: s.searching
            ? FilledButton.tonalIcon(
                onPressed: _vm.stopSearch,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(s.total == 0 ? 'Stop' : 'Stop · checked ${s.checked}/${s.total}',
                    overflow: TextOverflow.ellipsis),
              )
            : BusyButton(
                onPressed: s.startTimes.isEmpty || overQuota || (s.allRooms != null && s.types.isEmpty) ? null : _search,
                icon: Icons.search,
                label: 'Find free rooms',
                busyLabel: '',
              ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => SectionLabel(text, muted: true);

  Widget _buildDayPicker(BookRoomState s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 0; i <= bookingDaysAhead; i++) DateTime(today.year, today.month, today.day + i),
    ].where((d) => earliestStart(d, now) != null).toList();

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = days[i];
          final diff = d.difference(today).inDays;
          final top = diff == 0
              ? 'Today'
              : diff == 1
                  ? 'Tmrw'
                  : DateFormat('EEE').format(d);
          final selected = d == s.date;
          final scheme = Theme.of(context).colorScheme;
          return ChoiceChip(
            showCheckmark: false,
            selected: selected,
            onSelected: s.searching ? null : (_) => _vm.pickDay(d),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(top, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? null : scheme.onSurfaceVariant)),
                Text(DateFormat('d MMM').format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStartPicker(BookRoomState s) {
    final options = s.startTimes;
    if (options.isEmpty) {
      return const Text('No more slots today. Pick another day.');
    }
    final current = options.contains(s.startMin) ? s.startMin : options.first;
    // A field that opens a sheet of times at the bottom of the screen, within
    // thumb reach, instead of a long menu near the top.
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: s.searching ? null : () => _pickStart(options, current),
      icon: const Icon(Icons.access_time),
      label: Row(
        children: [
          Expanded(child: Text(hhmm(current), style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }

  Future<void> _pickStart(List<int> options, int current) async {
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
    if (picked != null && picked != current) _vm.pickStart(picked);
  }

  /// Collapsed: "Room types" with the picked types on one line. Tap to show
  /// a chip for every type.
  Widget _buildTypeSection(BookRoomState s) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final rooms = s.allRooms;
    final picked = s.types.toList()
      ..sort((a, b) {
        final qa = canonicalRoomType(a) != null ? 0 : 1;
        final qb = canonicalRoomType(b) != null ? 0 : 1;
        return qa != qb ? qa.compareTo(qb) : a.compareTo(b);
      });
    final summary = rooms == null
        ? (s.roomsError != null
            ? "Couldn't load the room types"
            : s.loadingRooms
                ? 'Loading room types…'
                : 'Discussion and meeting rooms')
        : picked.isEmpty
            ? 'None picked — pick at least one'
            : picked.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: rooms == null ? null : _vm.toggleTypesExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Room types', style: theme.textTheme.titleSmall?.copyWith(color: muted)),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: s.typesExpanded ? null : 1,
                          overflow: s.typesExpanded ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: picked.isEmpty && rooms != null ? theme.colorScheme.error : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rooms != null)
                    Icon(s.typesExpanded ? Icons.expand_less : Icons.expand_more, color: muted)
                  else if (s.roomsError != null)
                    TextButton(onPressed: _vm.loadRooms, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
        if (s.typesExpanded && rooms != null) ...[
          const SizedBox(height: 4),
          _buildTypeFilter(s),
        ],
      ],
    );
  }

  Widget _buildTypeFilter(BookRoomState s) {
    final theme = Theme.of(context);
    final rooms = s.allRooms;
    if (rooms == null) {
      if (s.roomsError != null) {
        return Row(
          children: [
            Expanded(child: Text("Couldn't load the room types.", style: theme.textTheme.bodySmall)),
            TextButton(onPressed: _vm.loadRooms, child: const Text('Retry')),
          ],
        );
      }
      return Text(
        s.loadingRooms ? 'Loading room types…' : 'Discussion and meeting rooms',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final counts = <String, int>{};
    for (final r in rooms) {
      if (r.rsrcTypName.isNotEmpty) counts[r.rsrcTypName] = (counts[r.rsrcTypName] ?? 0) + 1;
    }
    // Discussion and meeting rooms first, then the rest by name.
    final types = counts.keys.toList()
      ..sort((a, b) {
        final qa = canonicalRoomType(a) != null ? 0 : 1;
        final qb = canonicalRoomType(b) != null ? 0 : 1;
        return qa != qb ? qa.compareTo(qb) : a.compareTo(b);
      });

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in types)
          FilterChip(
            label: Text('$t (${counts[t]})'),
            selected: s.types.contains(t),
            onSelected: s.searching ? null : (on) => _vm.pickType(t, on),
          ),
      ],
    );
  }

  Widget _buildDurationPicker(BookRoomState s, int? maxLeft) {
    // Lengths past closing time or beyond the weekly hours left can't be picked.
    final valid = s.lengths.where((d) => maxLeft == null || d <= maxLeft).toList();
    // One row of equal segments so every length is visible at a glance.
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (final d in bookingLengths)
            ButtonSegment(
              value: d,
              enabled: !s.searching && valid.contains(d),
              label: Text(durationLabel(d).replaceAll(' min', 'm').replaceAll(' h', 'h'),
                  semanticsLabel: durationLabel(d)),
            ),
        ],
        selected: {s.duration},
        onSelectionChanged: (sel) => _vm.pickDuration(sel.first),
      ),
    );
  }

  List<Widget> _buildResults(BookRoomState s, WeeklyQuota? quota) {
    if (s.error != null) {
      return [
        MessageView(
          compact: true,
          tone: Tone.danger,
          icon: s.errorIsSession ? Icons.lock_clock : Icons.cloud_off,
          title: s.errorIsSession ? "Couldn't sign you in" : "Couldn't load rooms",
          message: s.error,
          action: FilledButton.icon(
            onPressed: _search,
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
              action: TextButton(onPressed: () => _search(only: List.of(s.failed)), child: const Text('Check again')),
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
            action: FilledButton.icon(
                onPressed: _search, icon: const Icon(Icons.search), label: const Text('Search again')),
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
          onChanged: _vm.filterResults,
        ),
        const SizedBox(height: 12),
      ],
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No rooms match "${s.filter}".', textAlign: TextAlign.center),
        ),
      for (final rm in shown) _roomTile(rm, fits(rm), quota),
    ];
  }

  Widget _roomTile(RoomWithSlots rm, bool canBook, WeeklyQuota? quota) {
    final scheme = Theme.of(context).colorScheme;
    final type = rm.room.quotaType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: canBook,
          onTap: () => _book(rm),
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
            onPressed: canBook ? () => _book(rm) : null,
            child: const Text('Book'),
          ),
        ),
      ),
    );
  }
}

/// Last check before booking, so a stray tap never books a room.
class _ConfirmBookingSheet extends ConsumerStatefulWidget {
  final RoomWithSlots room;
  final String date;
  final String slotSummary;
  final String? quotaNote;

  const _ConfirmBookingSheet({required this.room, required this.date, required this.slotSummary, this.quotaNote});

  @override
  ConsumerState<_ConfirmBookingSheet> createState() => _ConfirmBookingSheetState();
}

class _ConfirmBookingSheetState extends ConsumerState<_ConfirmBookingSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingServiceProvider)
          .initiateAndConfirmBooking(widget.room.room, widget.room.slots, widget.date);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = widget.room.room;
    final disclaimer = room.disclaimer.trim();

    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Confirm booking', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            row(Icons.meeting_room_outlined, room.rsrcName),
            row(Icons.schedule, widget.slotSummary),
            if (room.capacity > 0) row(Icons.groups_outlined, 'Seats ${room.capacity}'),
            if (widget.quotaNote != null) row(Icons.hourglass_bottom, widget.quotaNote!),
            if (disclaimer.isNotEmpty && disclaimer.toUpperCase() != 'N.A') ...[
              const SizedBox(height: 4),
              Text(disclaimer, style: theme.textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            BusyButton(
              onPressed: _confirm,
              busy: _busy,
              icon: Icons.check,
              label: _error == null ? 'Confirm booking' : 'Try again',
              busyLabel: 'Booking…',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
