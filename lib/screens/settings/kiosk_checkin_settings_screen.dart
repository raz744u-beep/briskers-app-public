import 'package:flutter/material.dart';

import '../../services/briskers_api.dart';

class KioskCheckInSettingsScreen extends StatefulWidget {
  const KioskCheckInSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<KioskCheckInSettingsScreen> createState() =>
      _KioskCheckInSettingsScreenState();
}

class _KioskCheckInSettingsScreenState
    extends State<KioskCheckInSettingsScreen> {
  static const _api = BriskersApi();

  final TextEditingController _disclaimer = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  int? _version;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disclaimer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _api.kioskSettings(widget.businessId);
      final raw = settings['disclaimer'];
      if (!mounted) return;

      setState(() {
        if (raw is Map) {
          final disclaimer = Map<String, dynamic>.from(raw);
          _disclaimer.text =
              disclaimer['text']?.toString() ?? '';
          _version = int.tryParse(
            disclaimer['version']?.toString() ?? '',
          );
        } else {
          _disclaimer.clear();
          _version = null;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final text = _disclaimer.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Disclaimer text is required.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await _api.saveKioskDisclaimer(
        widget.businessId,
        text,
      );
      final raw = result['disclaimer'];
      if (!mounted) return;

      setState(() {
        if (raw is Map) {
          final disclaimer = Map<String, dynamic>.from(raw);
          _disclaimer.text =
              disclaimer['text']?.toString() ?? text;
          _version = int.tryParse(
            disclaimer['version']?.toString() ?? '',
          );
        }
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _version == null
                ? 'Kiosk disclaimer saved.'
                : 'Kiosk disclaimer v$_version saved.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk Check-In'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.fact_check_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Customer check-in disclaimer',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            if (_version != null)
                              Chip(
                                label: Text('Version $_version'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Every save creates a new version. Existing kiosk registrations keep the exact disclaimer version and wording the customer accepted.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _disclaimer,
                          minLines: 9,
                          maxLines: 18,
                          textCapitalization:
                              TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Disclaimer text',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                            hintText:
                                'Paste the current paper check-in disclaimer here.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_version == null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'New-customer kiosk registration stays disabled until a disclaimer is saved. Existing appointment check-in still works.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : _version == null
                            ? 'Save disclaimer'
                            : 'Save as new version',
                  ),
                ),
              ],
            ),
    );
  }
}
