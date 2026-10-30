/// Isolated, deterministic simulation of Master/Slave invoice number windows.
///
/// NOT wired to the app or Supabase: no real invoice numbers are assigned.
/// A number from a device's 10-slot window is a *provisional* display number,
/// never a permanent customer-facing invoice number until reconciliation.
/// This distinction permits gap compaction without silently renumbering an
/// invoice whose official number was already given to a customer.
class NumberWindowLease {
  const NumberWindowLease({
    required this.deviceId,
    required this.start,
    required this.end,
    required this.epoch,
    required this.consumed,
  });

  final String deviceId;
  final int start;
  final int end;
  final int epoch;
  final Set<int> consumed;

  int? get nextAvailable {
    for (var number = start; number <= end; number++) {
      if (!consumed.contains(number)) return number;
    }
    return null;
  }

  NumberWindowLease consuming(int number) {
    if (number < start || number > end || consumed.contains(number)) {
      throw StateError('Number is outside the device lease or already used.');
    }
    return NumberWindowLease(
      deviceId: deviceId,
      start: start,
      end: end,
      epoch: epoch,
      consumed: {...consumed, number},
    );
  }
}

class ProvisionalInvoiceClaim {
  const ProvisionalInvoiceClaim({
    required this.documentId,
    required this.operationId,
    required this.deviceId,
    required this.epoch,
    required this.createdOrder,
    required this.provisionalNumber,
    required this.externallyShared,
    this.finalNumber,
  });

  final String documentId;
  final String operationId;
  final String deviceId;
  final int epoch;
  final int createdOrder;
  final int? provisionalNumber;
  final bool externallyShared;
  final int? finalNumber;

  String get visibleReference {
    if (finalNumber != null) return 'Invoice #$finalNumber';
    if (provisionalNumber != null) {
      return 'Provisional #$provisionalNumber';
    }
    return 'Local invoice $documentId';
  }

  ProvisionalInvoiceClaim finalizing(int number) => ProvisionalInvoiceClaim(
    documentId: documentId,
    operationId: operationId,
    deviceId: deviceId,
    epoch: epoch,
    createdOrder: createdOrder,
    provisionalNumber: provisionalNumber,
    externallyShared: externallyShared,
    finalNumber: number,
  );
}

class NumberWindowAssignment {
  const NumberWindowAssignment({
    required this.documentId,
    required this.operationId,
    required this.deviceId,
    required this.provisionalNumber,
    required this.finalNumber,
  });

  final String documentId;
  final String operationId;
  final String deviceId;
  final int? provisionalNumber;
  final int finalNumber;

  bool get numberChanged =>
      provisionalNumber != null && provisionalNumber != finalNumber;
}

class NumberWindowReconciliation {
  const NumberWindowReconciliation({
    required this.batchId,
    required this.epoch,
    required this.assignments,
    required this.newLeases,
    required this.nextFinalNumber,
  });

  final String batchId;
  final int epoch;
  final List<NumberWindowAssignment> assignments;
  final Map<String, NumberWindowLease> newLeases;
  final int nextFinalNumber;
}

/// Pure test model for a complete, coordinated two-device synchronization.
///
/// In production this requires atomic SQLite leases, Master acknowledgements,
/// authenticated LAN allocation, backend validation and device conflict tests.
class OfflineNumberWindowLab {
  OfflineNumberWindowLab({
    required this.masterDeviceId,
    required List<String> deviceIds,
    required int firstNumber,
    this.windowSize = 10,
  }) : deviceIds = List.unmodifiable(deviceIds),
       _nextFinalNumber = firstNumber {
    if (masterDeviceId.isEmpty ||
        deviceIds.isEmpty ||
        deviceIds.toSet().length != deviceIds.length ||
        deviceIds.first != masterDeviceId ||
        firstNumber < 1 ||
        windowSize < 1) {
      throw ArgumentError('Invalid Master, device list, first number, or window.');
    }
    _leases = _freshLeases(firstNumber, 1);
  }

  final String masterDeviceId;
  final List<String> deviceIds;
  final int windowSize;

  int _epoch = 1;
  int _nextFinalNumber;
  late Map<String, NumberWindowLease> _leases;
  final Map<String, ProvisionalInvoiceClaim> _claims = {};
  final Map<String, String> _operations = {};
  String? _lastBatchId;
  NumberWindowReconciliation? _lastResult;

  int get epoch => _epoch;
  int get nextFinalNumber => _nextFinalNumber;
  Map<String, NumberWindowLease> get leases => Map.unmodifiable(_leases);
  Map<String, ProvisionalInvoiceClaim> get claims => Map.unmodifiable(_claims);

  Map<String, NumberWindowLease> _freshLeases(int first, int epoch) {
    final values = <String, NumberWindowLease>{};
    for (var i = 0; i < deviceIds.length; i++) {
      final start = first + (i * windowSize);
      values[deviceIds[i]] = NumberWindowLease(
        deviceId: deviceIds[i],
        start: start,
        end: start + windowSize - 1,
        epoch: epoch,
        consumed: <int>{},
      );
    }
    return values;
  }

  ProvisionalInvoiceClaim create({
    required String deviceId,
    required String documentId,
    required String operationId,
    required int createdOrder,
    bool externallyShared = false,
  }) {
    if (documentId.isEmpty || operationId.isEmpty) {
      throw ArgumentError('A durable document and operation ID are required.');
    }
    final priorDocument = _operations[operationId];
    if (priorDocument != null) {
      if (priorDocument != documentId) {
        throw StateError('Operation ID cannot be reused for another invoice.');
      }
      return _claims[priorDocument]!;
    }
    if (_claims.containsKey(documentId)) {
      throw StateError('Document ID already exists with another operation.');
    }
    final lease = _leases[deviceId];
    if (lease == null || lease.epoch != _epoch) {
      throw StateError('Device has no authorized current number window.');
    }
    final slot = lease.nextAvailable;
    final claim = ProvisionalInvoiceClaim(
      documentId: documentId,
      operationId: operationId,
      deviceId: deviceId,
      epoch: _epoch,
      createdOrder: createdOrder,
      provisionalNumber: slot,
      externallyShared: externallyShared,
    );
    // This is an in-memory lab operation, not a durable SQLite transaction.
    if (slot != null) _leases[deviceId] = lease.consuming(slot);
    _claims[documentId] = claim;
    _operations[operationId] = documentId;
    return claim;
  }

  /// All enrolled devices must report/freeze their claims before rotating
  /// blocks. A disconnected device could still use its old, reserved slots.
  ///
  /// Final invoices never change number. Only provisional claims in the
  /// current epoch are assigned their official numbers, Master first.
  NumberWindowReconciliation synchronize({
    required String batchId,
    required Set<String> acknowledgedDevices,
  }) {
    if (batchId.isEmpty) throw ArgumentError('Batch ID is required.');
    if (_lastBatchId == batchId && _lastResult != null) {
      return _lastResult!;
    }
    if (acknowledgedDevices.length != deviceIds.length ||
        !acknowledgedDevices.containsAll(deviceIds)) {
      throw StateError('All devices must acknowledge before rotating leases.');
    }
    final pending = _claims.values
        .where((claim) => claim.finalNumber == null && claim.epoch == _epoch)
        .toList()
      ..sort((a, b) {
        final am = a.deviceId == masterDeviceId ? 0 : 1;
        final bm = b.deviceId == masterDeviceId ? 0 : 1;
        if (am != bm) return am.compareTo(bm);
        final order = a.createdOrder.compareTo(b.createdOrder);
        return order != 0 ? order : a.operationId.compareTo(b.operationId);
      });
    if (pending.isEmpty) throw StateError('No new invoices to reconcile.');

    // Prepare all changes before modifying any state. An invoice already
    // shared externally must NOT have its displayed number silently changed.
    final assignments = <NumberWindowAssignment>[];
    for (var i = 0; i < pending.length; i++) {
      final claim = pending[i];
      final official = _nextFinalNumber + i;
      if (claim.externallyShared &&
          claim.provisionalNumber != official) {
        throw StateError(
          'A shared invoice number needs explicit owner reconciliation.',
        );
      }
      assignments.add(NumberWindowAssignment(
        documentId: claim.documentId,
        operationId: claim.operationId,
        deviceId: claim.deviceId,
        provisionalNumber: claim.provisionalNumber,
        finalNumber: official,
      ));
    }

    final nextOfficial = _nextFinalNumber + pending.length;
    final newEpoch = _epoch + 1;
    final newLeases = _freshLeases(nextOfficial, newEpoch);
    for (final assignment in assignments) {
      final original = _claims[assignment.documentId]!;
      _claims[assignment.documentId] =
          original.finalizing(assignment.finalNumber);
    }
    _nextFinalNumber = nextOfficial;
    _epoch = newEpoch;
    _leases = newLeases;

    final result = NumberWindowReconciliation(
      batchId: batchId,
      epoch: newEpoch,
      assignments: List.unmodifiable(assignments),
      newLeases: Map.unmodifiable(newLeases),
      nextFinalNumber: nextOfficial,
    );
    _lastBatchId = batchId;
    _lastResult = result;
    return result;
  }
}
