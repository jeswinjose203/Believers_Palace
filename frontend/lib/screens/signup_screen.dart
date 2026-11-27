import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../core/firebase_app_config.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.verifyingExistingAccount = false});

  final bool verifyingExistingAccount;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _loading = false;
  String? _error;
  String? _notice;
  bool _verifying = false;
  bool _attemptsExhausted = false;
  String? _verificationId;
  int? _resendToken;
  int _requestGeneration = 0;
  PhoneAuthCredential? _automaticCredential;
  String? _firebaseIdToken;
  String? _destination;
  DateTime? _resendAt;
  DateTime? _expiresAt;
  Timer? _clock;
  final _codeController = TextEditingController();

  int get _resendSeconds {
    final remaining = _resendAt?.difference(DateTime.now()).inMilliseconds ?? 0;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  bool get _expired => _expiresAt?.isAfter(DateTime.now()) == false;

  final _usernameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();
  final TextEditingController _countryCodeController =
      TextEditingController(text: '+91');

  @override
  void dispose() {
    _clock?.cancel();
    _codeController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _mobileController.dispose();
    _countryCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_loading) return;
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final rePassword = _rePasswordController.text;

    if (!widget.verifyingExistingAccount) {
      if (name.isEmpty ||
          mobile.isEmpty ||
          email.isEmpty ||
          password.isEmpty ||
          rePassword.isEmpty) {
        setState(() => _error = 'Please fill all the fields');
        return;
      }
      if (!RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(_usernameController.text)) {
        setState(() => _error =
            'Use 3 to 32 letters, digits, or underscores for your username.');
        return;
      }
      final passwordBytes = utf8.encode(password).length;
      if (passwordBytes < 8 || passwordBytes > 72) {
        setState(() => _error = 'Password must be between 8 and 72 bytes.');
        return;
      }
      if (password != rePassword) {
        setState(() => _error = 'Passwords do not match');
        return;
      }

      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        setState(() => _error = 'Enter a valid email address.');
        return;
      }
    }
    final phoneInput = mobile.replaceAll(RegExp(r'[ ()-]'), '');
    final countryCode = _countryCodeController.text
        .trim()
        .replaceAll(RegExp(r'[ ()-]'), '');
    final phone = phoneInput.startsWith('+')
        ? phoneInput
        : '$countryCode$phoneInput';
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
      setState(
          () => _error = 'Include the country code, such as +919876543210.');
      return;
    }
    if (_destination == phone &&
        (_verificationId != null ||
            _automaticCredential != null ||
            _firebaseIdToken != null)) {
      setState(() {
        _verifying = true;
        _error = null;
        _notice = null;
      });
      return;
    }
    await _sendCode(phone);
  }

  Future<FirebaseAuth> _firebaseAuth() async {
    if (!FirebaseAppConfig.canInitialize) {
      throw const _PhoneSetupUnavailable();
    }
    final app = await FirebaseAppConfig.initialize();
    return FirebaseAuth.instanceFor(app: app);
  }

  Future<void> _sendCode(String phone) async {
    if (_loading) return;
    final wasVerifying = _verifying;
    final generation = ++_requestGeneration;
    final response = Completer<
        ({String? id, int? resendToken, FirebaseAuthException? error})>();
    PhoneAuthCredential? automaticCredential;
    var accepted = false;
    var active = true;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final auth = await _firebaseAuth();
      if (!mounted) return;
      await auth
          .verifyPhoneNumber(
            phoneNumber: phone,
            forceResendingToken: _destination == phone ? _resendToken : null,
            verificationCompleted: (credential) {
              if (!mounted || !active || generation != _requestGeneration) {
                return;
              }
              automaticCredential = credential;
              if (!response.isCompleted) {
                response.complete((
                  id: credential.verificationId,
                  resendToken: null,
                  error: null
                ));
              }
              if (accepted && !_loading && _verifying && !_expired) {
                setState(() {
                  _automaticCredential = credential;
                  _notice = 'Your device detected the verification code.';
                });
              }
            },
            verificationFailed: (error) {
              if (active && !response.isCompleted) {
                response.complete((id: null, resendToken: null, error: error));
              }
            },
            codeSent: (id, resendToken) {
              if (active && !response.isCompleted) {
                response
                    .complete((id: id, resendToken: resendToken, error: null));
              }
            },
            codeAutoRetrievalTimeout: (id) {
              if (active && !response.isCompleted) {
                response.complete((id: id, resendToken: null, error: null));
              }
            },
          )
          .timeout(const Duration(seconds: 90));
      final result = await response.future.timeout(const Duration(seconds: 90));
      if (result.error case final error?) throw error;
      if (!mounted) return;
      accepted = true;
      _codeController.clear();
      setState(() {
        _destination = phone;
        _verificationId = result.id;
        _resendToken = result.resendToken;
        _automaticCredential = automaticCredential;
        _firebaseIdToken = null;
        _resendAt = DateTime.now().add(const Duration(seconds: 60));
        _expiresAt = DateTime.now().add(const Duration(minutes: 10));
        _verifying = true;
        _attemptsExhausted = false;
        if (automaticCredential != null) {
          _notice = 'Your device detected the verification code.';
        } else if (wasVerifying) {
          _notice = 'A new code was requested. Use the latest SMS.';
        }
      });
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (_verifying) setState(() {});
      });
    } catch (e) {
      active = false;
      if (!mounted) return;
      setState(() {
        if (wasVerifying) {
          _resendAt = DateTime.now().add(const Duration(seconds: 60));
        }
        _error = _message(e,
            'Could not request a code. Check your connection and try again.');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    if (_loading || _expired || _attemptsExhausted) return;
    final code = _codeController.text;
    final automatic = _automaticCredential;
    if (_firebaseIdToken == null &&
        automatic == null &&
        !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the six-digit code from your SMS.');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_firebaseIdToken == null) {
        final auth = await _firebaseAuth();
        final credential =
            (_verificationId == null || code.isEmpty ? automatic : null) ??
                PhoneAuthProvider.credential(
                  verificationId: _verificationId!,
                  smsCode: code,
                );
        try {
          final result = await auth.signInWithCredential(credential);
          _firebaseIdToken = await result.user?.getIdToken();
          if (_firebaseIdToken == null) {
            throw StateError(
                'Firebase did not issue a phone verification token');
          }
        } finally {
          if (auth.currentUser != null) await auth.signOut();
        }
      }
      if (!mounted) return;
      final auth = ref.read(authProvider.notifier);
      if (widget.verifyingExistingAccount) {
        await auth.verifyPhone(_destination!, _firebaseIdToken!);
        if (mounted) navigator.pop(true);
        return;
      }
      await auth.register(
        _nameController.text.trim(),
        username: _usernameController.text,
        _emailController.text.trim(),
        _passwordController.text,
        phone: _destination!,
        firebaseIdToken: _firebaseIdToken!,
      );
      if (mounted) navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is FirebaseAuthException) {
          _automaticCredential = null;
          _attemptsExhausted =
              e.code == 'too-many-requests' || e.code == 'quota-exceeded';
          if (e.code == 'session-expired' ||
              e.code == 'invalid-verification-id' ||
              _verificationId == null) {
            _expiresAt = DateTime.now();
          }
        }
        if (e is ApiException && e.code == 'phone_proof_invalid') {
          _firebaseIdToken = null;
          _expiresAt = DateTime.now();
        }
        _error = _message(e,
            'Could not confirm signup. Try again, or sign in if your account was created.');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error, String fallback) {
    if (error is _PhoneSetupUnavailable) {
      return 'Mobile verification is unavailable on this build.';
    }
    if (error is FirebaseAuthException) {
      if (error.code == 'operation-not-allowed' &&
          (error.message?.contains('until this region enabled') ?? false)) {
        return 'Verification is unavailable for this country code.';
      }
      return switch (error.code) {
        'invalid-verification-code' => 'That code is incorrect. Try again.',
        'session-expired' ||
        'invalid-verification-id' =>
          'This code has expired. Request another code.',
        'invalid-phone-number' =>
          'Enter a valid mobile number with country code.',
        'too-many-requests' =>
          'Too many attempts. Wait before requesting another code.',
        'quota-exceeded' =>
          'SMS verification is temporarily unavailable. Try again later.',
        'operation-not-allowed' ||
        'app-not-authorized' =>
          'Mobile verification is temporarily unavailable.',
        _ => fallback,
      };
    }
    if (error is ApiException) {
      if (error.statusCode == 429 && error.code == null) {
        return 'Too many requests. Wait a minute and try again.';
      }
      if (error.statusCode < 500 ||
          error.code == 'phone_verification_unavailable') {
        return error.message;
      }
    }
    return fallback;
  }

  void _backToSignup() {
    if (_loading) return;
    _codeController.clear();
    setState(() {
      _verifying = false;
      _error = null;
      _notice = null;
    });
  }

  Widget _verificationScreen() {
    final resendSeconds = _resendSeconds;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Verify mobile number')),
        leading: BackButton(onPressed: _loading ? () {} : _backToSignup),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      _firebaseIdToken != null
                          ? context.tr('{0} is verified. Continue to create your account.', [_destination])
                          : _automaticCredential != null
                              ? context.tr('Your code was detected for {0}.', [_destination])
                              : context.tr('Enter the six-digit code sent to {0}.', [_destination]),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  if (_firebaseIdToken == null && _verificationId != null)
                    AutofillGroup(
                      child: TextField(
                        controller: _codeController,
                        enabled: !_loading && !_expired && !_attemptsExhausted,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        maxLength: 6,
                        onSubmitted: (_) => _verify(),
                        decoration: InputDecoration(
                          labelText: context.tr('Verification code'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null || _expired || _notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ??
                              (_expired
                                  ? context.tr('This code has expired. Request another code.')
                                  : context.tr(_notice!)),
                          style: TextStyle(
                            color: _error != null || _expired
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _loading || _expired || _attemptsExhausted
                        ? null
                        : _verify,
                    child: Text(widget.verifyingExistingAccount
                        ? context.tr('Verify phone')
                        : context.tr('Verify and create account')),
                  ),
                  TextButton(
                    onPressed: _loading || resendSeconds > 0
                        ? null
                        : () => _sendCode(_destination!),
                    child: Text(resendSeconds > 0
                        ? context.tr('Resend code in {0}s', [resendSeconds])
                        : context.tr('Send code again')),
                  ),
                  OutlinedButton(
                    onPressed: _loading ? null : _backToSignup,
                    child: Text(widget.verifyingExistingAccount
                        ? context.tr('Change number')
                        : context.tr('Back to signup')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_verifying && !_loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _verifying) _backToSignup();
      },
      child: _verifying
          ? _verificationScreen()
          : widget.verifyingExistingAccount
              ? _phoneForm()
              : _signupForm(),
    );
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

  Widget _phoneForm() => Scaffold(
        appBar: AppBar(title: Text(context.tr('Verify mobile number'))),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _mobileController,
              enabled: !_loading,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                labelText: context.tr('Mobile number with country code'),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _signUp,
              child: Text(context.tr('Send verification code')),
            ),
          ],
        ),
      );

  Widget _signupForm() {
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
                  Text(
                    context.tr('Sign Up'),
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
                          enabled: !_loading,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          decoration: _fieldDecoration('Name'),
                        ),

                        const SizedBox(height: 5),

                        TextField(
                          controller: _usernameController,
                          enabled: !_loading,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          decoration: _fieldDecoration('Username'),
                        ),
                        const SizedBox(height: 5),

                        // Mobile number
                        Row(
                          children: [
                            SizedBox(
                              width: 58,
                              child: TextField(
                                controller: _countryCodeController,
                                enabled: !_loading,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+]'),
                                  ),
                                ],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                                decoration: _fieldDecoration('Code'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _mobileController,
                                enabled: !_loading,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+ ()-]'),
                                  ),
                                ],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                                decoration: _fieldDecoration('Mob no.'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Email
                        TextField(
                          controller: _emailController,
                          enabled: !_loading,
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
                          enabled: !_loading,
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
                          enabled: !_loading,
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
                      context.tr(_error!),
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
                          : Text(
                              context.tr('OK'),
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
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.pop(context);
                              },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          context.tr('Back to login page'),
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

class _PhoneSetupUnavailable implements Exception {
  const _PhoneSetupUnavailable();
}
