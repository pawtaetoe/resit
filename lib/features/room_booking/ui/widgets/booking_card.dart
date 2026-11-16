import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';

/// One booking in My bookings: room, status, date and time, purpose, its
/// reference (tap to copy) and, while it's confirmed, a cancel button.
class BookingCard extends StatelessWidget {
  final Booking booking;
  final bool cancelling;
  final VoidCallback onCancel;
  final VoidCallback onCopyRef;

  const BookingCard({
    super.key,
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
    final canCancel = booking.status.toLowerCase() == 'confirmed' && booking.bookingRef.isNotEmpty;

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
