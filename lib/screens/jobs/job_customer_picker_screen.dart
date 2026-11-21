import 'dart:async';

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
  bool _searching = false;
  int _searchEpoch = 0;
  Timer? _debounce;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Query just the first local page instead of decoding the whole directory
  // before showing New Job. Searching pages the saved DB by any typed value.
  Future<void> _load({String query = ''}) async {
    final epoch = ++_searchEpoch;
    try {
      final rows = await _customers.customers(
        widget.businessId,
        search: query.isEmpty ? null : query,
        limit: 100,
      );
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _searching = false;
      });
    }
  }

  void _onSearchChanged() {
    ++_searchEpoch; // A late result can never replace the latest query.
    _debounce?.cancel();
    if (mounted) setState(() => _searching = true);
    final query = _search.text.trim();
    if (query.isEmpty) {
      unawaited(_load());
    } else {
      _debounce = Timer(const Duration(milliseconds: 220),
        () => unawaited(_load(query: query)));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _rows; // Already scoped and searched in SQLite.

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
              trailing: _search.text.isEmpty ? null : [
                IconButton(
                  tooltip: 'Clear customer search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _search.clear();
                    _onSearchChanged();
                  },
                ),
              ],
              onChanged: (_) => _onSearchChanged(),
            ),
          ),
          if (_searching && !_loading)
            const LinearProgressIndicator(minHeight: 2),
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
                                onTap: _searching ? null : () => Navigator.pop(context, customer),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
