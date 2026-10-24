import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/briskers_i18n.dart';
import '../../core/connection_mode.dart';
import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_vehicle_sync_service.dart';
import '../../services/local_customer_repository.dart';
import 'customer_detail_screen.dart';
import 'new_customer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
    this.onCustomerReviewed,
    this.detailBottomNavigationBar,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final ValueChanged<String>? onCustomerReviewed;
  final Widget? detailBottomNavigationBar;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static const _api = BriskersApi();
  final CustomerVehicleSyncService _sync =
      CustomerVehicleSyncService();
  final LocalCustomerRepository _localCustomers =
      LocalCustomerRepository();
  final _search = TextEditingController();
  Timer? _searchDebounce;
  int _searchRequest = 0;
  int _loadRequest = 0;
  List<Map<String, dynamic>>? _rows;
  int _totalCustomers = 0;
  String? _error;
  bool _onlineReady = false;
  bool _showingLocal = false;
  bool _refreshFailed = false;
  bool get _canManageCustomers => const {'owner', 'manager', 'office'}.contains(widget.roleCode);

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
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshOnline = true}) async {
    final request = ++_loadRequest;
    final query = _search.text.trim();
    var localAvailable = false;
    bool current() => mounted && request == _loadRequest &&
        query == _search.text.trim();
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
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

      if (current() && localAvailable) {
        setState(() {
          _rows = rows;
          _totalCustomers = total;
          _showingLocal = !_onlineReady;
          // A cache-first paint is expected in Auto, not a network error.
          _error = null;
        });
      }
    } catch (_) {
      // The online refresh below can still populate the local cache.
      }
    }

    if (!refreshOnline) return;

    if (BriskersConnectionModeController.instance.forceOffline) {
      if (!current()) return;
      setState(() {
        _rows ??= const <Map<String, dynamic>>[];
        _onlineReady = false;
        _showingLocal = true;
        _refreshFailed = false;
        _error = null;
      });
      return;
    }

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

      if (!current()) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          results[0] as List,
        );
        _totalCustomers = results[1] as int;
        _onlineReady = bootstrapped;
        _showingLocal = !bootstrapped;
        _refreshFailed = !bootstrapped;
        _error = null;
      });
    } catch (error) {
      if (!current()) return;
      // An unrelated interrupted bootstrap may have populated another
      // screen's cache since this request began. Keep any already displayed
      // customers instead of replacing them with a blank/error screen.
      final savedVisible = _rows != null && _rows!.isNotEmpty;
      setState(() {
        _onlineReady = false;
        _refreshFailed = true;
        _showingLocal = !forceOnline && (localAvailable || savedVisible);
        _rows ??= const <Map<String, dynamic>>[];
        _error = _friendlySyncError(error);
      });
    }
  }

  static String _friendlySyncError(Object error) {
    final description = error.toString().toLowerCase();
    if (description.contains('failed host lookup') ||
        description.contains('socketexception') ||
        description.contains('network is unreachable')) {
      return 'Cannot reach the Briskers server (network/DNS issue). '
          'Previously saved customers remain on this device. '
          'Check Wi-Fi or mobile data and refresh when connected.';
    }
    if (description.contains('timeout')) {
      return 'Customer download timed out. Saved customers are unchanged; '
          'retry after the connection stabilizes.';
    }
    return 'Customer download did not finish. Any locally saved customers '
        'remain available; try refreshing when the connection is stable.';
  }

  void _onSearchChanged(String _) {
    // A late network result must never replace a newer typed search.
    ++_loadRequest;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      _runSearch,
    );
  }

  Future<void> _runSearch() async {
    final request = ++_searchRequest;
    final query = _search.text.trim();
    final forceOnline =
        BriskersConnectionModeController.instance.forceOnline;

    try {
      final rows = forceOnline
          ? await _api.customers(
              widget.businessId,
              search: query.isEmpty ? null : query,
            )
          : await _localCustomers.customers(
              widget.businessId,
              search: query.isEmpty ? null : query,
            );

      if (!mounted || request != _searchRequest) return;
      setState(() {
        _rows = rows;
        _showingLocal = !forceOnline && !_onlineReady;
        _error = null;
      });
      // A failed multi-page bootstrap can leave only a subset available
      // offline. A typed search may query authorized server customers while
      // the full local directory is still rebuilding. Never treat a limited
      // online search page as the complete customer total.
      if (query.isNotEmpty && !forceOnline && !_onlineReady &&
          !BriskersConnectionModeController.instance.forceOffline) {
        try {
          final authorized = await _api.customers(
            widget.businessId, search: query, limit: 100);
          if (!mounted || request != _searchRequest ||
              _search.text.trim() != query) {
            return;
          }
          setState(() {
            _rows = authorized;
            _showingLocal = false;
            _error = null;
          });
        } catch (_) {
          // The local search results above stay usable if the remote read
          // times out or access is revoked. No guessed results are added.
        }
      }
    } catch (error) {
      if (!mounted || request != _searchRequest) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _add() async {
    if (!_canManageCustomers) return;
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
          roleCode: widget.roleCode,
          sharedBottomNavigationBar: widget.detailBottomNavigationBar,
          onReviewed: () => widget.onCustomerReviewed?.call(customer['id'].toString()),
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('customers'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (_showingLocal &&
                  (BriskersConnectionModeController.instance.forceOffline ||
                      _refreshFailed))
                Tooltip(
                  message: _refreshFailed
                      ? 'Customer refresh needs attention; saved customers shown'
                      : 'Offline: showing saved customers',
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.cloud_off_outlined,
                      size: 18, color: Color(0xFF667085)),
                  ),
                ),
              Text(
                '${tr('total')} $_totalCustomers',
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
                  hintText: tr('searchCustomers'),
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_search.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear customer search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          ++_loadRequest;
                          ++_searchRequest; // invalidate any stale search
                          _search.clear();
                          setState(() {});
                          _runSearch();
                        },
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {});
                    _onSearchChanged(value);
                  },
                  onSubmitted: (_) {
                    _searchDebounce?.cancel();
                    _runSearch();
                  },
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
                    padding: const EdgeInsets.only(bottom: 96),
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
                        leading: CircleAvatar(
                          backgroundColor:
                              BriskersColors.actionBlue.withValues(alpha: 0.14),
                          child: const Icon(
                            Icons.person,
                            color: BriskersColors.actionBlue,
                          ),
                        ),
                        title: Text(
                          '${customer['display_name'] ?? ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
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
                            Text(
                              '${customer['vehicle_count'] ?? 0} ${tr('cars')}',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _openCustomer(customer),
                      );
                    },
                  ),
                ),
        ),
      ],
        ),
        if (_canManageCustomers && MediaQuery.viewInsetsOf(context).bottom == 0)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'customers_screen-quick-create',
              onPressed: _add,
              backgroundColor: BriskersColors.actionBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}
