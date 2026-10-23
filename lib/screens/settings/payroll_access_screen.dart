import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../local/local_database_provider.dart';
import '../../services/local_job_access_history.dart';
import '../../services/payroll_personal_history.dart';
import '../../services/payroll_posting_gateway.dart';
import 'employees_settings_screen.dart';

/// Membership-scoped own-pay view and separately authorized office entry point.
class PayrollAccessScreen extends StatefulWidget {
  const PayrollAccessScreen({
    super.key,
    required this.businessId,
    this.gateway,
    this.history,
    this.currentUserId,
    this.userChanges,
  });
  final String businessId;
  final PayrollRoleGateway? gateway;
  final PayrollPersonalHistory? history;
  final String? Function()? currentUserId;
  final Stream<String?>? userChanges;
  @override
  State<PayrollAccessScreen> createState() => _PayrollAccessScreenState();
}

class _PayrollAccessScreenState extends State<PayrollAccessScreen> {
  late final String? _actor;
  late final PayrollRoleGateway _gateway;
  late final PayrollPersonalHistory _history;
  StreamSubscription<String?>? _subscription;
  bool _revoked = false, _busy = true, _manage = false;
  String? _message;
  List<Map<String, dynamic>> _rows = [];
  String? get _current => widget.currentUserId != null
      ? widget.currentUserId!()
      : LocalJobAccessHistory.currentUserId;
  bool get _allowed => !_revoked && _actor != null && _current == _actor;
  @override
  void initState() {
    super.initState();
    _actor = _current;
    _history =
        widget.history ??
        PayrollPersonalHistory(
          database: localDatabase,
          businessId: widget.businessId,
          actorId: _actor ?? '',
          isCurrent: () => _allowed,
        );
    _gateway =
        widget.gateway ??
        PayrollPostingGatewayV1(
          businessId: widget.businessId,
          isContextCurrent: () => _allowed,
          readProofBytes: (_) async => Uint8List(0),
        );
    Stream<String?> changes;
    try {
      changes =
          widget.userChanges ??
          Supabase.instance.client.auth.onAuthStateChange.map(
            (e) => e.session?.user.id,
          );
    } catch (_) {
      changes = const Stream.empty();
    }
    _subscription = changes.listen((id) {
      if (id != _actor) _invalidate();
    });
    _load();
  }

  void _invalidate() {
    _revoked = true;
    if (mounted) {
      setState(() {
        _rows = [];
        _manage = false;
        _busy = false;
        _message = 'Sign-in changed. Reopen payroll.';
      });
    }
  }

  @override
  void didUpdateWidget(covariant PayrollAccessScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) _invalidate();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final cached = await _history.read();
      if (!mounted || !_allowed) return;
      setState(() {
        _rows = cached;
        _busy = false;
        _manage = false;
      });
      final access = await _gateway.fetchAccess(widget.businessId);
      if (!mounted || !_allowed) return;
      if (access['enabled'] != true) {
        setState(
          () => _message =
              'Payroll sync is awaiting approval. Cached personal records remain available.',
        );
        return;
      }
      if (access['business_id'] != widget.businessId ||
          access['actor_id'] != _actor) {
        throw StateError('Payroll access mismatch');
      }
      await _history.refresh(_gateway);
      final rows = await _history.read();
      if (!mounted || !_allowed) return;
      setState(() {
        _rows = rows;
        _manage = access['can_manage'] == true;
        _message = null;
      });
    } catch (_) {
      if (mounted && _allowed) {
        setState(() {
          _busy = false;
          _manage = false;
          _message = 'Offline or unavailable. Showing cached personal records.';
        });
      }
    }
  }

  Future<void> _openManagement() async {
    if (!_allowed || !_manage) return;
    // Re-authorize the office grant at the action, never trust role text or cache.
    try {
      final access = await _gateway.fetchAccess(widget.businessId);
      if (!mounted || !_allowed) return;
      if (access['enabled'] != true ||
          access['can_manage'] != true ||
          access['actor_id'] != _actor ||
          access['business_id'] != widget.businessId) {
        setState(() => _manage = false);
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EmployeesSettingsScreen(
            businessId: widget.businessId,
            isOwner: false,
            canManagePayroll: true,
          ),
        ),
      );
      if (mounted && _allowed) await _load();
    } catch (_) {
      if (mounted) setState(() => _manage = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My payroll')),
    body: !_allowed
        ? const Center(child: Text('Sign-in required.'))
        : _busy
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_message != null) Text(_message!),
                if (_manage)
                  OutlinedButton.icon(
                    onPressed: _openManagement,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Manage payroll'),
                  ),
                const Text(
                  'Your pay records only. Pending payments are not paid.',
                ),
                if (_rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No personal payroll records cached.'),
                  ),
                for (final r in _rows)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${r['currency_code'] ?? 'Amount'} ${((r['amount_cents'] as int) / 100).toStringAsFixed(2)}',
                      ),
                      subtitle: Text(
                        '${r['status'] == 'posted'
                            ? 'Posted'
                            : r['status'] == 'void'
                            ? 'Void'
                            : 'Pending — NOT PAID'} • ${r['payment_date']}\nMethod: ${r['method_label'] ?? 'Not recorded'}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
}
