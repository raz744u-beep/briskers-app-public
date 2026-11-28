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
