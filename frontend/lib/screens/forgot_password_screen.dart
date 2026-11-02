import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'reset_password_screen.dart';

/// Lets a user request a password reset token for their email address.
/// The backend always responds success (no account enumeration); the reset
/// token is delivered out of band (email in production, server log in dev).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(apiServiceProvider).forgotPassword(_email.text.trim());
      setState(() => _sent = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToReset() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(email: _email.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              const Text(
                'Enter your account email and we\'ll send you a reset token.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                enabled: !_sent,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_sent) ...[
                const SizedBox(height: 16),
                const Text(
                  'If that email is registered, a reset token has been sent. '
                  'Enter it on the next screen along with your new password.',
                  style: TextStyle(color: Colors.green),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _goToReset,
                  child: const Text('I have a reset token'),
                ),
              ] else ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Reset Token'),
                ),
                TextButton(
                  onPressed: _goToReset,
                  child: const Text('I already have a token'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
