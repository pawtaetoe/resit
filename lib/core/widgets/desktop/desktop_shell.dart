import 'package:flutter/material.dart';
import 'package:resit/core/widgets/desktop/desktop_scope.dart';

/// One entry in the desktop sidebar.
class DesktopDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// The group heading shown above this entry (the SIT system it belongs to).
  final String? group;
  final WidgetBuilder builder;

  const DesktopDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
    this.group,
  });
}

/// The desktop window: a sidebar listing every part of the app, grouped by
/// SIT system, and the selected part on the right. Each part keeps its own
/// page history, so opening a course or a booking stays inside the content
/// area and the sidebar never disappears.
class DesktopShell extends StatefulWidget {
  final List<DesktopDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Shown at the top of the sidebar.
  final Widget header;

  /// Shown next to an entry's label (e.g. "sign-in needed" on Account).
  final Widget? Function(int index)? badge;

  const DesktopShell({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.header,
    this.badge,
  });

  /// Widest the content gets on very large screens.
  static const maxContentWidth = 1280.0;
  static const sidebarWidth = 248.0;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final _navigators = List.generate(widget.destinations.length, (_) => GlobalKey<NavigatorState>());
  final Set<int> _visited = {};

  void _select(int i) {
    if (i == widget.selected) {
      // Selecting the open part again goes back to its first page.
      _navigators[i].currentState?.popUntil((route) => route.isFirst);
    }
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    _visited.add(widget.selected);

    final sidebar = <Widget>[];
    String? group;
    for (var i = 0; i < widget.destinations.length; i++) {
      final d = widget.destinations[i];
      if (d.group != group) {
        group = d.group;
        sidebar.add(Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 6),
          child: group == null
              ? const Divider(height: 1)
              : Text(group, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ));
      }
      final selected = i == widget.selected;
      sidebar.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedColor: scheme.onSecondaryContainer,
          selectedTileColor: scheme.secondaryContainer,
          shape: const StadiumBorder(),
          visualDensity: const VisualDensity(vertical: -1),
          leading: Icon(selected ? d.selectedIcon : d.icon),
          title: Text(d.label, style: theme.textTheme.labelLarge),
          trailing: widget.badge?.call(i),
          onTap: () => _select(i),
        ),
      ));
    }

    return DesktopScope(
      desktop: true,
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: scheme.surfaceContainerLow,
              child: SizedBox(
                width: DesktopShell.sidebarWidth,
                child: SafeArea(
                  right: false,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [widget.header, ...sidebar],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: ColoredBox(
                color: scheme.surface,
                // Content stays clear of the system bars at the bottom and
                // right (e.g. a tablet's taskbar). The top is left to each
                // screen's toolbar, which pads for the status bar itself.
                child: SafeArea(
                  top: false,
                  left: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: DesktopShell.maxContentWidth),
                      child: IndexedStack(
                        index: widget.selected,
                        children: [
                          for (var i = 0; i < widget.destinations.length; i++)
                            _visited.contains(i)
                                ? HeroControllerScope.none(
                                    child: Navigator(
                                      key: _navigators[i],
                                      onGenerateRoute: (_) =>
                                          MaterialPageRoute<void>(builder: widget.destinations[i].builder),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
