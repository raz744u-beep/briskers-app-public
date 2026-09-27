import 'package:flutter/material.dart';

import '../../services/briskers_api.dart';

class CustomerVehicleFindingsSection extends StatelessWidget {
  const CustomerVehicleFindingsSection({
    super.key,
    required this.businessId,
    required this.vehicles,
  });

  final String businessId;
  final List<dynamic> vehicles;

  static const _api = BriskersApi();

  Future<List<Map<String, dynamic>>> _allFindings() async {
    final all = <Map<String, dynamic>>[];
    for (final raw in vehicles) {
      final vehicle = Map<String, dynamic>.from(raw as Map);
      final vehicleId = vehicle['id']?.toString() ?? '';
      if (vehicleId.isEmpty) continue;
      final rows = await _api.vehicleFindings(
        businessId,
        vehicleId,
        includeResolved: true,
      );
      for (final row in rows) {
        all.add(<String, dynamic>{
          ...row,
          '_vehicle_id': vehicleId,
        });
      }
    }
    return all;
  }

  Future<void> _showPhoto(
    BuildContext context,
    Map<String, dynamic> attachment,
  ) async {
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';
    if (bucket.isEmpty || key.isEmpty) return;

    final url = await _api.signedAttachmentUrl(bucket, key);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton.filled(
                tooltip: 'Close photo',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(
    BuildContext context,
    Map<String, dynamic> attachment,
  ) {
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';
    if (bucket.isEmpty || key.isEmpty) {
      return const Icon(
        Icons.warning_amber_rounded,
        color: Colors.deepOrange,
      );
    }
    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        final child = snapshot.hasData
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  snapshot.data!,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.deepOrange,
                  ),
                ),
              )
            : const SizedBox(
                width: 58,
                height: 58,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: snapshot.hasData ? () => _showPhoto(context, attachment) : null,
          child: child,
        );
      },
    );
  }

  String _vehicleLabel(Map<String, dynamic> vehicle) => <String>[
        if (vehicle['year'] != null) vehicle['year'].toString(),
        if ((vehicle['make']?.toString() ?? '').isNotEmpty)
          vehicle['make'].toString(),
        if ((vehicle['model']?.toString() ?? '').isNotEmpty)
          vehicle['model'].toString(),
      ].join(' ');

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _allFindings(),
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final totalOpen = allRows
            .where((finding) => finding['status']?.toString() == 'open')
            .length;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(
              Icons.car_repair_outlined,
              color: Colors.deepOrange,
            ),
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vehicle Findings',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (totalOpen > 0)
                  _FindingCountTriangle(count: totalOpen),
              ],
            ),
            subtitle: const Text('Open issues that follow the vehicle'),
            children: vehicles.map((raw) {
              final vehicle = Map<String, dynamic>.from(raw as Map);
              final vehicleId = vehicle['id']?.toString() ?? '';
              final label = _vehicleLabel(vehicle);
              final rows = allRows
                  .where(
                    (finding) =>
                        finding['_vehicle_id']?.toString() == vehicleId,
                  )
                  .toList();
              final open = rows
                  .where((finding) => finding['status']?.toString() == 'open')
                  .toList();
              final resolved = rows
                  .where(
                    (finding) =>
                        finding['status']?.toString() == 'resolved',
                  )
                  .toList();

              return ExpansionTile(
                initiallyExpanded: open.isNotEmpty,
                leading: CircleAvatar(
                  radius: 18,
                  child: Text(
                    open.length.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(
                  label.isEmpty ? 'Vehicle' : label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  open.isEmpty
                      ? 'No open findings'
                      : open.length == 1
                          ? '1 open finding'
                          : '${open.length} open findings',
                ),
                children: [
                  ...open.map((finding) {
                    final attachments = List<dynamic>.from(
                      finding['attachments'] ?? const [],
                    );
                    final job =
                        finding['found_job_number']?.toString() ?? '';
                    final invoice =
                        finding['found_document_number']?.toString() ?? '';

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(
                              finding['body']?.toString() ?? '',
                            ),
                            subtitle: Text(
                              <String>[
                                if (invoice.isNotEmpty)
                                  'Found Invoice #$invoice',
                                if (invoice.isEmpty && job.isNotEmpty)
                                  'Found $job',
                                if (attachments.isNotEmpty)
                                  attachments.length == 1
                                      ? '1 photo'
                                      : '${attachments.length} photos',
                                if (finding['include_on_invoice'] == true)
                                  'Invoice note',
                              ].join(' • '),
                            ),
                          ),
                          if (attachments.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: attachments
                                    .map(
                                      (raw) => _thumbnail(
                                        context,
                                        Map<String, dynamic>.from(
                                          raw as Map,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (resolved.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        resolved.length == 1
                            ? '1 resolved finding'
                            : '${resolved.length} resolved findings',
                      ),
                      children: resolved
                          .map(
                            (finding) => ListTile(
                              leading: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                              ),
                              title:
                                  Text(finding['body']?.toString() ?? ''),
                              subtitle: Text(
                                (finding['resolved_document_number']
                                                ?.toString() ??
                                            '')
                                        .isNotEmpty
                                    ? 'Resolved Invoice #${finding['resolved_document_number']}'
                                    : (finding['resolved_job_number']
                                                    ?.toString() ??
                                                '')
                                            .isNotEmpty
                                        ? 'Resolved ${finding['resolved_job_number']}'
                                        : 'Resolved',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

}


class _FindingCountTriangle extends StatelessWidget {
  const _FindingCountTriangle({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return SizedBox(
      width: 27,
      height: 24,
      child: CustomPaint(
        painter: const _FindingTrianglePainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF5A3A00),
                fontSize: label.length > 2 ? 8.5 : 11.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FindingTrianglePainter extends CustomPainter {
  const _FindingTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF4B400)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FindingTrianglePainter oldDelegate) => false;
}
