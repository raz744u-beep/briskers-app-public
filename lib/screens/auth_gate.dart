import 'dart:async';

import 'package:flutter/material.dart';

import '../core/supabase_config.dart';
import 'business_gate.dart';
import 'login_screen.dart';

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
    return supabase.auth.currentSession == null
        ? const LoginScreen()
        : const BusinessGate();
  }
}
