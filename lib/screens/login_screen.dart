import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _signUp = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.length < 6) {
      setState(() => _error = 'Enter a valid email and a password of at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await supabase.auth.signUp(email: email, password: _password.text);
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to sign in: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 48),
                const Icon(Icons.car_repair, size: 72),
                Text(
                  'Briskers',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Text('Auto Repair', textAlign: TextAlign.center),
                const SizedBox(height: 40),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_signUp ? 'Create development account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                  child: Text(
                    _signUp
                        ? 'I already have a development account'
                        : 'First test? Create an account',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Development build. Creating an account does not grant Briskers access until the Owner membership is linked.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
