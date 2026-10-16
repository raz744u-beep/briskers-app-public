import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';
import 'local_job_retirement.dart';
import 'local_job_deletion_v3.dart';

class LocalDocumentRepository {
  LocalDocumentRepository({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  // Estimates and accounting are retained. A retired Job only hides invoices;
  // an exact invoice tombstone also applies after a stale reassignment response.
  static String _visibleDocumentSql(String alias) =>
      """
    NOT EXISTS (SELECT 1 FROM local_job_retirement_entities r
      WHERE r.business_id = $alias.business_id
        AND r.state IN ('pending','accepted','locally_cancelled')
        AND ((r.entity_kind = 'invoice' AND r.entity_id = $alias.id)
          OR ($alias.kind = 'invoice' AND r.entity_kind = 'job'
            AND r.entity_id = $alias.job_id)))
    AND NOT EXISTS (SELECT 1 FROM local_job_deletion_v3_fences v3
      WHERE v3.business_id=$alias.business_id AND v3.entity_kind=$alias.kind
        AND v3.entity_id=$alias.id)
  """;

  static const _visibleJoinedJobSql = "NOT EXISTS(SELECT 1 FROM local_job_deletion_v3_fences hidden_job "
      "WHERE hidden_job.business_id=j.business_id AND hidden_job.entity_kind='job' AND hidden_job.entity_id=j.id)";

  Future<bool> _serverDocumentBlocked(
    String businessId,
    Map<String, dynamic> document,
  ) async {
    final id = document['id']?.toString() ?? '';
    if (await LocalJobRetirement.isDocumentBlocked(_database, businessId, id)) {
      return true;
    }
    final jobId = document['job_id']?.toString() ?? '';
    return (document['kind']?.toString() ?? 'invoice') == 'invoice' &&
        jobId.isNotEmpty &&
        (await LocalJobRetirement.blockedJobIds(_database, businessId, includeVisibilityScope: false)).contains(jobId);
  }

  Future<void> replaceFromServer(
    String businessId,
    List<Map<String, dynamic>> documents, {
    String? kind,
  }) async {
    await _database.transaction(() async {
      await LocalJobRetirement.ensureSchema(_database);
    await LocalJobDeletionV3.assertVisibilityActor(_database, businessId);
      // A pending request can be rejected later. Retain its exact prior row
      // rather than letting an unrelated full refresh erase the recovery data.
      final visible = _visibleDocumentSql('local_documents');
      await _database.customStatement(
        kind == null
            ? "DELETE FROM local_documents WHERE business_id = ? AND sync_state = 'synced' AND $visible"
            : "DELETE FROM local_documents WHERE business_id = ? AND kind = ? AND sync_state = 'synced' AND $visible",
        kind == null ? [businessId] : [businessId, kind],
      );
      for (final document in documents) {
        final id = document['id']?.toString() ?? '';
        if (id.isEmpty || await _serverDocumentBlocked(businessId, document)) {
          continue;
        }
        await _database.customStatement(
          '''
          INSERT INTO local_documents (
            id, business_id, job_id, customer_id, kind, document_number,
            status, display_status_code, closed_at, converted, total, document_date, future_date_flag, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
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
            document_date=excluded.document_date,
            future_date_flag=excluded.future_date_flag,
            created_at=excluded.created_at,
            server_updated_at=excluded.server_updated_at,
            row_version=excluded.row_version,
            sync_state='synced'
          WHERE local_documents.sync_state = 'synced'
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
            _documentDate(document['document_date']),
            document['future_date_flag'] == true ? 1 : 0,
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
        if (id.isEmpty || await _serverDocumentBlocked(businessId, document)) {
          continue;
        }
        await _database.customStatement(
          '''
          INSERT INTO local_documents (
            id, business_id, job_id, customer_id, kind, document_number,
            status, display_status_code, closed_at, converted, total, document_date, future_date_flag, created_at, server_updated_at, row_version, sync_state
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
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
            document_date=excluded.document_date,
            future_date_flag=excluded.future_date_flag,
            created_at=excluded.created_at,
            server_updated_at=excluded.server_updated_at,
            row_version=excluded.row_version,
            sync_state='synced'
          WHERE local_documents.sync_state = 'synced'
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
            _documentDate(document['document_date']),
            document['future_date_flag'] == true ? 1 : 0,
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
    await LocalJobRetirement.ensureSchema(_database);
    final visibilityGeneration = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
    final rows = await _database
        .customSelect(
          '''
      SELECT d.*, j.job_number, j.title AS job_title,
             coalesce(j.customer_name,c.display_name,'Customer') AS customer_name,
             coalesce(j.vehicle_label,'') AS vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
        AND $_visibleJoinedJobSql
      LEFT JOIN local_customers c ON c.business_id=d.business_id
        AND c.id=d.customer_id
      WHERE d.business_id = ? AND d.kind = ?
        AND ${_visibleDocumentSql('d')}
      ORDER BY d.document_date DESC NULLS LAST, d.created_at DESC, d.id
      ''',
          variables: [Variable<String>(businessId), Variable<String>(kind)],
        )
        .get();

    String displayStatus(QueryRow row) {
      if (row.read<String>('id').startsWith('local-invoice-') &&
          row.read<String>('sync_state') == 'pending') {
        return 'Pending sync';
      }
      final raw =
          row.readNullable<String>('display_status_code') ??
          row.readNullable<String>('status') ??
          '';
      if (raw.isEmpty) return '';
      return raw
          .split('_')
          .where((part) => part.isNotEmpty)
          .map(
            (part) => part.length == 1
                ? part.toUpperCase()
                : part[0].toUpperCase() + part.substring(1).toLowerCase(),
          )
          .join(' ');
    }

    final result = rows
        .map(
          (row) => <String, dynamic>{
            'id': row.read<String>('id'),
            'job_id': row.readNullable<String>('job_id'),
            'customer_id': row.readNullable<String>('customer_id'),
            'kind': row.read<String>('kind'),
            'document_number': row.readNullable<String>('document_number'),
            'status': row.readNullable<String>('status'),
            'converted': row.read<int>('converted') == 1,
            'row_version': row.readNullable<int>('row_version'),
            'display_status': displayStatus(row),
            'display_status_code': row.readNullable<String>(
              'display_status_code',
            ),
            'total_amount': row.read<double>('total'),
            'paid_amount': 0,
            'pending_payment': 0,
            'document_date': row.readNullable<String>('document_date'),
            'future_date_flag': row.read<int>('future_date_flag') == 1,
            'created_at': _isoFromDb(row.data['created_at']),
            'updated_at': _isoFromDb(row.data['server_updated_at']),
            'job_number': row.readNullable<String>('job_number'),
            'job_title': row.readNullable<String>('job_title'),
            'customer_name': row.readNullable<String>('customer_name'),
            'vehicle': row.readNullable<String>('vehicle_label'),
            '_local_snapshot': true,
          },
        )
        .toList();
    if (kind == 'estimate' &&
        (await LocalJobRetirement.blockedDocumentIds(
          _database,
          businessId,
        )).isNotEmpty) {
      final cache = LocalDocumentDetailCache(database: _database);
      for (final document in result) {
        if (document['converted'] != true) continue;
        final detail = await cache.load(businessId, document['id'].toString());
        final indexVersion = num.tryParse(
          document['row_version']?.toString() ?? '',
        );
        final detailVersion = num.tryParse(
          detail?['row_version']?.toString() ?? '',
        );
        if (detail?['_retired_conversion'] == true &&
            (indexVersion == null ||
                detailVersion == null ||
                detailVersion >= indexVersion)) {
          document['converted'] = false;
        }
      }
    }
    await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, visibilityGeneration);
    return result;
  }

  Future<String?> createdAtForDocument(
    String businessId,
    String documentId,
  ) async {
    await LocalJobRetirement.ensureSchema(_database);
    await LocalJobDeletionV3.assertVisibilityActor(_database, businessId);
    final rows = await _database
        .customSelect(
          '''
      SELECT created_at
      FROM local_documents d
      WHERE business_id = ? AND id = ? AND ${_visibleDocumentSql('d')}
      LIMIT 1
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<String>(documentId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return _isoFromDb(rows.first.data['created_at']);
  }

  Future<List<Map<String, dynamic>>> listByJob(
    String businessId,
    String jobId,
  ) async {
    await LocalJobRetirement.ensureSchema(_database);
    final visibilityGeneration = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
    final rows = await _database
        .customSelect(
          '''
      SELECT d.*, j.job_number, j.customer_name, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
        AND $_visibleJoinedJobSql
      WHERE d.business_id = ? AND d.job_id = ?
        AND ${_visibleDocumentSql('d')}
      ORDER BY d.document_date DESC NULLS LAST, d.created_at DESC, d.id
      ''',
          variables: [Variable<String>(businessId), Variable<String>(jobId)],
        )
        .get();

    String displayStatus(QueryRow row) {
      if (row.read<String>('id').startsWith('local-invoice-') &&
          row.read<String>('sync_state') == 'pending') {
        return 'Pending sync';
      }
      final raw =
          row.readNullable<String>('display_status_code') ??
          row.readNullable<String>('status') ??
          '';
      if (raw.isEmpty) return '';
      return raw
          .split('_')
          .where((part) => part.isNotEmpty)
          .map(
            (part) => part.length == 1
                ? part.toUpperCase()
                : part[0].toUpperCase() + part.substring(1).toLowerCase(),
          )
          .join(' ');
    }

    await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, visibilityGeneration);
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
            'display_status_code': row.readNullable<String>(
              'display_status_code',
            ),
            'total_amount': row.read<double>('total'),
            'paid_amount': 0,
            'pending_payment': 0,
            'document_date': row.readNullable<String>('document_date'),
            'future_date_flag': row.read<int>('future_date_flag') == 1,
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
    final estimates = await listByKind(businessId, kind: 'estimate');
    return estimates.where((document) {
      final status = document['status']?.toString().toLowerCase() ?? '';
      return document['converted'] != true &&
          !const {'accepted', 'declined', 'expired', 'void'}.contains(status);
    }).length;
  }

  Stream<int> watchOpenEstimateCount(String businessId) {
    // Conversion is a read-only projection of the retained exact detail link.
    // A retirement notification invalidates localDocuments even though its
    // historical converted column has deliberately not been overwritten.
    return _database
        .customSelect(
          "SELECT id FROM local_documents WHERE business_id = ? AND kind = 'estimate'",
          variables: [Variable<String>(businessId)],
          readsFrom: {_database.localDocuments},
        )
        .watch()
        .asyncMap((_) => openEstimateCount(businessId));
  }

  /// Read-only offline Home attention from the already-synced invoice index.
  /// Does not interpret a missing snapshot as evidence that invoices are paid.
  Future<Map<String, dynamic>> pendingCloseAttention(
    String businessId, {
    int limit = 25,
  }) async {
    await LocalJobRetirement.ensureSchema(_database);
    await LocalJobDeletionV3.assertVisibilityActor(_database, businessId);
    final where =
        '''
      d.business_id = ? AND d.kind = 'invoice'
      AND ${_visibleDocumentSql('d')}
      AND d.closed_at IS NULL
      AND lower(replace(coalesce(d.display_status_code, ''), ' ', '_'))
          IN ('pending_close', 'pendingclose')
    ''';
    final countRow = await _database
        .customSelect(
          'SELECT COUNT(*) AS count FROM local_documents d WHERE $where',
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    final rows = await _database
        .customSelect(
          '''
      SELECT d.id, d.document_number, d.job_id, d.customer_id,
             coalesce(c.display_name,j.customer_name,'Customer') AS customer_name,
             coalesce(j.job_number,'') AS job_number,
             coalesce(j.vehicle_label,'') AS vehicle
      FROM local_documents d
      LEFT JOIN local_jobs j ON j.business_id = d.business_id
        AND j.id = d.job_id AND $_visibleJoinedJobSql
      LEFT JOIN local_customers c ON c.business_id = d.business_id
        AND c.id = d.customer_id
      WHERE $where
      ORDER BY d.document_date DESC, d.created_at DESC
      LIMIT ?
      ''',
          variables: [Variable<String>(businessId), Variable<int>(limit)],
        )
        .get();
    return {
      'count': countRow.read<int>('count'),
      'items': [
        for (final row in rows)
          <String, dynamic>{
            'id': row.read<String>('id'),
            'document_number': row.readNullable<String>('document_number'),
            'job_id': row.readNullable<String>('job_id'),
            'job_number': row.read<String>('job_number'),
            'customer_name': row.read<String>('customer_name'),
            'vehicle': row.read<String>('vehicle'),
          },
      ],
    };
  }

  Future<int> openInvoiceCount(String businessId) async {
    await LocalJobRetirement.ensureSchema(_database);
    await LocalJobDeletionV3.assertVisibilityActor(_database, businessId);
    final row = await _database
        .customSelect(
          '''
      SELECT COUNT(*) AS count
      FROM local_documents d
      WHERE business_id = ?
        AND ${_visibleDocumentSql('d')}
        AND kind = 'invoice'
        AND closed_at IS NULL
        AND lower(COALESCE(status, '')) <> 'void'
      ''',
          variables: [Variable<String>(businessId)],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Stream<int> watchOpenInvoiceCount(String businessId) async* {
    await LocalJobRetirement.ensureSchema(_database);
    await LocalJobDeletionV3.assertVisibilityActor(_database, businessId);
    yield* _database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM local_documents d
          WHERE business_id = ?
            AND ${_visibleDocumentSql('d')}
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
    await LocalJobRetirement.ensureSchema(_database);
    final visibilityGeneration = await LocalJobDeletionV3.captureVisibilityGeneration(_database, businessId);
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return const [];
    final numeric = RegExp(r'^[0-9]+$').hasMatch(value);
    final like = '%$value%';
    final rows = await _database
        .customSelect(
          '''
      SELECT d.*, j.job_number, j.customer_name, j.vehicle_label
      FROM local_documents d
      LEFT JOIN local_jobs j
        ON j.business_id = d.business_id AND j.id = d.job_id
        AND $_visibleJoinedJobSql
      WHERE d.business_id = ?
        AND ${_visibleDocumentSql('d')}
        AND (
          (
            ? = 1 AND (
              lower(COALESCE(d.document_number, '')) = ?
              OR lower(COALESCE(d.document_number, '')) = ?
              OR lower(COALESCE(j.job_number, '')) = ?
            )
          )
          OR (
            ? = 0 AND (
              lower(COALESCE(d.document_number, '')) LIKE ?
              OR lower(COALESCE(j.job_number, '')) LIKE ?
              OR lower(COALESCE(j.customer_name, '')) LIKE ?
            )
          )
        )
      ORDER BY d.document_date DESC NULLS LAST, d.created_at DESC, d.id
      LIMIT ?
      ''',
          variables: [
            Variable<String>(businessId),
            Variable<int>(numeric ? 1 : 0),
            Variable<String>(value),
            Variable<String>('I-$value'),
            Variable<String>('MB-$value'),
            Variable<int>(numeric ? 1 : 0),
            Variable<String>(like),
            Variable<String>(like),
            Variable<String>(like),
            Variable<int>(limit),
          ],
        )
        .get();

    await LocalJobDeletionV3.assertVisibilityGeneration(_database, businessId, visibilityGeneration);
    return rows
        .map(
          (row) => <String, dynamic>{
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
          },
        )
        .toList();
  }

  // Preserve YYYY-MM-DD without converting a calendar date across timezones.
  // Legacy created_at is the Briskers import timestamp, not the issue date.
  String? _documentDate(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.length < 10) return null;
    final date = raw.substring(0, 10);
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}').hasMatch(date)) {
      return null;
    }
    return DateTime.tryParse(date) == null ? null : date;
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
    return DateTime.tryParse(value.toString())?.toUtc().toIso8601String();
  }

  String? _text(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  int? _int(Object? value) => int.tryParse(value?.toString() ?? '');
  double? _double(Object? value) => double.tryParse(value?.toString() ?? '');
  DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');
  int? _unix(DateTime? value) =>
      value == null ? null : value.toUtc().millisecondsSinceEpoch ~/ 1000;
}

