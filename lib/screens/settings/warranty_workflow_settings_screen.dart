import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class WarrantyWorkflowSettingsScreen extends StatefulWidget {
  const WarrantyWorkflowSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<WarrantyWorkflowSettingsScreen> createState() =>
      _WarrantyWorkflowSettingsScreenState();
}

class _WarrantyWorkflowSettingsScreenState
    extends State<WarrantyWorkflowSettingsScreen> {
  static const _api = BriskersApi();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _companies = const [];
  List<Map<String, dynamic>> _notes = const [];
  List<Map<String, dynamic>> _disclaimers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.warrantyCompanies(
          widget.businessId,
          includeInactive: true,
        ),
        _api.documentNoteTemplates(
          widget.businessId,
          includeInactive: true,
        ),
        _api.disclaimerTemplates(
          widget.businessId,
          includeInactive: true,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _companies = results[0];
        _notes = results[1];
        _disclaimers = results[2];
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

  Future<void> _editCompany([Map<String, dynamic>? company]) async {
    final name = TextEditingController(
      text: company?['name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: company?['claims_phone']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: company?['submission_email']?.toString() ?? '',
    );
    final portal = TextEditingController(
      text: company?['portal_url']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: company?['notes']?.toString() ?? '',
    );
    var active = company?['active'] != false;

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  company == null
                      ? 'Add warranty company'
                      : 'Edit warranty company',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  autofocus: company == null,
                  decoration: const InputDecoration(
                    labelText: 'Company name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Claims phone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Invoice submission email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: portal,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Portal / website (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  activeThumbColor: BriskersColors.invoices,
                  title: const Text('Active'),
                  onChanged: (value) =>
                      setSheetState(() => active = value),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.invoices,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (name.text.trim().isNotEmpty) {
                      Navigator.pop(sheetContext, true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final companyName = name.text.trim();
    final claimsPhone = phone.text.trim();
    final submissionEmail = email.text.trim();
    final portalUrl = portal.text.trim();
    final noteText = notes.text.trim();

    name.dispose();
    phone.dispose();
    email.dispose();
    portal.dispose();
    notes.dispose();

    if (save != true || companyName.isEmpty) return;

    if (company == null) {
      final id = await _api.createWarrantyCompany(
        widget.businessId,
        name: companyName,
        claimsPhone: claimsPhone.isEmpty ? null : claimsPhone,
        submissionEmail: submissionEmail.isEmpty ? null : submissionEmail,
      );
      if (portalUrl.isNotEmpty || noteText.isNotEmpty || !active) {
        await _api.updateWarrantyCompany(
          widget.businessId,
          id,
          name: companyName,
          claimsPhone: claimsPhone.isEmpty ? null : claimsPhone,
          submissionEmail:
              submissionEmail.isEmpty ? null : submissionEmail,
          portalUrl: portalUrl.isEmpty ? null : portalUrl,
          notes: noteText.isEmpty ? null : noteText,
          active: active,
        );
      }
    } else {
      await _api.updateWarrantyCompany(
        widget.businessId,
        company['id'].toString(),
        name: companyName,
        claimsPhone: claimsPhone.isEmpty ? null : claimsPhone,
        submissionEmail:
            submissionEmail.isEmpty ? null : submissionEmail,
        portalUrl: portalUrl.isEmpty ? null : portalUrl,
        notes: noteText.isEmpty ? null : noteText,
        active: active,
      );
    }

    await _load();
  }

  Future<void> _editNote([Map<String, dynamic>? note]) async {
    final name = TextEditingController(
      text: note?['name']?.toString() ?? '',
    );
    final body = TextEditingController(
      text: note?['body']?.toString() ?? '',
    );
    var quick = note?['show_in_quick_list'] != false;
    var active = note?['active'] != false;
    var type = note?['template_type']?.toString() == 'warranty'
        ? 'warranty'
        : 'standard';

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  note == null ? 'Add standard note' : 'Edit standard note',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  autofocus: note == null,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Text added to invoice notes',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'standard',
                      label: Text('Standard'),
                    ),
                    ButtonSegment(
                      value: 'warranty',
                      label: Text('Warranty'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) =>
                      setSheetState(() => type = value.first),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: BriskersColors.invoices,
                  value: quick,
                  title: const Text('Show in quick list'),
                  onChanged: (value) =>
                      setSheetState(() => quick = value == true),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  activeThumbColor: BriskersColors.invoices,
                  title: const Text('Active'),
                  onChanged: (value) =>
                      setSheetState(() => active = value),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.invoices,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (name.text.trim().isNotEmpty &&
                        body.text.trim().isNotEmpty) {
                      Navigator.pop(sheetContext, true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final templateName = name.text.trim();
    final templateBody = body.text.trim();
    name.dispose();
    body.dispose();

    if (save != true ||
        templateName.isEmpty ||
        templateBody.isEmpty) {
      return;
    }

    await _api.saveDocumentNoteTemplate(
      widget.businessId,
      templateId: note?['id']?.toString(),
      name: templateName,
      body: templateBody,
      templateType: type,
      showInQuickList: quick,
      active: active,
      sortOrder:
          int.tryParse(note?['sort_order']?.toString() ?? '') ?? 100,
    );

    await _load();
  }

  Future<void> _editDisclaimer([Map<String, dynamic>? disclaimer]) async {
    final name = TextEditingController(
      text: disclaimer?['name']?.toString() ?? '',
    );
    final body = TextEditingController(
      text: disclaimer?['body']?.toString() ?? '',
    );
    var signatureRequired =
        disclaimer?['signature_required'] != false;
    var active = disclaimer?['active'] != false;

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  disclaimer == null
                      ? 'Add disclaimer template'
                      : 'Edit disclaimer template',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  autofocus: disclaimer == null,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Disclaimer text',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: BriskersColors.invoices,
                  value: signatureRequired,
                  title: const Text(
                    'Require customer signature',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onChanged: (value) => setSheetState(
                    () => signatureRequired = value == true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  activeThumbColor: BriskersColors.invoices,
                  title: const Text('Active'),
                  onChanged: (value) =>
                      setSheetState(() => active = value),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.invoices,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (name.text.trim().isNotEmpty &&
                        body.text.trim().isNotEmpty) {
                      Navigator.pop(sheetContext, true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final templateName = name.text.trim();
    final templateBody = body.text.trim();
    name.dispose();
    body.dispose();

    if (save != true ||
        templateName.isEmpty ||
        templateBody.isEmpty) {
      return;
    }

    await _api.saveDisclaimerTemplate(
      widget.businessId,
      templateId: disclaimer?['id']?.toString(),
      name: templateName,
      body: templateBody,
      signatureRequired: signatureRequired,
      active: active,
      sortOrder: int.tryParse(
            disclaimer?['sort_order']?.toString() ?? '',
          ) ??
          100,
    );

    await _load();
  }

  Widget _sectionHeader(
    String title,
    String subtitle,
    VoidCallback onAdd,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: 'Add',
        onPressed: onAdd,
        icon: const Icon(
          Icons.add_circle_outline,
          color: BriskersColors.invoices,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warranty & invoice notes'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  _sectionHeader(
                    'Warranty companies',
                    'Claims phone and invoice submission email',
                    _editCompany,
                  ),
                  if (_companies.isEmpty)
                    const ListTile(
                      title: Text('No warranty companies saved yet.'),
                    )
                  else
                    ..._companies.map(
                      (company) => ListTile(
                        leading: Icon(
                          Icons.shield_outlined,
                          color: company['active'] == false
                              ? Colors.grey
                              : BriskersColors.invoices,
                        ),
                        title: Text(
                          company['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          <String>[
                            if ((company['claims_phone']?.toString() ?? '')
                                .isNotEmpty)
                              company['claims_phone'].toString(),
                            if ((company['submission_email']?.toString() ?? '')
                                .isNotEmpty)
                              company['submission_email'].toString(),
                            if (company['active'] == false) 'Inactive',
                          ].join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editCompany(company),
                      ),
                    ),
                  const Divider(height: 24),
                  _sectionHeader(
                    'Standard notes',
                    'Reusable notes added from the invoice Notes tab',
                    _editNote,
                  ),
                  if (_notes.isEmpty)
                    const ListTile(
                      title: Text('No standard note templates yet.'),
                    )
                  else
                    ..._notes.map(
                      (note) => ListTile(
                        leading: Icon(
                          note['template_type']?.toString() == 'warranty'
                              ? Icons.verified_outlined
                              : Icons.notes_outlined,
                          color: note['active'] == false
                              ? Colors.grey
                              : BriskersColors.invoices,
                        ),
                        title: Text(
                          note['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          note['body']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editNote(note),
                      ),
                    ),
                  const Divider(height: 24),
                  _sectionHeader(
                    'Disclaimer templates',
                    'Customer acknowledgments, optionally requiring signature',
                    _editDisclaimer,
                  ),
                  if (_disclaimers.isEmpty)
                    const ListTile(
                      title: Text('No disclaimer templates yet.'),
                    )
                  else
                    ..._disclaimers.map(
                      (disclaimer) => ListTile(
                        leading: Icon(
                          disclaimer['signature_required'] == true
                              ? Icons.draw_outlined
                              : Icons.info_outline,
                          color: disclaimer['active'] == false
                              ? Colors.grey
                              : BriskersColors.invoices,
                        ),
                        title: Text(
                          disclaimer['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          disclaimer['body']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editDisclaimer(disclaimer),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
