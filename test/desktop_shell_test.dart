import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/widgets/desktop.dart';

void main() {
  testWidgets('desktop content stays above a tablet taskbar', (tester) async {
    // A landscape tablet with a 48 px taskbar along the bottom.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: DesktopShell(
        destinations: [
          DesktopDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
            builder: (_) => Scaffold(
              // Like the app's screens: their own padding, so no automatic insets.
              body: ListView(padding: const EdgeInsets.all(16), children: [
                for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('Row $i')),
              ]),
            ),
          ),
        ],
        selected: 0,
        onSelect: (_) {},
        header: const Text('reSIT'),
      ),
    ));

    // Scroll to the end: the last row must end above the taskbar, not under it.
    await tester.drag(find.byType(ListView).last, const Offset(0, -5000));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('Row 29'));
    expect(last.bottom, lessThanOrEqualTo(800 - 48));
  });
}
