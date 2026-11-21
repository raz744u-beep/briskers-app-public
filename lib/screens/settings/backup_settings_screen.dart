import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/backup/backup_archive.dart';
import '../../services/backup/local_backup_service.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  String? _folder;
  Map<String, dynamic>? _status;
  bool _automatic = false, _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _folder = prefs.getString(LocalBackupService.rootKey);
      final raw = prefs.getString(LocalBackupService.statusKey);
      _status = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      _automatic = prefs.getBool(LocalBackupService.automaticKey) ?? false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not finish: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    await LocalBackupService.authorize(widget.businessId);
    final folder = await LocalBackupService.chooseFolder();
    if (folder == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalBackupService.rootKey, folder);
    await prefs.setString('briskers_backup_business_v1', widget.businessId);
  }

  Future<void> _restore() async {
    final source = await LocalBackupService.inspect(widget.businessId);
    if (source == null) return;
    try {
      final manifest = await BackupArchive.verify(
        source,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'Restore test passed.\n\nBackup: ${manifest['created_at']}\n'
            'Tables: ${(manifest['table_counts'] as Map).length}\n'
            'Files: ${(manifest['files'] as Map).length}\n'
            '${manifest['complete'] == true ? '' : '\nThis backup has missing-file warnings.\n'}'
            '\nThis replaces the app records after you close and reopen Briskers. '
            'A safety copy of the current database is kept. Sync stays off. '
            'Your sign-in and device authorization are kept on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await LocalBackupService.requestRestore(widget.businessId, source);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Ready to restore'),
          content: const Text(
            'Close Briskers now, then reopen it to finish restoring. No records have been replaced yet.',
          ),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Close Briskers'),
            ),
          ],
        ),
      );
    } finally {
      // A queued restore needs its staged files on the next launch.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(LocalBackupService.restoreRequest) == null) {
        await source.parent.delete(recursive: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & Restore')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Keep a complete copy of the records and files stored on this device. Choose a folder in Internal storage for offline backups.',
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _status == null ? Icons.warning_amber : Icons.backup_outlined,
          ),
          title: Text(
            _status == null
                ? 'No verified backup yet'
                : _status!['complete'] == true
                ? 'Last successful backup'
                : 'Backup saved with warnings',
          ),
          subtitle: _status == null
              ? null
              : Text(
                  '${DateTime.parse(_status!['created_at'] as String).toLocal()}\n${_status!['files']} files verified',
                ),
        ),
        if (_status?['warnings'] is List)
          for (final warning in (_status!['warnings'] as List))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('$warning'),
            ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(_choose),
          icon: const Icon(Icons.folder_open),
          label: Text(
            _folder == null ? 'Choose backup folder' : 'Change backup folder',
          ),
        ),
        if (_folder != null)
          const Text(
            'Dated copies are saved inside Briskers_Backup / Backups. Point your folder-sync app at Briskers_Backup to keep a copy elsewhere.',
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _folder == null
              ? null
              : () => _run(() async {
                  await LocalBackupService.create(widget.businessId);
                }),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Create Backup'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatic daily backup'),
          subtitle: const Text(
            'Runs while Briskers is open. Keeps dated copies; older backups are never automatically deleted.',
          ),
          value: _automatic,
          onChanged: _busy || _folder == null
              ? null
              : (value) => _run(() async {
                  await LocalBackupService.authorize(widget.businessId);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(LocalBackupService.automaticKey, value);
                  await prefs.setString(
                    'briskers_backup_business_v1',
                    widget.businessId,
                  );
                }),
        ),
        const Divider(),
        const Text(
          'Copy the original Expense IQ photos into Briskers for offline access '
          'and future backups. Select Internal storage / ExpenseIQ / photos. '
          'Keep the original folder until you verify a restored backup.',
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(
            () => LocalBackupService.importExpenseIqOriginals(widget.businessId),
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Import Expense IQ Photos'),
        ),
        const Divider(),
        const Text(
          'To restore, select a dated backup folder containing backup-info.json. Briskers checks its files and tests a separate restored copy first.',
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(_restore),
          icon: const Icon(Icons.restore),
          label: const Text('Check & Restore Backup'),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<String>(
          valueListenable: LocalBackupService.progress,
          builder: (_, value, _) => Text(value),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Text(_message!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        const Text(
          'A copy on this phone alone cannot protect against losing the phone. Verify that your chosen storage or folder-sync app has copied the dated backup elsewhere. Backups contain private shop records; keep the destination private.',
        ),
      ],
    ),
  );
}
