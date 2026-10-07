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
            status, display_status_code, closed_at, converted, total, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ''',
          [
            id,
            businessId,
            _text(document['job_id']),
            _text(document['customer_id']),
            document['kind']?.toString() ?? 'invoice',
            _text(document['document_number']),
            _text(document['status']),
            _text(document['display_status_code']),
            _unix(_date(document['closed_at'])),
            document['converted'] == true ? 1 : 0,
            _double(document['total_amount'] ?? document['total']) ?? 0,
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
            status, display_status_code, closed_at, converted, total, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
          ON CONFLICT(id) DO UPDATE SET
            job_id=excluded.job_id,
            customer_id=excluded.customer_id,
            kind=excluded.kind,
            document_number=excluded.document_number,
            status=excluded.status,
            display_status_code=excluded.display_status_code,
            closed_at=excluded.closed_at,
            converted=excluded.converted,
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
            _text(document['display_status_code']),
            _unix(_date(document['closed_at'])),
            document['converted'] == true ? 1 : 0,
            _double(document['total_amount'] ?? document['total']) ?? 0,
            _unix(_date(document['created_at'])),
            _unix(_date(document['updated_at'])),
            _int(document['row_version']),
          ],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> listByKind(
    String businessId, {
    required String kind,
  }) async {
    final rows = await _database.customSelect(
      '''
      SELECT d.*, j.job_number, j.customer_name, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
      WHERE d.business_id = ? AND d.kind = ?
      ORDER BY d.created_at DESC, d.id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(kind),
      ],
    ).get();

    String displayStatus(QueryRow row) {
      final raw = row.readNullable<String>('display_status_code') ??
          row.readNullable<String>('status') ??
          '';
      if (raw.isEmpty) return '';
      return raw
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) =>
              part.length == 1
                  ? part.toUpperCase()
                  : part[0].toUpperCase() + part.substring(1).toLowerCase())
          .join(' ');
    }

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'job_id': row.readNullable<String>('job_id'),
            'customer_id': row.readNullable<String>('customer_id'),
            'kind': row.read<String>('kind'),
            'document_number': row.readNullable<String>('document_number'),
            'status': row.readNullable<String>('status'),
            'converted': row.read<int>('converted') == 1,
            'display_status': displayStatus(row),
            'display_status_code':
                row.readNullable<String>('display_status_code'),
            'total_amount': row.read<double>('total'),
            'paid_amount': 0,
            'pending_payment': 0,
            'document_date': _isoFromDb(row.data['created_at']),
            'created_at': _isoFromDb(row.data['created_at']),
            'updated_at': _isoFromDb(row.data['server_updated_at']),
            'job_number': row.readNullable<String>('job_number'),
            'customer_name': row.readNullable<String>('customer_name'),
            'vehicle': row.readNullable<String>('vehicle_label'),
            '_local_snapshot': true,
          },
        )
        .toList();
  }
  Future<String?> createdAtForDocument(
    String businessId,
    String documentId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT created_at
      FROM local_documents
      WHERE business_id = ? AND id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(documentId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return _isoFromDb(rows.first.data['created_at']);
  }

  Future<List<Map<String, dynamic>>> listByJob(
    String businessId,
    String jobId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT d.*, j.job_number, j.customer_name, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
      WHERE d.business_id = ? AND d.job_id = ?
      ORDER BY d.created_at DESC, d.id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobId),
      ],
    ).get();

    String displayStatus(QueryRow row) {
      final raw = row.readNullable<String>('display_status_code') ??
          row.readNullable<String>('status') ??
          '';
      if (raw.isEmpty) return '';
      return raw
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => part.length == 1
              ? part.toUpperCase()
              : part[0].toUpperCase() + part.substring(1).toLowerCase())
          .join(' ');
    }

    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'job_id': row.readNullable<String>('job_id'),
            'customer_id': row.readNullable<String>('customer_id'),
            'kind': row.read<String>('kind'),
            'document_number': row.readNullable<String>('document_number'),
            'status': row.readNullable<String>('status'),
            'display_status': displayStatus(row),
            'display_status_code':
                row.readNullable<String>('display_status_code'),
            'total_amount': row.read<double>('total'),
            'paid_amount': 0,
            'pending_payment': 0,
            'document_date': _isoFromDb(row.data['created_at']),
            'created_at': _isoFromDb(row.data['created_at']),
            'updated_at': _isoFromDb(row.data['server_updated_at']),
            'job_number': row.readNullable<String>('job_number'),
            'customer_name': row.readNullable<String>('customer_name'),
            'vehicle': row.readNullable<String>('vehicle_label'),
            '_local_snapshot': true,
          },
        )
        .toList();
  }

  Future<int> openEstimateCount(String businessId) async {
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_documents
      WHERE business_id = ?
        AND kind = 'estimate'
        AND converted = 0
        AND lower(COALESCE(status, '')) NOT IN ('accepted', 'declined', 'expired', 'void')
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchOpenEstimateCount(String businessId) {
    return _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_documents
          WHERE business_id = ?
            AND kind = 'estimate'
            AND converted = 0
            AND lower(COALESCE(status, '')) NOT IN ('accepted', 'declined', 'expired', 'void')
          ''',
          variables: [Variable<String>(businessId)],
          readsFrom: {_database.localDocuments},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
  }

  Future<int> openInvoiceCount(String businessId) async {
    final row = await _database.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM local_documents
      WHERE business_id = ?
        AND kind = 'invoice'
        AND closed_at IS NULL
        AND lower(COALESCE(status, '')) <> 'void'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchOpenInvoiceCount(String businessId) {
    return _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_documents
          WHERE business_id = ?
            AND kind = 'invoice'
            AND closed_at IS NULL
            AND lower(COALESCE(status, '')) <> 'void'
          ''',
          variables: [Variable<String>(businessId)],
          readsFrom: {_database.localDocuments},
        )
        .watchSingle()
        .map((row) => row.read<int>('count'));
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

  String? _isoFromDb(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return DateTime.tryParse(value.toString())
        ?.toUtc()
        .toIso8601String();
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
