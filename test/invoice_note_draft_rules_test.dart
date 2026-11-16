import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/invoice_note_draft_rules.dart';

void main() {
  test('the note screen hides Save and Clear for an empty draft', () {
    expect(invoiceNoteDraftAction('', null), InvoiceNoteDraftAction.none);
    expect(invoiceNoteDraftAction('   ', ''), InvoiceNoteDraftAction.none);
  });

  test('editing notes offers Save, clearing a persisted note offers Clear', () {
    expect(invoiceNoteDraftAction('Text', ''), InvoiceNoteDraftAction.save);
    expect(
      invoiceNoteDraftAction('Updated', 'Earlier'),
      InvoiceNoteDraftAction.save,
    );
    expect(invoiceNoteDraftAction('Same', 'Same'), InvoiceNoteDraftAction.none);
    expect(
      invoiceNoteDraftAction(' ', 'Previously saved note'),
      InvoiceNoteDraftAction.clear,
    );
    expect(
      invoiceNoteDraftAction('Previously saved note', 'Previously saved note'),
      InvoiceNoteDraftAction.none,
    );
  });

  test(
    'standard note append preserves unsaved manually typed invoice text',
    () {
      final draft = 'The customer requested an oil change.';
      final note = 'Warranty: parts and labor 12 months / 12000 miles.';
      expect(mergeStandardNoteIntoDraft(draft, note), '$draft\n\n$note');
    },
  );

  test('newly created standard note can be added to an empty invoice', () {
    expect(mergeStandardNoteIntoDraft('', 'Warranty terms'), 'Warranty terms');
  });

  test('selecting the same standard note does not duplicate a paragraph', () {
    const body = 'Standard warranty note';
    const original = 'Customer requested service.\n\nStandard warranty note';
    expect(mergeStandardNoteIntoDraft(original, body), original);
    expect(mergeStandardNoteIntoDraft(original, '   '), original);
  });

  test('empty standard template names and bodies cannot be saved', () {
    expect(canSaveStandardNoteText('', 'Text'), isFalse);
    expect(canSaveStandardNoteText('Name', '  '), isFalse);
    expect(canSaveStandardNoteText('Warranty', 'Terms'), isTrue);
  });
  test(
    'multi-paragraph templates are never duplicated on repeated selection',
    () {
      const warranty =
          'Warranty 12 months / 12,000 miles.\n\nExclusions remain unchanged.';
      const manual = 'Customer requested the old part.';
      final once = mergeStandardNoteIntoDraft(manual, warranty);
      expect(mergeStandardNoteIntoDraft(once, warranty), once);
      expect(mergeStandardNoteIntoDraft(warranty, warranty), warranty);
      expect(
        mergeStandardNoteIntoDraft('$warranty\n\n$manual', warranty),
        '$warranty\n\n$manual',
      );
      expect(
        mergeStandardNoteIntoDraft('Partial Warranty', 'Warranty'),
        'Partial Warranty\n\nWarranty',
      );
    },
  );
}
