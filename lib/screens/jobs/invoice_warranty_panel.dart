import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/briskers_colors.dart';
import '../../core/warranty_payment_amounts.dart';
import '../../core/briskers_i18n.dart';
import '../../core/formatters.dart';
import '../../core/module_modal_theme.dart';
import '../../services/briskers_api.dart';

Widget _createWarrantyCompanyDialog(
  BuildContext context, {
  required TextEditingController name,
  required TextEditingController phone,
  required TextEditingController email,
  required bool autofocusName,
}) => AlertDialog(
  backgroundColor: Theme.of(context).colorScheme.surface,
  surfaceTintColor: Colors.transparent,
  insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
  actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
  scrollable: true,
  title: Text(tr('addWarrantyCompany')),
  content: SizedBox(
    width: MediaQuery.sizeOf(context).width * 0.92,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          autofocus: autofocusName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('companyName'),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: const [WarrantyPhoneTextInputFormatter()],
          decoration: InputDecoration(
            labelText: tr('claimsPhone'),
            hintText: '1-800-531-1925',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: tr('invoiceSubmissionEmail'),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
      ],
    ),
  ),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: Text(tr('cancel')),
    ),
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: name,
      builder: (context, value, _) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: BriskersColors.invoices,
          foregroundColor: Colors.white,
          minimumSize: const Size(96, 48),
        ),
        onPressed: value.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, true),
        child: Text(tr('add')),
      ),
    ),
  ],
);

class InvoiceWarrantyPanel extends StatefulWidget {
  const InvoiceWarrantyPanel({
    super.key,
    required this.businessId,
    required this.documentId,
    required this.expectedVersion,
    required this.invoiceTotal,
    required this.detail,
    required this.onChanged,
    required this.paymentProcessed,
    this.paymentPendingLabel,
    this.payments = const [],
    this.readOnly = false,
    this.onLocalWarrantyChanged,
  });

  final String businessId;
  final String documentId;
  final int expectedVersion;
  final num invoiceTotal;
  final Map<String, dynamic> detail;
  final Future<void> Function() onChanged;
  final bool paymentProcessed;
  final String? paymentPendingLabel;
  final List<Map<String, dynamic>> payments;
  final bool readOnly;
  final Future<void> Function(Map<String, dynamic>)? onLocalWarrantyChanged;

  @visibleForTesting
  static Widget createCompanyDialogForTesting(
    BuildContext context, {
    required TextEditingController name,
    required TextEditingController phone,
    required TextEditingController email,
  }) => _createWarrantyCompanyDialog(
    context,
    name: name,
    phone: phone,
    email: email,
    autofocusName: name.text.isEmpty,
  );

  @override
  State<InvoiceWarrantyPanel> createState() => _InvoiceWarrantyPanelState();
}

class _InvoiceWarrantyPanelState extends State<InvoiceWarrantyPanel>
    with ModuleModalState<InvoiceWarrantyPanel> {
  @override
  Color get modalAccent => BriskersColors.invoices;

  static const _api = BriskersApi();

  bool _expanded = false;
  bool _busy = false;
  bool _toggleInFlight = false;
  late bool _localEnabled;
  num _cardSurchargeRate = 0.03;

  bool get _enabled => _localEnabled;

  @override
  void initState() {
    super.initState();
    _localEnabled = widget.detail['extended_warranty'] == true;
    if (widget.onLocalWarrantyChanged == null) {
      _loadWarrantyPaymentSettings();
    }
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
    List<Map<String, dynamic>> companies, {
    bool allowCreate = true,
  }) async {
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
                  if (allowCreate) ListTile(
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
      builder: (dialogContext) => _createWarrantyCompanyDialog(
        dialogContext,
        name: name,
        phone: phone,
        email: email,
        autofocusName: initialName.isEmpty,
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

  Future<void> _saveLocalWarranty(Map<String, dynamic> values) async {
    final save = widget.onLocalWarrantyChanged;
    if (save == null) return;
    try {
      await save(values);
      if (mounted) {
        setState(() {
          _localEnabled = values['extended_warranty'] == true;
          _expanded = _localEnabled;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save warranty offline: $error')),
        );
      }
    }
  }

  String get _companiesKey => 'briskers_warranty_companies_${widget.businessId}';

  Future<List<Map<String, dynamic>>> _cachedWarrantyCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_companiesKey) ?? '[]');
      return (decoded as List)
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _cacheWarrantyCompanies(
      List<Map<String, dynamic>> companies) async {
    if (companies.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_companiesKey, jsonEncode(companies));
  }

  Future<void> _editLocalWarranty() async {
    final companies = await _cachedWarrantyCompanies();
    if (!mounted) return;
    Map<String, dynamic>? selected;
    final previousId = widget.detail['warranty_company_id']?.toString() ?? '';
    final previousName = widget.detail['warranty_company_name']?.toString() ?? '';
    for (final entry in companies) {
      if (entry['id']?.toString() == previousId ||
          (previousId.isEmpty && entry['name']?.toString() == previousName)) {
        selected = entry;
        break;
      }
    }
    // An existing company's saved details remain available when its list has
    // not yet been cached. Do not silently discard the saved ID.
    selected ??= previousName.isNotEmpty
        ? <String, dynamic>{
            'id': previousId,
            'name': previousName,
            'claims_phone': widget.detail['claims_phone'] ?? '',
            'submission_email': widget.detail['submission_email'] ?? '',
          }
        : null;
    final company = TextEditingController(
      text: previousName);
    final phone = TextEditingController(
      text: widget.detail['claims_phone']?.toString() ?? '');
    final email = TextEditingController(
      text: widget.detail['submission_email']?.toString() ?? '');
    final claim = TextEditingController(
      text: widget.detail['claim_number']?.toString() ?? '');
    final authorization = TextEditingController(
      text: widget.detail['authorization_number']?.toString() ?? '');
    final approved = TextEditingController(
      text: widget.detail['approved_amount']?.toString() ?? '');
    var rate = _number(widget.detail['surcharge_rate']);
    if (rate > 0) rate = _cardSurchargeRate;
    ModalRoute<dynamic>? sheetRoute;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            sheetRoute ??= ModalRoute.of(sheetContext);
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
                        final picked = await _pickCompany(sheetContext, companies, allowCreate: false);
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
                      initialValue: rate,
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
                          setSheetState(() => rate = value);
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
                                  'extended_warranty': true,
                                  'warranty_company_id': selected!['id']?.toString() ?? '',
                                  'warranty_company_name': selected!['name']?.toString() ?? '',
                                  'claims_phone': selected!['claims_phone']?.toString() ?? '',
                                  'submission_email': selected!['submission_email']?.toString() ?? '',
                                  'claim_number': claim.text.trim(),
                                  'authorization_number': authorization.text.trim(),
                                  'approved_amount': num.tryParse(approved.text.trim()),
                                  'surcharge_rate': rate,
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

      // The sheet still uses its controllers during the exit animation.
      await sheetRoute?.completed;
      company.dispose();
    phone.dispose();
    email.dispose();
    claim.dispose();
    authorization.dispose();
    approved.dispose();
    if (result == null) return;
    final approvedAmount = _number(result['approved_amount']);
    final cardRate = _number(result['surcharge_rate']);
    final approvedCents = WarrantyPaymentAmounts.cents(approvedAmount) ?? 0;
    final terminalCents = (approvedCents / (1 + cardRate)).round();
    final terminal = terminalCents / 100;
    final processorFee = (approvedCents - terminalCents) / 100;
    await _saveLocalWarranty({
      ...widget.detail,
      ...result,
      'terminal_amount': terminal,
      'net_applied': terminal,
      'processor_fee': processorFee,
      'customer_responsibility':
          (widget.invoiceTotal - terminal).clamp(0, double.infinity),
    });
  }

  Future<void> _enableWarranty() async {
    if (widget.readOnly || _busy) return;
    if (widget.onLocalWarrantyChanged != null) {
      await _saveLocalWarranty({...widget.detail, 'extended_warranty': true});
      return;
    }

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
    if (widget.onLocalWarrantyChanged != null) {
      await _saveLocalWarranty({...widget.detail, 'extended_warranty': false});
      return;
    }

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
    if (widget.onLocalWarrantyChanged != null) {
      await _editLocalWarranty();
      return;
    }

    setState(() => _busy = true);

    try {
      final companies = await _api.warrantyCompanies(widget.businessId);
      await _cacheWarrantyCompanies(companies);
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

      ModalRoute<dynamic>? sheetRoute;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            sheetRoute ??= ModalRoute.of(sheetContext);
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
                      initialValue: selectedRate,
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

      // The sheet still uses its controllers during the exit animation.
      await sheetRoute?.completed;
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

  Future<void> _onWarrantyChecked(bool selected) async {
    if (_toggleInFlight || _busy || widget.readOnly ||
        selected == _enabled) {
      return;
    }
    setState(() => _toggleInFlight = true);
    try {
      if (selected) {
        // Only enable and expand once. The old implementation first saved,
        // refreshed the invoice, then immediately opened a second editor
        // sheet; users saw the warranty box close/reopen on one checkbox tap.
        // Details are entered using the visible Enter/Edit action.
        await _enableWarranty();
      } else {
        // Keep existing confirmation and all warranty accounting safeguards.
        await _disableWarranty();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update warranty: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _toggleInFlight = false);
    }
  }

  Widget _warrantyToggle() {
    final enabled = _enabled;
    final company = widget.detail['warranty_company_name']?.toString() ?? '';
    final canChange = !widget.readOnly && !_busy && !_toggleInFlight;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
      child: Row(
        children: [
          Checkbox(
            key: const ValueKey('warranty-job-checkbox'),
            value: enabled,
            onChanged: canChange
                ? (value) => _onWarrantyChecked(value == true)
                : null,
            activeColor: BriskersColors.invoices,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: InkWell(
              onTap: canChange
                  ? () => _onWarrantyChecked(!enabled)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      BriskersLanguageController.instance.isSpanish
                          ? 'Trabajo de garantía'
                          : 'Warranty Job',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (enabled && company.isNotEmpty)
                      Text(
                        company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF667085)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (enabled)
            IconButton(
              key: const ValueKey('warranty-job-expand'),
              tooltip: _expanded
                  ? 'Collapse warranty information'
                  : 'Expand warranty information',
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _warrantyToggle();
    if (!_enabled) return header;

    final company = widget.detail['warranty_company_name']?.toString() ?? '';
    final auth = widget.detail['authorization_number']?.toString() ?? '';
    final claim = widget.detail['claim_number']?.toString() ?? '';
    final approved = _number(widget.detail['approved_amount']);
    final receipt = WarrantyPaymentAmounts.receipt(widget.detail, widget.payments);
    final terminal = receipt == null ? _number(widget.detail['terminal_amount']) : _number(receipt['amount']);
    final fee = _number(widget.detail['processor_fee']);
    final allocation = WarrantyPaymentAllocation.fromWarranty(
      invoiceTotal: widget.invoiceTotal, warranty: widget.detail);
    final customer = allocation.customerTotal;
    final breakdown = WarrantyPaymentAmounts.fromReceipt(gross: terminal, processorFee: fee);
    final phone = formatWarrantyPhone(
      widget.detail['claims_phone']?.toString(),
    );
    final email = widget.detail['submission_email']?.toString() ?? '';

    final missing = <String>[
      if (company.isEmpty) tr('company'),
      if (auth.isEmpty) tr('authorizationShort'),
      if (approved <= 0) tr('approvedAmountLower'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (_expanded) Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: BriskersColors.invoices.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BriskersColors.invoices.withValues(alpha: 0.25),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
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
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    company.isEmpty ? tr('extendedWarranty') : company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: widget.paymentPendingLabel != null
                        ? const Color(0xFFFFF4DE)
                        : widget.paymentProcessed
                        ? const Color(0xFFEAF8EE)
                        : const Color(0xFFFFECEC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.paymentPendingLabel != null
                            ? Icons.schedule
                            : widget.paymentProcessed
                            ? Icons.check
                            : Icons.close,
                        size: 13,
                        color: widget.paymentPendingLabel != null
                            ? const Color(0xFF946200)
                            : widget.paymentProcessed
                            ? const Color(0xFF0C9A43)
                            : const Color(0xFFC62828),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.paymentPendingLabel ?? (widget.paymentProcessed
                            ? tr('paid')
                            : tr('unpaid')),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: widget.paymentPendingLabel != null
                              ? const Color(0xFF946200)
                              : widget.paymentProcessed
                              ? const Color(0xFF0C9A43)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Text(
              missing.isEmpty
                  ? tr('approvedCustomerAllocationSummary')
                      .replaceAll('{approved}', _money(approved))
                      .replaceAll('{customer}', allocation.requiresReview
                          ? tr('warrantyAllocationReviewRequired') : _money(customer))
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
            // The compact Warranty Job header owns the expand/collapse
            // control, keeping the checked state distinct from visibility.
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
                    receipt == null ? tr('runWarrantyCardFor') : tr('actualGrossReceived'),
                    _money(terminal),
                    strong: true,
                  ),
                  _summaryRow(
                    '${(_number(widget.detail['surcharge_rate']) * 100).toStringAsFixed((_number(widget.detail['surcharge_rate']) * 100) % 1 == 0 ? 0 : 2)}% ${tr('threePercentSurcharge').replaceFirst('3% ', '')}',
                    allocation.requiresReview
                        ? tr('warrantyAllocationReviewRequired') : _money(fee),
                  ),
                  _summaryRow(
                    widget.paymentProcessed
                        ? tr('warrantyAppliedToInvoice')
                        : (widget.paymentPendingLabel != null
                            ? 'Warranty payment pending'
                            : 'Warranty amount to apply'),
                    _money(terminal),
                  ),
                  if (receipt != null && breakdown != null) _summaryRow(
                    tr('retainedReceipt'), _money(breakdown.retained)),
                  Text(tr('warrantyFeeNoDoubleCharge'), style: const TextStyle(fontSize: 12)),
                  _summaryRow(
                    tr('customerResponsibilityAllocation'),
                    allocation.requiresReview
                        ? tr('warrantyAllocationReviewRequired') : _money(customer),
                    strong: true,
                  ),
                  Text(tr('warrantyAllocationBalanceHelp'),
                    style: const TextStyle(fontSize: 12)),
                  if (allocation.requiresReview)
                    Text(tr('warrantyAllocationReviewHelp'),
                      style: TextStyle(fontSize: 12,
                        color: Theme.of(context).colorScheme.error)),
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
                            label: Text(missing.isNotEmpty
                                ? 'Enter warranty details'
                                : tr('edit')),
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
      ),
      ),
      ],
    );
  }
}
