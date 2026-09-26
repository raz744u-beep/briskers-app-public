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

  Widget _thumbnail(Map<String, dynamic> attachment) {
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
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.deepOrange,
            ),
          ),
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(
          Icons.car_repair_outlined,
          color: Colors.deepOrange,
        ),
        title: const Text(
          'Vehicle Findings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Open issues that follow the vehicle'),
        children: vehicles.map((raw) {
          final vehicle = Map<String, dynamic>.from(raw as Map);
          final vehicleId = vehicle['id']?.toString() ?? '';
          final label = _vehicleLabel(vehicle);

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _api.vehicleFindings(
              businessId,
              vehicleId,
              includeResolved: true,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Loading findings...'),
                );
              }

              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              final open = rows
                  .where((finding) => finding['status']?.toString() == 'open')
                  .toList();
              final resolved = rows
                  .where(
                    (finding) => finding['status']?.toString() == 'resolved',
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
                    final job = finding['found_job_number']?.toString() ?? '';
                    return ListTile(
                      leading: attachments.isEmpty
                          ? const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.deepOrange,
                            )
                          : _thumbnail(
                              Map<String, dynamic>.from(
                                attachments.first as Map,
                              ),
                            ),
                      title: Text(finding['body']?.toString() ?? ''),
                      subtitle: Text(
                        <String>[
                          if (job.isNotEmpty) 'Found $job',
                          if (attachments.isNotEmpty)
                            attachments.length == 1
                                ? '1 photo'
                                : '${attachments.length} photos',
                          if (finding['include_on_invoice'] == true)
                            'Invoice note',
                        ].join(' • '),
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
                                (finding['resolved_job_number']?.toString() ??
                                        '')
                                    .isEmpty
                                    ? 'Resolved'
                                    : 'Resolved ${finding['resolved_job_number']}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
