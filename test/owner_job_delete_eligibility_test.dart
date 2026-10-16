import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/owner_job_delete_eligibility.dart';

void main() {
  final allowed = <String, dynamic>{
    'can_delete': true,
    'invoices': [
      <String, dynamic>{'number': '6347', 'status': 'draft'},
    ],
  };

  test('Owner online unpaid preview is eligible only for review', () {
    expect(OwnerDeleteEligibility.canOfferDelete(allowed,
      isOwner: true, isOnline: true, hasPendingLocalWork: false), isTrue);
  });

  test('secretary, offline and pending outbox all block deletion', () {
    for (final args in [
      [false, true, false],
      [true, false, false],
      [true, true, true],
    ]) {
      expect(OwnerDeleteEligibility.canOfferDelete(allowed,
        isOwner: args[0], isOnline: args[1],
        hasPendingLocalWork: args[2]), isFalse);
    }
  });

  test('paid and closed invoices never pass local review', () {
    for (final status in ['paid', 'closed', 'void', 'cancelled']) {
      expect(OwnerDeleteEligibility.canOfferDelete({
        'can_delete': true,
        'invoices': [{'status': status}]
      }, isOwner: true, isOnline: true,
        hasPendingLocalWork: false), isFalse);
    }
  });

  test('server rejection or malformed plan fails closed', () {
    for (final plan in [
      <String, dynamic>{'can_delete': false, 'invoices': []},
      <String, dynamic>{'can_delete': true},
      <String, dynamic>{'can_delete': true, 'invoices': ['bad']},
    ]) {
      expect(OwnerDeleteEligibility.canOfferDelete(plan,
        isOwner: true, isOnline: true, hasPendingLocalWork: false), isFalse);
    }
  });

  test('number reclaim needs explicit request and validated reservation', () {
    expect(OwnerDeleteEligibility.canOfferNumberReclaim(
      explicitlyRequested: true, verifiedUnused: true,
      serverReservationAvailable: true), isTrue);
    expect(OwnerDeleteEligibility.canOfferNumberReclaim(
      explicitlyRequested: false, verifiedUnused: true,
      serverReservationAvailable: true), isFalse);
    expect(OwnerDeleteEligibility.canOfferNumberReclaim(
      explicitlyRequested: true, verifiedUnused: false,
      serverReservationAvailable: true), isFalse);
    expect(OwnerDeleteEligibility.canOfferNumberReclaim(
      explicitlyRequested: true, verifiedUnused: true,
      serverReservationAvailable: false), isFalse);
  });
}
