import 'package:flutter/material.dart';

import '../../services/email_draft_templates.dart';

class EmailTemplatesSettingsScreen extends StatefulWidget {
  const EmailTemplatesSettingsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  State<EmailTemplatesSettingsScreen> createState() => _EmailTemplatesSettingsScreenState();
}

class _EmailTemplatesSettingsScreenState extends State<EmailTemplatesSettingsScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final current = await EmailDraftTemplates.load(widget.businessId);
      if (!mounted) return;
      setState(() {
        _subject.text = current.subject;
        _body.text = current.body;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Enter both a subject and a message body.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await EmailDraftTemplates(
        subject: _subject.text.trim(),
        body: _body.text.trim(),
      ).save(widget.businessId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email draft templates saved on this device.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Email templates')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Used when opening Gmail from an invoice or estimate. '
                  'You can still edit each email in Gmail before sending.'),
              const SizedBox(height: 16),
              TextField(
                controller: _subject,
                decoration: const InputDecoration(
                  labelText: 'Email subject',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 9,
                decoration: const InputDecoration(
                  labelText: 'Email body',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Optional placeholders: {type} = Invoice or Estimate; '
                  '{typeLower} = invoice or estimate; {number} = document number. '
                  'Changes are saved on this device.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _saving ? null : () => setState(() {
                  _subject.text = EmailDraftTemplates.defaultSubject;
                  _body.text = EmailDraftTemplates.defaultBody;
                }),
                child: const Text('Restore default wording'),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save email templates'),
              ),
            ],
          ),
  );
}
