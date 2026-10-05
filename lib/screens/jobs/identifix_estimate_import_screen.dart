import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class IdentifixEstimateImportScreen extends StatefulWidget {
  const IdentifixEstimateImportScreen({
    super.key,
    required this.businessId,
    required this.jobId,
    required this.customerName,
    required this.vehicle,
    this.sourceType = 'identifix',
  });

  final String businessId;
  final String jobId;
  final String customerName;
  final String vehicle;
  final String sourceType;

  @override
  State<IdentifixEstimateImportScreen> createState() =>
      _IdentifixEstimateImportScreenState();
}

class _IdentifixEstimateImportScreenState
    extends State<IdentifixEstimateImportScreen> {
  static const _api = BriskersApi();

  final ImagePicker _picker = ImagePicker();

  bool get _handwritten => widget.sourceType == 'handwritten';
  String get _sourceLabel => _handwritten ? 'handwritten' : 'Identifix';

  XFile? _sourceFile;
  Uint8List? _sourceBytes;
  String _mimeType = 'image/jpeg';
  Map<String, dynamic>? _extraction;

  bool _reading = false;
  bool _creating = false;
  int _priceChecked = 0;
  int _priceTotal = 0;
  int _priceProblems = 0;
  String? _error;

  String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _money(Object? value) {
    final number = num.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: '\$').format(number);
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool get _customerMismatch {
    final source = _extraction?['customer_name']?.toString().trim() ?? '';
    if (source.isEmpty || widget.customerName.trim().isEmpty) return false;
    return _normalized(source) != _normalized(widget.customerName);
  }

  Future<void> _pick(ImageSource source) async {
    if (_reading || _creating) return;

    final image = await _picker.pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 2600,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;

    setState(() {
      _sourceFile = image;
      _sourceBytes = bytes;
      _mimeType = _mimeFor(image.name);
      _reading = true;
      _extraction = null;
      _error = null;
    });

    try {
      final extraction = await _api.parseIdentifixEstimate(
        widget.businessId,
        bytes,
        mimeType: _mimeType,
        sourceType: widget.sourceType,
      );
      if (!mounted) return;
      setState(() {
        _extraction = extraction;
        _reading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editLine(int index) async {
    final extraction = _extraction;
    if (extraction == null) return;

    final lines = List<dynamic>.from(extraction['lines'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    if (index < 0 || index >= lines.length) return;

    final edited = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ImportLineDialog(line: lines[index]),
    );
    if (edited == null || !mounted) return;

    lines[index] = edited;
    final updated = Map<String, dynamic>.from(extraction);
    updated['lines'] = lines;
    setState(() => _extraction = updated);
  }

  Future<void> _createEstimate() async {
    final extraction = _extraction;
    if (extraction == null || _creating) return;

    setState(() {
      _creating = true;
      _error = null;
      _priceChecked = 0;
      _priceProblems = 0;
      _priceTotal = 0;
    });

    try {
      final created = await _api.createIdentifixEstimate(
        widget.businessId,
        widget.jobId,
        extraction,
        sourceType: widget.sourceType,
      );
      final documentId = created['document_id']?.toString() ?? '';
      if (documentId.isEmpty) {
        throw Exception('Briskers did not return the new estimate.');
      }

      final bytes = _sourceBytes;
      final file = _sourceFile;
      if (bytes != null && file != null) {
        try {
          await _api.uploadDocumentSourceImage(
            widget.businessId,
            documentId,
            filename: file.name,
            mimeType: _mimeType,
            bytes: bytes,
          );
        } catch (_) {
          // The estimate already exists. Do not retry estimate creation just
          // because the source-image attachment could not be uploaded.
        }
      }

      final partLines = List<dynamic>.from(
        created['part_lines'] ?? const [],
      ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

      if (mounted) {
        setState(() => _priceTotal = partLines.length);
      }

      for (final line in partLines) {
        final lineId = line['line_id']?.toString() ?? '';
        try {
          final result = await _api.verifyImportedPartPrice(
            widget.businessId,
            lineId: lineId,
            partNumber: line['part_number']?.toString() ?? '',
            description: line['description']?.toString() ?? '',
            vehicle: widget.vehicle,
            importedUnitPrice:
                num.tryParse(line['imported_unit_price']?.toString() ?? '') ??
                    0,
          );
          final status = result['status']?.toString() ?? '';
          if (status == 'needs_review' || status == 'not_found') {
            _priceProblems++;
          }
        } catch (error) {
          _priceProblems++;
          if (lineId.isNotEmpty) {
            try {
              await _api.markImportedPartPriceReview(
                widget.businessId,
                lineId,
                note: 'Automatic dealer-price check failed. Review manually.',
              );
            } catch (_) {
              // The estimate remains editable even if the status update fails.
            }
          }
        }

        if (mounted) {
          setState(() => _priceChecked++);
        }
      }

      if (!mounted) return;
      Navigator.pop(context, documentId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.toString();
      });
    }
  }

  Widget _initialView() {
    if (_reading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                _handwritten
                    ? 'Reading handwritten estimate...'
                    : 'Reading Identifix estimate...',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 7),
              Text(
                'Briskers is extracting the estimate lines, part numbers, quantities and prices.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: BriskersColors.estimates.withValues(alpha: 0.12),
          child: const Icon(
            Icons.document_scanner_outlined,
            color: BriskersColors.estimates,
            size: 36,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _handwritten
              ? 'Scan handwritten estimate'
              : 'Import estimate from Identifix',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _handwritten
              ? 'This estimate will be linked to ${widget.customerName} and this job. '
                  'Scan the complete handwritten estimate, then review every extracted line before creating it.'
              : 'This estimate will be linked to ${widget.customerName} and this job. '
                  'Scan the complete printed Identifix estimate, then review the extracted lines.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: BriskersColors.estimates,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(
            _handwritten ? 'Scan handwritten estimate' : 'Scan printed estimate',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Upload estimate photo'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _creatingView() {
    final progress = _priceTotal <= 0
        ? null
        : _priceChecked / _priceTotal.clamp(1, 9999);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.price_check_outlined,
              size: 50,
              color: BriskersColors.estimates,
            ),
            const SizedBox(height: 16),
            const Text(
              'Creating estimate and checking dealer prices...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 14),
            if (_priceTotal > 0)
              Text('$_priceChecked of $_priceTotal part prices checked'),
            if (_priceProblems > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$_priceProblems line(s) will be marked for review.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final extraction = _extraction!;
    final lines = List<dynamic>.from(extraction['lines'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    final sourceVehicle = <String>[
      if (extraction['vehicle_year'] != null)
        extraction['vehicle_year'].toString(),
      if ((extraction['vehicle_make']?.toString() ?? '').isNotEmpty)
        extraction['vehicle_make'].toString(),
      if ((extraction['vehicle_model']?.toString() ?? '').isNotEmpty)
        extraction['vehicle_model'].toString(),
    ].join(' ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        Card(
          color: BriskersColors.estimates.withValues(alpha: 0.07),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      color: BriskersColors.estimates,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'AI extraction preview',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PreviewRow(
                  label: _handwritten ? 'Source estimate' : 'Identifix estimate',
                  value: extraction['estimate_number']?.toString() ?? '—',
                ),
                _PreviewRow(
                  label: 'Date',
                  value: extraction['estimate_date']?.toString() ?? '—',
                ),
                _PreviewRow(
                  label: 'Customer',
                  value: extraction['customer_name']?.toString() ?? '—',
                ),
                _PreviewRow(
                  label: 'Vehicle',
                  value: sourceVehicle.isEmpty
                      ? (extraction['vehicle_description']?.toString() ?? '—')
                      : sourceVehicle,
                ),
                if (extraction['mileage'] != null)
                  _PreviewRow(
                    label: 'Mileage',
                    value: extraction['mileage'].toString(),
                  ),
              ],
            ),
          ),
        ),
        if (_customerMismatch) ...[
          const SizedBox(height: 10),
          Card(
            color: Colors.orange.withValues(alpha: 0.10),
            child: const ListTile(
              leading: Icon(Icons.warning_amber_outlined, color: Colors.orange),
              title: Text('Customer name differs from this job'),
              subtitle: Text(
                'Review the scan before creating the Briskers estimate.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Estimate lines (${lines.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.refresh),
              label: const Text('Rescan'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...List.generate(lines.length, (index) {
          final line = lines[index];
          final type = line['type']?.toString() ?? 'other';
          final part = line['part_number']?.toString().trim() ?? '';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    BriskersColors.estimates.withValues(alpha: 0.12),
                child: Icon(
                  type == 'labor'
                      ? Icons.handyman_outlined
                      : type == 'supply'
                          ? Icons.inventory_2_outlined
                          : Icons.settings_outlined,
                  color: BriskersColors.estimates,
                ),
              ),
              title: Text(
                line['description']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                <String>[
                  type.toUpperCase(),
                  if (part.isNotEmpty) 'Part # $part',
                  'Qty ${line['quantity'] ?? 1}',
                  'Price ${_money(line['unit_price'])}',
                ].join(' • '),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editLine(index),
            ),
          );
        }),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _PreviewRow(
                  label: 'Source subtotal',
                  value: _money(extraction['subtotal']),
                ),
                _PreviewRow(
                  label: 'Source tax',
                  value: _money(extraction['sales_tax']),
                ),
                const Divider(),
                _PreviewRow(
                  label: 'Source total',
                  value: _money(extraction['total']),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'After creation, Briskers will automatically check every imported part number for the current OEM/dealer list price. Unclear results will be marked Needs review.',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: BriskersColors.estimates,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: lines.isEmpty ? null : _createEstimate,
          icon: const Icon(Icons.download_done_outlined),
          label: const Text('Create Briskers estimate'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.estimates.withValues(alpha: 0.09),
        title: const Text('Import from Identifix'),
      ),
      body: _creating
          ? _creatingView()
          : _extraction == null
              ? _initialView()
              : _preview(),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

class _ImportLineDialog extends StatefulWidget {
  const _ImportLineDialog({required this.line});

  final Map<String, dynamic> line;

  @override
  State<_ImportLineDialog> createState() => _ImportLineDialogState();
}

class _ImportLineDialogState extends State<_ImportLineDialog> {
  late final TextEditingController _description;
  late final TextEditingController _partNumber;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late String _type;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.line['type']?.toString() ?? 'other';
    _description = TextEditingController(
      text: widget.line['description']?.toString() ?? '',
    );
    _partNumber = TextEditingController(
      text: widget.line['part_number']?.toString() ?? '',
    );
    _quantity = TextEditingController(
      text: widget.line['quantity']?.toString() ?? '1',
    );
    _price = TextEditingController(
      text: widget.line['unit_price']?.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _description.dispose();
    _partNumber.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = num.tryParse(_quantity.text.trim());
    final price = num.tryParse(_price.text.trim());
    if (_description.text.trim().isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        price == null ||
        price < 0) {
      setState(() => _error = 'Enter a description, quantity and price.');
      return;
    }

    Navigator.pop(
      context,
      <String, dynamic>{
        'type': _type,
        'description': _description.text.trim(),
        'part_number': _partNumber.text.trim().isEmpty
            ? null
            : _partNumber.text.trim(),
        'quantity': quantity,
        'unit_price': price,
        'line_total': quantity * price,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review imported line'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'part', child: Text('Part')),
                DropdownMenuItem(value: 'labor', child: Text('Labor')),
                DropdownMenuItem(value: 'supply', child: Text('Supply')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _partNumber,
              decoration: const InputDecoration(labelText: 'Part number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Imported unit price',
                prefixText: '\$ ',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Use line'),
        ),
      ],
    );
  }
}
