import 'package:flutter/material.dart';

void showSuccess(BuildContext context, String message, {SnackBarAction? action}) =>
    _show(context, message, Icons.check_circle_outline, action: action);

void showError(BuildContext context, String message) =>
    _show(context, message, Icons.error_outline, error: true);

void _show(BuildContext context, String message, IconData icon,
    {bool error = false, SnackBarAction? action}) {
  final scheme = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    backgroundColor: error ? scheme.error : null,
    action: action,
    content: Row(
      children: [
        Icon(icon, color: error ? scheme.onError : scheme.onInverseSurface),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
  ));
}
