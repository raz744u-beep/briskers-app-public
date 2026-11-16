import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_lan_sync_protocol.dart';

void main() {
  const planner = ShopLanBatchPlanner();
  const owner = ShopLanPeer(
    shopId: 'briskers',
    deviceId: 'owner-phone',
    role: ShopLanRole.owner,
    isPaired: true,
  );
  const secretary = ShopLanPeer(
    shopId: 'briskers',
    deviceId: 'secretary-phone',
    role: ShopLanRole.secretary,
    isPaired: true,
  );
  const checkIn = ShopLanChangeRef(
    shopId: 'briskers',
    operationId: 'op-kiosk-001',
    originDeviceId: 'kiosk',
    scope: ShopLanScope.kioskCheckIn,
    payloadDigest: 'sha256:checkin-one',
    sequence: 1,
  );
  const payroll = ShopLanChangeRef(
    shopId: 'briskers',
    operationId: 'op-payroll-001',
    originDeviceId: 'owner-phone',
    scope: ShopLanScope.payroll,
    payloadDigest: 'sha256:payroll-one',
    sequence: 2,
  );

  test('kiosk check-in can be scheduled for paired Owner and Secretary', () {
    expect(
      planner.plan(shopId: 'briskers', recipient: owner, changes: [checkIn]),
      [checkIn],
    );
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: secretary,
        changes: [checkIn],
      ),
      [checkIn],
    );
  });

  test('unpaired, revoked, cross-shop and kiosk recipients get no changes', () {
    final recipients = <ShopLanPeer>[
      const ShopLanPeer(
        shopId: 'briskers',
        deviceId: 'stranger',
        role: ShopLanRole.owner,
        isPaired: false,
      ),
      const ShopLanPeer(
        shopId: 'briskers',
        deviceId: 'old-phone',
        role: ShopLanRole.owner,
        isPaired: true,
        isRevoked: true,
      ),
      const ShopLanPeer(
        shopId: 'someone-else',
        deviceId: 'other-shop',
        role: ShopLanRole.owner,
        isPaired: true,
      ),
      const ShopLanPeer(
        shopId: 'briskers',
        deviceId: 'kiosk',
        role: ShopLanRole.kiosk,
        isPaired: true,
      ),
      const ShopLanPeer(
        shopId: 'briskers',
        deviceId: 'mechanic',
        role: ShopLanRole.mechanic,
        isPaired: true,
      ),
    ];
    for (final recipient in recipients) {
      expect(
        planner.plan(
          shopId: 'briskers',
          recipient: recipient,
          changes: [checkIn, payroll],
        ),
        isEmpty,
      );
    }
  });

  test('initial pilot blocks payroll and all non-check-in data', () {
    const invoice = ShopLanChangeRef(
      shopId: 'briskers',
      operationId: 'op-invoice-01',
      originDeviceId: 'kiosk',
      scope: ShopLanScope.document,
      payloadDigest: 'sha256:invoice-one',
      sequence: 3,
    );
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: secretary,
        changes: [payroll, invoice, checkIn],
      ),
      [checkIn],
    );
  });

  test('foreign business changes are excluded even for paired recipient', () {
    const other = ShopLanChangeRef(
      shopId: 'different-shop',
      operationId: 'op-other',
      originDeviceId: 'other-kiosk',
      scope: ShopLanScope.kioskCheckIn,
      payloadDigest: 'sha256:other',
      sequence: 1,
    );
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [other, checkIn],
      ),
      [checkIn],
    );
  });

  test('durable ACK skips a change; sending alone never creates an ACK', () {
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [checkIn],
        durablyAcknowledgedOperationIds: {'op-kiosk-001'},
      ),
      isEmpty,
    );
    expect(
      planner.plan(shopId: 'briskers', recipient: owner, changes: [checkIn]),
      [checkIn],
    );
  });

  test('a repeated identical reference is selected once', () {
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [checkIn, checkIn],
      ),
      [checkIn],
    );
  });

  test('same operation ID with a different digest fails loudly', () {
    const mismatch = ShopLanChangeRef(
      shopId: 'briskers',
      operationId: 'op-kiosk-001',
      originDeviceId: 'kiosk',
      scope: ShopLanScope.kioskCheckIn,
      payloadDigest: 'sha256:changed-payload',
      sequence: 1,
    );
    expect(
      () => planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [checkIn, mismatch],
      ),
      throwsStateError,
    );
  });

  test('batch limit is respected without accepting oversized limits', () {
    const second = ShopLanChangeRef(
      shopId: 'briskers',
      operationId: 'op-kiosk-002',
      originDeviceId: 'kiosk',
      scope: ShopLanScope.kioskCheckIn,
      payloadDigest: 'sha256:checkin-two',
      sequence: 2,
    );
    expect(
      planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [checkIn, second],
        maxOperations: 1,
      ),
      [checkIn],
    );
    expect(
      () => planner.plan(
        shopId: 'briskers',
        recipient: owner,
        changes: [checkIn],
        maxOperations: 501,
      ),
      throwsRangeError,
    );
  });
}
