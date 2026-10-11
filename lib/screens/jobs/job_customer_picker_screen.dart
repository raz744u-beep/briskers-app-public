import 'package:flutter/material.dart';

import '../../services/local_customer_repository.dart';

/// Uses its own route and controller so the keyboard cannot collapse a dialog
/// or leave the Jobs list under a partially dismissed overlay.
class JobCustomerPickerScreen extends StatefulWidget {
  const JobCustomerPickerScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<JobCustomerPickerScreen> createState() => _JobCustomerPickerScreenState();
}

class _JobCustomerPickerScreenState extends State<JobCustomerPickerScreen> {
  final _search = TextEditingController();
  final _customers = LocalCustomerRepository();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _customers.customers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final matches = _rows.where((row) {
      final name = (row['display_name'] ?? row['name'] ?? '').toString().toLowerCase();
      final phone = (row['phone'] ?? row['list_phone'] ?? '').toString().toLowerCase();
      final email = (row['email'] ?? row['list_email'] ?? '').toString().toLowerCase();
      return name.contains(term) || phone.contains(term) || email.contains(term);
    }).take(100).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New Job — Customer')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Search name, phone, or email',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Could not load saved customers: $_error'))
                    : matches.isEmpty
                        ? const Center(child: Text('No matching customers'))
                        : ListView.builder(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final customer = matches[index];
                              return ListTile(
                                title: Text(customer['display_name']?.toString() ??
                                    customer['name']?.toString() ?? 'Customer'),
                                subtitle: Text(customer['list_phone']?.toString() ??
                                    customer['phone']?.toString() ?? ''),
                                onTap: () => Navigator.pop(context, customer),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
