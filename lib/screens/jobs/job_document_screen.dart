import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../core/briskers_colors.dart';
import '../../core/briskers_i18n.dart';
import '../../core/formatters.dart';
import '../../core/invoice_status_style.dart';
import '../../services/briskers_api.dart';
import '../../services/document_pdf_service.dart';
import '../../services/gmail_compose_service.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/local_catalog_repository.dart';
import '../expenses/expense_detail_screen.dart';
import '../expenses/expense_entry_screen.dart';
import 'customer_invoice_signature_screen.dart';
import 'invoice_warranty_panel.dart';
import 'job_detail_screen.dart';

class JobDocumentScreen extends StatefulWidget {
  const JobDocumentScreen({
    super.key,
    required this.businessId,
    required this.documentId,
    required this.isOwner,
    this.canManageExpenses = false,
    this.initialAction,
  });

  final String businessId;
  final String documentId;
  final bool isOwner;
  final bool canManageExpenses;
  final String? initialAction;

  @override
  State<JobDocumentScreen> createState() => _JobDocumentScreenState();
}

class _JobDocumentScreenState extends State<JobDocumentScreen> {
  static const _api = BriskersApi();
  final _localCatalog = LocalCatalogRepository();
  final _catalogSync = CatalogSyncService();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _workspaceHeaderController = ScrollController();
  final GlobalKey _workspaceHeaderKey = GlobalKey();
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _notesFocusNode = FocusNode();

  Map<String, dynamic>? _detail;
  Map<String, dynamic> _identifixMeta = const {};
  Map<String, dynamic> _warrantyDetail = const {};
  Map<String, dynamic> _signatureStatus = const {};
  Map<String, dynamic> _submissionReadiness = const {};
  List<Map<String, dynamic>> _invoiceStyles = const [];
  List<Map<String, dynamic>> _openFindings = const [];
  num _defaultTaxRate = 0;
  bool _loading = true;
  bool _busy = false;
  bool _initialActionHandled = false;
  bool _notesDirty = false;
  String? _error;

  bool get _estimate => _detail?['kind']?.toString() == 'estimate';
  bool get _converted => _detail?['converted'] == true;
  bool get _readOnly => _estimate && _converted;
  bool get _canManageInvoiceExpenses =>
      widget.isOwner || widget.canManageExpenses;

  Color get _accent =>
      _estimate ? BriskersColors.estimates : BriskersColors.jobs;

  Color get _documentActionColor =>
      _estimate ? BriskersColors.estimates : BriskersColors.invoices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _workspaceHeaderController.dispose();
    _notesController.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  Future<void> _collapseWorkspaceHeader() async {
    if (!_workspaceHeaderController.hasClients) return;

    final headerContext = _workspaceHeaderKey.currentContext;
    final headerBox = headerContext?.findRenderObject() as RenderBox?;
    final headerHeight = headerBox?.size.height ?? 0;
    if (headerHeight <= 0) return;

    final position = _workspaceHeaderController.position;
    final target = headerHeight.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    // Only collapse the shared header. Never use maxScrollExtent here:
    // NestedScrollView's max extent also includes the active tab's content.
    if (position.pixels >= target - 0.5) return;

    await _workspaceHeaderController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  bool _findingNeedsInvoiceAttention(
    Map<String, dynamic> finding, {
    Map<String, dynamic>? detail,
  }) {
    final status = finding['status']?.toString() ?? 'open';
    if (status == 'resolved') return false;

    final document = detail ?? _detail;
    final invoiceJobId = document?['job_id']?.toString() ?? '';
    final repairJobId = finding['repair_job_id']?.toString() ?? '';

    // A finding assigned to this same job is already being addressed here.
    // It remains technically "in_job" until the job is completed, but it
    // should not be shown as a red unresolved warning on this invoice.
    if (status == 'in_job' &&
        invoiceJobId.isNotEmpty &&
        repairJobId == invoiceJobId) {
      return false;
    }

    return true;
  }

  Future<void> _load() async {
    try {
      final detail = await _api.documentDetail(
        widget.businessId,
        widget.documentId,
      );
      final taxSettings = await _api.taxSettings(widget.businessId);
      List<Map<String, dynamic>> invoiceStyles = const [];
      List<Map<String, dynamic>> openFindings = const [];
      Map<String, dynamic> warrantyDetail = const {};
      Map<String, dynamic> signatureStatus = const {};
      Map<String, dynamic> submissionReadiness = const {};
      if (detail['kind']?.toString() == 'invoice') {
        invoiceStyles = await _api.invoiceStatusStyles(widget.businessId);
        try {
          warrantyDetail = await _api.documentWarrantyDetail(
            widget.businessId,
            widget.documentId,
          );
        } catch (_) {
          warrantyDetail = const {};
        }
        try {
          signatureStatus = await _api.documentSignatureStatus(
            widget.businessId,
            widget.documentId,
          );
        } catch (_) {
          signatureStatus = const {};
        }
        try {
          submissionReadiness = await _api.warrantySubmissionReadiness(
            widget.businessId,
            widget.documentId,
          );
        } catch (_) {
          submissionReadiness = const {};
        }
        final vehicleId = detail['vehicle_id']?.toString() ?? '';
        if (vehicleId.isNotEmpty) {
          try {
            final findings = await _api.vehicleFindings(
              widget.businessId,
              vehicleId,
              includeResolved: false,
            );
            openFindings = findings
                .where(
                  (finding) => _findingNeedsInvoiceAttention(
                    finding,
                    detail: detail,
                  ),
                )
                .toList();
          } catch (_) {
            openFindings = const [];
          }
        }
      }

      Map<String, dynamic> identifixMeta = const {};
      if (detail['kind']?.toString() == 'estimate') {
        try {
          identifixMeta = await _api.identifixPricingStatus(
            widget.businessId,
            widget.documentId,
          );
        } catch (_) {
          identifixMeta = const {};
        }
      }

      if (!mounted) return;
      setState(() {
        _detail = detail;
        if (!_notesDirty && !_notesFocusNode.hasFocus) {
          _notesController.text = detail['memo']?.toString() ?? '';
        }
        _identifixMeta = identifixMeta;
        _warrantyDetail = warrantyDetail;
        _signatureStatus = signatureStatus;
        _submissionReadiness = submissionReadiness;
        _invoiceStyles = invoiceStyles;
        _openFindings = openFindings;
        _defaultTaxRate =
            num.tryParse(taxSettings['sales_tax_rate']?.toString() ?? '') ?? 0;
        _loading = false;
        _error = null;
      });
      if (!_initialActionHandled &&
          (widget.initialAction?.trim().isNotEmpty ?? false)) {
        _initialActionHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runInitialAction(widget.initialAction!);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  int get _version =>
      int.tryParse(_detail?['row_version']?.toString() ?? '') ?? 1;

  num _number(Object? raw) => num.tryParse(raw?.toString() ?? '') ?? 0;

  String _money(Object? raw) =>
      NumberFormat.currency(symbol: '\$').format(_number(raw));

  bool _warrantyPaymentProcessed() {
    if (_warrantyDetail['extended_warranty'] != true) return false;

    final terminalAmount = _number(_warrantyDetail['terminal_amount']);
    if (terminalAmount <= 0.005) return false;

    final surchargeRate = _number(_warrantyDetail['surcharge_rate']);
    final usesCheck = surchargeRate <= 0.000001;
    final payments = List<dynamic>.from(_detail?['payments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map));

    return payments.any((payment) {
      final amount = _number(payment['amount']);
      final method =
          payment['payment_method_name']?.toString().trim().toLowerCase() ?? '';
      final amountMatches = (amount - terminalAmount).abs() < 0.005;
      final methodMatches = usesCheck
          ? method == 'check' || method.contains('check')
          : method == 'credit card' ||
              (method.contains('credit') && method.contains('card'));
      return amountMatches && methodMatches;
    });
  }

  String _paymentDate(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '';
    return DateFormat('MMM d, yyyy  h:mm a').format(parsed.toLocal());
  }

  Future<void> _runInitialAction(String action) async {
    switch (action) {
      case 'edit':
        await _editDocumentHeader();
        break;
      case 'copy':
        await _copyInvoice();
        break;
      case 'add_expense':
        await _addInvoiceExpense();
        break;
      case 'expenses':
        await _showInvoiceExpenses();
        break;
      case 'payment':
        await _enterPayment();
        break;
      case 'findings':
        await _showInvoiceFindings();
        break;
      case 'job':
        await _openLinkedJob();
        break;
      case 'preview':
        await _previewPdf();
        break;
      case 'send':
        await _showSendMenu();
        break;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>?> _translateManualEntry(
    Map<String, dynamic> input, {
    bool translateName = true,
    bool translateDescription = true,
  }) async {
    if (!BriskersLanguageController.instance.isSpanish) {
      return input;
    }

    final keys = <String>[];
    final texts = <String>[];

    void addField(String key, bool enabled) {
      if (!enabled) return;
      final value = input[key]?.toString() ?? '';
      keys.add(key);
      texts.add(value);
    }

    addField('name', translateName);
    addField('description', translateDescription);

    if (texts.isEmpty) return input;

    try {
      final translated = await _api.translateManualDocumentText(
        widget.businessId,
        texts,
      );
      if (translated.length != texts.length) {
        throw Exception('Translation result was incomplete.');
      }

      final result = Map<String, dynamic>.from(input);
      for (var index = 0; index < keys.length; index++) {
        final value = translated[index].trim();
        result[keys[index]] = value.isEmpty ? null : value;
      }
      return result;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _error =
            'Could not translate the Spanish text to English. Please try again.\n$error';
      });
      return null;
    }
  }

  Future<String?> _translateManualNote(String value) async {
    if (!BriskersLanguageController.instance.isSpanish ||
        value.trim().isEmpty) {
      return value;
    }

    try {
      final translated = await _api.translateManualDocumentText(
        widget.businessId,
        [value],
      );
      if (translated.isEmpty) {
        throw Exception('Translation result was empty.');
      }
      return translated.first.trim();
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _error =
            'Could not translate the Spanish note to English. Please try again.\n$error';
      });
      return null;
    }
  }

  Future<void> _addInvoiceExpense() async {
    if (_estimate || !_canManageInvoiceExpenses || _detail == null) return;
    final number = _detail!['document_number']?.toString().trim() ?? '';
    final jobId = _detail!['job_id']?.toString();
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEntryScreen(
          businessId: widget.businessId,
          jobId: jobId == null || jobId.isEmpty ? null : jobId,
          documentId: widget.documentId,
          contextLabel: number.isEmpty ? 'This invoice' : 'Invoice #$number',
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _showInvoiceExpenses() async {
    if (_estimate || !_canManageInvoiceExpenses) return;
    try {
      final expenses = await _api.documentExpenses(
        widget.businessId,
        widget.documentId,
      );
      if (!mounted) return;

      if (expenses.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('No related expenses'),
            content: Text(
              (_detail?['job_number']?.toString() ?? '').isEmpty
                  ? 'There are no expenses or credits linked to this invoice yet.'
                  : 'There are no expenses or credits linked to this invoice '
                      'or its job yet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.expenses,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _addInvoiceExpense();
                },
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Add expense'),
              ),
            ],
          ),
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (_detail?['job_number']?.toString() ?? '').isEmpty
                              ? tr('invoiceExpensesCredits')
                              : tr('jobInvoiceExpenses'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _addInvoiceExpense();
                        },
                        icon: const Icon(Icons.add_card_outlined),
                        label: Text(tr('add')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                    itemCount: expenses.length,
                    itemBuilder: (context, index) {
                      final expense = expenses[index];
                      final id = expense['id']?.toString() ?? '';
                      final vendor =
                          expense['vendor']?.toString() ?? 'Expense';
                      final category =
                          expense['category']?.toString() ?? '';
                      final date =
                          expense['transaction_date']?.toString() ?? '';
                      final scope =
                          expense['scope']?.toString() ?? 'invoice';
                      final jobNumber =
                          expense['job_number']?.toString() ?? '';
                      final scopeLabel = scope == 'invoice'
                          ? tr('invoiceLinked')
                          : (jobNumber.isEmpty
                              ? tr('jobExpense')
                              : '${tr('jobLabel')} $jobNumber');
                      final receiptCount = int.tryParse(
                            expense['receipt_count']?.toString() ?? '',
                          ) ??
                          0;
                      final income =
                          expense['direction']?.toString() == 'income';
                      final directionColor = income
                          ? const Color(0xFF169B62)
                          : const Color(0xFFC62828);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: id.isEmpty
                              ? null
                              : () async {
                                  Navigator.pop(sheetContext);
                                  await Navigator.push<void>(
                                    this.context,
                                    MaterialPageRoute(
                                      builder: (_) => ExpenseDetailScreen(
                                        businessId: widget.businessId,
                                        transactionId: id,
                                      ),
                                    ),
                                  );
                                  await _load();
                                },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      directionColor.withValues(alpha: 0.10),
                                  child: Icon(
                                    income
                                        ? Icons.south_west
                                        : Icons.north_east,
                                    color: directionColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vendor,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        <String>[
                                          scopeLabel,
                                          if (category.isNotEmpty) category,
                                          if (date.isNotEmpty) date,
                                        ].join(' • '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${income ? '+' : '-'}${_money(expense['amount'])}',
                                      style: TextStyle(
                                        fontSize: 17.5,
                                        fontWeight: FontWeight.w900,
                                        color: directionColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (receiptCount > 0) ...[
                                          Icon(
                                            Icons.photo_outlined,
                                            size: 17,
                                            color: directionColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$receiptCount',
                                            style: TextStyle(
                                              color: directionColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 21,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _addCatalogItem() async {
    if (_readOnly) return;

    List<Map<String, dynamic>> items;
    try {
      await _catalogSync.ensureBootstrap(widget.businessId);
      items = await _localCatalog.items(
        widget.businessId,
        includeInactive: false,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final controller = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(items);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> filter(String value) async {
              final results = await _localCatalog.items(
                widget.businessId,
                search: value.trim().isEmpty ? null : value,
                includeInactive: false,
              );
              if (!sheetContext.mounted) return;
              setSheetState(() {
                filtered = results;
              });
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: filter,
                        decoration: InputDecoration(
                          labelText: tr('searchItems'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(tr('noMatchingItems')))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        _accent.withValues(alpha: 0.12),
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      color: _accent,
                                    ),
                                  ),
                                  title: Text(
                                    item['name']?.toString() ?? '',
                                  ),
                                  subtitle: Text(
                                    <String>[
                                      if ((item['category']?.toString() ?? '')
                                          .isNotEmpty)
                                        item['category'].toString(),
                                      _money(item['selling_price']),
                                    ].join(' • '),
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;

    final line = <String, dynamic>{
      'name': selected['name']?.toString() ?? 'Item',
      'description': selected['description']?.toString(),
      'quantity': 1,
      'unit_price': _number(selected['selling_price']),
      'tax_rate': selected['taxable'] == true ? _defaultTaxRate : 0,
      'line_kind': 'item',
    };

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditLineDialog(
        line: line,
        accent: _documentActionColor,
        title: 'Add item to invoice',
        saveLabel: 'Add to Invoice',
        lockCatalogFields: true,
        clearNumericOnFirstTap: true,
      ),
    );
    if (result == null) return;
    final translatedResult = await _translateManualEntry(
      result,
      translateName: false,
    );
    if (translatedResult == null) return;

    await _run(() async {
      await _api.addDocumentLine(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: translatedResult['name'].toString(),
        description: translatedResult['description']?.toString(),
        itemId: selected['id']?.toString(),
        quantity: translatedResult['quantity'] as num,
        unitPrice: translatedResult['unit_price'] as num,
        taxRate: translatedResult['tax_rate'] as num,
        lineKind: translatedResult['line_kind'].toString(),
      );
    });
  }

  Future<void> _addCustomLine() async {
    if (_readOnly) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomLineDialog(
        defaultTaxRate: _defaultTaxRate,
        accent: _documentActionColor,
      ),
    );
    if (result == null) return;
    final translatedResult = await _translateManualEntry(result);
    if (translatedResult == null) return;

    await _run(() async {
      await _api.addDocumentLine(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: translatedResult['name'].toString(),
        description: translatedResult['description']?.toString(),
        quantity: translatedResult['quantity'] as num,
        unitPrice: translatedResult['unit_price'] as num,
        taxRate: translatedResult['tax_rate'] as num,
        lineKind: translatedResult['line_kind'].toString(),
      );
    });
  }

  Future<void> _editLine(Map<String, dynamic> line) async {
    if (_readOnly) return;

    if (line['line_kind']?.toString() == 'discount') {
      await _editDiscount(line);
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditLineDialog(
        line: line,
        accent: _documentActionColor,
        title: tr('editInvoiceItem'),
        saveLabel: tr('saveChanges'),
        lockCatalogFields: line['item_id'] != null,
      ),
    );
    if (result == null) return;
    final translatedResult = await _translateManualEntry(result);
    if (translatedResult == null) return;

    await _run(() async {
      await _api.updateDocumentLineV2(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
        name: translatedResult['name'].toString(),
        quantity: translatedResult['quantity'] as num,
        unitPrice: translatedResult['unit_price'] as num,
        taxRate: translatedResult['tax_rate'] as num,
        description: translatedResult['description']?.toString(),
        lineKind: translatedResult['line_kind'].toString(),
      );
    });
  }

  Future<void> _addDiscount() async {
    if (_readOnly) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DiscountDialog(
        accent: _documentActionColor,
      ),
    );
    if (result == null) return;
    final translatedResult = await _translateManualEntry(result);
    if (translatedResult == null) return;

    await _run(() async {
      await _api.addDocumentDiscount(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        name: translatedResult['name'].toString(),
        method: translatedResult['method'].toString(),
        value: translatedResult['value'] as num,
        timing: translatedResult['timing'].toString(),
        description: translatedResult['description']?.toString(),
      );
    });
  }

  Future<void> _editDiscount(Map<String, dynamic> line) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DiscountDialog(
        line: line,
        accent: _documentActionColor,
      ),
    );
    if (result == null) return;
    final translatedResult = await _translateManualEntry(result);
    if (translatedResult == null) return;

    await _run(() async {
      await _api.updateDocumentDiscount(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
        name: translatedResult['name'].toString(),
        method: translatedResult['method'].toString(),
        value: translatedResult['value'] as num,
        timing: translatedResult['timing'].toString(),
        description: translatedResult['description']?.toString(),
      );
    });
  }

  Future<void> _deleteLine(Map<String, dynamic> line) async {
    if (_readOnly) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove line?'),
        content: Text(
          'Remove "${line['name'] ?? 'this item'}" from the document?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(tr('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      await _api.deleteDocumentLine(
        widget.businessId,
        line['id'].toString(),
        expectedVersion: _version,
      );
    });
  }

  Future<void> _copyLine(Map<String, dynamic> line) async {
    if (_readOnly || _busy) return;
    await _run(() => _api.copyDocumentLine(
          widget.businessId,
          line['id'].toString(),
          expectedVersion: _version,
        ));
  }

  Future<void> _moveLine(
    Map<String, dynamic> line,
    String direction,
  ) async {
    if (_readOnly || _busy) return;
    await _run(() => _api.moveDocumentLine(
          widget.businessId,
          line['id'].toString(),
          expectedVersion: _version,
          direction: direction,
        ));
  }

  Future<void> _showLineActions(
    Map<String, dynamic> line, {
    required bool canMoveUp,
    required bool canMoveDown,
  }) async {
    if (_readOnly || _busy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit item'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy item'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              enabled: canMoveUp,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Move up'),
              onTap: canMoveUp
                  ? () => Navigator.pop(sheetContext, 'up')
                  : null,
            ),
            ListTile(
              enabled: canMoveDown,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Move down'),
              onTap: canMoveDown
                  ? () => Navigator.pop(sheetContext, 'down')
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete item'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') await _editLine(line);
    if (action == 'copy') await _copyLine(line);
    if (action == 'up') await _moveLine(line, 'up');
    if (action == 'down') await _moveLine(line, 'down');
    if (action == 'delete') await _deleteLine(line);
  }

  Future<Map<String, dynamic>?> _preparePdf() async {
    final lines = List<dynamic>.from(_detail?['lines'] ?? const []);
    if (lines.isEmpty) {
      setState(() => _error = 'Add at least one item before creating a PDF.');
      return null;
    }

    try {
      final currentStatus = _detail?['status']?.toString() ?? 'draft';
      final currentNumber =
          _detail?['document_number']?.toString().trim() ?? '';
      if (currentStatus == 'draft' || currentNumber.isEmpty) {
        await _api.issueDocument(
          widget.businessId,
          widget.documentId,
          expectedVersion: _version,
        );
      }
      final detail = await _api.documentDetail(
        widget.businessId,
        widget.documentId,
      );
      if (!_estimate) {
        final warranty = await _api.documentWarrantyDetail(
          widget.businessId,
          widget.documentId,
        );
        detail.addAll(warranty);

        final signature = await _api.documentSignatureStatus(
          widget.businessId,
          widget.documentId,
        );
        final bucket = signature['bucket']?.toString() ?? '';
        final key = signature['key']?.toString() ?? '';
        if (signature['is_current'] == true &&
            bucket.isNotEmpty &&
            key.isNotEmpty) {
          detail['signature_bytes'] =
              await _api.downloadAttachment(bucket, key);
          detail['signer_name'] = signature['signer_name'];
          detail['signed_at'] = signature['signed_at'];
          detail['signature_current'] = true;
        }

        if (mounted) {
          setState(() {
            _detail = detail;
            _warrantyDetail = warranty;
            _signatureStatus = signature;
          });
        }
      } else if (mounted) {
        setState(() => _detail = detail);
      }
      return detail;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    }
  }

  Future<void> _previewPdf() async {
    final detail = await _preparePdf();
    if (detail == null || !mounted) return;

    try {
      final bytes = await DocumentPdfService.build(detail);
      if (!mounted) return;

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              backgroundColor: _accent.withValues(alpha: 0.10),
              title: Text(_estimate ? 'Estimate PDF' : 'Invoice PDF'),
            ),
            body: PdfPreview(
              build: (format) async => bytes,
              pdfFileName: DocumentPdfService.fileName(detail),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not create the PDF preview. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the PDF preview.'),
        ),
      );
    }
  }

  Future<void> _printPdf() async {
    final detail = await _preparePdf();
    if (detail == null) return;
    final bytes = await DocumentPdfService.build(detail);
    await Printing.layoutPdf(
      name: DocumentPdfService.fileName(detail),
      onLayout: (format) async => bytes,
    );
  }

  Future<void> _sharePdf() async {
    final detail = await _preparePdf();
    if (detail == null) return;
    final bytes = await DocumentPdfService.build(detail);
    await Printing.sharePdf(
      bytes: bytes,
      filename: DocumentPdfService.fileName(detail),
    );
  }

  Future<void> _convertEstimate() async {
    if (!_estimate || _converted) return;

    final lines = List<dynamic>.from(_detail?['lines'] ?? const []);
    if (lines.isEmpty) {
      setState(() => _error = 'Add at least one item before creating an invoice.');
      return;
    }

    String? invoiceId;
    await _run(() async {
      invoiceId = await _api.convertEstimate(
        widget.businessId,
        widget.documentId,
      );
    });

    if (!mounted || invoiceId == null) return;
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId!,
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _paymentMethods() async {
    final options = await _api.paymentOptions(widget.businessId);
    return List<dynamic>.from(options['methods'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<void> _enterPayment() async {
    await _collapseWorkspaceHeader();
    if (_estimate) return;

    List<Map<String, dynamic>> methods;
    try {
      methods = await _paymentMethods();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;
    if (methods.isEmpty) {
      setState(() => _error = 'No payment methods are configured.');
      return;
    }

    final finalized = _number(_detail?['paid_amount']);
    final pending = _number(_detail?['pending_payment']);
    final total = _number(_detail?['total_amount']);
    final remaining = total - finalized - pending;
    if (remaining <= 0.005) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentEntryDialog(
        methods: methods,
        initialAmount: remaining,
        title: tr('addPayment'),
        saveLabel: tr('addPayment'),
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.addPendingInvoicePayment(
        widget.businessId,
        widget.documentId,
        amount: result['amount'] as num,
        methodId: result['method_id'].toString(),
      );
    });
  }

  Future<void> _enterWarrantyPayment() async {
    await _collapseWorkspaceHeader();
    if (_estimate || _warrantyDetail['extended_warranty'] != true || _busy) {
      return;
    }

    List<Map<String, dynamic>> methods;
    try {
      methods = await _paymentMethods();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted || methods.isEmpty) {
      if (mounted) setState(() => _error = tr('warrantyPaymentMethodMissing'));
      return;
    }

    final finalized = _number(_detail?['paid_amount']);
    final pending = _number(_detail?['pending_payment']);
    final total = _number(_detail?['total_amount']);
    final remaining = total - finalized - pending;
    if (remaining <= 0.005) return;

    final warrantyNet = _number(_warrantyDetail['terminal_amount']);
    if (warrantyNet <= 0.005) return;

    final amount = warrantyNet > remaining ? remaining : warrantyNet;
    final surchargeRate = _number(_warrantyDetail['surcharge_rate']);
    final wantsCheck = surchargeRate <= 0.000001;

    Map<String, dynamic>? method;
    for (final candidate in methods) {
      final name = candidate['name']?.toString().trim().toLowerCase() ?? '';
      final matches = wantsCheck
          ? name == 'check' || name.contains('check')
          : name == 'credit card' ||
              (name.contains('credit') && name.contains('card'));
      if (matches) {
        method = candidate;
        break;
      }
    }

    if (method == null) {
      setState(() => _error = tr('warrantyPaymentMethodMissing'));
      return;
    }

    await _run(() async {
      await _api.addPendingInvoicePayment(
        widget.businessId,
        widget.documentId,
        amount: amount,
        methodId: method!['id'].toString(),
      );
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('warrantyPaymentApplied'))),
    );
  }

  Future<void> _showPaymentContextMenu(
    Map<String, dynamic> payment,
  ) async {
    if (_busy || payment['state']?.toString() != 'pending') return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('editPayment')),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            if (widget.isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(tr('removePayment')),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editPayment(payment);
    } else if (action == 'remove') {
      await _deletePayment(payment);
    }
  }

  Future<void> _editPayment(Map<String, dynamic> payment) async {
    if (_estimate || payment['state']?.toString() != 'pending') return;

    List<Map<String, dynamic>> methods;
    try {
      methods = await _paymentMethods();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted || methods.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentEntryDialog(
        methods: methods,
        initialAmount: _number(payment['amount']),
        initialMethodId: payment['payment_method_id']?.toString(),
        title: tr('editPayment'),
        saveLabel: tr('saveChanges'),
      ),
    );
    if (result == null) return;

    await _run(() async {
      await _api.updatePendingInvoicePayment(
        widget.businessId,
        payment['id'].toString(),
        amount: result['amount'] as num,
        methodId: result['method_id'].toString(),
      );
    });
  }

  Future<void> _deletePayment(Map<String, dynamic> payment) async {
    if (!widget.isOwner ||
        _estimate ||
        payment['state']?.toString() != 'pending') {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("${tr('removePayment')}?"),
        content: Text(
          'Remove the ${_money(payment['amount'])} '
          '${payment['payment_method_name'] ?? 'payment'} entry?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() => _api.deletePendingInvoicePayment(
          widget.businessId,
          payment['id'].toString(),
        ));
  }

  Future<Map<String, dynamic>?> _pickInvoiceCustomer() async {
    final customers = await _api.customers(widget.businessId, limit: 200);
    if (!mounted) return null;
    var query = '';

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = customers.where((customer) {
            final name = customer['display_name']?.toString() ?? '';
            return query.isEmpty ||
                name.toLowerCase().contains(query.toLowerCase());
          }).toList();

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select customer',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search customers',
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final customer = visible[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer['display_name']?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (customer['problem_flag'] == true)
                                const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                  size: 18,
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${customer['vehicle_count'] ?? 0} vehicle(s)',
                          ),
                          onTap: () =>
                              Navigator.pop(sheetContext, customer),
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
  }

  Future<Map<String, dynamic>?> _pickInvoiceVehicle(
    String customerId,
  ) async {
    final detail = await _api.customerDetail(widget.businessId, customerId);
    final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (!mounted) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Select vehicle',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('No vehicle'),
              onTap: () => Navigator.pop(
                sheetContext,
                <String, dynamic>{'id': null},
              ),
            ),
            if (vehicles.isNotEmpty) const Divider(),
            ...vehicles.map((vehicle) {
              final label = <String>[
                if (vehicle['year'] != null) vehicle['year'].toString(),
                if ((vehicle['make']?.toString() ?? '').isNotEmpty)
                  vehicle['make'].toString(),
                if ((vehicle['model']?.toString() ?? '').isNotEmpty)
                  vehicle['model'].toString(),
              ].join(' ');

              return ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(label.isEmpty ? 'Vehicle' : label),
                subtitle: (vehicle['vin']?.toString() ?? '').isEmpty
                    ? null
                    : Text('VIN: ${vehicle['vin']}'),
                onTap: () => Navigator.pop(sheetContext, vehicle),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _vehicleLabel(Map<String, dynamic>? vehicle) {
    if (vehicle == null || vehicle['id'] == null) return '';
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      if ((vehicle['make']?.toString() ?? '').isNotEmpty)
        vehicle['make'].toString(),
      if ((vehicle['model']?.toString() ?? '').isNotEmpty)
        vehicle['model'].toString(),
    ].join(' ');
  }

  Future<void> _editDocumentHeader() async {
    if (_readOnly || _detail == null || _busy) return;

    var customerId = _detail!['customer_id']?.toString() ?? '';
    var customerName = _detail!['customer_name']?.toString() ?? '';
    String? vehicleId = _detail!['vehicle_id']?.toString();
    var vehicleName = _detail!['vehicle']?.toString() ?? '';
    var mileageText = _detail!['odometer_in']?.toString().trim() ?? '';
    final claimController = TextEditingController(
      text: _detail!['claim_number']?.toString() ?? '',
    );
    final authorizationController = TextEditingController(
      text: _detail!['authorization_number']?.toString() ?? '',
    );
    var date = DateTime.tryParse(
          _detail!['document_date']?.toString() ?? '',
        ) ??
        DateTime.now();

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      _estimate
                          ? 'Edit estimate details'
                          : 'Edit invoice details',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Customer'),
                  subtitle: Text(customerName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final customer = await _pickInvoiceCustomer();
                    if (customer == null) return;
                    final newId = customer['id']?.toString() ?? '';
                    if (newId.isEmpty) return;

                    final vehicle = await _pickInvoiceVehicle(newId);
                    setSheetState(() {
                      customerId = newId;
                      customerName =
                          customer['display_name']?.toString() ?? '';
                      vehicleId = vehicle?['id']?.toString();
                      vehicleName = _vehicleLabel(vehicle);
                      mileageText = vehicle?['mileage']?.toString().trim() ?? '';
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.directions_car_outlined),
                  title: const Text('Vehicle'),
                  subtitle: Text(
                    vehicleName.isEmpty ? 'No vehicle' : vehicleName,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: customerId.isEmpty
                      ? null
                      : () async {
                          final vehicle =
                              await _pickInvoiceVehicle(customerId);
                          if (vehicle == null) return;
                          setSheetState(() {
                            vehicleId = vehicle['id']?.toString();
                            vehicleName = _vehicleLabel(vehicle);
                            mileageText = vehicle['mileage']?.toString().trim() ?? '';
                          });
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('Mileage'),
                  subtitle: Text(
                    mileageText.isEmpty
                        ? 'Not entered'
                        : '${_quantity(mileageText)} mi',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: vehicleId == null || vehicleId!.isEmpty
                      ? null
                      : () async {
                          final controller = TextEditingController(
                            text: mileageText,
                          );
                          final saveMileage = await showDialog<bool>(
                            context: sheetContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Mileage'),
                              content: TextField(
                                controller: controller,
                                autofocus: true,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Current mileage',
                                  suffixText: 'mi',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: Text(tr('cancel')),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _documentActionColor,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          if (saveMileage == true) {
                            final raw = controller.text
                                .replaceAll(',', '')
                                .trim();
                            if (raw.isEmpty || num.tryParse(raw) != null) {
                              setSheetState(() => mileageText = raw);
                            } else if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter valid mileage.'),
                                ),
                              );
                            }
                          }
                          controller.dispose();
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Date'),
                  subtitle: Text(
                    DateFormat('MMM d, yyyy').format(date),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: sheetContext,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) {
                      setSheetState(() => date = selected);
                    }
                  },
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: claimController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Claim number',
                    prefixIcon: Icon(Icons.assignment_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: authorizationController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Authorization number',
                    prefixIcon: Icon(Icons.verified_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if ((_detail!['job_number']?.toString() ?? '').isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Changing the customer or vehicle will detach this document from its current Job.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _documentActionColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: customerId.isEmpty
                        ? null
                        : () => Navigator.pop(sheetContext, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final newClaimNumber = claimController.text.trim();
    final newAuthorizationNumber = authorizationController.text.trim();
    claimController.dispose();
    authorizationController.dispose();

    if (save != true) return;

    final originalCustomerId = _detail!['customer_id']?.toString() ?? '';
    final originalVehicleId = _detail!['vehicle_id']?.toString();
    final originalDate = DateTime.tryParse(
      _detail!['document_date']?.toString() ?? '',
    );
    final originalMileage =
        _detail!['odometer_in']?.toString().replaceAll(',', '').trim() ?? '';
    final newMileage = mileageText.replaceAll(',', '').trim();
    final originalClaimNumber =
        _detail!['claim_number']?.toString().trim() ?? '';
    final originalAuthorizationNumber =
        _detail!['authorization_number']?.toString().trim() ?? '';

    final headerChanged =
        customerId != originalCustomerId ||
        vehicleId != originalVehicleId ||
        originalDate == null ||
        DateUtils.dateOnly(originalDate) != DateUtils.dateOnly(date);

    if (headerChanged) {
      await _run(() async {
        await _api.updateDocumentHeader(
          widget.businessId,
          widget.documentId,
          expectedVersion: _version,
          customerId: customerId,
          vehicleId: vehicleId,
          documentDate: date,
        );
      });

      if (_detail == null ||
          _detail!['customer_id']?.toString() != customerId ||
          _detail!['vehicle_id']?.toString() != vehicleId) {
        if (mounted) {
          setState(() {
            _error =
                'The invoice customer/vehicle change did not persist. Please try again.';
          });
        }
        return;
      }
    }

    if (newMileage != originalMileage) {
      await _run(() async {
        await _api.updateDocumentMileage(
          widget.businessId,
          widget.documentId,
          odometer: newMileage.isEmpty ? null : num.tryParse(newMileage),
        );
      });
    }

    if (newClaimNumber != originalClaimNumber ||
        newAuthorizationNumber != originalAuthorizationNumber) {
      await _run(() async {
        await _api.updateDocumentClaimInfo(
          widget.businessId,
          widget.documentId,
          expectedVersion: _version,
          claimNumber: newClaimNumber.isEmpty ? null : newClaimNumber,
          authorizationNumber:
              newAuthorizationNumber.isEmpty ? null : newAuthorizationNumber,
        );
      });
    }

    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice details updated.')),
      );
    }
  }

  Future<void> _copyInvoice() async {
    if (_estimate || _detail == null || _busy) return;

    var copyNotes = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Copy invoice?'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Copy invoice notes'),
            value: copyNotes,
            onChanged: (value) =>
                setDialogState(() => copyNotes = value == true),
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
              child: const Text('Copy invoice'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    String? newId;
    await _run(() async {
      newId = await _api.copyInvoice(
        widget.businessId,
        widget.documentId,
        copyNotes: copyNotes,
      );
    });

    if (!mounted || newId == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: newId!,
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
          initialAction: 'edit',
        ),
      ),
    );
  }

  Future<void> _deleteOrVoidInvoice() async {
    if (!widget.isOwner || _estimate || _detail == null || _busy) return;

    final finalizedPaid = _number(_detail!['paid_amount']);
    final pendingPaid = _number(_detail!['pending_payment']);

    if (finalizedPaid > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paid invoice'),
          content: const Text(
            'This invoice has finalized payment activity, so it cannot be deleted or reused. Use the correction/reversal workflow if it needs to be changed.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('ok')),
            ),
          ],
        ),
      );
      return;
    }

    if (pendingPaid > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Payments entered'),
          content: const Text(
            'Remove the entered payments first. Once there are no payments on this invoice, it can be reassigned or deleted.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _documentActionColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: const Text(
          'This invoice has no finalized payment. It will be deleted and its invoice number can be reused, even if it was previously previewed, printed, emailed, or shown to the customer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete invoice'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() {
        _busy = true;
        _error = null;
      });

      await _api.deleteDraftInvoice(
        widget.businessId,
        widget.documentId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEstimate() async {
    if (!widget.isOwner || !_estimate || _detail == null || _busy) return;

    if (_converted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Converted estimate'),
          content: const Text(
            'This estimate was converted to an invoice and is kept as part '
            'of that invoice history, so it cannot be deleted.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _documentActionColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final number = _detail!['document_number']?.toString().trim() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete estimate?'),
        content: Text(
          number.isEmpty
              ? 'This estimate will be permanently deleted.'
              : 'Estimate #$number will be permanently deleted and its '
                  'number can be reused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete estimate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() {
        _busy = true;
        _error = null;
      });

      await _api.deleteEstimate(
        widget.businessId,
        widget.documentId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Estimate could not be deleted'),
            content: Text(error.toString()),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _documentActionColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _findingMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addInvoiceFinding() async {
    if (_estimate || _detail == null || _busy) return;

    final vehicleId = _detail!['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      setState(() => _error = 'Select a vehicle before adding a finding.');
      return;
    }

    final controller = TextEditingController();
    var includeOnInvoice = true;
    final photos = <XFile>[];

    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add vehicle finding',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Finding',
                      hintText: 'Describe the issue found during service',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include on invoice notes'),
                    value: includeOnInvoice,
                    onChanged: (value) => setSheetState(
                      () => includeOnInvoice = value == true,
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        photos.length == 1
                            ? '1 photo selected'
                            : '${photos.length} photos selected',
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _picker.pickMultiImage(
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (picked.isNotEmpty) {
                              setSheetState(() => photos.addAll(picked));
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final photo = await _picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 88,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (photo != null) {
                              setSheetState(() => photos.add(photo));
                            }
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _documentActionColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                      child: const Text('Add finding'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final body = controller.text.trim();
    controller.dispose();
    if (save != true || body.isEmpty) return;

    await _run(() async {
      final findingId = await _api.createInvoiceFinding(
        widget.businessId,
        widget.documentId,
        body: body,
        includeOnInvoice: includeOnInvoice,
      );

      for (final photo in photos) {
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _findingMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }
    });
  }

  Future<void> _showInvoiceFindings() async {
    if (_estimate || _detail == null || _busy) return;

    final vehicleId = _detail!['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      setState(() => _error = 'Select a vehicle before viewing findings.');
      return;
    }

    List<Map<String, dynamic>> findings;
    try {
      final allFindings = await _api.vehicleFindings(
        widget.businessId,
        vehicleId,
        includeResolved: false,
      );
      findings = allFindings
          .where(_findingNeedsInvoiceAttention)
          .toList();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vehicle findings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add finding',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _addInvoiceFinding();
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: findings.isEmpty
                    ? const Center(
                        child: Text(
                          'No open findings need attention on this invoice.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: findings.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final finding = findings[index];
                          final sourceJob =
                              finding['found_job_number']?.toString() ?? '';
                          final sourceInvoice =
                              finding['found_document_number']?.toString() ??
                                  '';

                          return ListTile(
                            leading: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.deepOrange,
                            ),
                            title: Text(
                              finding['body']?.toString() ?? '',
                            ),
                            subtitle: Text(
                              sourceInvoice.isNotEmpty
                                  ? 'Found on Invoice #$sourceInvoice'
                                  : sourceJob.isNotEmpty
                                      ? 'Found on Job $sourceJob'
                                      : 'Open finding',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                Navigator.pop(sheetContext);
                                await _run(() =>
                                    _api.resolveVehicleFindingByInvoice(
                                      widget.businessId,
                                      finding['id'].toString(),
                                      widget.documentId,
                                    ));
                              },
                              child: const Text('Resolve'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _emailPdf() async {
    await _sharePdf();
  }

  Future<void> _showSendMenu() async {
    if (_busy) return;
    final number = _detail?['document_number']?.toString().trim() ?? '';
    final label = _estimate ? 'Estimate' : 'Invoice';

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(
                    number.isEmpty ? 'Send $label' : 'Send $label #$number',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!_estimate &&
                  _warrantyDetail['extended_warranty'] == true)
                ListTile(
                  leading: const Icon(
                    Icons.shield_outlined,
                    color: BriskersColors.invoices,
                  ),
                  title: const Text(
                    'Submit to warranty company',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _submissionReadiness['ready'] == true
                        ? 'All required information is complete'
                        : 'Checks VIN, mileage, authorization and signature',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.pop(sheetContext, 'warranty_submit'),
                ),
              if (!_estimate &&
                  _warrantyDetail['extended_warranty'] == true)
                const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                subtitle: const Text('Send the PDF through an email app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'email'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Print PDF'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'print'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share PDF'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, 'share'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'warranty_submit') {
      await _prepareWarrantySubmission();
    }
    if (action == 'email') await _emailPdf();
    if (action == 'print') await _printPdf();
    if (action == 'share') await _sharePdf();
  }

  String _dateLabel(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    return DateFormat('MMM d, yyyy').format(parsed.toLocal());
  }

  String _quantity(Object? raw) {
    final value = _number(raw);
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(2);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  String _taxLabel(List<Map<String, dynamic>> lines) {
    final rates = lines
        .map((line) => _number(line['tax_rate']))
        .where((rate) => rate > 0)
        .toSet();
    if (rates.length != 1) return tr('tax');
    final percent = rates.single * 100;
    var value = percent.toStringAsFixed(2);
    while (value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    return '${tr('tax')} ($value%)';
  }

  Map<String, dynamic>? _invoiceStyle(String code) {
    for (final item in _invoiceStyles) {
      if (item['code']?.toString() == code) return item;
    }
    return null;
  }

  String _invoiceStatusCode({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
  }) {
    final rawStatus = _detail?['status']?.toString() ?? 'draft';
    if (rawStatus == 'void') return 'void';
    final shownPaid = finalizedPaid + pendingPaid;
    if (pendingPaid > 0 &&
        total > 0 &&
        shownPaid >= total - 0.005) {
      return 'pending_close';
    }
    if (total > 0 && finalizedPaid >= total - 0.005) return 'paid';
    if (shownPaid > 0) return 'partial';
    return 'open';
  }

  String _statusLabel({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
  }) {
    final rawStatus = _detail?['status']?.toString() ?? 'draft';
    if (_readOnly) return 'Converted';
    if (_estimate) {
      if (rawStatus == 'void') return tr('documentVoid');
      if (rawStatus == 'accepted') return tr('documentAccepted');
      if (rawStatus == 'declined') return tr('documentDeclined');
      if (rawStatus == 'expired') return tr('documentExpired');
      if (rawStatus == 'issued') return tr('documentIssued');
      return tr('documentDraft');
    }

    final code = _invoiceStatusCode(
      total: total,
      finalizedPaid: finalizedPaid,
      pendingPaid: pendingPaid,
    );
    if (BriskersLanguageController.instance.isSpanish) {
      switch (code) {
        case 'partial':
          return tr('invoicePartial');
        case 'pending_close':
          return tr('invoicePendingClose');
        case 'paid':
          return tr('invoicePaid');
        case 'void':
          return tr('documentVoid');
        default:
          return tr('invoiceOpen');
      }
    }

    final style = _invoiceStyle(code);
    if (style != null) return style['name']?.toString() ?? 'Open';
    switch (code) {
      case 'partial':
        return 'Partial';
      case 'pending_close':
        return 'Pending Close';
      case 'paid':
        return 'Paid';
      case 'void':
        return 'Void';
      default:
        return 'Open';
    }
  }

  Color _statusColor(String label, {String? code}) {
    if (!_estimate && code != null) {
      final style = _invoiceStyle(code);
      if (style != null) {
        return invoiceStatusColorFromHex(
          style['color_hex']?.toString(),
          fallback: BriskersColors.invoices,
        );
      }
    }

    switch (label) {
      case 'Accepted':
        return const Color(0xFF169B62);
      case 'Issued':
        return const Color(0xFF1976D2);
      case 'Void':
      case 'Declined':
      case 'Expired':
        return const Color(0xFFC62828);
      case 'Converted':
        return BriskersColors.estimates;
      default:
        return _accent;
    }
  }

  IconData _statusIcon(String label, {String? code}) {
    if (!_estimate && code != null) {
      final style = _invoiceStyle(code);
      if (style != null) {
        return invoiceStatusIcon(style['icon_key']?.toString());
      }
    }

    switch (label) {
      case 'Accepted':
        return Icons.check_circle;
      case 'Void':
      case 'Declined':
      case 'Expired':
        return Icons.cancel;
      case 'Converted':
        return Icons.transform;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _statusPill(String label, {String? code}) {
    final color = _statusColor(label, code: code);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(label, code: code), size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLinkedJob() async {
    final jobId = _detail?['job_id']?.toString() ?? '';
    if (jobId.isEmpty || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: jobId,
          roleCode: widget.isOwner ? 'owner' : 'office',
        ),
      ),
    );
    await _load();
  }

  Future<void> _openConvertedInvoice() async {
    final invoiceId = _detail?['converted_invoice_id']?.toString() ?? '';
    if (invoiceId.isEmpty || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: widget.isOwner,
          canManageExpenses: widget.canManageExpenses,
        ),
      ),
    );
    await _load();
  }

  Widget _convertedInvoiceBanner() {
    final invoiceNumber =
        _detail?['converted_invoice_number']?.toString().trim() ?? '';
    final convertedDate = _dateLabel(_detail?['converted_invoice_date']);
    final title = invoiceNumber.isEmpty
        ? 'Converted to Invoice'
        : 'Converted to Invoice #$invoiceNumber';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBEBD3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF159447),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Color(0xFF08752F),
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
                if (convertedDate.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Converted $convertedDate',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Color(0xFF405064),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _openConvertedInvoice,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF08752F),
              side: const BorderSide(color: Color(0xFF59B875)),
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 9,
              ),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text(
              'View',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _openFindingsBanner() {
    if (_estimate || _openFindings.isEmpty) {
      return const SizedBox.shrink();
    }

    final count = _openFindings.length;
    final firstBody = _openFindings.first['body']?.toString().trim() ?? '';
    final more = count > 1 ? count - 1 : 0;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: _busy ? null : _showInvoiceFindings,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 7),
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF4B7B2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFC62828),
                size: 23,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count OPEN FINDING${count == 1 ? '' : 'S'}',
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (firstBody.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        firstBody,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF26354D),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (more > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '+$more more open finding${more == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right,
                  color: Color(0xFFC62828),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _customerHeader() {
    final customer = _detail?['customer_name']?.toString().trim() ?? '';
    final phone = _detail?['customer_phone']?.toString().trim() ?? '';
    final vehicle = _detail?['vehicle']?.toString().trim() ?? '';
    final vin = _detail?['vehicle_vin']?.toString().trim() ?? '';
    final mileage = _detail?['odometer_in']?.toString().trim() ?? '';
    final date = _dateLabel(_detail?['document_date']);
    final job = _detail?['job_number']?.toString().trim() ?? '';

    Widget infoLine(
      IconData icon,
      String value, {
      bool bold = false,
      int maxLines = 2,
      VoidCallback? onTap,
      Color? valueColor,
      bool underline = false,
      bool problemFlag = false,
    }) {
      final line = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF26354D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.visible,
              softWrap: true,
              style: TextStyle(
                fontSize: bold ? 18 : 15,
                height: 1.2,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: valueColor ?? const Color(0xFF101827),
                decoration:
                    underline ? TextDecoration.underline : TextDecoration.none,
              ),
            ),
          ),
          if (problemFlag) ...[
            const SizedBox(width: 5),
            const Icon(Icons.flag, color: Colors.red, size: 19),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: valueColor ?? _accent,
            ),
          ],
        ],
      );

      return onTap == null
          ? line
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: line,
              ),
            );
    }

    final vehicleMileage = <String>[
      if (vehicle.isNotEmpty) vehicle,
      if (mileage.isNotEmpty) '${_quantity(mileage)} mi',
    ].join(' · ');

    final customerInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        infoLine(
          Icons.person_outline,
          customer.isEmpty ? 'Customer' : customer,
          bold: true,
          maxLines: 2,
          problemFlag: _detail?['customer_problem_flag'] == true,
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          infoLine(
            Icons.phone_outlined,
            formatUsPhone(phone),
            maxLines: 1,
          ),
        ],
        const SizedBox(height: 8),
        infoLine(
          Icons.directions_car_outlined,
          vehicleMileage.isEmpty ? 'No vehicle' : vehicleMileage,
          maxLines: 2,
        ),
        if (vin.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              'VIN: $vin',
              softWrap: true,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF405064),
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );

    final documentInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        infoLine(
          Icons.calendar_month_outlined,
          date.isEmpty
              ? '${tr('date')}: —'
              : '${tr('date')}: $date',
          maxLines: 2,
        ),
        const SizedBox(height: 7),
        infoLine(
          Icons.receipt_long_outlined,
          job.isEmpty ? '—' : '${tr('jobLabel')} $job',
          maxLines: 1,
          onTap: job.isEmpty ? null : _openLinkedJob,
          valueColor: job.isEmpty ? null : _accent,
          underline: job.isNotEmpty,
        ),
      ],
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 430) {
            final compactCustomer = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoLine(
                  Icons.person_outline,
                  customer.isEmpty ? 'Customer' : customer,
                  bold: true,
                  maxLines: 2,
                  problemFlag: _detail?['customer_problem_flag'] == true,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  infoLine(
                    Icons.phone_outlined,
                    formatUsPhone(phone),
                    maxLines: 1,
                  ),
                ],
              ],
            );

            final compactVehicle = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoLine(
                  Icons.directions_car_outlined,
                  vehicleMileage.isEmpty ? 'No vehicle' : vehicleMileage,
                  maxLines: 2,
                ),
                if (vin.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      'VIN: $vin',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF405064),
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: compactCustomer),
                    const SizedBox(width: 14),
                    Expanded(child: compactVehicle),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFD7E0E4)),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: infoLine(
                        Icons.calendar_month_outlined,
                        date.isEmpty ? '${tr('date')}: —' : date,
                        maxLines: 1,
                      ),
                    ),
                    if (job.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: infoLine(
                          Icons.receipt_long_outlined,
                          '${tr('jobLabel')} $job',
                          maxLines: 1,
                          onTap: _openLinkedJob,
                          valueColor: _accent,
                          underline: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: customerInfo),
              Container(
                width: 1,
                constraints: const BoxConstraints(minHeight: 92),
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: const Color(0xFFD7E0E4),
              ),
              Expanded(flex: 4, child: documentInfo),
            ],
          );
        },
      ),
    );
  }

  Widget _itemsTab(
    List<Map<String, dynamic>> lines, {
    required num shownPaid,
    required num balance,
  }) {
    final importLines = List<dynamic>.from(
      _identifixMeta['lines'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final importByLine = <String, Map<String, dynamic>>{
      for (final item in importLines)
        if ((item['line_id']?.toString() ?? '').isNotEmpty)
          item['line_id'].toString(): item,
    };
    final identifixImported =
        _identifixMeta['source_system']?.toString() == 'identifix';
    final verifiedCount = importLines
        .where((item) => item['verification_status'] == 'verified')
        .length;
    final updatedCount = importLines
        .where((item) => item['verification_status'] == 'updated')
        .length;
    final reviewCount = importLines
        .where(
          (item) =>
              item['verification_status'] == 'needs_review' ||
              item['verification_status'] == 'not_found',
        )
        .length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (identifixImported)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BriskersColors.estimates.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: BriskersColors.estimates.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    color: BriskersColors.estimates,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      <String>[
                        'Imported from Identifix',
                        if ((_identifixMeta['source_reference']?.toString() ?? '')
                            .isNotEmpty)
                          'Source #${_identifixMeta['source_reference']}',
                        '$verifiedCount verified',
                        if (updatedCount > 0) '$updatedCount updated',
                        if (reviewCount > 0) '$reviewCount needs review',
                      ].join(' • '),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            color: const Color(0xFFF2F6F7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('itemColumn'),
                    style: const TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    tr('qtyColumn'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    tr('amountColumn'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF405064),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('No items added yet.')),
            )
          else
            ...lines.map((line) {
              final description =
                  line['description']?.toString().trim() ?? '';
              final amount = _number(line['net_amount']);
              final importMeta =
                  importByLine[line['id']?.toString()] ?? const {};
              final partNumber =
                  importMeta['part_number']?.toString().trim() ?? '';
              final verification =
                  importMeta['verification_status']?.toString() ?? '';
              final dealerList = importMeta['dealer_list_price'];
              final importedPrice = importMeta['imported_unit_price'];
              return InkWell(
                onTap: _readOnly || _busy ? null : () => _editLine(line),
                onLongPress: _readOnly || _busy
                    ? null
                    : () => _showLineActions(
                          line,
                          canMoveUp:
                              line['position'] != lines.first['position'],
                          canMoveDown:
                              line['position'] != lines.last['position'],
                        ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE1E6E9)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0D1528),
                              ),
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.25,
                                  color: Color(0xFF405064),
                                ),
                              ),
                            ],
                            if (partNumber.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Part # $partNumber',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF405064),
                                ),
                              ),
                            ],
                            if (verification.isNotEmpty &&
                                verification != 'not_applicable') ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _PriceVerificationChip(status: verification),
                                  if (dealerList != null)
                                    Text(
                                      verification == 'updated' &&
                                              importedPrice != null
                                          ? 'Identifix ${_money(importedPrice)} → Dealer list ${_money(dealerList)}'
                                          : 'Dealer list ${_money(dealerList)}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF405064),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 58,
                        child: Text(
                          _quantity(line['quantity']),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFF182239),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 92,
                        child: Text(
                          _money(amount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFF182239),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              children: [
                _AmountRow(
                  label: 'Subtotal',
                  value: _money(
                    lines
                        .where((line) => line['line_kind'] != 'discount')
                        .fold<num>(
                          0,
                          (sum, line) => sum + _number(line['net_amount']),
                        ),
                  ),
                ),
                if (lines.any((line) => line['line_kind'] == 'discount'))
                  _AmountRow(
                    label: 'Discount',
                    value: _money(
                      lines
                          .where((line) => line['line_kind'] == 'discount')
                          .fold<num>(
                            0,
                            (sum, line) =>
                                sum + _number(line['net_amount']),
                          ),
                    ),
                  ),
                _AmountRow(
                  label: _taxLabel(lines),
                  value: _money(_detail!['tax_amount']),
                ),
                const Divider(height: 18),
                _AmountRow(
                  label: 'TOTAL',
                  value: _money(_detail!['total_amount']),
                  bold: true,
                ),
                if (!_estimate) ...[
                  _AmountRow(
                    label: 'Amount Paid',
                    value: _money(shownPaid),
                    valueColor: shownPaid > 0
                        ? const Color(0xFF0C9A43)
                        : null,
                  ),
                  _AmountRow(
                    label: 'Balance Due',
                    value: _money(balance < 0 ? 0 : balance),
                    bold: balance > 0,
                  ),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _paymentTab({
    required num total,
    required num finalizedPaid,
    required num pendingPaid,
    required num balance,
  }) {
    final payments = List<dynamic>.from(_detail?['payments'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final shownPaid = finalizedPaid + pendingPaid;
    final safeBalance = balance < 0 ? 0 : balance;
    final warrantyNet = _number(_warrantyDetail['terminal_amount']);
    final warrantyRate = _number(_warrantyDetail['surcharge_rate']);
    final warrantyUsesCheck = warrantyRate <= 0.000001;
    final warrantyPaymentAlreadyPresent = payments.any((payment) {
      final amount = _number(payment['amount']);
      final method =
          payment['payment_method_name']?.toString().trim().toLowerCase() ?? '';
      final amountMatches = (amount - warrantyNet).abs() < 0.005;
      final methodMatches = warrantyUsesCheck
          ? method == 'check' || method.contains('check')
          : method == 'credit card' ||
              (method.contains('credit') && method.contains('card'));
      return amountMatches && methodMatches;
    });

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text(
            tr('paymentSection'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _AmountRow(
                    label: tr('invoiceTotal'),
                    value: _money(total),
                  ),
                  _AmountRow(
                    label: tr('paid'),
                    value: _money(shownPaid),
                    valueColor:
                        shownPaid > 0 ? const Color(0xFF0C9A43) : null,
                  ),
                  const Divider(height: 18),
                  _AmountRow(
                    label: tr('balance'),
                    value: _money(safeBalance),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          if (_warrantyDetail['extended_warranty'] == true &&
              warrantyNet > 0.005 &&
              safeBalance > 0.005 &&
              !warrantyPaymentAlreadyPresent) ...[
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              color: BriskersColors.invoices.withValues(alpha: 0.07),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: BriskersColors.invoices,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('warrantyPayment'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _money(
                            warrantyNet >
                                    safeBalance
                                ? safeBalance
                                : warrantyNet,
                          ),
                          style: const TextStyle(
                            color: BriskersColors.invoices,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('warrantyPaymentHelp'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: BriskersColors.invoices,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : _enterWarrantyPayment,
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(tr('applyWarrantyPayment')),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('payments'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (payments.isNotEmpty)
                Text(
                  '${payments.length}',
                  style: const TextStyle(
                    color: Color(0xFF405064),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(tr('noPaymentsYet')),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < payments.length; index++) ...[
                    Builder(
                      builder: (context) {
                        final payment = payments[index];
                        final editable =
                            payment['state']?.toString() == 'pending';
                        final methodName =
                            payment['payment_method_name']?.toString() ??
                                tr('paymentSection');
                        final paymentAmount = _number(payment['amount']);
                        final methodLower = methodName.trim().toLowerCase();
                        final warrantyMethodMatches = warrantyUsesCheck
                            ? methodLower == 'check' ||
                                methodLower.contains('check')
                            : methodLower == 'credit card' ||
                                (methodLower.contains('credit') &&
                                    methodLower.contains('card'));
                        final warrantyAmountMatches =
                            (paymentAmount - warrantyNet).abs() < 0.005;
                        final isWarrantyPayment =
                            _warrantyDetail['extended_warranty'] == true &&
                                warrantyMethodMatches &&
                                warrantyAmountMatches;
                        final warrantyCompany = _warrantyDetail[
                                    'warranty_company_name']
                                ?.toString()
                                .trim() ??
                            '';
                        final companyFirstWord = warrantyCompany.isEmpty
                            ? tr('warrantyPayment')
                            : warrantyCompany.split(RegExp(r'\\s+')).first;
                        final source =
                            isWarrantyPayment ? companyFirstWord : 'customer';

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 0, 8, 0),
                          onLongPress: editable && !_busy
                              ? () => _showPaymentContextMenu(payment)
                              : null,
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF0C9A43).withValues(alpha: 0.10),
                            child: const Icon(
                              Icons.payments_outlined,
                              color: Color(0xFF0C9A43),
                            ),
                          ),
                          title: Text(
                            '$methodName - $source',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          subtitle: (() {
                            final paymentDate =
                                _paymentDate(payment['entered_at']);
                            if (paymentDate.isEmpty) return null;
                            return Text(
                              paymentDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w400,
                              ),
                            );
                          })(),
                          trailing: Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Text(
                              _money(paymentAmount),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (index != payments.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (safeBalance > 0.005)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.invoices,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _enterPayment,
                icon: const Icon(Icons.add_card_outlined),
                label: Text(tr('addPayment')),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: pendingPaid > 0
                    ? const Color(0xFFFFF4DE)
                    : const Color(0xFFEAF8EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: pendingPaid > 0
                      ? const Color(0xFFF1CC7A)
                      : const Color(0xFFCBEBD3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    pendingPaid > 0 ? Icons.schedule : Icons.check_circle,
                    color: pendingPaid > 0
                        ? const Color(0xFFE58A00)
                        : const Color(0xFF0C9A43),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pendingPaid > 0
                        ? tr('paidInFullPendingClose')
                        : tr('paidInFull'),
                    style: TextStyle(
                      color: pendingPaid > 0
                          ? const Color(0xFFA45F00)
                          : const Color(0xFF08752F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _captureCustomerSignature() async {
    if (_estimate || _busy || _detail == null) return;

    final detail = await _preparePdf();
    if (detail == null || !mounted) return;

    final disclaimers = List<dynamic>.from(
      _warrantyDetail['disclaimers'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerInvoiceSignatureScreen(
          customerName: detail['customer_name']?.toString() ?? '',
          invoiceNumber: detail['document_number']?.toString() ?? '',
          invoiceTotal: _money(detail['total_amount']),
          disclaimers: disclaimers,
          extendedWarranty:
              _warrantyDetail['extended_warranty'] == true,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final bytes = result['bytes'];
    final signerName = result['signer_name']?.toString().trim() ?? '';
    if (bytes is! Uint8List || signerName.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _api.uploadDocumentSignature(
        widget.businessId,
        widget.documentId,
        signerName: signerName,
        bytes: bytes,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer signature saved.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSubmissionRequirements() async {
    if (_estimate || _busy) return;

    Map<String, dynamic> readiness;
    try {
      readiness = await _api.warrantySubmissionReadiness(
        widget.businessId,
        widget.documentId,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;

    final ready = readiness['ready'] == true;
    final missing = List<dynamic>.from(
      readiness['missing'] ?? const [],
    ).map((item) => item.toString()).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          ready ? 'Ready for warranty submission' : 'Warranty submission blocked',
        ),
        content: ready
            ? Text(
                'All required warranty information is complete.\n\n'
                'Submission email: '
                '${readiness['submission_email'] ?? ''}',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Complete the following before submitting:',
                  ),
                  const SizedBox(height: 10),
                  ...missing.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFC62828),
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.invoices,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) {
      setState(() => _submissionReadiness = readiness);
    }
  }

  Future<void> _prepareWarrantySubmission() async {
    if (_estimate || _busy) return;

    Map<String, dynamic> readiness;
    try {
      readiness = await _api.warrantySubmissionReadiness(
        widget.businessId,
        widget.documentId,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (readiness['ready'] != true) {
      if (mounted) setState(() => _submissionReadiness = readiness);
      await _showSubmissionRequirements();
      return;
    }

    final detail = await _preparePdf();
    if (detail == null || !mounted) return;

    final signature = await _api.documentSignatureStatus(
      widget.businessId,
      widget.documentId,
    );
    final bucket = signature['bucket']?.toString() ?? '';
    final key = signature['key']?.toString() ?? '';
    if (bucket.isNotEmpty && key.isNotEmpty) {
      detail['signature_bytes'] = await _api.downloadAttachment(bucket, key);
      detail['signer_name'] = signature['signer_name'];
      detail['signed_at'] = signature['signed_at'];
      detail['signature_current'] = signature['is_current'] == true;
    }

    final bytes = await DocumentPdfService.build(detail);
    final email = readiness['submission_email']?.toString() ?? '';

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Warranty submission ready'),
            content: Text(
              'The signed warranty PDF is complete.\n\n'
              'Submit to: $email\n\n'
              'The system share sheet will open with the signed PDF attached.',
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
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final filename = DocumentPdfService.fileName(detail);
    final customerName =
        detail['customer_name']?.toString().trim() ?? '';
    final vehicle =
        detail['vehicle']?.toString().trim() ?? '';
    final claim =
        detail['claim_number']?.toString().trim() ?? '';
    final authorization =
        detail['authorization_number']?.toString().trim() ?? '';

    final subject = [
      customerName,
      authorization,
    ].where((value) => value.isNotEmpty).join(' - ');

    final body = <String>[
      'Please find the attached signed invoice for warranty processing.',
      '',
      if (customerName.isNotEmpty) 'Customer: $customerName',
      if (vehicle.isNotEmpty) 'Vehicle: $vehicle',
      if (claim.isNotEmpty) 'Claim #: $claim',
      if (authorization.isNotEmpty)
        'Authorization #: $authorization',
      '',
      'Briskers Foreign Auto Repair',
    ].join('\n');

    try {
      await GmailComposeService.composePdf(
        bytes: bytes,
        filename: filename,
        to: email,
        subject: subject,
        body: body,
      );
    } catch (_) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    }
  }

  Future<void> _addStandardNote() async {
    await _collapseWorkspaceHeader();
    if (_readOnly || _busy) return;

    List<Map<String, dynamic>> templates;
    try {
      templates = await _api.documentNoteTemplates(widget.businessId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }

    if (!mounted) return;

    if (templates.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('standardNotes')),
          content: Text(tr('noStandardNoteTemplates')),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _documentActionColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              title: Text(
                tr('addStandardNote'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(tr('selectSavedNote')),
            ),
            const Divider(height: 1),
            ...templates.map(
              (template) => ListTile(
                leading: Icon(
                  template['template_type']?.toString() == 'warranty'
                      ? Icons.verified_outlined
                      : Icons.notes_outlined,
                  color: _estimate
                      ? BriskersColors.estimates
                      : BriskersColors.invoices,
                ),
                title: Text(
                  template['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  template['body']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, template),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;

    final body = selected['body']?.toString().trim() ?? '';
    if (body.isEmpty) return;

    final current = _detail?['memo']?.toString().trim() ?? '';
    final combined = current.isEmpty
        ? body
        : current.contains(body)
            ? current
            : '$current\n\n$body';

    await _run(
      () => _api.updateDocumentNotes(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        memo: combined,
      ),
    );
  }

  Future<Map<String, dynamic>?> _editDisclaimerSheet({
    Map<String, dynamic>? initial,
    Map<String, dynamic>? template,
  }) async {
    final title = TextEditingController(
      text: initial?['title']?.toString() ??
          template?['name']?.toString() ??
          '',
    );
    final body = TextEditingController(
      text: initial?['body']?.toString() ??
          template?['body']?.toString() ??
          '',
    );
    var signatureRequired =
        initial?['signature_required'] == true ||
            (initial == null && template?['signature_required'] != false);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
                  tr('customerDisclaimer'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: tr('title'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: tr('disclaimerText'),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: BriskersColors.invoices,
                  value: signatureRequired,
                  onChanged: (value) => setSheetState(
                    () => signatureRequired = value == true,
                  ),
                  title: Text(
                    tr('requireCustomerSignature'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    tr('disclaimerSignedInvoiceHelp'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.invoices,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final t = title.text.trim();
                    final b = body.text.trim();
                    if (t.isEmpty || b.isEmpty) return;
                    Navigator.pop(
                      sheetContext,
                      {
                        'title': t,
                        'body': b,
                        'signature_required': signatureRequired,
                      },
                    );
                  },
                  child: Text(tr('saveDisclaimer')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    title.dispose();
    body.dispose();
    return result;
  }

  Future<void> _addDisclaimer() async {
    await _collapseWorkspaceHeader();
    if (_estimate || _readOnly || _busy) return;

    List<Map<String, dynamic>> templates = const [];
    try {
      templates = await _api.disclaimerTemplates(widget.businessId);
    } catch (_) {
      templates = const [];
    }

    if (!mounted) return;

    final choice = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              title: Text(
                tr('addDisclaimer'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(tr('chooseDisclaimerTemplate')),
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_note_outlined,
                color: BriskersColors.invoices,
              ),
              title: Text(tr('customDisclaimer')),
              onTap: () => Navigator.pop(sheetContext, <String, dynamic>{}),
            ),
            if (templates.isNotEmpty) const Divider(height: 1),
            ...templates.map(
              (template) => ListTile(
                leading: Icon(
                  template['signature_required'] == true
                      ? Icons.draw_outlined
                      : Icons.info_outline,
                  color: BriskersColors.invoices,
                ),
                title: Text(
                  template['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  template['body']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, template),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    final edited = await _editDisclaimerSheet(
      template: choice.isEmpty ? null : choice,
    );
    if (edited == null) return;

    await _api.saveDocumentDisclaimer(
      widget.businessId,
      widget.documentId,
      templateId: choice['id']?.toString(),
      title: edited['title'].toString(),
      body: edited['body'].toString(),
      signatureRequired: edited['signature_required'] == true,
    );
    await _load();
  }

  Future<void> _editDisclaimer(Map<String, dynamic> disclaimer) async {
    if (_estimate || _readOnly || _busy) return;

    final edited = await _editDisclaimerSheet(initial: disclaimer);
    if (edited == null) return;

    await _api.saveDocumentDisclaimer(
      widget.businessId,
      widget.documentId,
      disclaimerId: disclaimer['id']?.toString(),
      templateId: disclaimer['template_id']?.toString(),
      title: edited['title'].toString(),
      body: edited['body'].toString(),
      signatureRequired: edited['signature_required'] == true,
    );
    await _load();
  }

  Future<void> _deleteDisclaimer(Map<String, dynamic> disclaimer) async {
    if (_estimate || _readOnly || _busy) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove disclaimer?'),
            content: Text(
              disclaimer['title']?.toString() ??
                  'Remove this disclaimer from the invoice?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
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

    await _api.deleteDocumentDisclaimer(
      widget.businessId,
      widget.documentId,
      disclaimer['id'].toString(),
    );
    await _load();
  }

  Future<void> _showDisclaimers() async {
    if (_estimate) return;

    final disclaimers = List<dynamic>.from(
      _warrantyDetail['disclaimers'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('invoiceDisclaimers'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!_readOnly)
                      IconButton(
                        tooltip: tr('addDisclaimer'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _addDisclaimer();
                        },
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: BriskersColors.invoices,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: disclaimers.isEmpty
                    ? Center(
                        child: Text(tr('noDisclaimerOnInvoice')),
                      )
                    : ListView.separated(
                        itemCount: disclaimers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final disclaimer = disclaimers[index];
                          return ListTile(
                            leading: Icon(
                              disclaimer['signature_required'] == true
                                  ? Icons.draw_outlined
                                  : Icons.info_outline,
                              color: disclaimer['signature_required'] == true
                                  ? const Color(0xFFC66A00)
                                  : BriskersColors.invoices,
                            ),
                            title: Text(
                              disclaimer['title']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              disclaimer['body']?.toString() ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: _readOnly
                                ? null
                                : () {
                                    Navigator.pop(sheetContext);
                                    _editDisclaimer(disclaimer);
                                  },
                            trailing: _readOnly
                                ? null
                                : IconButton(
                                    tooltip: 'Remove disclaimer',
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _deleteDisclaimer(disclaimer);
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInlineNotes() async {
    if (_readOnly || _busy || !_notesDirty) return;
    final value = _notesController.text.trim();
    final translatedValue = await _translateManualNote(value);
    if (translatedValue == null || !mounted) return;

    await _run(
      () => _api.updateDocumentNotes(
        widget.businessId,
        widget.documentId,
        expectedVersion: _version,
        memo: translatedValue.isEmpty ? null : translatedValue,
      ),
    );

    if (mounted && _error == null) {
      setState(() {
        _notesDirty = false;
        _notesController.text = translatedValue;
      });
    }
  }

  Widget _notesTab() {
    final disclaimers = List<dynamic>.from(
      _warrantyDetail['disclaimers'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final signatureNeeded =
        _warrantyDetail['signature_required'] == true ||
            disclaimers.any((item) => item['signature_required'] == true);
    final signatureCurrent = _signatureStatus['is_current'] == true;
    final signerName = _signatureStatus['signer_name']?.toString() ?? '';
    final signedAt = DateTime.tryParse(
      _signatureStatus['signed_at']?.toString() ?? '',
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text(
            _estimate ? tr('estimateNotes') : tr('invoiceNotes'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            focusNode: _notesFocusNode,
            readOnly: _readOnly,
            minLines: 3,
            maxLines: 7,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (!_notesDirty) {
                setState(() => _notesDirty = true);
              }
            },
            decoration: InputDecoration(
              hintText: _estimate
                  ? tr('noEstimateNotes')
                  : tr('noInvoiceNotes'),
              alignLabelWithHint: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFA),
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD8E0DE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD8E0DE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _estimate
                      ? BriskersColors.estimates
                      : BriskersColors.invoices,
                  width: 2,
                ),
              ),
            ),
          ),
          if (!_readOnly && _notesDirty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _estimate
                      ? BriskersColors.estimates
                      : BriskersColors.invoices,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _saveInlineNotes,
                icon: const Icon(Icons.check),
                label: Text(tr('saveNotes')),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!_readOnly)
            OutlinedButton.icon(
              onPressed: _busy ? null : _addStandardNote,
              icon: const Icon(Icons.playlist_add_outlined),
              label: Text(tr('addStandardNote')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _estimate
                    ? BriskersColors.estimates
                    : BriskersColors.invoices,
                alignment: Alignment.centerLeft,
              ),
            ),
          if (!_estimate) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFFF7F8FA),
              child: ListTile(
                leading: Icon(
                  disclaimers.isEmpty
                      ? Icons.info_outline
                      : signatureNeeded
                          ? Icons.draw_outlined
                          : Icons.description_outlined,
                  color: signatureNeeded
                      ? const Color(0xFFC66A00)
                      : BriskersColors.invoices,
                ),
                title: Text(
                  tr('disclaimer'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  disclaimers.isEmpty
                      ? tr('none')
                      : disclaimers.length == 1
                          ? disclaimers.first['title']?.toString() ?? '1 disclaimer'
                          : '${disclaimers.length} disclaimers',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDisclaimers,
              ),
            ),
            if (signatureNeeded) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                color: signatureCurrent
                    ? const Color(0xFFEAF8EE)
                    : const Color(0xFFFFF7E8),
                child: ListTile(
                  leading: Icon(
                    signatureCurrent
                        ? Icons.check_circle_outline
                        : Icons.draw_outlined,
                    color: signatureCurrent
                        ? BriskersColors.invoices
                        : const Color(0xFFC66A00),
                  ),
                  title: Text(
                    signatureCurrent
                        ? tr('customerSignatureComplete')
                        : tr('customerSignatureRequired'),
                    style: TextStyle(
                      color: signatureCurrent
                          ? BriskersColors.invoices
                          : const Color(0xFF8A4B00),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    signatureCurrent
                        ? <String>[
                            if (signerName.isNotEmpty) signerName,
                            if (signedAt != null)
                              DateFormat('MMM d, yyyy h:mm a')
                                  .format(signedAt.toLocal()),
                          ].join(' • ')
                        : tr('signatureRequiredBeforeSubmission'),
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _captureCustomerSignature,
                    child: Text(signatureCurrent ? tr('resign') : tr('sign')),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            tr('notesPdfHelp'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: onTap == null
                    ? Theme.of(context).disabledColor
                    : _accent,
                size: 29,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? Theme.of(context).disabledColor
                      : _accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDocumentHeaderActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_readOnly)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(
                    _estimate ? tr('editEstimate') : tr('editInvoice'),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
              if (!_estimate)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(tr('copyInvoice')),
                  onTap: () => Navigator.pop(sheetContext, 'copy'),
                ),
              if (!_estimate)
                ListTile(
                  leading: const Icon(Icons.car_repair_outlined),
                  title: Text(tr('vehicleFindings')),
                  onTap: () => Navigator.pop(sheetContext, 'findings'),
                ),
              if (!_estimate && _canManageInvoiceExpenses)
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(tr('viewExpenses')),
                  onTap: () => Navigator.pop(sheetContext, 'expenses'),
                ),
              if (!_estimate && _canManageInvoiceExpenses)
                ListTile(
                  leading: const Icon(Icons.add_card_outlined),
                  title: Text(tr('addExpense')),
                  onTap: () => Navigator.pop(sheetContext, 'add_expense'),
                ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(tr('refresh')),
                onTap: () => Navigator.pop(sheetContext, 'refresh'),
              ),
              if (_estimate && !_converted)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(tr('createInvoice')),
                  onTap: () => Navigator.pop(sheetContext, 'convert'),
                ),
              if (widget.isOwner && (!_estimate || !_converted)) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    _estimate ? tr('deleteEstimate') : tr('deleteInvoice'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'refresh':
        await _load();
      case 'convert':
        await _convertEstimate();
      case 'edit':
        await _editDocumentHeader();
      case 'copy':
        await _copyInvoice();
      case 'findings':
        await _showInvoiceFindings();
      case 'expenses':
        await _showInvoiceExpenses();
      case 'add_expense':
        await _addInvoiceExpense();
      case 'delete':
        if (_estimate) {
          await _deleteEstimate();
        } else {
          await _deleteOrVoidInvoice();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          title: const Text('Document'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          title: const Text('Document'),
        ),
        body: Center(child: Text(_error ?? 'Document not found.')),
      );
    }

    final lines = List<dynamic>.from(_detail!['lines'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    final number = _detail!['document_number']?.toString().trim() ?? '';
    final finalizedPaid = _number(_detail!['paid_amount']);
    final pendingPaid = _number(_detail!['pending_payment']);
    final total = _number(_detail!['total_amount']);
    final shownPaid = finalizedPaid + pendingPaid;
    final balance = total - shownPaid;
    final statusCode = _estimate
        ? null
        : _invoiceStatusCode(
            total: total,
            finalizedPaid: finalizedPaid,
            pendingPaid: pendingPaid,
          );
    final statusLabel = _statusLabel(
      total: total,
      finalizedPaid: finalizedPaid,
      pendingPaid: pendingPaid,
    );
    final tabCount = _estimate ? 2 : 3;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 1,
          titleSpacing: 0,
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: _showDocumentHeaderActions,
            child: Row(
              children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      number.isEmpty
                          ? (_estimate ? tr('estimate') : tr('invoice'))
                          : (_estimate
                              ? '${tr('estimate')} #$number'
                              : '${tr('invoice')} #$number'),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(statusLabel, code: statusCode),
              ],
            ),
          ),
          actions: [
            if (!_readOnly)
              IconButton(
                tooltip: _estimate ? tr('editEstimate') : tr('editInvoice'),
                onPressed: _busy ? null : _editDocumentHeader,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: NestedScrollView(
          controller: _workspaceHeaderController,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Container(
                key: _workspaceHeaderKey,
                child: Column(
                  children: [
                  _customerHeader(),
                  if (!_estimate)
                    InvoiceWarrantyPanel(
                      businessId: widget.businessId,
                      documentId: widget.documentId,
                      expectedVersion: _version,
                      invoiceTotal: total,
                      detail: _warrantyDetail,
                      readOnly: _readOnly,
                      paymentProcessed: _warrantyPaymentProcessed(),
                      onChanged: _load,
                    ),
                  _openFindingsBanner(),
                  if (_estimate && _converted) _convertedInvoiceBanner(),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _DocumentTabsHeaderDelegate(
                accent: _accent,
                isEstimate: _estimate,
                onTap: (_) => _collapseWorkspaceHeader(),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _itemsTab(
                lines,
                shownPaid: shownPaid,
                balance: balance,
              ),
              if (!_estimate)
                _paymentTab(
                  total: total,
                  finalizedPaid: finalizedPaid,
                  pendingPaid: pendingPaid,
                  balance: balance,
                ),
              _notesTab(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFDDE4E6)),
              ),
            ),
            child: Row(
              children: [
                _bottomAction(
                  icon: Icons.add_circle,
                  label: tr('addItem'),
                  onTap: _readOnly || _busy
                      ? null
                      : () async {
                          await _collapseWorkspaceHeader();
                          if (!context.mounted) return;
                          final action =
                              await showModalBottomSheet<String>(
                            context: context,
                            showDragHandle: true,
                            builder: (sheetContext) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.inventory_2_outlined,
                                    ),
                                    title: Text(tr('addFromItemList')),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'catalog'),
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.add_box_outlined),
                                    title: Text(tr('addCustomLine')),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'custom'),
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.percent_outlined,
                                    ),
                                    title: Text(tr('addDiscount')),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, 'discount'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (action == 'catalog') await _addCatalogItem();
                          if (action == 'custom') await _addCustomLine();
                          if (action == 'discount') await _addDiscount();
                        },
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFDDE4E6),
                ),
                _bottomAction(
                  icon: Icons.visibility_outlined,
                  label: tr('preview'),
                  onTap: _busy ? null : _previewPdf,
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFDDE4E6),
                ),
                _bottomAction(
                  icon: Icons.outbox_outlined,
                  label: tr('send'),
                  onTap: _busy ? null : _showSendMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentTabsHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  _DocumentTabsHeaderDelegate({
    required this.accent,
    required this.isEstimate,
    required this.onTap,
  });

  final Color accent;
  final bool isEstimate;
  final ValueChanged<int> onTap;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      elevation: overlapsContent ? 1 : 0,
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE4E9EB)),
            bottom: BorderSide(color: Color(0xFFE4E9EB)),
          ),
        ),
        child: TabBar(
          onTap: onTap,
          indicatorColor: accent,
          indicatorWeight: 3,
          labelColor: accent,
          unselectedLabelColor: const Color(0xFF26354D),
          labelStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
          ),
          tabs: [
            Tab(text: tr('itemsTab')),
            if (!isEstimate) Tab(text: tr('paymentTab')),
            Tab(text: tr('notesTab')),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DocumentTabsHeaderDelegate oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.isEstimate != isEstimate;
  }
}

class _PriceVerificationChip extends StatelessWidget {
  const _PriceVerificationChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final IconData icon;
    late final Color color;

    switch (status) {
      case 'verified':
        label = 'Verified';
        icon = Icons.check_circle_outline;
        color = const Color(0xFF169B62);
        break;
      case 'updated':
        label = 'Updated';
        icon = Icons.sync_alt;
        color = const Color(0xFFE58A00);
        break;
      case 'needs_review':
        label = 'Needs review';
        icon = Icons.warning_amber_outlined;
        color = const Color(0xFFC62828);
        break;
      case 'not_found':
        label = 'Price not found';
        icon = Icons.search_off_outlined;
        color = const Color(0xFFC62828);
        break;
      case 'manual':
        label = 'Manual price';
        icon = Icons.edit_outlined;
        color = const Color(0xFF607D8B);
        break;
      case 'pending':
        label = 'Checking';
        icon = Icons.hourglass_top_outlined;
        color = BriskersColors.estimates;
        break;
      default:
        label = status;
        icon = Icons.info_outline;
        color = const Color(0xFF607D8B);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 18 : 15,
      color: const Color(0xFF182239),
    );
    final valueStyle = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      fontSize: bold ? 19 : 15,
      color: valueColor ?? const Color(0xFF182239),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _CustomLineDialog extends StatefulWidget {
  const _CustomLineDialog({
    required this.defaultTaxRate,
    required this.accent,
  });

  final num defaultTaxRate;
  final Color accent;

  @override
  State<_CustomLineDialog> createState() => _CustomLineDialogState();
}

class _CustomLineDialogState extends State<_CustomLineDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  late final TextEditingController _taxPercent;
  String _lineKind = 'item';
  String? _error;
  bool _quantityCleared = false;
  bool _priceCleared = false;

  @override
  void initState() {
    super.initState();
    var percent = (widget.defaultTaxRate * 100).toStringAsFixed(3);
    while (percent.contains('.') && percent.endsWith('0')) {
      percent = percent.substring(0, percent.length - 1);
    }
    if (percent.endsWith('.')) {
      percent = percent.substring(0, percent.length - 1);
    }
    _taxPercent = TextEditingController(text: percent);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _taxPercent.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = num.tryParse(_quantity.text.trim());
    final price = num.tryParse(_price.text.trim());
    final taxPercent = num.tryParse(_taxPercent.text.trim());
    if (_name.text.trim().isEmpty ||
        quantity == null ||
        price == null ||
        taxPercent == null ||
        quantity <= 0 ||
        price < 0 ||
        taxPercent < 0 ||
        taxPercent > 100) {
      setState(() => _error = 'Enter a valid name, quantity, price and tax.');
      return;
    }
    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'quantity': _lineKind == 'discount' ? -quantity.abs() : quantity,
        'unit_price': price,
        'tax_rate': taxPercent / 100,
        'line_kind': _lineKind,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('addCustomLine')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('item'),
                helperText: BriskersLanguageController.instance.isSpanish
                    ? tr('translateEnglishNotice')
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: tr('description'),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _lineKind,
              decoration: InputDecoration(labelText: tr('type')),
              items: [
                DropdownMenuItem(
                  value: 'item',
                  child: Text(tr('partItem')),
                ),
                DropdownMenuItem(
                  value: 'labor',
                  child: Text(tr('labor')),
                ),
                DropdownMenuItem(
                  value: 'supply',
                  child: Text(tr('shopSupply')),
                ),
                DropdownMenuItem(
                  value: 'other',
                  child: Text(tr('other')),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _lineKind = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onTap: () {
                if (_quantityCleared) return;
                _quantity.clear();
                _quantityCleared = true;
              },
              decoration: InputDecoration(labelText: tr('quantity')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onTap: () {
                if (_priceCleared) return;
                _price.clear();
                _priceCleared = true;
              },
              decoration: InputDecoration(
                labelText: tr('price'),
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _taxPercent,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('tax'),
                suffixText: '%',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(tr('add')),
        ),
      ],
    );
  }
}

class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({
    required this.line,
    required this.accent,
    this.title = 'Edit item',
    this.saveLabel = 'Save',
    this.lockCatalogFields = false,
    this.clearNumericOnFirstTap = false,
  });

  final Map<String, dynamic> line;
  final Color accent;
  final String title;
  final String saveLabel;
  final bool lockCatalogFields;
  final bool clearNumericOnFirstTap;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _taxPercent;
  late String _lineKind;
  String? _error;
  bool _quantityCleared = false;
  bool _priceCleared = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.line['name']?.toString() ?? '',
    );
    _lineKind = widget.line['line_kind']?.toString() ?? 'item';
    _description = TextEditingController(
      text: widget.line['description']?.toString() ?? '',
    );
    final initialQuantity =
        num.tryParse(widget.line['quantity']?.toString() ?? '') ?? 1;
    _quantity = TextEditingController(
      text: initialQuantity.abs().toString(),
    );
    _price = TextEditingController(
      text: widget.line['unit_price']?.toString() ?? '0',
    );
    final rate = num.tryParse(widget.line['tax_rate']?.toString() ?? '') ?? 0;
    _taxPercent = TextEditingController(text: (rate * 100).toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    _taxPercent.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = num.tryParse(_quantity.text.trim());
    final price = num.tryParse(_price.text.trim());
    final taxPercent = num.tryParse(_taxPercent.text.trim());
    if (_name.text.trim().isEmpty ||
        quantity == null ||
        price == null ||
        taxPercent == null ||
        quantity <= 0 ||
        price < 0 ||
        taxPercent < 0 ||
        taxPercent > 100) {
      setState(() => _error = 'Enter a valid quantity, price and tax.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim(),
        'line_kind': _lineKind,
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'quantity': _lineKind == 'discount'
            ? -quantity.abs()
            : quantity,
        'unit_price': price,
        'tax_rate': taxPercent / 100,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final keyboardOpen = viewInsets.bottom > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: keyboardOpen ? 0.94 : 0.86,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    16,
                    18,
                    keyboardOpen ? 110 : 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        scrollPadding: const EdgeInsets.only(bottom: 180),
                        controller: _name,
                        readOnly: widget.lockCatalogFields,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: tr('item'),
                          border: const OutlineInputBorder(),
                          filled: widget.lockCatalogFields,
                          fillColor: widget.lockCatalogFields
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.45)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        scrollPadding: const EdgeInsets.only(bottom: 180),
                        controller: _description,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: tr('description'),
                          helperText:
                              BriskersLanguageController.instance.isSpanish
                                  ? tr('translateEnglishNotice')
                                  : null,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              scrollPadding:
                                  const EdgeInsets.only(bottom: 180),
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onTap: () {
                                if (!widget.clearNumericOnFirstTap ||
                                    _quantityCleared) {
                                  return;
                                }
                                _quantity.clear();
                                _quantityCleared = true;
                              },
                              decoration: InputDecoration(
                                labelText: tr('qtyColumn'),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              scrollPadding:
                                  const EdgeInsets.only(bottom: 180),
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onTap: () {
                                if (!widget.clearNumericOnFirstTap ||
                                    _priceCleared) {
                                  return;
                                }
                                _price.clear();
                                _priceCleared = true;
                              },
                              decoration: InputDecoration(
                                labelText: tr('price'),
                                prefixText: '\$ ',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!widget.lockCatalogFields) ...[
                        const SizedBox(height: 12),
                        TextField(
                        scrollPadding: const EdgeInsets.only(bottom: 180),
                          controller: _taxPercent,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: tr('tax'),
                            suffixText: '%',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _lineKind,
                          decoration: InputDecoration(
                            labelText: tr('type'),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'item',
                              child: Text(tr('partItem')),
                            ),
                            DropdownMenuItem(
                              value: 'labor',
                              child: Text(tr('labor')),
                            ),
                            DropdownMenuItem(
                              value: 'supply',
                              child: Text(tr('shopSupply')),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(tr('other')),
                            ),
                            DropdownMenuItem(
                              value: 'shipping',
                              child: Text(tr('shipping')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _lineKind = value);
                            }
                          },
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: Text(widget.saveLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.accent,
    this.line,
  });

  final Color accent;
  final Map<String, dynamic>? line;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _value;
  late String _method;
  late String _timing;
  String? _error;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _name = TextEditingController(
      text: line?['name']?.toString() ?? 'Discount',
    );
    _description = TextEditingController(
      text: line?['description']?.toString() ?? '',
    );
    _method = line?['discount_method']?.toString() ?? 'amount';
    _timing = line?['discount_timing']?.toString() ?? 'before_tax';

    final rawValue = line?['discount_value'];
    final fallback = (num.tryParse(line?['net_amount']?.toString() ?? '') ?? 0)
        .abs();
    _value = TextEditingController(
      text: rawValue?.toString() ?? fallback.toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final value = num.tryParse(_value.text.trim());
    if (value == null ||
        value < 0 ||
        (_method == 'percent' && value > 100)) {
      setState(() => _error = _method == 'percent'
          ? 'Enter a percentage from 0 to 100.'
          : 'Enter a valid discount amount.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'name': _name.text.trim().isEmpty ? 'Discount' : _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'method': _method,
        'value': value,
        'timing': _timing,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final keyboardOpen = viewInsets.bottom > 0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: keyboardOpen ? 0.96 : 0.68,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.line == null ? 'Add Discount' : 'Edit Discount',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'amount',
                            label: Text('Amount'),
                            icon: Icon(Icons.attach_money),
                          ),
                          ButtonSegment(
                            value: 'percent',
                            label: Text('Percentage'),
                            icon: Icon(Icons.percent),
                          ),
                        ],
                        selected: {_method},
                        onSelectionChanged: (value) {
                          setState(() => _method = value.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _value,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        scrollPadding: const EdgeInsets.only(bottom: 180),
                        decoration: InputDecoration(
                          labelText: _method == 'percent'
                              ? 'Discount percentage'
                              : 'Discount amount',
                          prefixText: _method == 'amount' ? '\$ ' : null,
                          suffixText: _method == 'percent' ? '%' : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'before_tax',
                            label: Text('Before Tax'),
                          ),
                          ButtonSegment(
                            value: 'after_tax',
                            label: Text('After Tax'),
                          ),
                        ],
                        selected: {_timing},
                        onSelectionChanged: (value) {
                          setState(() => _timing = value.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _timing == 'before_tax'
                            ? 'Tax is recalculated after this discount is applied.'
                            : 'Tax is calculated first, then this discount is subtracted.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: Text(
                          widget.line == null
                              ? 'Add Discount'
                              : 'Save Discount',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentEntryDialog extends StatefulWidget {
  const _PaymentEntryDialog({
    required this.methods,
    required this.initialAmount,
    this.initialMethodId,
    this.title = 'Add payment',
    this.saveLabel = 'Save payment',
  });

  final List<Map<String, dynamic>> methods;
  final num initialAmount;
  final String? initialMethodId;
  final String title;
  final String saveLabel;

  @override
  State<_PaymentEntryDialog> createState() => _PaymentEntryDialogState();
}

class _PaymentEntryDialogState extends State<_PaymentEntryDialog> {
  late final TextEditingController _amount;
  late String _methodId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.initialAmount.toStringAsFixed(2),
    );
    final existing = widget.initialMethodId;
    _methodId = existing != null &&
            widget.methods.any((item) => item['id']?.toString() == existing)
        ? existing
        : widget.methods.first['id'].toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid payment amount.');
      return;
    }
    Navigator.pop(
      context,
      <String, dynamic>{
        'amount': amount,
        'method_id': _methodId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('paymentAmount'),
              prefixText: '\$ ',
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(
                  color: BriskersColors.invoices,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _methodId,
            decoration: InputDecoration(
              labelText: tr('paymentMethod'),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(
                  color: BriskersColors.invoices,
                  width: 2,
                ),
              ),
            ),
            items: widget.methods
                .map(
                  (method) => DropdownMenuItem<String>(
                    value: method['id'].toString(),
                    child: Text(method['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _methodId = value);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: BriskersColors.invoices,
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: BriskersColors.invoices,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
