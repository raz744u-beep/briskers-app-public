import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

class LocalDocumentRepository {
  LocalDocumentRepository({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<void> replaceFromServer(
    String businessId,
    List<Map<String, dynamic>> documents, {
    String? kind,
  }) async {
    await _database.transaction(() async {
      await _database.customStatement(
        kind == null
            ? "DELETE FROM local_documents WHERE business_id = ? AND sync_state = 'synced'"
            : "DELETE FROM local_documents WHERE business_id = ? AND kind = ? AND sync_state = 'synced'",
        kind == null ? [businessId] : [businessId, kind],
      );
      for (final document in documents) {
        final id = document['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _database.customStatement(
          '''
          INSERT OR REPLACE INTO local_documents (
            id, business_id, job_id, customer_id, kind, document_number,
            status, total, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ''',
          [
            id,
            businessId,
            _text(document['job_id']),
            _text(document['customer_id']),
            document['kind']?.toString() ?? 'invoice',
            _text(document['document_number']),
            _text(document['status']),
            _double(document['total']) ?? 0,
            _unix(_date(document['created_at'])),
            _unix(_date(document['updated_at'])),
            _int(document['row_version']),
          ],
        );
      }
    });
  }

  Future<void> upsertFromServer(
    String businessId,
    List<Map<String, dynamic>> documents,
  ) async {
    await _database.transaction(() async {
      for (final document in documents) {
        final id = document['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _database.customStatement(
          '''
          INSERT INTO local_documents (
            id, business_id, job_id, customer_id, kind, document_number,
            status, total, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ON CONFLICT(id) DO UPDATE SET
            job_id=excluded.job_id,
            customer_id=excluded.customer_id,
            kind=excluded.kind,
            document_number=excluded.document_number,
            status=excluded.status,
            total=excluded.total,
            created_at=excluded.created_at,
            server_updated_at=excluded.server_updated_at,
            row_version=excluded.row_version,
            sync_state='synced'
          WHERE local_documents.sync_state = 'synced'
          ''',
          [
            id, businessId, _text(document['job_id']),
            _text(document['customer_id']),
            document['kind']?.toString() ?? 'invoice',
            _text(document['document_number']), _text(document['status']),
            _double(document['total_amount'] ?? document['total']) ?? 0,
            _unix(_date(document['created_at'])),
            _unix(_date(document['updated_at'])),
            _int(document['row_version']),
          ],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> search(
    String businessId,
    String query, {
    int limit = 30,
  }) async {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return const [];
    final like = '%$value%';
    final rows = await _database.customSelect(
      '''
      SELECT d.*, j.job_number, j.customer_name, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
      WHERE d.business_id = ?
        AND (
          lower(COALESCE(d.document_number, '')) LIKE ?
          OR lower(COALESCE(j.job_number, '')) LIKE ?
          OR lower(COALESCE(j.customer_name, '')) LIKE ?
        )
      ORDER BY d.created_at DESC, d.id
      LIMIT ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(like),
        Variable<String>(like),
        Variable<String>(like),
        Variable<int>(limit),
      ],
    ).get();

    return rows.map((row) => <String, dynamic>{
      'id': row.read<String>('id'),
      'job_id': row.readNullable<String>('job_id'),
      'customer_id': row.readNullable<String>('customer_id'),
      'kind': row.read<String>('kind'),
      'document_number': row.readNullable<String>('document_number'),
      'status': row.readNullable<String>('status'),
      'total': row.read<double>('total'),
      'job_number': row.readNullable<String>('job_number'),
      'customer_name': row.readNullable<String>('customer_name'),
      'vehicle': row.readNullable<String>('vehicle_label'),
      '_local_snapshot': true,
    }).toList();
  }

  String? _text(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  int? _int(Object? value) => int.tryParse(value?.toString() ?? '');
  double? _double(Object? value) => double.tryParse(value?.toString() ?? '');
  DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');
  int? _unix(DateTime? value) => value == null
      ? null
      : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
