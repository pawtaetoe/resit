import 'package:flutter/material.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';

/// Discussion and meeting rooms first, then the rest by name.
int _compareRoomTypes(String a, String b) {
  final qa = canonicalRoomType(a) != null ? 0 : 1;
  final qb = canonicalRoomType(b) != null ? 0 : 1;
  return qa != qb ? qa.compareTo(qb) : a.compareTo(b);
}

/// The room type filter. Collapsed: "Room types" with the picked types on
/// one line. Tap to show a chip for every type.
class RoomTypeSection extends StatelessWidget {
  /// Every room the school lists; null until loaded.
  final List<Room>? rooms;
  final Set<String> picked;
  final bool loading;
  final String? error;
  final bool expanded;

  /// Whether the picked types can be changed (not during a search).
  final bool enabled;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRetry;
  final void Function(String type, bool picked) onPick;

  const RoomTypeSection({
    super.key,
    required this.rooms,
    required this.picked,
    required this.loading,
    required this.error,
    required this.expanded,
    required this.enabled,
    required this.onToggleExpanded,
    required this.onRetry,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final rooms = this.rooms;
    final picked = this.picked.toList()..sort(_compareRoomTypes);
    final summary = rooms == null
        ? (error != null
            ? "Couldn't load the room types"
            : loading
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
            onTap: rooms == null ? null : onToggleExpanded,
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
                          maxLines: expanded ? null : 1,
                          overflow: expanded ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: picked.isEmpty && rooms != null ? theme.colorScheme.error : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rooms != null)
                    Icon(expanded ? Icons.expand_less : Icons.expand_more, color: muted)
                  else if (error != null)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
        if (expanded && rooms != null) ...[
          const SizedBox(height: 4),
          _chips(rooms),
        ],
      ],
    );
  }

  /// A chip for every room type, with how many rooms it has.
  Widget _chips(List<Room> rooms) {
    final counts = <String, int>{};
    for (final r in rooms) {
      if (r.rsrcTypName.isNotEmpty) counts[r.rsrcTypName] = (counts[r.rsrcTypName] ?? 0) + 1;
    }
    final types = counts.keys.toList()..sort(_compareRoomTypes);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in types)
          FilterChip(
            label: Text('$t (${counts[t]})'),
            selected: picked.contains(t),
            onSelected: enabled ? (on) => onPick(t, on) : null,
          ),
      ],
    );
  }
}
