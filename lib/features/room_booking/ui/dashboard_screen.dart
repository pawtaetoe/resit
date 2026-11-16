import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/ui/book_room_view_model.dart';
import 'package:resit/features/room_booking/ui/manage_booking_screen.dart';
import 'package:resit/features/room_booking/ui/quota_card.dart';
import 'package:resit/features/room_booking/ui/widgets/confirm_booking_sheet.dart';
import 'package:resit/features/room_booking/ui/widgets/day_picker.dart';
import 'package:resit/features/room_booking/ui/widgets/duration_picker.dart';
import 'package:resit/features/room_booking/ui/widgets/room_results.dart';
import 'package:resit/features/room_booking/ui/widgets/room_type_section.dart';
import 'package:resit/features/room_booking/ui/widgets/start_time_field.dart';
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
      builder: (_) => ConfirmBookingSheet(room: room, date: s.apiDate, slotSummary: summary, quotaNote: quotaNote),
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
    final vm = _vm;
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
          const SectionLabel('Day', muted: true),
          DayPicker(selected: s.date, onSelected: s.searching ? null : vm.pickDay),
          const SizedBox(height: 20),
          const SectionLabel('Start time', muted: true),
          StartTimeField(options: s.startTimes, startMin: s.startMin, enabled: !s.searching, onChanged: vm.pickStart),
          const SizedBox(height: 20),
          const SectionLabel('How long', muted: true),
          DurationPicker(
            selected: s.duration,
            // Lengths past closing time or beyond the weekly hours left can't be picked.
            available: s.lengths.where((d) => maxLeft == null || d <= maxLeft).toList(),
            enabled: !s.searching,
            onChanged: vm.pickDuration,
          ),
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
          RoomTypeSection(
            rooms: s.allRooms,
            picked: s.types,
            loading: s.loadingRooms,
            error: s.roomsError,
            expanded: s.typesExpanded,
            enabled: !s.searching,
            onToggleExpanded: vm.toggleTypesExpanded,
            onRetry: vm.loadRooms,
            onPick: vm.pickType,
          ),
          const SizedBox(height: 16),
          QuotaSummary(day: s.date),
          const SizedBox(height: 24),
          SizedBox(key: _resultsKey),
          ...roomResults(
            context,
            state: s,
            quota: quota,
            onSearch: _search,
            onCheckAgain: (failed) => _search(only: failed),
            onFilter: vm.filterResults,
            onBook: _book,
          ),
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
                onPressed: vm.stopSearch,
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
}
