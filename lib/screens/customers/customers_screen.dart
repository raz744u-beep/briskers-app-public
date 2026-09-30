import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../services/briskers_api.dart';
import 'customer_detail_screen.dart';
import 'new_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.businessId,
    this.refreshToken = 0,
  });

  final String businessId;
  final int refreshToken;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const _api = BriskersApi();
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  int _totalCustomers = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final query = _search.text.trim();
      final results = await Future.wait<dynamic>([
        _api.customers(
          widget.businessId,
          search: query.isEmpty ? null : query,
        ),
        _api.customerTotal(widget.businessId),
      ]);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(results[0] as List);
          _totalCustomers = results[1] as int;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _add() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewCustomerScreen(businessId: widget.businessId),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          businessId: widget.businessId,
          customerId: '${customer['id']}',
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Customers',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                'Total $_totalCustomers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search customers',
                  leading: const Icon(Icons.search),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _add,
                tooltip: 'Add customer',
                icon: const Icon(Icons.person_add),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _rows == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _rows!.length,
                    itemBuilder: (context, index) {
                      final customer = _rows![index];
                      final rawPhone = '${customer['phone'] ?? ''}';
                      final email = '${customer['email'] ?? ''}';
                      final contact = <String>[
                        if (rawPhone.isNotEmpty) formatUsPhone(rawPhone),
                        if (email.isNotEmpty) email,
                      ].join(' • ');

                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          '${customer['display_name'] ?? ''}',
                        ),
                        subtitle: contact.isEmpty ? null : Text(contact),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (customer['problem_flag'] == true) ...[
                              const Icon(
                                Icons.flag,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text('${customer['vehicle_count'] ?? 0} cars'),
                          ],
                        ),
                        onTap: () => _openCustomer(customer),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
