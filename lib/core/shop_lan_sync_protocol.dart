/// Pure, read-only planning for future authenticated shop-LAN replication.
///
/// This module never reads or mutates a business database, never sends payloads,
/// and never acknowledges receipt. Real transfer must additionally verify the
/// peer's cryptographic identity and persist atomic replay receipts in SQLite.
enum ShopLanRole { owner, secretary, mechanic, kiosk }

enum ShopLanScope {
  kioskCheckIn,
  customerVehicle,
  appointment,
  job,
  document,
  task,
  payment,
  payroll,
  ownerDeletion,
}

class ShopLanPeer {
  const ShopLanPeer({
    required this.shopId,
    required this.deviceId,
    required this.role,
    required this.isPaired,
    this.isRevoked = false,
  });

  final String shopId;
  final String deviceId;
  final ShopLanRole role;

  /// True only after an external authenticated enrollment check. A raw
  /// network probe is NOT evidence that a peer is paired.
  final bool isPaired;
  final bool isRevoked;
}

/// Immutable reference only. Actual payload bytes must travel on an encrypted,
/// authenticated channel after the receiver's permissions are checked.
class ShopLanChangeRef {
  const ShopLanChangeRef({
    required this.shopId,
    required this.operationId,
    required this.originDeviceId,
    required this.scope,
    required this.payloadDigest,
    required this.sequence,
  });

  final String shopId;
  final String operationId;
  final String originDeviceId;
  final ShopLanScope scope;
  final String payloadDigest;
  final int sequence;
}

/// Selects a bounded set of pending change references for a paired recipient.
///
/// This initial authorization matrix deliberately allows ONLY kiosk check-in
/// references to reach Owner and Secretary peers. Every other scope is blocked
/// until explicit role-by-entity permission checks and durable replay are added.
/// An ACK supplied here must have been persisted by the receiving device, not
/// inferred from sending an HTTP request.
class ShopLanBatchPlanner {
  const ShopLanBatchPlanner();

  List<ShopLanChangeRef> plan({
    required String shopId,
    required ShopLanPeer recipient,
    required Iterable<ShopLanChangeRef> changes,
    Set<String> durablyAcknowledgedOperationIds = const <String>{},
    int maxOperations = 50,
  }) {
    if (maxOperations < 1 || maxOperations > 500) {
      throw RangeError.range(maxOperations, 1, 500, 'maxOperations');
    }
    if (recipient.shopId != shopId ||
        recipient.deviceId.trim().isEmpty ||
        !recipient.isPaired ||
        recipient.isRevoked) {
      return const <ShopLanChangeRef>[];
    }

    final seen = <String, String>{};
    final batch = <ShopLanChangeRef>[];
    for (final change in changes) {
      if (change.shopId != shopId) continue;
      if (change.operationId.trim().isEmpty ||
          change.originDeviceId.trim().isEmpty ||
          change.payloadDigest.trim().isEmpty ||
          change.sequence < 0) {
        throw ArgumentError('Invalid immutable shop LAN operation reference');
      }
      final existingDigest = seen[change.operationId];
      if (existingDigest != null && existingDigest != change.payloadDigest) {
        throw StateError('Conflicting replay of operation ${change.operationId}');
      }
      if (existingDigest != null) continue;
      seen[change.operationId] = change.payloadDigest;

      if (change.originDeviceId == recipient.deviceId ||
          durablyAcknowledgedOperationIds.contains(change.operationId) ||
          !_isScopeAuthorized(recipient.role, change.scope)) {
        continue;
      }
      if (batch.length < maxOperations) batch.add(change);
    }
    return List<ShopLanChangeRef>.unmodifiable(batch);
  }

  bool _isScopeAuthorized(ShopLanRole role, ShopLanScope scope) {
    // No data is released merely because a device claims a role over Wi-Fi:
    // the pairing/authorization layer must verify enrolled credentials first.
    switch (role) {
      case ShopLanRole.owner:
      case ShopLanRole.secretary:
        return scope == ShopLanScope.kioskCheckIn;
      case ShopLanRole.mechanic:
      case ShopLanRole.kiosk:
        return false;
    }
  }
}
