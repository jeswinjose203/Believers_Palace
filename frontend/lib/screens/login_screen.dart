import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _hidePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // On success authProvider flips to authenticated and main.dart swaps
      // the home widget to MainScreen.
      await ref.read(authProvider.notifier).login(email, password);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  void _signUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
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
                  // Logo moved higher
                  const SizedBox(height: 10),

                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Welcome text
                  const Text(
                    'Welcome to Believers Palace',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Times New Roman',
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF72216F),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Login box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      12,
                    ),
                    decoration: BoxDecoration(
                      // Diagonal gradient: top-left -> bottom-right
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
                        // Email / Phone
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'email',
                            hintStyle: TextStyle(
                              color: Color(0xFFDAB8D7),
                              fontSize: 10,
                            ),
                            border: InputBorder.none,
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xFFD39ACA),
                                width: 0.8,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white,
                                width: 1,
                              ),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 3,
                            ),
                          ),
                        ),

                        const SizedBox(height: 7),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            hintText: 'password',
                            hintStyle: const TextStyle(
                              color: Color(0xFFDAB8D7),
                              fontSize: 10,
                            ),
                            border: InputBorder.none,
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xFFD39ACA),
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
                              vertical: 3,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _hidePassword = !_hidePassword;
                                });
                              },
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Forgot password button
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 25),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
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

                  const SizedBox(height: 6),

                  // Sign up button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Don’t have an account?',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF333333),
                        ),
                      ),
                      TextButton(
                        onPressed: _signUp,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF702078),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Bottom tagline
                  const Text(
                    'Bringing people and places of faith together.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF777777),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}