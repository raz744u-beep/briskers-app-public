import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/briskers_colors.dart';

class CustomerInvoiceSignatureScreen extends StatefulWidget {
  const CustomerInvoiceSignatureScreen({
    super.key,
    required this.customerName,
    required this.invoiceNumber,
    required this.invoiceTotal,
    required this.disclaimers,
    required this.extendedWarranty,
  });

  final String customerName;
  final String invoiceNumber;
  final String invoiceTotal;
  final List<Map<String, dynamic>> disclaimers;
  final bool extendedWarranty;

  @override
  State<CustomerInvoiceSignatureScreen> createState() =>
      _CustomerInvoiceSignatureScreenState();
}

class _CustomerInvoiceSignatureScreenState
    extends State<CustomerInvoiceSignatureScreen> {
  final GlobalKey _signatureKey = GlobalKey();
  final TextEditingController _nameController = TextEditingController();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.customerName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _hasSignature =>
      _strokes.any((stroke) => stroke.length > 1);

  void _startStroke(Offset point) {
    setState(() {
      _strokes.add(<Offset>[point]);
    });
  }

  void _continueStroke(Offset point) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.add(point);
    });
  }

  void _clear() {
    setState(_strokes.clear);
  }

  Future<Uint8List?> _renderSignature() async {
    final boundary =
        _signatureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return data?.buffer.asUint8List();
  }

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || !_hasSignature || _saving) return;

    setState(() => _saving = true);
    try {
      final bytes = await _renderSignature();
      if (bytes == null || !mounted) return;
      Navigator.pop(
        context,
        <String, dynamic>{
          'signer_name': name,
          'bytes': bytes,
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.invoiceNumber.isEmpty
        ? 'Review & Sign Invoice'
        : 'Review & Sign Invoice #${widget.invoiceNumber}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.invoices,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Text(
              'Customer review',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please review the invoice and acknowledgments below before signing.',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              color: BriskersColors.invoices.withValues(alpha: 0.07),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: BriskersColors.invoices,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.invoiceNumber.isEmpty
                            ? 'Invoice'
                            : 'Invoice #${widget.invoiceNumber}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      widget.invoiceTotal,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: BriskersColors.invoices,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.extendedWarranty) ...[
              const SizedBox(height: 14),
              const Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    Icons.shield_outlined,
                    color: BriskersColors.invoices,
                  ),
                  title: Text(
                    'Extended warranty invoice',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Your signature is required for warranty submission.',
                  ),
                ),
              ),
            ],
            if (widget.disclaimers.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Acknowledgments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.disclaimers.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item['title']?.toString() ??
                              'Customer acknowledgment',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['body']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Customer name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Customer signature',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _strokes.isEmpty ? null : _clear,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            RepaintBoundary(
              key: _signatureKey,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _hasSignature
                        ? BriskersColors.invoices
                        : const Color(0xFFCBD5E1),
                    width: _hasSignature ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) =>
                          _startStroke(details.localPosition),
                      onPanUpdate: (details) =>
                          _continueStroke(details.localPosition),
                      child: CustomPaint(
                        painter: _SignaturePainter(_strokes),
                        size: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign inside the box using a finger or stylus.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskersColors.invoices,
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    _hasSignature &&
                            _nameController.text.trim().isNotEmpty &&
                            !_saving
                        ? _confirm
                        : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _saving ? 'Saving signature...' : 'Accept & Sign',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
