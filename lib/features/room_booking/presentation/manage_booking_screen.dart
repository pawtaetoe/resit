import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/presentation/dashboard_screen.dart';
import 'package:resit/features/room_booking/presentation/quota_card.dart';
import 'package:resit/core/widgets/desktop.dart';

/// My bookings: upcoming (confirmed) and past bookings, with cancel.
class ManageBookingScreen extends StatelessWidget {
  const ManageBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthGate(title: 'My bookings', builder: (_) => const _ManageBookingsView());
  }
}

enum _Tab { upcoming, past }

class _ManageBookingsView extends ConsumerStatefulWidget {
  const _ManageBookingsView();

  @override
  ConsumerState<_ManageBookingsView> createState() => _ManageBookingsViewState();
}

class _ManageBookingsViewState extends ConsumerState<_ManageBookingsView> {
  bool _isLoading = false;
  List<Booking>? _bookings;
  String? _error;
  bool _errorIsSession = false;
  _Tab _tab = _Tab.upcoming;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchBookings());
  }

  DateTime _parseBookingDateTime(String dateStr, String timeRangeStr) {
    try {
      final date = DateFormat('d MMM yyyy').parse(dateStr);
      if (timeRangeStr.contains('-')) {
        final parts = timeRangeStr.split('-')[0].trim().split(':');
        if (parts.length == 2) {
          return date.add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
        }
      }
      return date;
    } catch (_) {
      try {
        return DateFormat('d MMM yyyy').parse(dateStr);
      } catch (_) {
        return DateTime(1970);
      }
    }
  }

  Future<void> _fetchBookings({bool force = false}) async {
    final tab = _tab;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(bookingServiceProvider);
      List<Booking> list;

      if (tab == _Tab.upcoming) {
        final raw = await service.getBookings(bookingStatus: 'current', force: force);
        list = raw.where((b) => b.status.toLowerCase() == 'confirmed').toList();
        // Soonest first: that's the one you need next.
        list.sort(
            (a, b) => _parseBookingDateTime(a.date, a.timeRange).compareTo(_parseBookingDateTime(b.date, b.timeRange)));
      } else {
        // History plus current bookings that are no longer confirmed.
        List<Booking> history = [];
        try {
          history = await service.getBookings(bookingStatus: 'history', force: force);
        } catch (_) {
          // History may be unavailable; show what we have.
        }
        List<Booking> current = [];
        try {
          current = await service.getBookings(bookingStatus: 'current', force: force);
        } catch (_) {}

        final combined = <String, Booking>{};
        for (final b in history) {
          combined[b.bookingRef] = b;
        }
        for (final b in current.where((b) => b.status.toLowerCase() != 'confirmed')) {
          combined[b.bookingRef] = b;
        }
        list = combined.values.toList()
          ..sort((a, b) =>
              _parseBookingDateTime(b.date, b.timeRange).compareTo(_parseBookingDateTime(a.date, a.timeRange)));
      }

      // Ignore a late answer for a tab the user has already left.
      if (mounted && tab == _tab) setState(() => _bookings = list);
    } catch (e) {
      if (mounted && tab == _tab) {
        setState(() {
          _error = friendlyError(e);
          _errorIsSession = isSessionError(e);
        });
      }
    } finally {
      if (mounted && tab == _tab) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel(Booking booking) async {
    final confirmed = await showChoiceSheet<bool>(
      context,
      icon: Icons.event_busy,
      title: 'Cancel this booking?',
      message: '${booking.roomName}\n${booking.date}, ${booking.timeRange}\n\n'
          "The room is released straight away and this can't be undone.",
      choices: const [
        SheetChoice(true, 'Cancel booking', icon: Icons.event_busy, primary: true, danger: true),
        SheetChoice(false, 'Keep booking'),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling.add(booking.bookingRef));
    try {
      await ref.read(bookingServiceProvider).cancelBooking(booking.cancelId);
      if (!mounted) return;
      ref.invalidate(quotaDataProvider);
      ref.invalidate(nextBookingProvider);
      HapticFeedback.mediumImpact();
      showSuccess(context, 'Booking for ${booking.roomName} cancelled. Its hours are back in your weekly allowance.');
      await _fetchBookings();
    } catch (e) {
      if (mounted) showError(context, "Couldn't cancel: ${friendlyError(e)}");
    } finally {
      if (mounted) setState(() => _cancelling.remove(booking.bookingRef));
    }
  }

  final Set<String> _cancelling = {};

  Future<void> _refresh() {
    ref.invalidate(quotaDataProvider);
    return _fetchBookings(force: true);
  }

  void _copyRef(String ref) {
    Clipboard.setData(ClipboardData(text: ref));
    showSuccess(context, 'Booking reference $ref copied.');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: thumbAppBar('My bookings'),
      // Switching lists sits next to back, under the thumb; refresh is a
      // pull-down on the list.
      bottomNavigationBar: ThumbBar(
        child: ThumbToggle<_Tab>(
          options: const [
            ThumbToggleOption(_Tab.upcoming, 'Upcoming', icon: Icons.upcoming_outlined),
            ThumbToggleOption(_Tab.past, 'Past', icon: Icons.history),
          ],
          selected: _tab,
          onChanged: (tab) {
            setState(() {
              _tab = tab;
              _bookings = null;
            });
            _fetchBookings();
          },
        ),
      ),
      body: Column(
        children: [
          RefreshStrip(active: _isLoading && _bookings != null),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _bookings == null) {
      return const MessageView(
        icon: Icons.event_note_outlined,
        title: 'Getting your bookings…',
        action: SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    }

    if (_error != null) {
      return MessageView(
        icon: _errorIsSession ? Icons.lock_clock : Icons.cloud_off,
        tone: Tone.danger,
        title: _errorIsSession ? "Couldn't sign you in" : "Couldn't load bookings",
        message: _error,
        action: FilledButton.icon(
          onPressed: _fetchBookings,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    final bookings = _bookings ?? const <Booking>[];
    final showQuota = _tab == _Tab.upcoming;
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: MessageView(
                icon: Icons.event_available_outlined,
                title: _tab == _Tab.upcoming ? 'No upcoming bookings' : 'No past bookings',
                message: _tab == _Tab.upcoming
                    ? 'Rooms you book will show up here.'
                    : 'Finished and cancelled bookings will show up here.',
                action: _tab == _Tab.upcoming
                    ? FilledButton.icon(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const DashboardScreen()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Book a room'),
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
        itemCount: bookings.length + (showQuota ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: Space.card),
        itemBuilder: (context, index) {
          if (showQuota && index == 0) return QuotaCard(day: DateTime.now());
          final i = index - (showQuota ? 1 : 0);
          return _BookingCard(
            booking: bookings[i],
            cancelling: _cancelling.contains(bookings[i].bookingRef),
            onCancel: () => _cancel(bookings[i]),
            onCopyRef: () => _copyRef(bookings[i].bookingRef),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final bool cancelling;
  final VoidCallback onCancel;
  final VoidCallback onCopyRef;

  const _BookingCard({
    required this.booking,
    required this.cancelling,
    required this.onCancel,
    required this.onCopyRef,
  });

  (Tone, IconData) _statusLook(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return (Tone.success, Icons.check_circle_outline);
      case 'cancelled':
        return (Tone.danger, Icons.cancel_outlined);
      default:
        return (Tone.neutral, Icons.info_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (tone, icon) = _statusLook(booking.status);
    final canCancel = booking.status.toLowerCase() == 'confirmed' && booking.cancelId.isNotEmpty;

    Widget detail(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(booking.roomName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(label: booking.status, tone: tone, icon: icon),
                ],
              ),
            ),
            detail(Icons.calendar_today_outlined, booking.date),
            detail(Icons.schedule, booking.timeRange),
            if (booking.purpose.isNotEmpty && booking.purpose != 'N.A') detail(Icons.label_outline, booking.purpose),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                    ),
                    onPressed: onCopyRef,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text('Ref ${booking.bookingRef}', overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (canCancel)
                  cancelling
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                          onPressed: onCancel,
                          icon: const Icon(Icons.event_busy, size: 18),
                          label: const Text('Cancel'),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
