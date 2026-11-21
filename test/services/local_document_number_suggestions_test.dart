import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_number_suggestions.dart';

void main() {
  late BriskersLocalDatabase db;
  setUp(() => db=BriskersLocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('uses highest invoice and job numbers, ignoring temporary IDs',
      () async {
    for (final n in const ['6331','6358','TEMP-XYZ','MB-6354']) {
      await db.customStatement(
        '''INSERT INTO local_documents(id,business_id,kind,document_number)
        VALUES(?,?,'invoice',?)''',['invoice-$n','shop',n],
      );
    }
    for (final n in const ['J-35','J-39','TEMP-ABC']) {
      await db.customStatement(
        '''INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number)
        VALUES(?,?,'full','Test','open',?)''',['job-$n','shop',n],
      );
    }
    final s=await LocalDocumentNumberSuggestions(database:db).suggest('shop');
    expect(s.invoice,'6359');
    expect(s.job,'J-40');
    expect(s.latestInvoice,'6358');
    expect(s.latestJob,'J-39');
  });
  test('does not use numbers from another business',() async {
    await db.customStatement(
      '''INSERT INTO local_documents(id,business_id,kind,document_number)
      VALUES('other','other-shop','invoice','9000')''',
    );
    final s=await LocalDocumentNumberSuggestions(database:db).suggest('shop');
    expect(s.invoice,isNull);
    expect(s.job,isNull);
  });
  test('does not invent a starting number when no local sequence exists',
      () async {
    final s=await LocalDocumentNumberSuggestions(database:db).suggest('shop');
    expect(s.invoice,isNull);
    expect(s.job,isNull);
  });
}
