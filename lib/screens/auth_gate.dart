import 'package:flutter/material.dart';
import '../services/local_owner_security.dart';
import 'business_gate.dart';
import 'local_owner_unlock_screen.dart';

/// Startup no longer requires Supabase authentication.
/// New devices must be securely provisioned; never invent an Owner account.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: LocalOwnerSecurity.instance.isConfigured,
    builder: (context, configured) {
      if (!configured.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (configured.data == true) return const LocalOwnerUnlockScreen();
      return FutureBuilder<Map<String, dynamic>?>(
        future: LocalOwnerSecurity.instance.cachedOwnerProfile(),
        builder: (context, profile) {
          if (profile.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (profile.data != null) {
            return LocalOwnerSetupScreen(
              onCompleted: () {
                if (!mounted) return;
                Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                  builder: (_) => BusinessGate(
                    localOwnerIdentity: LocalOwnerSecurity.instance.unlockedIdentity),
                ));
              },
              onSkip: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Set up your Owner password to continue offline.')));
              },
            );
          }
          return const Scaffold(
            body: Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.phonelink_lock_outlined, size: 52),
                SizedBox(height: 18),
                Text('This device is not initialized for local Owner access.',
                    textAlign: TextAlign.center),
                SizedBox(height: 12),
                Text('No saved Owner profile was found. Your existing data '
                     'was not modified. Secure device provisioning is required.',
                     textAlign: TextAlign.center),
              ]),
            )),
          );
        },
      );
    },
  );
}
