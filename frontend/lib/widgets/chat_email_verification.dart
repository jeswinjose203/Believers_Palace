import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../screens/verify_email_screen.dart';

class ChatEmailVerification extends StatelessWidget {
  const ChatEmailVerification({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Verify your email to access chat.')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
              ),
              child: Text(context.tr('Verify email')),
            ),
          ],
        ),
      ),
    );
  }
}
