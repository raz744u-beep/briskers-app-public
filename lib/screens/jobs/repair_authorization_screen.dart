import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/briskers_colors.dart';
import '../../core/repair_group.dart';
import '../../services/local_repair_groups.dart';
import '../../widgets/repair_evidence_photo.dart';

/// The same local review document will be used by document-scoped kiosk
/// sessions. This Owner-device entry point does not perform any network I/O.
class RepairAuthorizationScreen extends StatefulWidget {
  const RepairAuthorizationScreen({super.key, required this.business,
    required this.estimate, required this.detail, required this.store});
  final String business, estimate;
  final Map<String, dynamic> detail;
  final LocalRepairGroups store;
  @override State<RepairAuthorizationScreen> createState() => _RepairAuthorizationScreenState();
}
class _RepairAuthorizationScreenState extends State<RepairAuthorizationScreen> {
  final event = LocalRepairGroups.newId();
  final signatureKey = GlobalKey();
  final strokes = <List<Offset>>[];
  final signer = TextEditingController();
  final notes = TextEditingController();
  final choices = <String, RepairDecision>{};
  late final Future<({List<RepairGroup> groups, Map<String, dynamic> scope})> review;
  RepairAuthorizationMethod method = RepairAuthorizationMethod.deviceSignature;
  bool reviewing = false, busy = false;
  String? error;
  @override void initState() {
    super.initState();
    signer.text = widget.detail['customer_name']?.toString() ?? '';
    review = _load();
  }
  Future<({List<RepairGroup> groups, Map<String, dynamic> scope})> _load() async => (
    groups: (await widget.store.groups(widget.business, widget.estimate, widget.detail))
      .where((group) => group.lines.isNotEmpty).toList(),
    scope: await widget.store.snapshot(widget.business, widget.estimate, widget.detail),
  );
  @override void dispose() { signer.dispose(); notes.dispose(); super.dispose(); }
  bool get signed => method == RepairAuthorizationMethod.deviceSignature;
  bool get hasSignature => strokes.any((stroke) => stroke.length > 1);
  Future<void> _save(Map<String, dynamic> scope) async {
    if (busy) { return; }
    setState(() { busy = true; error = null; });
    try {
      Uint8List? bytes;
      if (signed) {
        if (!hasSignature) { throw StateError('Please sign before submitting.'); }
        final boundary = signatureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) { throw StateError('Signature is unavailable. Please try again.'); }
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        bytes = png?.buffer.asUint8List();
      }
      await widget.store.authorize(widget.business, widget.estimate, eventId: event,
        expectedScope: scope, decisions: choices, method: method,
        actor: signer.text, notes: notes.text, signature: bytes);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) { if (mounted) setState(() => error = '$failure'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(foregroundColor: Colors.white, title: const Text('Repair authorization'),
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: BriskersColors.blueHeader))),
    body: SafeArea(child: FutureBuilder(future: review, builder: (context, snapshot) {
      final data = snapshot.data;
      if (snapshot.hasError) { return Center(child: Text('Cannot open repair review: ${snapshot.error}')); }
      if (data == null) { return const Center(child: CircularProgressIndicator()); }
      final allChosen = data.groups.isNotEmpty && data.groups.every((group) => choices.containsKey(group.id));
      final approved = data.groups.where((group) => choices[group.id] == RepairDecision.approved)
        .fold<int>(0, (sum, group) => sum + group.quotedCents);
      final charges = (widget.detail['lines'] as List? ?? const []).whereType<Map>()
        .map((line) => Map<String, dynamic>.from(line)).where(RepairGroup.isGeneralCharge).toList();
      final chargeCents = approved > 0 ? charges.fold<int>(0, (sum, line) => sum + RepairGroup.lineCents(line)) : 0;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('Estimate ${widget.detail['document_number'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        Text('${widget.detail['customer_name'] ?? ''} · ${widget.detail['vehicle'] ?? ''}'),
        const SizedBox(height: 12),
        Text(reviewing ? 'Review your selections before submitting.' : 'Approve or decline each repair group.'),
        for (final group in data.groups) Card(color: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(side: const BorderSide(color: BriskersColors.divider), borderRadius: BorderRadius.circular(10)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${group.name} · \$${(group.quotedCents / 100).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (group.description.isNotEmpty) Text(group.description),
            for (final line in group.lines) Padding(padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${line['name']} · Qty ${line['quantity']} · \$${(RepairGroup.lineCents(line) / 100).toStringAsFixed(2)}')),
            for (final evidence in group.evidence) ...[
              if (evidence['body'] != null) Text('${evidence['body']}'),
              Wrap(spacing: 8, children: [for (final photo in (evidence['photos'] as List? ?? const []).whereType<Map>())
                RepairEvidencePhoto(business: widget.business, photo: Map<String, dynamic>.from(photo), store: widget.store) ]),
            ],
            const SizedBox(height: 6),
            if (!reviewing) DropdownButtonFormField<RepairDecision>(
              initialValue: choices[group.id], decoration: const InputDecoration(labelText: 'Decision'),
              items: const [DropdownMenuItem(value: RepairDecision.approved, child: Text('Approved')),
                DropdownMenuItem(value: RepairDecision.declined, child: Text('Declined'))],
              onChanged: busy ? null : (value) { if (value != null) setState(() => choices[group.id] = value); }),
            if (reviewing) Text(choices[group.id] == RepairDecision.approved ? 'Approved' : 'Declined',
              style: TextStyle(color: choices[group.id] == RepairDecision.approved ? BriskersColors.confirm : BriskersColors.destructive)),
          ]))),
        if (charges.isNotEmpty) Text('General charges (supplies / discounts): \$${(chargeCents / 100).toStringAsFixed(2)}'),
        Text('Authorized total including tax: \$${((approved + chargeCents) / 100).toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!reviewing) FilledButton(style: FilledButton.styleFrom(backgroundColor: BriskersColors.confirm),
          onPressed: allChosen ? () => setState(() => reviewing = true) : null, child: const Text('Review selections')),
        if (reviewing) ...[
          TextButton(onPressed: busy ? null : () => setState(() { reviewing = false; strokes.clear(); }), child: const Text('Change selections')),
          DropdownButtonFormField<RepairAuthorizationMethod>(initialValue: method,
            decoration: const InputDecoration(labelText: 'Authorization method'),
            items: const [DropdownMenuItem(value: RepairAuthorizationMethod.deviceSignature, child: Text('Customer signature on this device')),
              DropdownMenuItem(value: RepairAuthorizationMethod.telephone, child: Text('Owner-recorded telephone authorization')),
              DropdownMenuItem(value: RepairAuthorizationMethod.inPerson, child: Text('Owner-recorded in-person authorization'))],
            onChanged: busy ? null : (value) { if (value != null) setState(() { method = value; strokes.clear(); }); }),
          TextField(controller: signer, enabled: !busy, decoration: InputDecoration(labelText: signed ? 'Customer name' : 'Recorded by')),
          TextField(controller: notes, enabled: !busy, maxLines: 3,
            decoration: InputDecoration(labelText: signed ? 'Notes (optional)' : 'Authorization notes (required)')),
          if (signed) ...[
            const SizedBox(height: 10), const Text('Customer signature'),
            RepaintBoundary(key: signatureKey, child: SizedBox(height: 170, child: ClipRect(child: GestureDetector(
              onPanStart: busy ? null : (details) => setState(() => strokes.add([details.localPosition])),
              onPanUpdate: busy ? null : (details) => setState(() { if (strokes.isNotEmpty) strokes.last.add(details.localPosition); }),
              child: CustomPaint(painter: _RepairSignaturePainter(strokes), child: const SizedBox.expand()))))),
            TextButton(onPressed: busy ? null : () => setState(strokes.clear), child: const Text('Clear signature')),
          ],
          if (error != null) Text(error!, style: const TextStyle(color: BriskersColors.destructive)),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: BriskersColors.confirm),
            onPressed: busy || !allChosen ? null : () => _save(data.scope), child: Text(busy ? 'Saving…' : 'Submit authorization')),
        ],
      ]);
    })),
  );
}
class _RepairSignaturePainter extends CustomPainter {
  const _RepairSignaturePainter(this.strokes);
  final List<List<Offset>> strokes;
  @override void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final ink = Paint()..color = BriskersColors.text..strokeWidth = 3
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) { continue; }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) { path.lineTo(point.dx, point.dy); }
      canvas.drawPath(path, ink);
    }
  }
  @override bool shouldRepaint(covariant _RepairSignaturePainter oldDelegate) => true;
}
