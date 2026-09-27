import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/briskers_api.dart';

class CustomerVehicleFindingsSection extends StatefulWidget {
  const CustomerVehicleFindingsSection({
    super.key,
    required this.businessId,
    required this.vehicles,
  });

  final String businessId;
  final List<dynamic> vehicles;

  @override
  State<CustomerVehicleFindingsSection> createState() =>
      _CustomerVehicleFindingsSectionState();
}

class _CustomerVehicleFindingsSectionState
    extends State<CustomerVehicleFindingsSection> {
  static const _api = BriskersApi();

  late Future<List<Map<String, dynamic>>> _findingsFuture;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _findingsFuture = _allFindings();
  }

  @override
  void didUpdateWidget(covariant CustomerVehicleFindingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.vehicles != widget.vehicles) {
      _findingsFuture = _allFindings();
    }
  }

  Future<List<Map<String, dynamic>>> _allFindings() async {
    final all = <Map<String, dynamic>>[];

    for (final raw in widget.vehicles) {
      final vehicle = Map<String, dynamic>.from(raw as Map);
      final vehicleId = vehicle['id']?.toString() ?? '';
      if (vehicleId.isEmpty) continue;

      final rows = await _api.vehicleFindings(
        widget.businessId,
        vehicleId,
        includeResolved: true,
      );

      final vehicleLabel = _vehicleLabel(vehicle);
      for (final row in rows) {
        all.add(<String, dynamic>{
          ...row,
          '_vehicle_id': vehicleId,
          '_vehicle_label': vehicleLabel,
        });
      }
    }

    return all;
  }

  String _vehicleLabel(Map<String, dynamic> vehicle) => <String>[
        if (vehicle['year'] != null) vehicle['year'].toString(),
        if ((vehicle['make']?.toString() ?? '').isNotEmpty)
          vehicle['make'].toString(),
        if ((vehicle['model']?.toString() ?? '').isNotEmpty)
          vehicle['model'].toString(),
      ].join(' ');

  String _dateLabel(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    return DateFormat('MMM d, yyyy').format(parsed.toLocal());
  }

  Future<void> _showPhotoGallery(
    BuildContext context,
    List<Map<String, dynamic>> attachments, {
    int initialIndex = 0,
  }) async {
    if (attachments.isEmpty) return;

    try {
      final urls = <String>[];
      for (final attachment in attachments) {
        final bucket = attachment['bucket']?.toString() ?? '';
        final key = attachment['key']?.toString() ?? '';
        if (bucket.isEmpty || key.isEmpty) continue;
        urls.add(await _api.signedAttachmentUrl(bucket, key));
      }

      if (urls.isEmpty || !context.mounted) return;

      var current = initialIndex.clamp(0, urls.length - 1);
      final controller = PageController(initialPage: current);

      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: urls.length,
                    onPageChanged: (index) =>
                        setDialogState(() => current = index),
                    itemBuilder: (context, index) => InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image.network(
                          urls[index],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 56,
                          ),
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
                if (urls.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${current + 1} / ${urls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      controller.dispose();
    } catch (_) {
      // Keep the findings list usable even if a photo cannot be opened.
    }
  }

  Widget _findingThumbnail(
    BuildContext context,
    List<Map<String, dynamic>> attachments,
  ) {
    const size = 58.0;

    if (attachments.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.car_repair_outlined,
          color: Colors.deepOrange,
          size: 25,
        ),
      );
    }

    final first = attachments.first;
    final bucket = first['bucket']?.toString() ?? '';
    final key = first['key']?.toString() ?? '';

    if (bucket.isEmpty || key.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.deepOrange,
        ),
      );
    }

    return FutureBuilder<String>(
      future: _api.signedAttachmentUrl(bucket, key),
      builder: (context, snapshot) {
        final image = snapshot.hasData
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  snapshot.data!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    color: const Color(0xFFF3F5F7),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
              )
            : const SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: snapshot.hasData
              ? () => _showPhotoGallery(context, attachments)
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              image,
              if (attachments.length > 1)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+${attachments.length - 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _findingRow(
    BuildContext context,
    Map<String, dynamic> finding, {
    required bool showVehicle,
  }) {
    final attachments = List<dynamic>.from(
      finding['attachments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final body = finding['body']?.toString().trim() ?? '';
    final date = _dateLabel(finding['created_at']);
    final vehicle = finding['_vehicle_label']?.toString().trim() ?? '';

    final subtitle = <String>[
      if (date.isNotEmpty) date,
      if (showVehicle && vehicle.isNotEmpty) vehicle,
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
      child: Row(
        children: [
          _findingThumbnail(context, attachments),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  body.isEmpty ? 'Vehicle finding' : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            size: 24,
            color: Color(0xFF374151),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vehicles.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _findingsFuture,
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final open = allRows
            .where((finding) => finding['status']?.toString() == 'open')
            .toList();
        final resolved = allRows
            .where((finding) => finding['status']?.toString() == 'resolved')
            .toList();

        final showVehicle = widget.vehicles.length > 1;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: false,
            onExpansionChanged: (value) =>
                setState(() => _expanded = value),
            tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            childrenPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.car_repair_outlined,
              color: Colors.deepOrange,
            ),
            title: const Text(
              'Vehicle Findings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Open issues that follow the vehicle'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (!_expanded && open.isNotEmpty)
                  _FindingCountTriangle(count: open.length),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 24,
                  color: const Color(0xFF374151),
                ),
              ],
            ),
            children: [
              if (open.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No open findings'),
                  ),
                )
              else
                for (var index = 0; index < open.length; index++) ...[
                  _findingRow(
                    context,
                    open[index],
                    showVehicle: showVehicle,
                  ),
                  if (index != open.length - 1)
                    const Divider(
                      height: 1,
                      indent: 86,
                      endIndent: 16,
                    ),
                ],
              if (resolved.isNotEmpty) ...[
                const Divider(height: 1),
                ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: Text(
                    resolved.length == 1
                        ? '1 resolved finding'
                        : '${resolved.length} resolved findings',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  children: [
                    for (var index = 0; index < resolved.length; index++) ...[
                      _findingRow(
                        context,
                        resolved[index],
                        showVehicle: showVehicle,
                      ),
                      if (index != resolved.length - 1)
                        const Divider(
                          height: 1,
                          indent: 86,
                          endIndent: 16,
                        ),
                    ],
                  ],
                ),
              ],
            ],
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
