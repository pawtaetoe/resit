import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:resit/core/widgets/thumb_bar.dart';

/// Marks the part of the app laid out for a desktop window (a sidebar, a
/// toolbar at the top, mouse and keyboard) rather than a phone.
class DesktopScope extends InheritedWidget {
  final bool desktop;

  const DesktopScope({super.key, required this.desktop, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopScope>()?.desktop ?? false;

  @override
  bool updateShouldNotify(DesktopScope old) => old.desktop != desktop;
}

/// A [Scaffold] for screens with a [thumbAppBar] and a [ThumbBar].
///
/// On a phone it is exactly that: the title at the top and the actions in a
/// bar at the bottom, within thumb reach. In a desktop window the actions
/// move up into a toolbar on the right of the title bar, with a standard
/// back button on the left, as desktop apps have them.
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;

  const AppScaffold({super.key, this.appBar, this.body, this.bottomNavigationBar});

  /// The toolbar's height in a desktop window.
  static const toolbarHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final bar = bottomNavigationBar;
    final top = appBar;
    if (!DesktopScope.of(context) || top is! AppBar || (bar != null && bar is! ThumbBar)) {
      return Scaffold(appBar: appBar, body: body, bottomNavigationBar: bottomNavigationBar);
    }
    final thumb = bar as ThumbBar?;
    final canPop = Navigator.of(context).canPop();
    final theme = Theme.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(480.0, math.max(300.0, constraints.maxWidth * 0.42));
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: toolbarHeight,
          automaticallyImplyLeading: false,
          leading: canPop ? const BackButton() : null,
          titleSpacing: canPop ? 0 : 24,
          title: top.title,
          actions: [
            if (thumb?.child case final child?)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: SizedBox(
                  width: width,
                  height: ThumbBar.heightOf(context),
                  // The phone bar's roomy button padding doesn't fit a toolbar.
                  child: Theme(data: _compactButtons(theme), child: child),
                ),
              ),
          ],
          bottom: thumb?.caption == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(32),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DefaultTextStyle.merge(
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        child: thumb!.caption!,
                      ),
                    ),
                  ),
                ),
          shape: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        body: body,
      );
    });
  }
}

ThemeData _compactButtons(ThemeData theme) {
  const padding = EdgeInsets.symmetric(horizontal: 16);
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(padding: padding).merge(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(padding: padding).merge(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: TextButton.styleFrom(padding: padding).merge(theme.textButtonTheme.style)),
  );
}

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
                                    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: widget.destinations[i].builder),
                                  ),
                                )
                              : const SizedBox.shrink(),
                      ],
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
