import 'package:flutter/material.dart';

import '../core/supabase_config.dart';
import '../services/briskers_api.dart';
import 'shell_screen.dart';

class BusinessGate extends StatefulWidget {
  const BusinessGate({super.key});

  @override
  State<BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends State<BusinessGate> {
  static const _api = BriskersApi();
  List<Map<String, dynamic>>? _businesses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final businesses = await _api.myBusinesses();
      if (mounted) {
        setState(() {
          _businesses = businesses;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _businesses = const [];
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_businesses == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_businesses!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Briskers Setup')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, size: 56),
              const SizedBox(height: 16),
              Text('Account ready', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'This login is not linked to the Briskers development business yet. Return to ChatGPT and the account can be attached as Owner.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => supabase.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      );
    }

    final business = _businesses!.first;
    return ShellScreen(
      businessId: '${business['business_id'] ?? business['id']}',
      businessName: '${business['business_name'] ?? business['name'] ?? 'Briskers'}',
      roleCode: '${business['role_code'] ?? business['role'] ?? ''}',
    );
  }
}
