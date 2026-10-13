/// Strict contract for the dedicated test-data cleanup endpoint. A list row,
/// job number, or an empty cached document list is never deletion authority.
class TestJobCleanupPlan {
  TestJobCleanupPlan._({
    required this.businessId,
    required this.jobId,
    required this.jobNumber,
    required this.fingerprint,
    required this.documents,
    required this.dependencies,
    required this.blockedReasons,
    required this.receivedAt,
    required bool serverAllowsDeletion,
  }) : canDelete = serverAllowsDeletion && blockedReasons.isEmpty;

  factory TestJobCleanupPlan.fromJson(
    Map<String, dynamic> json, {
    required String businessId,
    required String jobId,
    DateTime? receivedAt,
  }) {
    final rawDocuments = json['documents'];
    final rawReasons = json['blocked_reasons'];
    final rawDependencies = json['dependencies'];
    if (json['schema_version'] != 1 ||
        businessId.isEmpty || jobId.isEmpty ||
        json['business_id'] != businessId || json['job_id'] != jobId ||
        json['job_number'] is! String ||
        (json['job_number'] as String).trim().isEmpty ||
        json['fingerprint'] is! String ||
        (json['fingerprint'] as String).isEmpty ||
        json['can_delete'] is! bool || json['rollout_enabled'] is! bool ||
        rawDocuments is! List ||
        rawReasons is! List || rawDependencies is! Map ||
        rawReasons.any((value) => value is! String || value.isEmpty)) {
      throw const FormatException('Cleanup preview could not be verified.');
    }
    final documents = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final raw in rawDocuments) {
      if (raw is! Map || raw['id'] is! String ||
          (raw['id'] as String).isEmpty || !ids.add(raw['id'] as String) ||
          !const ['invoice', 'estimate'].contains(raw['kind']) ||
          raw['status'] is! String ||
          (raw['number'] != null && raw['number'] is! String) ||
          raw['total'] is! num || !(raw['total'] as num).isFinite) {
        throw const FormatException('Linked document details are incomplete.');
      }
      documents.add(Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(raw),
      ));
    }
    final dependencies = <String, int>{};
    for (final entry in rawDependencies.entries) {
      if (entry.key is! String || entry.value is! int || entry.value < 0) {
        throw const FormatException('Cleanup reference counts are unknown.');
      }
      dependencies[entry.key as String] = entry.value as int;
    }
    final reasons = List<String>.from(rawReasons);
    if (json['rollout_enabled'] != true) {
      reasons.add('Cleanup is locked until safe-client rollout is verified on the server.');
    }
    if (json['can_delete'] != true && reasons.isEmpty) {
      reasons.add('The server has not approved this cleanup.');
    }
    final jobNumber = json['job_number'] as String;
    if (TestJobCleanupPolicy.isProtectedJob(jobNumber) ||
        documents.any((document) =>
            TestJobCleanupPolicy.isProtectedDocument(
              document['kind'] as String, document['number'] as String?,
            ))) {
      reasons.add('This Job or linked document is a protected real record.');
    }
    return TestJobCleanupPlan._(
      businessId: businessId,
      jobId: jobId,
      jobNumber: jobNumber,
      fingerprint: json['fingerprint'] as String,
      documents: List.unmodifiable(documents),
      dependencies: Map.unmodifiable(dependencies),
      blockedReasons: List.unmodifiable(reasons),
      receivedAt: receivedAt ?? DateTime.now(),
      serverAllowsDeletion: json['can_delete'] == true,
    );
  }

  final String businessId;
  final String jobId;
  final String jobNumber;
  final String fingerprint;
  final List<Map<String, dynamic>> documents;
  final Map<String, int> dependencies;
  final List<String> blockedReasons;
  final DateTime receivedAt;
  final bool canDelete;

  Set<String> get documentIds =>
      documents.map((document) => document['id'] as String).toSet();
  String get confirmationText => 'DELETE TEST $jobNumber';

  TestJobCleanupPlan withLocalBlockers(Iterable<String> reasons) =>
      TestJobCleanupPlan._(
        businessId: businessId, jobId: jobId, jobNumber: jobNumber,
        fingerprint: fingerprint, documents: documents,
        dependencies: dependencies, receivedAt: receivedAt,
        blockedReasons: List.unmodifiable({...blockedReasons, ...reasons}),
        serverAllowsDeletion: canDelete,
      );
}

class TestJobCleanupPolicy {
  static const previewLifetime = Duration(minutes: 2);

  static int? _number(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(?:[A-Za-z]+[- ]?)?0*(\d+)$')
        .firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool isProtectedJob(String number) =>
      const {7, 11, 12}.contains(_number(number));

  static bool isProtectedDocument(String kind, String? number) =>
      (kind == 'invoice' && const {6331, 6332, 6334}.contains(_number(number))) ||
      (kind == 'estimate' && _number(number) == 1997);

  static bool hasPendingSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return false;
    if (snapshot['sync_state'] == 'pending' ||
        snapshot['sync_state'] == 'conflict' ||
        snapshot['_local_pending_payment'] == true ||
        snapshot['_payment_reconciliation_required'] == true) return true;
    for (final key in const ['paid_amount', 'pending_payment']) {
      if (!snapshot.containsKey(key)) continue;
      final amount = num.tryParse('${snapshot[key]}');
      if (amount == null || !amount.isFinite || amount != 0) return true;
    }
    final payments = snapshot['payments'];
    if (payments != null && (payments is! List || payments.isNotEmpty)) return true;
    final lines = snapshot['lines'];
    return lines is List && lines.whereType<Map>().any((line) => line['_local_pending'] == true);
  }

  static void requireOwner(String roleCode) {
    if (roleCode != 'owner') throw StateError('Owner access required.');
  }

  static void requireExecutable(
    TestJobCleanupPlan plan, {
    required String roleCode,
    required String confirmation,
    DateTime? now,
  }) {
    requireOwner(roleCode);
    if (!plan.canDelete) {
      throw StateError(plan.blockedReasons.join('\n'));
    }
    final age = (now ?? DateTime.now()).difference(plan.receivedAt);
    if (age.isNegative || age > previewLifetime) {
      throw StateError('This preview has expired. Preview the Job again.');
    }
    if (confirmation != plan.confirmationText) {
      throw StateError('Type the exact Job confirmation to continue.');
    }
  }
}

class TestJobCleanupTombstones {
  TestJobCleanupTombstones._(this.jobIds, this.documentIds);
  final Set<String> jobIds;
  final Set<String> documentIds;

  factory TestJobCleanupTombstones.fromJson(
    Map<String, dynamic> json, String businessId,
  ) {
    final jobs = json['deleted_job_ids'];
    final documents = json['deleted_document_ids'];
    if (json['schema_version'] != 1 || json['business_id'] != businessId ||
        jobs is! List || documents is! List ||
        jobs.any((id) => id is! String || id.isEmpty) ||
        documents.any((id) => id is! String || id.isEmpty)) {
      throw const FormatException('Cleanup deletion feed could not be verified.');
    }
    return TestJobCleanupTombstones._(
      Set.unmodifiable(jobs.cast<String>()),
      Set.unmodifiable(documents.cast<String>()),
    );
  }
}
