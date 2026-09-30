import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/local_customer_repository.dart';
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
  final CustomerVehicleSyncService _sync =
      CustomerVehicleSyncService();
  final LocalCustomerRepository _localCustomers =
      LocalCustomerRepository();
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  int _totalCustomers = 0;
  String? _error;
  bool _onlineReady = false;
  bool _showingLocal = false;

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

  Future<void> _load({bool refreshOnline = true}) async {
    final query = _search.text.trim();
    var localAvailable = false;

    try {
      final results = await Future.wait<dynamic>([
        _localCustomers.customers(
          widget.businessId,
          search: query.isEmpty ? null : query,
        ),
        _localCustomers.customerTotal(widget.businessId),
        _localCustomers.hasBootstrap(widget.businessId),
      ]);

      final rows =
          List<Map<String, dynamic>>.from(results[0] as List);
      final total = results[1] as int;
      final bootstrapped = results[2] == true;
      localAvailable = bootstrapped || rows.isNotEmpty;

      if (mounted && localAvailable) {
        setState(() {
          _rows = rows;
          _totalCustomers = total;
          _showingLocal = !_onlineReady;
          _error = null;
        });
      }
    } catch (_) {
      // The online refresh below can still populate the local cache.
    }

    if (!refreshOnline) return;

    try {
      await _sync.pull(widget.businessId);
      final bootstrapped =
          await _localCustomers.hasBootstrap(widget.businessId);
      final results = await Future.wait<dynamic>([
        _localCustomers.customers(
          widget.businessId,
          search: query.isEmpty ? null : query,
        ),
        _localCustomers.customerTotal(widget.businessId),
      ]);

      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          results[0] as List,
        );
        _totalCustomers = results[1] as int;
        _onlineReady = bootstrapped;
        _showingLocal = !bootstrapped;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineReady = false;
        if (localAvailable) {
          _showingLocal = true;
          _error = null;
        } else {
          _rows ??= const [];
          _error = error.toString();
        }
      });
    }
  }

  Future<void> _add() async {
    if (!_onlineReady) return;
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
                  onSubmitted: (_) =>
                      _load(refreshOnline: false),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _onlineReady ? _add : null,
                tooltip: 'Add customer',
                icon: const Icon(Icons.person_add),
              ),
            ],
          ),
        ),
        if (_showingLocal)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 18),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Showing saved customers • editing requires a connection',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
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
