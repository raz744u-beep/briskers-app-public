import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/connection_mode.dart';
import '../../core/briskers_colors.dart';
import '../../local/local_database_provider.dart';
import '../../widgets/vehicle_findings.dart';
import '../../services/offline_work_findings_service.dart';
import '../../services/work_finding_merge.dart';
import '../../services/vehicle_finding_actions_service.dart';
import '../../services/finding_job_choice_policy.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';
import '../../services/job_summary_visibility.dart';
import '../../services/local_attachment_cache.dart';
import '../../services/offline_customer_detail_write_service.dart';

class CustomerVehicleFindingsSection extends StatefulWidget {
  const CustomerVehicleFindingsSection({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.vehicles,
    this.canManage = false,
    this.canDelete = false,
    this.initiallyExpanded = false,
    this.cacheScopeKey,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;
  final bool canManage;
  final bool canDelete;
  final bool initiallyExpanded;
  // Invoice entry uses a vehicle-scoped snapshot so it cannot overwrite
  // the Customer Overview's multi-vehicle cached Findings.
  final String? cacheScopeKey;

  @override
  State<CustomerVehicleFindingsSection> createState() =>
      _CustomerVehicleFindingsSectionState();
}

class _CustomerVehicleFindingsSectionState
    extends State<CustomerVehicleFindingsSection> {
  static const _api = BriskersApi();
  static const _cache = CustomerDetailCache();
  final LocalAttachmentCache _attachmentCache = LocalAttachmentCache();
  final OfflineCustomerDetailWriteService _offlineWrites =
      OfflineCustomerDetailWriteService();
  final ImagePicker _picker = ImagePicker();
  final _workFindings = OfflineWorkFindingsService();
  final _findingActions = VehicleFindingActionsService();
  StreamSubscription<String>? _findingChanges;

  late JobSummaryVisibility _jobVisibility;
  final ValueNotifier<int> _quarantineChanges = ValueNotifier(0);
  late Future<List<Map<String, dynamic>>> _findingsFuture;
  bool _expanded = false;
  bool _busy = false;
  String? _error;
  String get _findingCacheSection => widget.cacheScopeKey ?? 'findings';

  // Flutter parents often rebuild their vehicle list with a new List object.
  // Compare stable vehicle identities, not List identity, to avoid restarting
  // Findings loads (and reappearing spinners) on every unrelated rebuild.
  String _vehicleIds(List<dynamic> vehicles) {
    final ids = vehicles.whereType<Map>()
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toList()..sort();
    return ids.join('|');
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _listenForQuarantine();
    _findingsFuture = _allFindings();
    _findingChanges = VehicleFindingActionsService.changes.listen((businessId) {
      if (mounted && businessId == widget.businessId) {
        setState(() => _findingsFuture = _allFindings(cacheOnly: true));
      }
    });
  }

  void _listenForQuarantine() {
    _jobVisibility = JobSummaryVisibility(
      businessId: widget.businessId,
      onQuarantine: (_) {
        if (!mounted) return;
        _quarantineChanges.value++;
        // Reset the FutureBuilder so its retained old data cannot paint while
        // the exact archived finding identities are checked in the database.
        setState(() => _findingsFuture = _allFindings(cacheOnly: true));
      },
    );
  }

  @override
  void dispose() {
    _findingChanges?.cancel();
    _jobVisibility.dispose();
    _quarantineChanges.dispose();
    super.dispose();
  }

  Widget _guardModal(
    int generation,
    Widget child,
  ) => ValueListenableBuilder<int>(
    valueListenable: _quarantineChanges,
    child: child,
    builder: (context, current, content) => current == generation
        ? content!
        : const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Job access changed. Close and reopen to verify this finding.',
              ),
            ),
          ),
  );

  @override
  void didUpdateWidget(covariant CustomerVehicleFindingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId) {
      _jobVisibility.dispose();
      _quarantineChanges.value++;
      _listenForQuarantine();
    }
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId ||
        oldWidget.cacheScopeKey != widget.cacheScopeKey ||
        _vehicleIds(oldWidget.vehicles) != _vehicleIds(widget.vehicles)) {
      _findingsFuture = _allFindings();
    }
  }

  Future<void> _refresh({bool cacheOnly = false}) async {
    if (!mounted) return;
    final future = _allFindings(cacheOnly: cacheOnly);
    setState(() {
      _findingsFuture = future;
      _error = null;
    });
    await future;
  }

  Future<List<Map<String, dynamic>>> _allFindings({
    bool cacheOnly = false,
  }) async {
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    final businessId = widget.businessId;
    final customerId = widget.customerId;
    Future<List<Map<String, dynamic>>> cachedFindings() async {
      final cached = await _cache.load(
        businessId, customerId, _findingCacheSection);
      final rows = cached is List
          ? cached
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      await _findingActions.recoverPendingCustomerCache(businessId, rows);
      final local = <Map<String, dynamic>>[];
      for (final raw in widget.vehicles.whereType<Map>()) {
        final vehicle = Map<String, dynamic>.from(raw);
        final vehicleId = vehicle['id']?.toString() ?? '';
        if (vehicleId.isEmpty) continue;
        final found = await _workFindings.loadLocalFindings(
          businessId,
          vehicleId,
        );
        local.addAll(
          found.map(
            (row) => {
              ...row,
              '_vehicle_id': vehicleId,
              '_vehicle_label': _vehicleLabel(vehicle),
            },
          ),
        );
      }
      final vehicleIds = widget.vehicles.whereType<Map>()
          .map((v) => v['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty).toSet();
      final scopedRows = rows.where((row) {
        final vehicle = row['_vehicle_id']?.toString() ??
            row['vehicle_id']?.toString() ?? '';
        return vehicleIds.contains(vehicle);
      }).toList();
      final cachedVisible = await visibility.filterFindings(
          scopedRows, cached: true);
      final localVisible = await visibility.filterFindings(local);
      final visible = await _findingActions.project(
        businessId,
        mergeWorkFindings(cachedVisible, localVisible),
      );
      if (!visibility.isCurrent(generation)) return [];
      await _cache.save(businessId, customerId, _findingCacheSection,
        JobSummaryVisibility.stampSnapshot(visible, await visibility.captureSnapshotGeneration()));
      return visibility.isCurrent(generation) ? visible : [];
    }

    if (cacheOnly || BriskersConnectionModeController.instance.forceOffline) {
      return cachedFindings();
    }

    Future<List<Map<String, dynamic>>> loadRemote() async {
    final all = <Map<String, dynamic>>[];
    try {
      final snapshotGeneration = await visibility.captureSnapshotGeneration();
      for (final raw in widget.vehicles) {
        if (!visibility.isCurrent(generation)) return [];
        final vehicle = Map<String, dynamic>.from(raw as Map);
        final vehicleId = vehicle['id']?.toString() ?? '';
        if (vehicleId.isEmpty) continue;
        final rows = await _api.vehicleFindings(
          businessId,
          vehicleId,
          includeResolved: true,
        );
        final permitted = await visibility.filterFindings(rows);
        if (!visibility.isCurrent(generation)) return [];
        await _workFindings.seedServerFindingsIfClean(
          businessId,
          vehicleId,
          permitted,
        );
        final local = await _workFindings.loadLocalFindings(
          businessId,
          vehicleId,
        );
        final vehicleLabel = _vehicleLabel(vehicle);
        for (final row in mergeWorkFindings(permitted, local)) {
          all.add(<String, dynamic>{
            ...row,
            '_vehicle_id': vehicleId,
            '_vehicle_label': vehicleLabel,
          });
        }
      }
      final visible = await visibility.filterFindings(all);
      if (!visibility.isCurrent(generation)) return [];
      await _cache.save(
        businessId,
        customerId,
        _findingCacheSection,
        JobSummaryVisibility.stampSnapshot(visible, snapshotGeneration),
      );
      // Image downloads must never delay the findings list. Each file is
      // stored in the persistent attachment cache when it becomes available.
      unawaited(() async {
        final pending = <Future<dynamic>>[];
        try {
          for (final finding in visible) {
            if (!visibility.isCurrent(generation)) return;
            final attachments = List<dynamic>.from(
              finding['attachments'] ?? const [],
            ).whereType<Map>().map((raw) => Map<String, dynamic>.from(raw));
            for (final attachment in attachments) {
              final bucket =
                  attachment['bucket']?.toString() ?? 'briskers-private';
              final key = attachment['key']?.toString() ?? '';
              if (key.isEmpty) continue;
              pending.add(_attachmentCache.getOrDownload(bucket, key));
              if (pending.length >= 4) {
                await Future.wait(pending);
                pending.clear();
              }
            }
          }
          if (pending.isNotEmpty) await Future.wait(pending);
        } catch (_) {
          // A photo download error cannot interrupt record navigation.
        }
      }());
      return visibility.isCurrent(generation) ? visible : [];
    } catch (_) {
      if (!visibility.isCurrent(generation)) return [];
      return cachedFindings();
    }
    }

    // Force Online explicitly requests the server; regular Auto mode must
    // paint the permission-scoped local snapshot first instead of waiting
    // through serial per-vehicle RPCs or attachment downloads.
    if (BriskersConnectionModeController.instance.forceOnline) {
      return loadRemote();
    }
    final local = await cachedFindings();
    if (visibility.isCurrent(generation)) {
      unawaited(() async {
        final remote = await loadRemote();
        if (!mounted || !visibility.isCurrent(generation)) return;
        setState(() {
          _findingsFuture =
              Future<List<Map<String, dynamic>>>.value(remote);
        });
      }());
    }
    return local;
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

  Future<void> _previewStagedFindingPhoto(XFile photo) async {
    if (!mounted) return;
    // The selected file is local to this draft. Previewing it must not
    // create, upload, or delete a finding or any photo on disk.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Finding photo',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close photo preview',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.sizeOf(dialogContext).height * 0.65,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.file(
                    File(photo.path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('Cannot preview the selected photo.'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addFinding() async {
    if (_busy || !widget.canManage) return;

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
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(sheetContext).height * 0.48,
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 28,
              ),
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
                    title: const Text('Include in Invoice Notes'),
                    value: includeOnInvoice,
                    onChanged: (value) =>
                        setSheetState(() => includeOnInvoice = value == true),
                  ),
                  if (photos.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        photos.length == 1
                            ? '1 photo selected — tap to preview'
                            : '${photos.length} photos selected — tap to preview',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        key: const ValueKey('finding-selected-photo-strip'),
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final photo = photos[index];
                          return SizedBox(
                            width: 118,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: InkWell(
                                    key: ValueKey('finding-photo-preview-$index'),
                                    onTap: () => _previewStagedFindingPhoto(photo),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(photo.path),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const Center(
                                              child: Icon(Icons.broken_image_outlined),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton.filledTonal(
                                    key: ValueKey('finding-photo-remove-$index'),
                                    tooltip: 'Remove selected photo',
                                    onPressed: () => setSheetState(
                                      () => photos.removeAt(index),
                                    ),
                                    icon: const Icon(Icons.close, size: 18),
                                    iconSize: 18,
                                    constraints: const BoxConstraints(
                                      minWidth: 35, minHeight: 35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _picker.pickMultiImage(
                              imageQuality: 100,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (!sheetContext.mounted) return;
                            if (picked.isNotEmpty) {
                              setSheetState(() => photos.addAll(picked));
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined, color: Colors.teal),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final photo = await _picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 100,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            if (!sheetContext.mounted) return;
                            if (photo != null) {
                              setSheetState(() => photos.add(photo));
                            }
                          },
                          icon: const Icon(Icons.photo_camera_outlined, color: Colors.teal),
                          label: const Text('Camera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                      ),
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
      final stagedPhotos = <Map<String, dynamic>>[];
      for (final photo in photos) {
        stagedPhotos.add({
          'filename': photo.name,
          'mime_type': _imageMime(photo.name),
          'bytes': await photo.readAsBytes(),
        });
      }

      await _offlineWrites.createFinding(
        widget.businessId,
        widget.customerId,
        vehicleId,
        body: body,
        includeOnInvoice: includeOnInvoice,
        photos: stagedPhotos,
      );

      await _refresh(cacheOnly: true);

      if (!BriskersConnectionModeController.instance.forceOffline) {
        unawaited(
          _offlineWrites.flush(widget.businessId).then((_) => _refresh()),
        );
      }
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
    final quarantine = _quarantineChanges.value;

    final images = <ImageProvider>[];
    for (final attachment in attachments) {
      final localPath = attachment['local_file_path']?.toString() ?? '';
      if (localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          images.add(FileImage(file));
          continue;
        }
      }

      final bucket = attachment['bucket']?.toString() ?? 'briskers-private';
      final key = attachment['key']?.toString() ?? '';
      if (key.isEmpty) continue;

      final cached = await _attachmentCache.existing(bucket, key);
      if (cached != null) {
        images.add(FileImage(cached));
        continue;
      }

      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          final file = await _attachmentCache.getOrDownload(bucket, key);
          if (file != null) images.add(FileImage(file));
        } catch (_) {}
      }
    }

    if (images.isEmpty ||
        !context.mounted ||
        quarantine != _quarantineChanges.value) {
      return;
    }

    var current = initialIndex.clamp(0, images.length - 1);
    final controller = PageController(initialPage: current);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => _guardModal(quarantine,
          Dialog(
            insetPadding: const EdgeInsets.all(12),
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: images.length,
                    onPageChanged: (index) =>
                        setDialogState(() => current = index),
                    itemBuilder: (context, index) => InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image(image: images[index], fit: BoxFit.contain),
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
                if (images.length > 1)
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
                          '${current + 1} / ${images.length}',
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
      ),
    );

    controller.dispose();
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
    final localPath = first['local_file_path']?.toString() ?? '';
    if (localPath.isNotEmpty && File(localPath).existsSync()) {
      return InkWell(
        onTap: () => _showPhotoGallery(context, attachments),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(localPath),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final bucket = first['bucket']?.toString() ?? 'briskers-private';
    final key = first['key']?.toString() ?? '';
    if (key.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
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

    return FutureBuilder<File?>(
      future: _attachmentCache.existing(bucket, key),
      builder: (context, snapshot) {
        final file = snapshot.data;
        return InkWell(
          onTap: file == null
              ? null
              : () => _showPhotoGallery(context, attachments),
          child: file == null
              ? Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F5F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    color: Colors.deepOrange,
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    file,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
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
          imageQuality: 100,
          maxWidth: 1920,
          maxHeight: 1920,
        ),
      );
    } else {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (photo != null) picked.add(photo);
    }

    if (picked.isEmpty) return current;

    setState(() => _busy = true);
    try {
      final staged = <Map<String, dynamic>>[];
      for (final photo in picked) {
        staged.add({
          'filename': photo.name,
          'mime_type': _imageMime(photo.name),
          'bytes': await photo.readAsBytes(),
        });
      }

      final updated = await _offlineWrites.addFindingPhotos(
        widget.businessId,
        widget.customerId,
        findingId,
        photos: staged,
      );

      if (!BriskersConnectionModeController.instance.forceOffline) {
        unawaited(_offlineWrites.flush(widget.businessId));
      }
      return updated;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFinding(Map<String, dynamic> finding) async {
    final findingId = finding['id']?.toString() ?? '';
    if (findingId.isEmpty || !mounted || !widget.canManage) return;
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    final allowed = await visibility.filterFindings([finding]);
    if (!mounted || !visibility.isCurrent(generation) || allowed.isEmpty) {
      return;
    }
    final quarantine = _quarantineChanges.value;

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
      builder: (sheetContext) => _guardModal(
        quarantine,
        StatefulBuilder(
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
                builder: (dialogContext) => _guardModal(
                  quarantine,
                  AlertDialog(
                    title: const Text('Edit finding'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 7,
                      decoration: const InputDecoration(labelText: 'Finding'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: BriskersColors.vehicles,
                          foregroundColor: Colors.white,
                        ),
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
                ),
              );
              controller.dispose();
              if (quarantine != _quarantineChanges.value ||
                  updatedBody == null ||
                  updatedBody == localBody) {
                return;
              }

              setSheetState(() => actionBusy = true);
              try {
                final foundJobId = finding['found_job_id']?.toString() ?? '';
                if (foundJobId.isNotEmpty) {
                  await _workFindings.updateLocalFinding(widget.businessId,
                    foundJobId, findingId, body: updatedBody);
                  if (!BriskersConnectionModeController.instance.forceOffline) {
                    unawaited(_workFindings.flush(widget.businessId));
                  }
                } else {
                  await _offlineWrites.updateFinding(
                    widget.businessId, widget.customerId, findingId,
                    body: updatedBody);
                  if (!BriskersConnectionModeController.instance.forceOffline) {
                    unawaited(_offlineWrites.flush(widget.businessId));
                  }
                }
                changed = true;
                setSheetState(() => localBody = updatedBody);
              } catch (error) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => actionBusy = false);
                }
              }
            }

            Future<void> deleteFinding() async {
              if (!widget.canDelete || finding['can_delete'] != true ||
                  findingId.startsWith('local-finding-') ||
                  BriskersConnectionModeController.instance.forceOffline) { return; }
              final confirmed = await showDialog<bool>(
                context: sheetContext,
                builder: (dialogContext) => _guardModal(
                  quarantine,
                  AlertDialog(
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
                ),
              );
              if (confirmed != true || quarantine != _quarantineChanges.value) {
                return;
              }

              setSheetState(() => actionBusy = true);
              try {
                await _api.deleteVehicleFinding(widget.businessId, findingId);
                changed = true;
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() => actionBusy = false);
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            }

            Future<void> toggleInvoiceNotes(bool value) async {
              setSheetState(() => actionBusy = true);
              try {
                await _findingActions.setInvoiceFlag(
                  widget.businessId,
                  finding,
                  value,
                  customerId: widget.customerId,
                );
                if (!BriskersConnectionModeController.instance.forceOffline) {
                  unawaited(_offlineWrites.flush(widget.businessId));
                }
                changed = true;
                setSheetState(() => includeOnInvoice = value);
              } catch (error) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
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
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
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
                        if (widget.canDelete && finding['can_delete'] == true &&
                            !findingId.startsWith('local-finding-') &&
                            !BriskersConnectionModeController.instance.forceOffline)
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
                        (attachment) =>
                            _findingThumbnail(sheetContext, [attachment]),
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
                        : (value) => toggleInvoiceNotes(value == true),
                    title: const Text(
                      'Include in Invoice Notes',
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
      ),
    );

    if (quarantine != _quarantineChanges.value) return;
    if (changed && mounted) await _refresh();
    if (addAnother && mounted) await _addFinding();
  }

  Future<String?> _chooseFindingJob(
    Map<String, dynamic> finding, {
    bool resolving = false,
  }) async {
    final linked = finding['repair_job_id']?.toString() ?? '';
    if (resolving && linked.isNotEmpty) return linked;
    final vehicleId =
        (finding['vehicle_id'] ?? finding['_vehicle_id'])?.toString() ?? '';
    if (vehicleId.isEmpty) return null;
    final local = await localDatabase
        .customSelect(
          'SELECT id,job_number,title,status FROM local_jobs '
          'WHERE business_id=? AND customer_id=? AND vehicle_id=?',
          variables: [
            Variable<String>(widget.businessId),
            Variable<String>(widget.customerId),
            Variable<String>(vehicleId),
          ],
        )
        .get();
    var jobs = local.map((row) => Map<String, dynamic>.from(row.data)).toList();
    if (!BriskersConnectionModeController.instance.forceOffline) {
      try {
        // Unlike the generic Jobs list, customer service history includes
        // the vehicle ID and completed Jobs, and is scoped by customer on
        // the server before anything reaches this picker.
        final remote = await _api.customerServiceHistory(
          widget.businessId, widget.customerId);
        jobs = {
          for (final row in jobs) row['id'].toString(): row,
          for (final row in remote)
            if (row['vehicle_id']?.toString() == vehicleId &&
                (row['id']?.toString() ?? '').isNotEmpty)
              row['id'].toString(): row,
        }.values.toList();
      } catch (_) {
        // Only already-saved jobs remain selectable while disconnected.
      }
    }
    jobs = await _jobVisibility.filter(jobs);
    final active = jobs.where((job) =>
        findingJobChoice(job['status'], resolving: resolving) ==
        FindingJobChoice.active).toList();
    final historical = jobs.where((job) =>
        findingJobChoice(job['status'], resolving: resolving) ==
        FindingJobChoice.completedHistory).toList();
    if (!mounted) return null;
    if (active.isEmpty && historical.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resolving
            ? 'No eligible Jobs found for this vehicle.'
            : 'Open a Job for this vehicle first.')),
      );
      return null;
    }

    Widget jobChoice(BuildContext sheetContext, Map<String, dynamic> job,
        {required bool completed}) {
      final jobId = job['id']?.toString() ?? '';
      final number = job['job_number']?.toString().trim() ?? '';
      final label = number.isNotEmpty ? 'Job $number' : 'Job';
      return ListTile(
        leading: Icon(completed ? Icons.history_outlined : Icons.work_outline),
        title: Text(label),
        subtitle: Text([
          job['title']?.toString() ?? '',
          if (completed) 'Completed',
        ].where((part) => part.isNotEmpty).join(' • ')),
        onTap: jobId.isEmpty ? null : () async {
          if (completed) {
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Resolve using completed Job?'),
                content: Text(
                  'Confirm that the repair on $label resolved this finding. '
                  'Briskers will record that historical '
                  'Job and mark the finding Resolved. It will NOT reopen the '
                  'Job, change its invoice, payments or payroll. The '
                  'resolution is recorded now; the repair date is not changed.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirm resolved'),
                  ),
                ],
              ),
            );
            if (confirmed != true || !sheetContext.mounted) return;
          }
          if (sheetContext.mounted) Navigator.pop(sheetContext, jobId);
        },
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.68,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  resolving ? 'Resolve on Job' : 'Add to Job',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (active.isNotEmpty) ...[
                const ListTile(title: Text('Active Jobs')),
                for (final job in active)
                  jobChoice(sheetContext, job, completed: false),
              ],
              if (resolving && historical.isNotEmpty) ...[
                const Divider(),
                const ListTile(
                  title: Text('Completed Jobs — historical repair'),
                  subtitle: Text(
                    'Select only the Job on which the issue was repaired. '
                    'Existing invoices and payroll will not be changed.',
                  ),
                ),
                for (final job in historical)
                  jobChoice(sheetContext, job, completed: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeFinding(Future<dynamic> Function() change) async {
    if (_busy || !widget.canManage) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
      await _refresh(cacheOnly: true);
      if (!BriskersConnectionModeController.instance.forceOffline) {
        unawaited(
          _offlineWrites
              .flush(widget.businessId)
              .then((_) => _refresh(cacheOnly: true)),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFindingToJob(Map<String, dynamic> finding) async {
    final jobId = await _chooseFindingJob(finding);
    if (jobId != null && mounted) {
      await _changeFinding(
        () => _findingActions.addToJob(
          widget.businessId,
          finding,
          jobId,
          customerId: widget.customerId,
        ),
      );
    }
  }

  Future<void> _resolveFinding(Map<String, dynamic> finding) async {
    final jobId = await _chooseFindingJob(finding, resolving: true);
    if (jobId != null && mounted) {
      await _changeFinding(
        () => _findingActions.resolve(
          widget.businessId,
          finding,
          jobId,
          customerId: widget.customerId,
        ),
      );
    }
  }

  Future<void> _addFindingPhotos(Map<String, dynamic> finding) async {
    try {
      final current = (finding['attachments'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
      await _uploadMorePhotos(finding['id'].toString(), current);
      await _refresh(cacheOnly: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vehicles.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(('vehicle-findings', _jobVisibility.epoch)),
      future: _findingsFuture,
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final open = allRows
            .where((finding) => finding['status']?.toString() != 'resolved')
            .toList();

        final showVehicle = widget.vehicles.length > 1;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: widget.initiallyExpanded,
            onExpansionChanged: (value) => setState(() => _expanded = value),
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
                    onPressed: _busy || !widget.canManage ? null : _addFinding,
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
              VehicleFindings(
                findings: allRows,
                busy: _busy,
                canEdit: widget.canManage,
                canManage: widget.canManage,
                canIncludeOnInvoice: widget.canManage,
                showVehicle: showVehicle,
                onEdit: _openFinding,
                onAddPhotos: _addFindingPhotos,
                onAddToJob: _addFindingToJob,
                onResolve: _resolveFinding,
                onReopen: (finding) => _changeFinding(
                  () => _findingActions.reopen(
                    widget.businessId,
                    finding,
                    customerId: widget.customerId,
                  ),
                ),
                onRemoveFromJob: (finding) => _changeFinding(
                  () => _findingActions.removeFromJob(
                    widget.businessId,
                    finding,
                    finding['repair_job_id'].toString(),
                    customerId: widget.customerId,
                  ),
                ),
                onInvoiceChanged: (finding, include) => _changeFinding(
                  () => _findingActions.setInvoiceFlag(
                    widget.businessId,
                    finding,
                    include,
                    customerId: widget.customerId,
                  ),
                ),
                photoBuilder: (finding, photo) =>
                    _findingThumbnail(context, [photo]),
              ),
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
