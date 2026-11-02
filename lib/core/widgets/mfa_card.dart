import 'package:flutter/material.dart';
import 'package:resit/core/auth/auth_service.dart';

/// Tells the user to approve the sign-in in Microsoft Authenticator, showing
/// the number to match when ADFS provides one.
class MfaCard extends StatelessWidget {
  final MfaChallenge challenge;

  const MfaCard({super.key, required this.challenge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final fg = color.onPrimaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_lock, size: 40, color: fg),
            const SizedBox(height: 8),
            Text(
              'Approve on your phone',
              style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(challenge.message, style: TextStyle(color: fg), textAlign: TextAlign.center),
            if (challenge.number != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: color.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  challenge.number!,
                  semanticsLabel: 'Number to enter: ${challenge.number!.split('').join(' ')}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: color.onSurface,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for approval. This screen updates on its own.',
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
