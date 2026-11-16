import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';

/// Last check before booking, so a stray tap never books a room.
class ConfirmBookingSheet extends ConsumerStatefulWidget {
  final RoomWithSlots room;
  final String date;
  final String slotSummary;
  final String? quotaNote;

  const ConfirmBookingSheet({super.key, required this.room, required this.date, required this.slotSummary, this.quotaNote});

  @override
  ConsumerState<ConfirmBookingSheet> createState() => _ConfirmBookingSheetState();
}

class _ConfirmBookingSheetState extends ConsumerState<ConfirmBookingSheet> {
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
