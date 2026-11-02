import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/data/quota.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/room_booking/presentation/quota_card.dart';

/// Book a room: pick a day, a start time and a length, then choose from the
/// rooms free for the whole slot.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthGate(title: 'Book a room', builder: (_) => const _BookRoomView());
  }
}

/// Booking hours offered by RBS, in minutes since midnight.
const _openMin = 7 * 60;
const _closeMin = 22 * 60;
const _durations = [30, 60, 90, 120, 180, 240];
const _daysAhead = 14;

String _hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';
}

int _toMin(String time) {
  final parts = time.trim().split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Returns the slots covering the whole requested range, or an empty list if
/// any part of it is taken or missing. E.g. 13:00-14:00 needs both
/// 13:00-13:30 and 13:30-14:00 to be available.
List<RoomSlot> slotsInRange(List<RoomSlot> slots, int lo, int hi) {
  if (hi <= lo) return [];

  final inRange = <({RoomSlot slot, int start, int end})>[];
  for (final sl in slots) {
    try {
      final parts = sl.label.split('-');
      final s = _toMin(parts[0]);
      final e = _toMin(parts[1]);
      if (s >= lo && e <= hi) inRange.add((slot: sl, start: s, end: e));
    } catch (_) {
      // ignore malformed labels
    }
  }
  inRange.sort((a, b) => a.start.compareTo(b.start));

  // Slots must be available and run back-to-back from lo to hi.
  var cursor = lo;
  for (final s in inRange) {
    if (!s.slot.available || s.start != cursor) return [];
    cursor = s.end;
  }
  if (cursor != hi) return [];
  return inRange.map((s) => s.slot).toList();
}

class _BookRoomView extends ConsumerStatefulWidget {
  const _BookRoomView();

  @override
  ConsumerState<_BookRoomView> createState() => _BookRoomViewState();
}

class _BookRoomViewState extends ConsumerState<_BookRoomView> {
  late DateTime _date;
  late int _startMin;
  int _duration = 120;

  bool _searching = false;
  List<RoomWithSlots>? _rooms;

  /// Progress of the per-room search, and rooms that couldn't be checked.
  int _checked = 0;
  int _total = 0;
  List<Room> _failed = [];
  Object? _firstFailure;
  StreamSubscription<RoomCheck>? _searchSub;
  String? _error;
  bool _errorIsSession = false;
  String _filter = '';
  final _resultsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final today = _today();
    final earliest = _earliestStart(today);
    if (earliest == null) {
      // Too late to book today: start on tomorrow.
      _date = today.add(const Duration(days: 1));
      _startMin = 9 * 60;
    } else {
      _date = today;
      _startMin = earliest < 13 * 60 ? 13 * 60 : earliest;
    }
    _duration = _validDurations().contains(120) ? 120 : _validDurations().last;
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isToday(DateTime d) => d == _today();

  /// First bookable half hour on [day], or null if none are left.
  int? _earliestStart(DateTime day) {
    var earliest = _openMin;
    if (_isToday(day)) {
      final now = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;
      earliest = ((nowMin + 29) ~/ 30) * 30; // round up to the next half hour
      if (earliest < _openMin) earliest = _openMin;
    }
    return earliest <= _closeMin - 30 ? earliest : null;
  }

  List<int> _startOptions() {
    final first = _earliestStart(_date);
    if (first == null) return [];
    return [for (var m = first; m <= _closeMin - 30; m += 30) m];
  }

  List<int> _validDurations() => _durations.where((d) => _startMin + d <= _closeMin).toList();

  int get _endMin => _startMin + _duration;

  String get _apiDate => DateFormat('d MMM yyyy').format(_date);

  String get _slotSummary => '${DateFormat('EEE d MMM').format(_date)} · ${_hhmm(_startMin)} – ${_hhmm(_endMin)}';

  /// Any change to the search makes old results misleading, so clear them.
  void _changeSearch(VoidCallback change) {
    setState(() {
      change();
      final starts = _startOptions();
      if (starts.isNotEmpty && !starts.contains(_startMin)) {
        _startMin = starts.firstWhere((m) => m >= _startMin, orElse: () => starts.last);
      }
      final valid = _validDurations();
      if (!valid.contains(_duration)) _duration = valid.isEmpty ? 30 : valid.last;
      _searchSub?.cancel();
      _searching = false;
      _rooms = null;
      _failed = [];
      _error = null;
    });
  }

  @override
  void dispose() {
    _searchSub?.cancel();
    super.dispose();
  }

  /// Checks rooms one per request, several at once, and lists each free
  /// room as soon as its answer arrives. With [only], re-checks just those
  /// rooms (the ones that failed) and keeps the results found so far.
  Future<void> _search({List<Room>? only}) async {
    await _searchSub?.cancel();
    setState(() {
      _searching = true;
      _error = null;
      _firstFailure = null;
      if (only == null) {
        _rooms = [];
        _failed = [];
        _filter = '';
        _checked = 0;
        _total = 0;
      } else {
        _failed = [];
        _checked = 0;
        _total = only.length;
      }
    });

    try {
      final service = ref.read(bookingServiceProvider);
      final rooms = only ?? await service.getRooms();
      if (!mounted) return;
      setState(() => _total = rooms.length);
      if (only == null) _revealResults();

      // Fixed now, so late answers are matched against the slot that was
      // searched even if the form changes meanwhile.
      final start = _startMin;
      final end = _endMin;
      final done = Completer<void>();

      _searchSub = service.checkEachRoom(rooms, _apiDate, _hhmm(_openMin), _hhmm(_closeMin)).listen(
        (check) {
          if (!mounted) return;
          setState(() {
            _checked++;
            if (check.error != null) {
              _failed.add(check.room);
              _firstFailure ??= check.error;
            } else if (check.result != null) {
              final picks = slotsInRange(check.result!.slots, start, end);
              if (picks.isNotEmpty) _rooms?.add(RoomWithSlots(check.room, picks));
            }
          });
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;

      // Every room failed: show it as an error rather than "no rooms free".
      if (mounted && _total > 0 && _failed.length == _total && (_rooms?.isEmpty ?? true)) {
        throw _firstFailure ?? Exception("Couldn't check any rooms.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _errorIsSession = isSessionError(e);
          _failed = [];
        });
        _revealResults();
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

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
    final summary = _slotSummary;
    final type = room.room.rsrcTypName;
    final quota = weeklyQuotaFor(ref, _date);
    final quotaNote = quota == null || !quotaRoomTypes.contains(type)
        ? null
        : 'Uses ${formatHours(_duration)} of your weekly ${roomTypeLabel(type).toLowerCase()} hours. '
            '${formatHours(quota.remaining(type) - _duration)} left after this.';
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmBookingSheet(room: room, date: _apiDate, slotSummary: summary, quotaNote: quotaNote),
    );
    if (booked != true || !mounted) return;

    ref.invalidate(quotaDataProvider);
    setState(() => _rooms?.remove(room));
    showSuccess(
      context,
      'Booked ${room.room.rsrcName} for $summary.',
      action: SnackBarAction(
        label: 'My bookings',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageBookingScreen()),
        ),
      ),
    );
  }

  /// Most hours left for any room type in the selected week (null = unknown).
  int? _maxLeft(WeeklyQuota? quota) =>
      quota == null ? null : quotaRoomTypes.map(quota.remaining).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quota = weeklyQuotaFor(ref, _date);
    final maxLeft = _maxLeft(quota);
    final overQuota = maxLeft != null && _duration > maxLeft;

    return Scaffold(
      appBar: thumbAppBar('Book a room'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _label(context, 'Day'),
          _buildDayPicker(),
          const SizedBox(height: 20),
          _label(context, 'Start time'),
          _buildStartPicker(),
          const SizedBox(height: 20),
          _label(context, 'How long'),
          _buildDurationPicker(maxLeft),
          if (overQuota) ...[
            const SizedBox(height: 8),
            Text(
              maxLeft == 0
                  ? "You've used all your booking hours for this week. Pick a day in another week."
                  : 'Only ${formatHours(maxLeft)} left this week. Pick a shorter time.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          QuotaCard(day: _date),
          const SizedBox(height: 24),
          SizedBox(key: _resultsKey),
          ..._buildResults(),
        ],
      ),
      // The chosen slot and the search button stay under the thumb while
      // the options scroll above.
      bottomNavigationBar: ThumbBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _slotSummary,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            BusyButton(
              onPressed: _startOptions().isEmpty || overQuota ? null : _search,
              busy: _searching,
              icon: Icons.search,
              label: 'Find free rooms',
              busyLabel: _total == 0 ? 'Checking rooms…' : 'Checking rooms… $_checked/$_total',
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildDayPicker() {
    final today = _today();
    final days = [
      for (var i = 0; i <= _daysAhead; i++) DateTime(today.year, today.month, today.day + i),
    ].where((d) => _earliestStart(d) != null).toList();

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
          final selected = d == _date;
          final scheme = Theme.of(context).colorScheme;
          return ChoiceChip(
            showCheckmark: false,
            selected: selected,
            onSelected: _searching ? null : (_) => _changeSearch(() => _date = d),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(top, style: TextStyle(fontSize: 12, color: selected ? null : scheme.onSurfaceVariant)),
                Text(DateFormat('d MMM').format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStartPicker() {
    final options = _startOptions();
    if (options.isEmpty) {
      return const Text('No more slots today. Pick another day.');
    }
    return DropdownButtonFormField<int>(
      initialValue: options.contains(_startMin) ? _startMin : options.first,
      key: ValueKey(_date), // rebuild with fresh options when the day changes
      decoration: const InputDecoration(prefixIcon: Icon(Icons.access_time)),
      menuMaxHeight: 320,
      items: [for (final m in options) DropdownMenuItem(value: m, child: Text(_hhmm(m)))],
      onChanged: _searching ? null : (m) => _changeSearch(() => _startMin = m!),
    );
  }

  Widget _buildDurationPicker(int? maxLeft) {
    // Lengths past closing time or beyond the weekly hours left can't be picked.
    final valid = _validDurations().where((d) => maxLeft == null || d <= maxLeft).toList();
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
          for (final d in _durations)
            ButtonSegment(
              value: d,
              enabled: !_searching && valid.contains(d),
              label: Text(_durationLabel(d).replaceAll(' min', 'm').replaceAll(' h', 'h'),
                  semanticsLabel: _durationLabel(d)),
            ),
        ],
        selected: {_duration},
        onSelectionChanged: (s) => _changeSearch(() => _duration = s.first),
      ),
    );
  }

  List<Widget> _buildResults() {
    if (_error != null) {
      return [
        MessageView(
          icon: _errorIsSession ? Icons.lock_clock : Icons.cloud_off,
          title: _errorIsSession ? "Couldn't sign you in" : "Couldn't load rooms",
          message: _error,
          action: FilledButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ];
    }

    final rooms = _rooms;
    if (rooms == null) return [];
    final theme = Theme.of(context);

    // While checking: progress, with free rooms listed below as they arrive.
    final progress = _searching
        ? <Widget>[
            Text(
              _total == 0 ? 'Getting the room list…' : 'Checked $_checked of $_total rooms…',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _total == 0 ? null : _checked / _total),
            ),
            const SizedBox(height: 16),
          ]
        : const <Widget>[];

    // Rooms that couldn't be checked even after a retry.
    final failedNote = !_searching && _failed.isNotEmpty
        ? <Widget>[
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                title: Text(
                  "${_failed.length} ${_failed.length == 1 ? 'room' : 'rooms'} couldn't be checked",
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                trailing: TextButton(
                  onPressed: () => _search(only: List.of(_failed)),
                  child: const Text('Check again'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ]
        : const <Widget>[];

    if (rooms.isEmpty) {
      if (_searching || _failed.isNotEmpty) return [...progress, ...failedNote];
      return [
        const MessageView(
          icon: Icons.meeting_room_outlined,
          title: 'No rooms free for this slot',
          message: 'Try a shorter time, a different start time or another day.',
        ),
      ];
    }

    final quota = weeklyQuotaFor(ref, _date);
    bool fits(RoomWithSlots r) => quota == null || quota.fits(r.room.rsrcTypName, _duration);

    final q = _filter.toLowerCase();
    final shown = (q.isEmpty
        ? [...rooms]
        : rooms.where((r) => '${r.room.rsrcName} ${r.room.rsrcTypName}'.toLowerCase().contains(q)).toList())
      // Rooms you can still book come first.
      ..sort((a, b) => (fits(a) ? 0 : 1).compareTo(fits(b) ? 0 : 1));
    return [
      ...progress,
      ...failedNote,
      Text(
        '${rooms.length} ${rooms.length == 1 ? 'room' : 'rooms'} free${_searching ? ' so far' : ''}',
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
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 12),
      ],
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No rooms match "$_filter".', textAlign: TextAlign.center),
        ),
      for (final rm in shown) _roomTile(rm, fits(rm), quota),
    ];
  }

  Widget _roomTile(RoomWithSlots rm, bool canBook, WeeklyQuota? quota) {
    final scheme = Theme.of(context).colorScheme;
    final type = rm.room.rsrcTypName;
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
                if (type.isNotEmpty) type,
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
