import 'dart:async';

import 'package:flutter/material.dart';
import 'package:resit/sites/adfs/totp.dart';

/// The current code with a countdown, refreshed every second.
class LiveCode extends StatefulWidget {
  final TotpConfig config;
  const LiveCode({super.key, required this.config});

  @override
  State<LiveCode> createState() => _LiveCodeState();
}

class _LiveCodeState extends State<LiveCode> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    // Redraws only while it can be seen: not on another tab (TickerMode off)
    // or with the app in the background.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final code = widget.config.codeAt(now);
    final left = widget.config.secondsLeft(now);
    final half = code.length ~/ 2;
    final shown = '${code.substring(0, half)} ${code.substring(half)}';

    return Semantics(
      label: 'Current code ${code.split('').join(' ')}, changes in $left seconds',
      excludeSemantics: true,
      child: Row(
        children: [
          Text(
            shown,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              value: left / widget.config.period,
              strokeWidth: 3,
              color: left <= 5 ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(width: 6),
          Text('${left}s', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
