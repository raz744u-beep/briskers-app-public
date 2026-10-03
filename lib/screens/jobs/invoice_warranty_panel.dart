import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class InvoiceWarrantyPanel extends StatefulWidget {
  const InvoiceWarrantyPanel({
    super.key,
    required this.businessId,
    required this.documentId,
    required this.expectedVersion,
    required this.invoiceTotal,
    required this.detail,
    required this.onChanged,
    this.readOnly = false,
  });

  final String businessId;
  final String documentId;
  final int expectedVersion;
  final num invoiceTotal;
  final Map<String, dynamic> detail;
  final Future<void> Function() onChanged;
  final bool readOnly;

  @override
  State<InvoiceWarrantyPanel> createState() => _InvoiceWarrantyPanelState();
}

class _InvoiceWarrantyPanelState extends State<InvoiceWarrantyPanel> {
  static const _api = BriskersApi();

  bool _expanded = false;
  bool _busy = false;

  bool get _enabled => widget.detail['extended_warranty'] == true;

  num _number(Object? raw) => num.tryParse(raw?.toString() ?? '') ?? 0;

  String _money(Object? raw) =>
      NumberFormat.currency(symbol: '\$').format(_number(raw));

  Future<Map<String, dynamic>?> _pickCompany(
    BuildContext context,
    List<Map<String, dynamic>> companies,
  ) async {
    final search = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(companies);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void filter(String value) {
            final needle = value.trim().toLowerCase();
            setSheetState(() {
              filtered = companies.where((company) {
                final name = company['name']?.toString().toLowerCase() ?? '';
                return needle.isEmpty || name.contains(needle);
              }).toList();
            });
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      onChanged: filter,
                      decoration: const InputDecoration(
                        labelText: 'Warranty company',
                        hintText: 'Search or type a new company',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.add_business_outlined,
                      color: BriskersColors.invoices,
                    ),
                    title: Text(
                      search.text.trim().isEmpty
                          ? 'Add new warranty company'
                          : 'Add “${search.text.trim()}”',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () async {
                      final name = search.text.trim();
                      final created = await _createCompany(
                        sheetContext,
                        initialName: name,
                      );
                      if (created != null && sheetContext.mounted) {
                        Navigator.pop(sheetContext, created);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching companies.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final company = filtered[index];
                              final phone =
                                  company['claims_phone']?.toString() ?? '';
                              final email =
                                  company['submission_email']?.toString() ?? '';
                              return ListTile(
                                leading: const Icon(
                                  Icons.shield_outlined,
                                  color: BriskersColors.invoices,
                                ),
                                title: Text(
                                  company['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  <String>[
                                    if (phone.isNotEmpty) phone,
                                    if (email.isNotEmpty) email,
                                  ].join(' • '),
                                ),
                                onTap: () =>
                                    Navigator.pop(sheetContext, company),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    search.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _createCompany(
    BuildContext context, {
    String initialName = '',
  }) async {
    final name = TextEditingController(text: initialName);
    final phone = TextEditingController();
    final email = TextEditingController();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add warranty company'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: initialName.isEmpty,
                decoration: const InputDecoration(
                  labelText: 'Company name',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Claims phone',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Invoice submission email',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.invoices,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final companyName = name.text.trim();
    final claimsPhone = phone.text.trim();
    final submissionEmail = email.text.trim();

    name.dispose();
    phone.dispose();
    email.dispose();

    if (save != true || companyName.isEmpty) return null;

    final id = await _api.createWarrantyCompany(
      widget.businessId,
      name: companyName,
      claimsPhone: claimsPhone.isEmpty ? null : claimsPhone,
      submissionEmail: submissionEmail.isEmpty ? null : submissionEmail,
    );

    return {
      'id': id,
      'name': companyName,
      'claims_phone': claimsPhone,
      'submission_email': submissionEmail,
      'active': true,
    };
  }

  Future<void> _enableWarranty() async {
    if (widget.readOnly || _busy) return;
    setState(() => _busy = true);
    try {
      await _api.updateDocumentWarranty(
        widget.businessId,
        widget.documentId,
        expectedVersion: widget.expectedVersion,
        extendedWarranty: true,
      );
      await widget.onChanged();
      if (mounted) setState(() => _expanded = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableWarranty() async {
    if (widget.readOnly || _busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove extended warranty?'),
            content: const Text(
              'Warranty company, authorization and payment-allocation details '
              'will be removed from this invoice.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.invoices,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await _api.updateDocumentWarranty(
        widget.businessId,
        widget.documentId,
        expectedVersion: widget.expectedVersion,
        extendedWarranty: false,
      );
      await widget.onChanged();
      if (mounted) setState(() => _expanded = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editWarranty() async {
    if (widget.readOnly || _busy) return;

    setState(() => _busy = true);

    try {
      final companies = await _api.warrantyCompanies(widget.businessId);
      if (!mounted) return;

      Map<String, dynamic>? selected;
      final selectedId = widget.detail['warranty_company_id']?.toString() ?? '';
      for (final company in companies) {
        if (company['id']?.toString() == selectedId) {
          selected = company;
          break;
        }
      }

      final claim = TextEditingController(
        text: widget.detail['claim_number']?.toString() ?? '',
      );
      final authorization = TextEditingController(
        text: widget.detail['authorization_number']?.toString() ?? '',
      );
      final approved = TextEditingController(
        text: _number(widget.detail['approved_amount']) > 0
            ? _number(widget.detail['approved_amount']).toStringAsFixed(2)
            : '',
      );

      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedName = selected?['name']?.toString() ?? '';
            final phone = selected?['claims_phone']?.toString() ?? '';
            final email = selected?['submission_email']?.toString() ?? '';

            return SafeArea(
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
                    const Text(
                      'Extended Warranty',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await _pickCompany(
                          sheetContext,
                          companies,
                        );
                        if (picked != null && sheetContext.mounted) {
                          setSheetState(() => selected = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Warranty company',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shield_outlined),
                          suffixIcon: Icon(Icons.chevron_right),
                        ),
                        child: Text(
                          selectedName.isEmpty
                              ? 'Select or add company'
                              : selectedName,
                          style: TextStyle(
                            fontWeight: selectedName.isEmpty
                                ? FontWeight.w400
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (phone.isNotEmpty || email.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        <String>[
                          if (phone.isNotEmpty) 'Claims: \$phone',
                          if (email.isNotEmpty) 'Submit: \$email',
                        ].join('\\n'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: claim,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Claim number (optional)',
                        prefixIcon: Icon(Icons.assignment_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: authorization,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Authorization number',
                        prefixIcon: Icon(Icons.verified_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: approved,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Approved warranty amount',
                        prefixText: '\\$ ',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'The 3% processor surcharge does not count as shop '
                      'revenue. Briskers will apply only the net warranty '
                      'amount to the invoice and leave the difference in the '
                      'customer balance.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: BriskersColors.invoices,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: selected == null
                          ? null
                          : () => Navigator.pop(
                                sheetContext,
                                {
                                  'company_id': selected!['id']?.toString(),
                                  'claim': claim.text.trim(),
                                  'authorization':
                                      authorization.text.trim(),
                                  'approved': approved.text.trim(),
                                },
                              ),
                      child: const Text('Save warranty information'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      claim.dispose();
      authorization.dispose();
      approved.dispose();

      if (result == null) return;

      final approvedAmount =
          num.tryParse(result['approved']?.toString() ?? '');

      await _api.updateDocumentWarranty(
        widget.businessId,
        widget.documentId,
        expectedVersion: widget.expectedVersion,
        extendedWarranty: true,
        warrantyCompanyId: result['company_id']?.toString(),
        claimNumber: (result['claim']?.toString() ?? '').isEmpty
            ? null
            : result['claim']?.toString(),
        authorizationNumber:
            (result['authorization']?.toString() ?? '').isEmpty
                ? null
                : result['authorization']?.toString(),
        approvedAmount: approvedAmount,
        surchargeRate: 0.03,
      );
      await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF667085),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 16 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              color: strong ? BriskersColors.invoices : const Color(0xFF182239),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: CheckboxListTile(
          value: false,
          enabled: !widget.readOnly && !_busy,
          contentPadding: EdgeInsets.zero,
          activeColor: BriskersColors.invoices,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Extended warranty job',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Enable warranty company, authorization and payment allocation.',
          ),
          onChanged: (value) {
            if (value == true) _enableWarranty();
          },
        ),
      );
    }

    final company = widget.detail['warranty_company_name']?.toString() ?? '';
    final auth = widget.detail['authorization_number']?.toString() ?? '';
    final claim = widget.detail['claim_number']?.toString() ?? '';
    final approved = _number(widget.detail['approved_amount']);
    final terminal = _number(widget.detail['terminal_amount']);
    final fee = _number(widget.detail['processor_fee']);
    final customer = _number(widget.detail['customer_responsibility']);
    final phone = widget.detail['claims_phone']?.toString() ?? '';
    final email = widget.detail['submission_email']?.toString() ?? '';

    final missing = <String>[
      if (company.isEmpty) 'company',
      if (auth.isEmpty) 'authorization #',
      if (approved <= 0) 'approved amount',
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: BriskersColors.invoices.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BriskersColors.invoices.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE9F6ED),
              child: Icon(
                Icons.shield_outlined,
                color: BriskersColors.invoices,
              ),
            ),
            title: Text(
              company.isEmpty ? 'Extended Warranty' : company,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              missing.isEmpty
                  ? 'Approved ${_money(approved)} • Customer ${_money(customer)}'
                  : 'Missing: ${missing.join(', ')}',
              style: TextStyle(
                color: missing.isEmpty
                    ? BriskersColors.invoices
                    : const Color(0xFFC66A00),
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (claim.isNotEmpty)
                    _summaryRow('Claim number', claim),
                  _summaryRow(
                    'Authorization number',
                    auth.isEmpty ? 'Missing' : auth,
                  ),
                  if (phone.isNotEmpty) _summaryRow('Claims phone', phone),
                  if (email.isNotEmpty) _summaryRow('Submission email', email),
                  const Divider(height: 18),
                  _summaryRow('Approved amount', _money(approved)),
                  _summaryRow(
                    'Run warranty card for',
                    _money(terminal),
                    strong: true,
                  ),
                  _summaryRow('3% processor surcharge', _money(fee)),
                  _summaryRow(
                    'Warranty applied to invoice',
                    _money(terminal),
                  ),
                  _summaryRow(
                    'Customer responsibility',
                    _money(customer),
                    strong: true,
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _disableWarranty,
                            icon: const Icon(Icons.close),
                            label: const Text('Remove'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: BriskersColors.invoices,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _busy ? null : _editWarranty,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
