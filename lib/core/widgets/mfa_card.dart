import 'package:flutter/material.dart';
import 'package:resit/core/auth/auth_service.dart';

/// Tells the user to approve the sign-in in Microsoft Authenticator, showing
/// the number to match when ADFS provides one.
class MfaCard extends StatelessWidget {
  final MfaChallenge challenge;

  const MfaCard({super.key, required this.challenge});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phonelink_lock, size: 40, color: color.onPrimaryContainer),
          const SizedBox(height: 8),
          Text(
            'Approve in Microsoft Authenticator',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color.onPrimaryContainer),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            challenge.message,
            style: TextStyle(color: color.onPrimaryContainer),
            textAlign: TextAlign.center,
          ),
          if (challenge.number != null) ...[
            const SizedBox(height: 12),
            Text(
              challenge.number!,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 4, color: color.onPrimaryContainer),
            ),
          ],
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
