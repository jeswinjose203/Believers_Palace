import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../screens/verify_email_screen.dart';

/// A banner shown while the signed-in user's email is unverified. It offers to
/// resend the verification email and to re-check verification status (the user
/// verifies by opening the link in their email, which hits the backend).
class VerifyEmailBanner extends ConsumerStatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  ConsumerState<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends ConsumerState<VerifyEmailBanner> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(okMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null || user.emailVerified) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.amber.shade100,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: Colors.brown),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Please verify your email (${user.email}). '
                  'Tap to enter your token, or check your inbox.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_busy)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                TextButton(
                  onPressed: () => _run(
                    ref.read(authProvider.notifier).resendVerification,
                    'Verification email sent',
                  ),
                  child: const Text('Resend'),
                ),
                TextButton(
                  onPressed: () => _run(
                    ref.read(authProvider.notifier).refreshUser,
                    'Status refreshed',
                  ),
                  child: const Text('I verified'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
