import 'dart:io';

import 'package:briskers_app/services/lan_inventory_session.dart';
import 'package:briskers_app/services/lan_record_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

LanInventoryEntry entry(
  String identity, {
  String kind = 'job',
  String fingerprint = 'same',
  bool pending = false,
  bool hasDocumentDetail = true,
}) => (
  kind: kind,
  identity: identity,
  fingerprint: fingerprint,
  pending: pending,
  hasDocumentDetail: hasDocumentDetail,
  review: const {},
);

void main() {
  test('accepts LAN comparison codes and rejects unrelated QR payloads', () {
    final key = '${'A' * 43}=';

    expect(LanInventorySession.isComparisonCode(' 192.168.0.25:43210/$key '), isTrue);
    expect(LanInventorySession.isComparisonCode('https://192.168.0.25:43210/$key'), isFalse);
    expect(LanInventorySession.isComparisonCode('8.8.8.8:43210/$key'), isFalse);
    expect(LanInventorySession.isComparisonCode('192.168.0.25:65536/$key'), isFalse);
    expect(LanInventorySession.isComparisonCode('192.168.0.25:43210/short'), isFalse);
  });

  test('fetches a job copy bundle from an encrypted Wi-Fi session', () async {
    final List<InternetAddress> addresses;
    try {
      addresses = await LanInventorySession.addresses();
    } on SocketException {
      markTestSkipped('This runner could not enumerate network interfaces.');
      return;
    }
    if (addresses.isEmpty) {
      markTestSkipped('This runner has no private IPv4 interface.');
      return;
    }
    const business = 'synthetic-shop';
    final job = entry(
      LanRecordInventory.recordIdentity(business, 'job', 'job-1'),
    );
    final bundle = <String, dynamic>{
      'version': 1,
      'jobs': {
        'cursor': 42,
        'records': [
          {'id': 'job-1'},
        ],
      },
    };
    final session = await LanInventorySession.offer(
      address: addresses.first,
      business: business,
      inventory: [job],
      recordCopy: bundle,
    );
    addTearDown(session.close);

    final inventory = await LanInventorySession.fetch(session.code, business);
    expect(inventory.single.identity, job.identity);
    expect(
      await LanInventorySession.fetchRecordCopy(session.code, business),
      bundle,
    );
  });

  test('compares stable IDs and separates unverified records from differences', () {
    final result = LanRecordInventory.compare([
      entry('source-only'),
      entry('same'),
      entry('edited', fingerprint: 'source'),
      entry('pending', pending: true),
      entry('invoice-index', kind: 'invoice', hasDocumentDetail: false),
      entry('pending-on-destination'),
    ], [
      entry('destination-only'),
      entry('same'),
      entry('edited', fingerprint: 'destination'),
      entry('pending-on-destination', pending: true),
    ]);
    expect(result.onlyOnSource.map((item) => item.identity), ['source-only']);
    expect(result.onlyOnDestination.map((item) => item.identity), ['destination-only']);
    expect(result.different.map((item) => item.identity), ['edited']);
    expect(result.destinationVersions['edited']?.fingerprint, 'destination');
    expect(result.destinationVersions['pending-on-destination']?.pending, isTrue);
    expect(result.unverified.map((item) => item.identity),
        ['pending', 'invoice-index', 'pending-on-destination']);
  });

  test('rejects duplicate manifest identities', () {
    expect(() => LanRecordInventory.compare(
      [entry('repeated'), entry('repeated')], const [],
    ), throwsFormatException);
  });
}
