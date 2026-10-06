import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';

class CustomerVehicleFindingsSection extends StatefulWidget {
  const CustomerVehicleFindingsSection({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.vehicles,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;

  @override
  State<CustomerVehicleFindingsSection> createState() =>
      _CustomerVehicleFindingsSectionState();
}

class _CustomerVehicleFindingsSectionState
    extends State<CustomerVehicleFindingsSection> {
  static const _api = BriskersApi();
  static const _cache = CustomerDetailCache();
  final ImagePicker _picker = ImagePicker();

  late Future<List<Map<String, dynamic>>> _findingsFuture;
  bool _expanded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _findingsFuture = _allFindings();
  }

  @override
  void didUpdateWidget(covariant CustomerVehicleFindingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId ||
        oldWidget.vehicles != widget.vehicles) {
      _findingsFuture = _allFindings();
    }
  }

  Future<void> _refresh() async {
    final future = _allFindings();
    setState(() {
      _findingsFuture = future;
      _error = null;
    });
    await future;
  }

  Future<List<Map<String, dynamic>>> _allFindings() async {
    if (BriskersConnectionModeController.instance.forceOffline) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'findings',
      );
      return cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
    }

    final all = <Map<String, dynamic>>[];
    try {
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
      await _cache.save(
        widget.businessId,
        widget.customerId,
        'findings',
        all,
      );
      return all;
    } catch (_) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'findings',
      );
      return cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
    }
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

  String _imageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<Map<String, dynamic>?> _chooseVehicle() async {
    final vehicles = widget.vehicles
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((vehicle) => (vehicle['id']?.toString() ?? '').isNotEmpty)
        .toList();

    if (vehicles.isEmpty) return null;
    if (vehicles.length == 1) return vehicles.first;

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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            ...vehicles.map(
              (vehicle) => ListTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(
                  _vehicleLabel(vehicle).isEmpty
                      ? 'Vehicle'
                      : _vehicleLabel(vehicle),
                ),
                subtitle: (vehicle['vin']?.toString() ?? '').isEmpty
                    ? null
                    : Text('VIN: ${vehicle['vin']}'),
                onTap: () => Navigator.pop(sheetContext, vehicle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFinding() async {
    if (_busy) return;

    final vehicle = await _chooseVehicle();
    if (vehicle == null || !mounted) return;
    final vehicleId = vehicle['id']?.toString() ?? '';
    if (vehicleId.isEmpty) return;

    final controller = TextEditingController();
    final photos = <XFile>[];
    var includeOnInvoice = false;

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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add finding — ${_vehicleLabel(vehicle)}',
                      style: const TextStyle(
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
                      hintText: 'Example: Oil leak visible around valve cover',
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                    child: FilledButton.icon(
                      onPressed: () {
                        if (controller.text.trim().isEmpty) return;
                        Navigator.pop(sheetContext, true);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add finding'),
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

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final findingId = await _api.createVehicleFindingForVehicle(
        widget.businessId,
        widget.customerId,
        vehicleId,
        body: body,
        includeOnInvoice: includeOnInvoice,
      );

      for (final photo in photos) {
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _imageMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }

      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<List<Map<String, dynamic>>> _uploadMorePhotos(
    String findingId,
    List<Map<String, dynamic>> current,
  ) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('You can select multiple photos'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return current;

    final picked = <XFile>[];
    if (source == 'gallery') {
      picked.addAll(
        await _picker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1920,
          maxHeight: 1920,
        ),
      );
    } else {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null) picked.add(photo);
    }

    if (picked.isEmpty) return current;

    setState(() => _busy = true);
    try {
      for (final photo in picked) {
        await _api.uploadVehicleFindingPhoto(
          widget.businessId,
          findingId,
          filename: photo.name,
          mimeType: _imageMime(photo.name),
          bytes: await photo.readAsBytes(),
        );
      }

      final rows = await _allFindings();
      final updated = rows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == findingId,
            orElse: () => null,
          );
      if (updated == null) return current;
      return List<dynamic>.from(
        updated['attachments'] ?? const [],
      ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFinding(Map<String, dynamic> finding) async {
    final findingId = finding['id']?.toString() ?? '';
    if (findingId.isEmpty || !mounted) return;

    var localBody = finding['body']?.toString().trim() ?? '';
    var localAttachments = List<dynamic>.from(
      finding['attachments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    var includeOnInvoice = finding['include_on_invoice'] == true;
    var actionBusy = false;
    var changed = false;
    var addAnother = false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final vehicle = finding['_vehicle_label']?.toString().trim() ?? '';
          final date = _dateLabel(finding['created_at']);
          final rawStatus = finding['status']?.toString() ?? 'open';
          final status = rawStatus == 'resolved'
              ? 'Resolved'
              : rawStatus == 'in_job'
                  ? 'In Job'
                  : 'Open';

          Future<void> editFinding() async {
            final controller = TextEditingController(text: localBody);
            final updatedBody = await showDialog<String>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Edit finding'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'Finding',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) {
                        Navigator.pop(dialogContext, value);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            controller.dispose();
            if (updatedBody == null || updatedBody == localBody) return;

            setSheetState(() => actionBusy = true);
            try {
              await _api.updateVehicleFinding(
                widget.businessId,
                findingId,
                body: updatedBody,
              );
              changed = true;
              setSheetState(() => localBody = updatedBody);
            } catch (error) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => actionBusy = false);
              }
            }
          }

          Future<void> deleteFinding() async {
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Delete finding?'),
                content: const Text(
                  'This will permanently delete this vehicle finding.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;

            setSheetState(() => actionBusy = true);
            try {
              await _api.deleteVehicleFinding(
                widget.businessId,
                findingId,
              );
              changed = true;
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (error) {
              if (sheetContext.mounted) {
                setSheetState(() => actionBusy = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            }
          }

          Future<void> toggleInvoiceNotes(bool value) async {
            setSheetState(() => actionBusy = true);
            try {
              await _api.setVehicleFindingInvoiceFlag(
                widget.businessId,
                findingId,
                value,
              );
              changed = true;
              setSheetState(() => includeOnInvoice = value);
            } catch (error) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => actionBusy = false);
              }
            }
          }

          Future<void> addPhotos() async {
            try {
              final updated = await _uploadMorePhotos(
                findingId,
                localAttachments,
              );
              if (updated.length != localAttachments.length) {
                changed = true;
                if (sheetContext.mounted) {
                  setSheetState(() => localAttachments = updated);
                }
              }
            } catch (error) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            }
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vehicle finding',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: status == 'Open'
                            ? const Color(0xFFA56B00)
                            : status == 'In Job'
                                ? Colors.blue
                                : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (vehicle.isNotEmpty)
                  Text(
                    vehicle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (date.isNotEmpty) Text(date),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: actionBusy ? null : editFinding,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: actionBusy ? null : deleteFinding,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  localBody.isEmpty ? 'Vehicle finding' : localBody,
                  style: const TextStyle(fontSize: 16, height: 1.35),
                ),
                const SizedBox(height: 16),
                Text(
                  localAttachments.isEmpty
                      ? 'Photos'
                      : 'Photos (${localAttachments.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...localAttachments.map(
                      (attachment) => _findingThumbnail(
                        sheetContext,
                        [attachment],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: actionBusy || _busy ? null : addPhotos,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, size: 30),
                            SizedBox(height: 2),
                            Text(
                              'Add photo',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: includeOnInvoice,
                  onChanged: actionBusy
                      ? null
                      : (value) =>
                          toggleInvoiceNotes(value == true),
                  title: const Text(
                    'Include on invoice notes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    includeOnInvoice
                        ? 'Included in invoice notes.'
                        : 'Not included in invoice notes.',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: actionBusy
                      ? null
                      : () {
                          addAnother = true;
                          Navigator.pop(sheetContext);
                        },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add another finding'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (changed && mounted) await _refresh();
    if (addAnother && mounted) await _addFinding();
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

    final status = finding['status']?.toString() ?? 'open';
    final repairJob = finding['repair_job_number']?.toString() ?? '';
    final subtitle = <String>[
      if (status == 'in_job')
        repairJob.isEmpty ? 'In job' : 'In $repairJob',
      if (date.isNotEmpty) date,
      if (showVehicle && vehicle.isNotEmpty) vehicle,
    ].join(' • ');

    return InkWell(
      onTap: () => _openFinding(finding),
      child: Padding(
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
            .where((finding) =>
                finding['status']?.toString() != 'resolved')
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 12, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: BriskersConnectionModeController.instance.forceOffline || _busy
                        ? null
                        : _addFinding,
                    icon: const Icon(Icons.add_circle_outline, size: 19),
                    label: const Text('Add finding'),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
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
