import 'package:flutter/material.dart';

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
