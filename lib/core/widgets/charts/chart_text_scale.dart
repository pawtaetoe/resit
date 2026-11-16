import 'package:flutter/widgets.dart';

/// Chart labels follow the user's text size, up to 1.3×: beyond that they'd
/// overrun the chart's margins, and "Show as table" has the same numbers at
/// full size.
TextScaler chartTextScale(BuildContext context) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
