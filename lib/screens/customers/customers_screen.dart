import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../services/briskers_api.dart';
import 'customer_detail_screen.dart';
import 'new_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const _api = BriskersApi();
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final query = _search.text.trim();
      final rows = await _api.customers(
        widget.businessId,
        search: query.isEmpty ? null : query,
      );
      if (mounted) {
        setState(() {
          _rows = rows;
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
          padding: const EdgeInsets.all(12),
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
                        trailing: Text(
                          '${customer['vehicle_count'] ?? 0} cars',
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
