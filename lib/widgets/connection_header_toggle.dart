import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../core/connection_mode.dart';
import '../local/local_database_provider.dart';

/// Compact shell-header control. Displays the selected preference separately
/// from the most recent successful local data pull (not an invented sync state).
class ConnectionHeaderToggle extends StatefulWidget {
  const ConnectionHeaderToggle({super.key, required this.businessId});
  final String businessId;

  @override
  State<ConnectionHeaderToggle> createState() => _ConnectionHeaderToggleState();
}

class _ConnectionHeaderToggleState extends State<ConnectionHeaderToggle> {
  final _controller = BriskersConnectionModeController.instance;
  DateTime? _lastPull;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_modeChanged);
    _refreshTimestamp();
  }

  void _modeChanged() {
    if (mounted) setState(() {});
    _refreshTimestamp();
  }

  Future<void> _refreshTimestamp() async {
    try {
      final rows = await localDatabase.customSelect(
        'SELECT MAX(last_pull_at) AS latest FROM local_sync_states '
        'WHERE business_id = ? AND last_error IS NULL AND bootstrapped = 1',
        variables: [Variable<String>(widget.businessId)],
      ).get();
      final latest = rows.isEmpty ? null : rows.first.data['latest'];
      DateTime? parsed;
      if (latest is DateTime) {
        parsed = latest;
      } else if (latest is int) {
        parsed = DateTime.fromMillisecondsSinceEpoch(latest * 1000, isUtc: true);
      } else if (latest != null) {
        parsed = DateTime.tryParse(latest.toString());
      }
      if (mounted) setState(() => _lastPull = parsed);
    } catch (_) {
      if (mounted) setState(() => _lastPull = null);
    }
  }

  String get _lastLabel {
    final value = _lastPull;
    if (value == null) return 'Not yet synced';
    final elapsed = DateTime.now().difference(value);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Last sync: just now';
    if (elapsed.inMinutes < 60) return 'Last sync: ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Last sync: ${elapsed.inHours}h ago';
    return 'Last sync: ${value.toLocal().month}/${value.toLocal().day}';
  }

  @override
  void dispose() {
    _controller.removeListener(_modeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _controller.mode;
    final icon = mode == BriskersConnectionMode.offline
        ? Icons.wifi_off_rounded
        : mode == BriskersConnectionMode.online
            ? Icons.cloud_outlined : Icons.wifi_rounded;
    final color = mode == BriskersConnectionMode.offline
        ? const Color(0xFFC62828)
        : mode == BriskersConnectionMode.online
            ? const Color(0xFF1767AD) : const Color(0xFF008B80);
    final label = switch (mode) {
      BriskersConnectionMode.auto => 'Auto',
      BriskersConnectionMode.offline => 'Offline',
      BriskersConnectionMode.online => 'Online',
    };

    return SizedBox(
      width: 114,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PopupMenuButton<BriskersConnectionMode>(
            tooltip: 'Connection mode',
            onOpened: _refreshTimestamp,
            onSelected: (next) async {
              await _controller.setMode(next);
              await _refreshTimestamp();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: BriskersConnectionMode.auto,
                child: Text('Auto'),
              ),
              PopupMenuItem(
                value: BriskersConnectionMode.offline,
                child: Text('Force Offline'),
              ),
              PopupMenuItem(
                value: BriskersConnectionMode.online,
                child: Text('Force Online'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color),
                color: color.withValues(alpha: 0.06),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 17),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
                  const Icon(Icons.keyboard_arrow_down, size: 15),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_lastLabel,
              maxLines: 1,
              style: const TextStyle(fontSize: 10, color: Color(0xFF687481))),
          ),
        ],
      ),
    );
  }
}
