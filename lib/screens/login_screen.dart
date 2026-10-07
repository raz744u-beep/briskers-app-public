import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _brandBlue = Color(0xFF0D6FD3);
  static const _brandBlueBright = Color(0xFF258EF0);
  static const _ink = Color(0xFF15263D);
  static const _muted = Color(0xFF718199);
  static const _fieldBorder = Color(0xFFD8E2EE);
  static const _rememberEmailKey = 'briskers_remember_email';
  static const _rememberEnabledKey = 'briskers_remember_enabled';

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _signUp = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberEnabledKey) ?? true;
    final saved = remember ? prefs.getString(_rememberEmailKey) : null;
    if (!mounted) return;
    setState(() {
      _rememberMe = remember;
      if (saved != null && saved.isNotEmpty) _email.text = saved;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _persistRememberedLogin(String login) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberEnabledKey, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(_rememberEmailKey, login);
    } else {
      await prefs.remove(_rememberEmailKey);
    }
  }

  Future<void> _submit() async {
    final login = _email.text.trim();
    if (login.isEmpty || _password.text.length < 6) {
      setState(
        () => _error =
            'Enter your email or phone and a password of at least 6 characters.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final isEmail = login.contains('@');
      if (_signUp) {
        if (isEmail) {
          await supabase.auth.signUp(email: login, password: _password.text);
        } else {
          await supabase.auth.signUp(phone: login, password: _password.text);
        }
      } else {
        if (isEmail) {
          await supabase.auth.signInWithPassword(
            email: login,
            password: _password.text,
          );
        } else {
          await supabase.auth.signInWithPassword(
            phone: login,
            password: _password.text,
          );
        }
        await _persistRememberedLogin(login);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _signUp
              ? 'Unable to create account: $error'
              : 'Unable to sign in: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to send reset email: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleAccountMode() {
    if (_busy) return;
    setState(() {
      _signUp = !_signUp;
      _error = null;
    });
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(
        color: _muted,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: _muted, size: 23),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFFDFEFF),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _fieldBorder, width: 1.3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brandBlue, width: 1.7),
      ),
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_brandBlueBright, _brandBlue],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: _brandBlue.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _signUp ? 'Create Account' : 'Log In',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!_signUp) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward, size: 23),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _brandBlue,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 760;
              final logoWidth = compact ? 250.0 : 275.0;
              final carHeight = compact ? 105.0 : 135.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      26,
                      compact ? 9 : 16,
                      26,
                      0,
                    ),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/briskers_header_logo.png',
                              width: logoWidth,
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 16),
                          Text(
                            _signUp ? 'Create Account' : 'Welcome Back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ink,
                              fontSize: compact ? 28 : 30,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _signUp
                                ? 'Create your Briskers shop account'
                                : 'Sign in to manage your shop',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _muted,
                              fontSize: compact ? 17 : 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: compact ? 15 : 22),
                          SizedBox(
                            height: 57,
                            child: TextField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _fieldDecoration(
                                hint: 'Email or phone',
                                icon: Icons.mail_outline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 57,
                            child: TextField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _busy ? null : _submit(),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: _fieldDecoration(
                                hint: 'Password',
                                icon: Icons.lock_outline,
                                suffix: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          );
                                        },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: _muted,
                                    size: 23,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!_signUp) ...[
                            const SizedBox(height: 7),
                            SizedBox(
                              height: 39,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: _brandBlue,
                                      checkColor: Colors.white,
                                      side: const BorderSide(
                                        color: _brandBlue,
                                        width: 1.4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      onChanged: _busy
                                          ? null
                                          : (value) {
                                              setState(
                                                () => _rememberMe =
                                                    value ?? false,
                                              );
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Remember me',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed:
                                        _busy ? null : _forgotPassword,
                                    style: TextButton.styleFrom(
                                      foregroundColor: _brandBlue,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                    ),
                                    child: const Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 8 : 12),
                          _primaryButton(),
                          SizedBox(height: compact ? 11 : 16),
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: _fieldBorder,
                                  thickness: 1.1,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: _fieldBorder,
                                  thickness: 1.1,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          SizedBox(
                            height: 51,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _toggleAccountMode,
                              icon: Icon(
                                _signUp
                                    ? Icons.login_outlined
                                    : Icons.person_add_alt_1_outlined,
                                size: 22,
                              ),
                              label: Text(
                                _signUp ? 'Back to Log In' : 'Create Account',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _brandBlue,
                                side: const BorderSide(
                                  color: _brandBlue,
                                  width: 1.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: compact ? 11 : 13,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F8FC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.directions_car_outlined,
                                  color: _muted,
                                  size: 31,
                                ),
                                SizedBox(width: 13),
                                SizedBox(
                                  height: 44,
                                  child: VerticalDivider(
                                    color: _fieldBorder,
                                    width: 1,
                                    thickness: 1.1,
                                  ),
                                ),
                                SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Professional. Reliable. Foreign Car Experts.',
                                        style: TextStyle(
                                          color: _ink,
                                          fontSize: 13,
                                          height: 1.2,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Keeping you and your customers on the road.',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 12.5,
                                          height: 1.2,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? 2 : 6),
                          IgnorePointer(
                            child: Opacity(
                              opacity: 0.30,
                              child: SizedBox(
                                height: carHeight,
                                child: Image.asset(
                                  'assets/home_car.png',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
