import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../services/api_service.dart';

/// Lets the user request and enter an email verification code.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = ref.read(authProvider).user?.email;
    if (_loading || _resending || email == null) return;
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the six-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      await ref.read(apiServiceProvider).verifyEmail(email, _code.text);
      await auth.refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).resendVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your inbox for a recent code.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).user?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              Text(
                email == null
                    ? 'Enter the six-digit code from your email.'
                    : 'Request a code for $email and enter it below.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: 'Six-digit code'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    _loading || _resending || email == null ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
              TextButton(
                onPressed:
                    _loading || _resending || email == null ? null : _resend,
                child: _resending
                    ? const Text('Sending...')
                    : const Text('Send verification code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
