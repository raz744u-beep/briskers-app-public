import 'dart:async';

import 'package:flutter/material.dart';

import '../core/supabase_config.dart';
import 'business_gate.dart';
import 'login_screen.dart';
import 'local_owner_unlock_screen.dart';
import '../services/local_owner_security.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: LocalOwnerSecurity.instance.isConfigured,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // Local identity wins, including after the old Supabase token expires.
        if (snapshot.data == true) return const LocalOwnerUnlockScreen();
        // One-time migration only: existing verified accounts can enroll
        // an Owner password using their locally saved business context.
        return supabase.auth.currentSession == null
            ? const LoginScreen()
            : const BusinessGate();
      },
    );
  }
}
