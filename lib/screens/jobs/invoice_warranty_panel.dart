import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/briskers_i18n.dart';
import '../../core/formatters.dart';
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
  late bool _localEnabled;
  num _cardSurchargeRate = 0.03;

  bool get _enabled => _localEnabled;

  @override
  void initState() {
    super.initState();
    _localEnabled = widget.detail['extended_warranty'] == true;
    _loadWarrantyPaymentSettings();
  }

  Future<void> _loadWarrantyPaymentSettings() async {
    try {
      final settings = await _api.warrantyPaymentSettings(widget.businessId);
      final rate = num.tryParse(
            settings['card_surcharge_rate']?.toString() ?? '',
          ) ??
          0.03;
      if (mounted) setState(() => _cardSurchargeRate = rate);
    } catch (_) {
      // Keep the safe 3% default if settings are temporarily unavailable.
    }
  }

  @override
  void didUpdateWidget(covariant InvoiceWarrantyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) {
      _localEnabled = widget.detail['extended_warranty'] == true;
    }
  }

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
                      decoration: InputDecoration(
                        labelText: tr('warrantyCompany'),
                        hintText: tr('searchOrTypeWarrantyCompany'),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
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
                          ? tr('addNewWarrantyCompany')
                          : tr('addNamedCompany').replaceAll(
                              '{name}',
                              search.text.trim(),
                            ),
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
                        ? Center(child: Text(tr('noMatchingCompanies')))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final company = filtered[index];
                              final phone = formatWarrantyPhone(
                                company['claims_phone']?.toString(),
                              );
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
        title: Text(tr('addWarrantyCompany')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: initialName.isEmpty,
                decoration: InputDecoration(
                  labelText: tr('companyName'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: const [
                  WarrantyPhoneTextInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: tr('claimsPhone'),
                  hintText: '1-800-531-1925',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: tr('invoiceSubmissionEmail'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.invoices,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('add')),
          ),
        ],
      ),
    );

    final companyName = name.text.trim();
    final claimsPhone = formatWarrantyPhone(phone.text.trim());
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

    setState(() {
      _localEnabled = true;
      _expanded = true;
      _busy = true;
    });

    try {
      await _api.updateDocumentWarranty(
        widget.businessId,
        widget.documentId,
        expectedVersion: widget.expectedVersion,
        extendedWarranty: true,
      );

      if (mounted) {
        setState(() => _busy = false);
      }

      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        setState(() {
          _localEnabled = false;
          _expanded = false;
          _busy = false;
        });
      }
      rethrow;
    }
  }

  Future<void> _disableWarranty() async {
    if (widget.readOnly || _busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr('removeExtendedWarranty')),
            content: Text(tr('removeExtendedWarrantyBody')),
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
                child: Text(tr('remove')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _localEnabled = false;
      _expanded = false;
      _busy = true;
    });
    try {
      await _api.updateDocumentWarranty(
        widget.businessId,
        widget.documentId,
        expectedVersion: widget.expectedVersion,
        extendedWarranty: false,
      );
      if (mounted) setState(() => _busy = false);
      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        setState(() {
          _localEnabled = true;
          _busy = false;
        });
      }
      rethrow;
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
      num selectedRate = _number(widget.detail['surcharge_rate']);
      if (selectedRate <= 0) {
        selectedRate = 0;
      } else {
        selectedRate = _cardSurchargeRate;
      }

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
                    Text(
                      tr('extendedWarranty'),
                      style: const TextStyle(
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
                        decoration: InputDecoration(
                          labelText: tr('warrantyCompany'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.shield_outlined),
                          suffixIcon: const Icon(Icons.chevron_right),
                        ),
                        child: Text(
                          selectedName.isEmpty
                              ? tr('selectOrAddCompany')
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
                        ].join('\n'),
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
                      decoration: InputDecoration(
                        labelText: tr('claimNumberOptional'),
                        prefixIcon: const Icon(Icons.assignment_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: authorization,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: tr('authorizationNumber'),
                        prefixIcon: const Icon(Icons.verified_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: approved,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Approved warranty amount',
                        prefixText: '\$ ',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<num>(
                      value: selectedRate,
                      decoration: InputDecoration(
                        labelText: tr('warrantyPaymentType'),
                        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem<num>(
                          value: 0,
                          child: Text(tr('warrantyCheckOption')),
                        ),
                        DropdownMenuItem<num>(
                          value: _cardSurchargeRate,
                          child: Text(
                            tr('warrantyCardOption').replaceAll(
                              '{percent}',
                              (_cardSurchargeRate * 100)
                                  .toStringAsFixed(
                                    (_cardSurchargeRate * 100) % 1 == 0 ? 0 : 2,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedRate = value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr('warrantySurchargeExplanation'),
                      style: const TextStyle(
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
                                  'surcharge_rate': selectedRate,
                                },
                              ),
                      child: Text(tr('saveWarrantyInformation')),
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
        surchargeRate:
            num.tryParse(result['surcharge_rate']?.toString() ?? '') ??
                _cardSurchargeRate,
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: false,
                onChanged: widget.readOnly || _busy
                    ? null
                    : (value) {
                        if (value == true) _enableWarranty();
                      },
                activeColor: BriskersColors.invoices,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tr('extendedWarrantyJob'),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.settings_outlined,
                size: 20,
                color: Color(0xFFB0B7C3),
              ),
            ],
          ),
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
    final phone = formatWarrantyPhone(
      widget.detail['claims_phone']?.toString(),
    );
    final email = widget.detail['submission_email']?.toString() ?? '';

    final missing = <String>[
      if (company.isEmpty) tr('company'),
      if (auth.isEmpty) tr('authorizationShort'),
      if (approved <= 0) tr('approvedAmountLower'),
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
              company.isEmpty ? tr('extendedWarranty') : company,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              missing.isEmpty
                  ? tr('approvedCustomerSummary')
                      .replaceAll('{approved}', _money(approved))
                      .replaceAll('{customer}', _money(customer))
                  : tr('missingSummary').replaceAll(
                      '{items}',
                      missing.join(', '),
                    ),
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
                    _summaryRow(tr('claimNumber'), claim),
                  _summaryRow(
                    tr('authorizationNumber'),
                    auth.isEmpty ? tr('missing') : auth,
                  ),
                  if (phone.isNotEmpty) _summaryRow(tr('claimsPhone'), phone),
                  if (email.isNotEmpty) _summaryRow(tr('submissionEmail'), email),
                  const Divider(height: 18),
                  _summaryRow(tr('approvedTotal'), _money(approved)),
                  _summaryRow(
                    tr('runWarrantyCardFor'),
                    _money(terminal),
                    strong: true,
                  ),
                  _summaryRow(
                    '${(_number(widget.detail['surcharge_rate']) * 100).toStringAsFixed((_number(widget.detail['surcharge_rate']) * 100) % 1 == 0 ? 0 : 2)}% ${tr('threePercentSurcharge').replaceFirst('3% ', '')}',
                    _money(fee),
                  ),
                  _summaryRow(
                    tr('warrantyAppliedToInvoice'),
                    _money(terminal),
                  ),
                  _summaryRow(
                    tr('customerResponsibility'),
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
                            label: Text(tr('remove')),
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
                            label: Text(tr('edit')),
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
