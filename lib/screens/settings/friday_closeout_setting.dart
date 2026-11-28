import 'package:flutter/material.dart';

import '../../core/friday_closeout_schedule.dart';
import '../../services/friday_closeout_preferences.dart';

class FridayCloseoutSetting extends StatefulWidget {
  const FridayCloseoutSetting({super.key, required this.businessId});

  final String businessId;

  @override
  State<FridayCloseoutSetting> createState() => _FridayCloseoutSettingState();
}

class _FridayCloseoutSettingState extends State<FridayCloseoutSetting> {
  late final _preferences = FridayCloseoutPreferences(widget.businessId);
  late final _loading = _preferences.load();
  FridayCloseoutSchedule? _saved;
  bool _saving = false;

  Future<void> _save(FridayCloseoutSchedule schedule) async {
    setState(() => _saving = true);
    try {
      await _preferences.save(schedule);
      if (mounted) setState(() => _saved = schedule);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friday Closeout setting could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FridayCloseoutSchedule>(
    future: _loading,
    builder: (context, snapshot) {
      final schedule = _saved ?? snapshot.data;
      final start = schedule == null
          ? null
          : TimeOfDay(
              hour: schedule.startMinute ~/ 60,
              minute: schedule.startMinute % 60,
            );
      return Column(
        children: [
          SwitchListTile(
            title: const Text('Friday Closeout on Home'),
            subtitle: const Text(
              'Show the shop closeout in the Owner Dashboard on Fridays.',
            ),
            value: schedule?.enabled ?? false,
            onChanged: schedule == null || _saving
                ? null
                : (enabled) => _save(
                    FridayCloseoutSchedule(
                      enabled: enabled,
                      startMinute: schedule.startMinute,
                    ),
                  ),
          ),
          if (schedule?.enabled == true && start != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Show starting at'),
              subtitle: Text('${start.format(context)} · Gretna time'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving
                  ? null
                  : () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: start,
                      );
                      if (!mounted || selected == null) return;
                      await _save(
                        FridayCloseoutSchedule(
                          enabled: true,
                          startMinute: selected.hour * 60 + selected.minute,
                        ),
                      );
                    },
            ),
        ],
      );
    },
  );
}
