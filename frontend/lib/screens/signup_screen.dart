import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _loading = false;
  String? _error;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController =
      TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final rePassword = _rePasswordController.text;

    if (name.isEmpty ||
        mobile.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        rePassword.isEmpty) {
      setState(() => _error = 'Please fill all the fields');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (password != rePassword) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(authProvider.notifier)
          .register(name, email, password, phone: mobile);
      // authProvider is now authenticated and main.dart shows MainScreen
      // underneath; remove this pushed route (and anything above the root)
      // so the user lands on the app instead of the sign-up form.
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFFD8A8D2),
        fontSize: 9,
      ),
      border: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: Color(0xFF55204F),
          width: 0.8,
        ),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: Color(0xFF55204F),
          width: 0.8,
        ),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(
          color: Colors.white,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Logo
                  const SizedBox(height: 10),

                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Sign In title
                  const Text(
                    'Sign Up',
                    style: TextStyle(
                      fontFamily: 'Times New Roman',
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF72216F),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Sign up form
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      18,
                      8,
                      18,
                      10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF702078),
                          Color(0xFFC43FB0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Name
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration('Name'),
                        ),

                        const SizedBox(height: 5),

                        // Mobile number
                        TextField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration('Mob no:'),
                        ),

                        const SizedBox(height: 5),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration('email'),
                        ),

                        const SizedBox(height: 5),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration('Password'),
                        ),

                        const SizedBox(height: 5),

                        // Re-enter password
                        TextField(
                          controller: _rePasswordController,
                          obscureText: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration(
                            'Re-enter Password',
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // OK button
                  SizedBox(
                    width: 100,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF702078),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'OK',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Back to login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Back to ',
                        style: TextStyle(
                          fontSize: 8,
                          color: Color(0xFF333333),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'login page',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}