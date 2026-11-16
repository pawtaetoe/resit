import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:resit/core/widgets/desktop/desktop_scope.dart';
import 'package:resit/core/widgets/thumb_bar.dart';

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
