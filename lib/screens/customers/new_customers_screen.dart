import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';
import '../../core/formatters.dart';
import '../../services/customer_notification_service.dart';
import '../../services/local_customer_repository.dart';
import 'customer_detail_screen.dart';

/// A snapshot of the badge tap. Later arrivals are deliberately not consumed
/// with this review, and normal Customers search is never inherited or changed.
class NewCustomersScreen extends StatefulWidget {
  const NewCustomersScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    required this.customerIds,
    required this.notifications,
    required this.onViewAll,
    this.repository,
    this.profileBuilder,
  });

  final String businessId;
  final String roleCode;
  final List<String> customerIds;
  final CustomerNotificationService notifications;
  final VoidCallback onViewAll;
  final LocalCustomerRepository? repository;
  final Widget Function(String customerId, VoidCallback onReviewed)?
  profileBuilder;

  @override
  State<NewCustomersScreen> createState() => _NewCustomersScreenState();
}

class _NewCustomersScreenState extends State<NewCustomersScreen> {
  List<Map<String, dynamic>>? _rows;
  final Set<String> _reviewed = {};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await (widget.repository ?? LocalCustomerRepository())
          .customersByIds(widget.businessId, widget.customerIds);
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = tr('newCustomersLoadError'));
    }
  }

  Future<void> _markReviewed(Iterable<String> ids) async {
    final reviewed = ids.toSet();
    if (mounted) setState(() => _saving = true);
    try {
      await widget.notifications.markReviewed(reviewed);
      if (mounted) {
        setState(() {
          _reviewed.addAll(reviewed);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = tr('newCustomersReviewError'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(Map<String, dynamic> customer) async {
    final id = customer['id'].toString();
    void reviewed() => unawaited(_markReviewed([id]));
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.profileBuilder?.call(id, reviewed) ??
            CustomerDetailScreen(
              businessId: widget.businessId,
              customerId: id,
              roleCode: widget.roleCode,
              onReviewed: reviewed,
            ),
      ),
    );
    // A profile failure or immediate Back leaves the event unread.
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tr('newCustomers'),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: widget.onViewAll,
              child: Text(tr('viewAllCustomers')),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(tr('newCustomersReviewHint')),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_rows != null && _rows!.isNotEmpty)
        TextButton.icon(
          onPressed: _saving
              ? null
              : () => _markReviewed(_rows!.map((row) => row['id'].toString())),
          icon: const Icon(Icons.done_all),
          label: Text(tr('markCustomersReviewed')),
        ),
      Expanded(
        child: _rows == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : TextButton(onPressed: _load, child: Text(tr('retry'))),
              )
            : _rows!.isEmpty
            ? Center(child: Text(tr('noNewCustomersAvailable')))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _rows!.length,
                  itemBuilder: (context, index) {
                    final row = _rows![index];
                    final phone = row['phone']?.toString() ?? '';
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        row['display_name']?.toString() ?? tr('customer'),
                      ),
                      subtitle: phone.isEmpty
                          ? null
                          : Text(formatUsPhone(phone)),
                      trailing: _reviewed.contains(row['id'])
                          ? Icon(
                              Icons.check_circle_outline,
                              semanticLabel: tr('reviewed'),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => _open(row),
                    );
                  },
                ),
              ),
      ),
    ],
  );
}
