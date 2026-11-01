import 'package:flutter/material.dart';
import '../services/local_owner_security.dart';
import '../core/connection_mode.dart';
import 'business_gate.dart';

class LocalOwnerUnlockScreen extends StatefulWidget {
  const LocalOwnerUnlockScreen({super.key});
  @override
  State<LocalOwnerUnlockScreen> createState() => _LocalOwnerUnlockScreenState();
}

class _LocalOwnerUnlockScreenState extends State<LocalOwnerUnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _password.dispose(); super.dispose(); }

  Future<void> _unlock({bool biometric = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final security = LocalOwnerSecurity.instance;
      final ok = biometric
          ? await security.unlockWithBiometrics()
          : await security.unlockWithPassword(_password.text);
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = biometric
            ? 'Biometric verification was unavailable or cancelled. Use your password.'
            : 'Incorrect Owner password.');
        return;
      }
      // Keep normal app operations local-only until sync is redesigned.
      await BriskersConnectionModeController.instance
          .setMode(BriskersConnectionMode.offline);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => BusinessGate(localOwnerIdentity: security.unlockedIdentity),
      ));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not unlock. Try your password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Briskers Owner')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 16),
          const Text('Unlock locally', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('No internet or Supabase login needed.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(controller: _password, obscureText: true,
            autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Owner password'),
            onSubmitted: (_) => _unlock()),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : () => _unlock(),
            child: const Text('Unlock with password')),
          FutureBuilder<bool>(
            future: LocalOwnerSecurity.instance.biometricsEnabled,
            builder: (context, snapshot) => snapshot.data == true
              ? TextButton.icon(onPressed: _busy ? null : () => _unlock(biometric: true),
                  icon: const Icon(Icons.fingerprint), label: const Text('Use face or fingerprint'))
              : const SizedBox.shrink()),
        ],
      )))),
  );
}

/// Migration uses a previously verified Owner session AND saved business
/// context. It cannot provision an Owner from a fresh, untrusted installation.
class LocalOwnerSetupScreen extends StatefulWidget {
  const LocalOwnerSetupScreen({super.key, required this.onCompleted,
    required this.onSkip});
  final VoidCallback onCompleted;
  final VoidCallback onSkip;
  @override
  State<LocalOwnerSetupScreen> createState() => _LocalOwnerSetupScreenState();
}

class _LocalOwnerSetupScreenState extends State<LocalOwnerSetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _enableBiometrics = false;
  String? _error;
  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_busy) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final security = LocalOwnerSecurity.instance;
      await security.enrollExistingOwner(_password.text);
      if (_enableBiometrics) await security.setBiometricsEnabled(true);
      await BriskersConnectionModeController.instance
          .setMode(BriskersConnectionMode.offline);
      if (mounted) widget.onCompleted();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set up local Owner access')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
        const Text('Use Briskers without Supabase login', style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('This securely transfers your already verified Owner identity '
          'to this phone. Future access uses your password or biometrics offline.'),
        const SizedBox(height: 20),
        TextField(controller: _password, obscureText: true, autocorrect: false,
          enableSuggestions: false, decoration: const InputDecoration(
            labelText: 'New Owner password (at least 10 characters)')),
        const SizedBox(height: 12),
        TextField(controller: _confirm, obscureText: true, autocorrect: false,
          enableSuggestions: false, decoration: const InputDecoration(
            labelText: 'Confirm Owner password')),
        const SizedBox(height: 12),
        CheckboxListTile(value: _enableBiometrics,
          title: const Text('Also allow face or fingerprint unlock'),
          subtitle: const Text('Uses biometrics enrolled on this device'),
          onChanged: _busy ? null : (value) =>
            setState(() => _enableBiometrics = value ?? false)),
        if (_error != null) Text(_error!, style: TextStyle(
          color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Enable local Owner access')),
        TextButton(onPressed: _busy ? null : widget.onSkip, child: const Text('Not now')),
      ]))),
  );
}
