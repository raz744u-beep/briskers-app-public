// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:io';

import 'package:drift/drift.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_document_detail_cache.dart';
import 'local_invoice_status_styles_cache.dart';
import 'local_tax_settings_cache.dart';

enum BriskersDiagnosticLevel {
  pass,
  warning,
  fail,
}

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.category,
    required this.title,
    required this.level,
    required this.summary,
    this.details = const [],
  });

  final String id;
  final String category;
  final String title;
  final BriskersDiagnosticLevel level;
  final String summary;
  final List<String> details;
}

class DiagnosticsReport {
  const DiagnosticsReport({
    required this.startedAt,
    required this.finishedAt,
    required this.full,
    required this.connectionMode,
    required this.checks,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final bool full;
  final String connectionMode;
  final List<DiagnosticCheck> checks;

  int get passed =>
      checks.where((check) => check.level == BriskersDiagnosticLevel.pass).length;
  int get warnings =>
      checks.where((check) => check.level == BriskersDiagnosticLevel.warning).length;
  int get failed =>
      checks.where((check) => check.level == BriskersDiagnosticLevel.fail).length;

  String toText() {
    final buffer = StringBuffer()
      ..writeln('Briskers Diagnostics')
      ..writeln('Mode: ' + (full ? 'Full Check' : 'Quick Check'))
      ..writeln('Connection: ' + connectionMode)
      ..writeln('Started: ' + startedAt.toLocal().toIso8601String())
      ..writeln('Finished: ' + finishedAt.toLocal().toIso8601String())
      ..writeln(
        'Result: $passed passed, $warnings warnings, $failed failed',
      )
      ..writeln();

    for (final check in checks) {
      final marker = switch (check.level) {
        BriskersDiagnosticLevel.pass => 'PASS',
        BriskersDiagnosticLevel.warning => 'WARN',
        BriskersDiagnosticLevel.fail => 'FAIL',
      };
      buffer.writeln(
        '[' + marker + '] ' + check.id + ' ' + check.title,
      );
      buffer.writeln('  ' + check.summary);
      for (final detail in check.details) {
        buffer.writeln('  - ' + detail);
      }
    }
    return buffer.toString();
  }
}

class BriskersDiagnosticsService {
  BriskersDiagnosticsService({
    BriskersLocalDatabase? database,
    LocalDocumentDetailCache detailCache =
        const LocalDocumentDetailCache(),
    LocalTaxSettingsCache? taxSettingsCache,
    LocalInvoiceStatusStylesCache? invoiceStatusStylesCache,
    BriskersConnectionModeController? connectionMode,
  })  : _database = database ?? localDatabase,
        _detailCache = detailCache,
        _taxSettingsCache =
            taxSettingsCache ?? LocalTaxSettingsCache(),
        _invoiceStatusStylesCache =
            invoiceStatusStylesCache ?? LocalInvoiceStatusStylesCache(),
        _connectionMode =
            connectionMode ?? BriskersConnectionModeController.instance;

  final BriskersLocalDatabase _database;
  final LocalDocumentDetailCache _detailCache;
  final LocalTaxSettingsCache _taxSettingsCache;
  final LocalInvoiceStatusStylesCache _invoiceStatusStylesCache;
  final BriskersConnectionModeController _connectionMode;

  Future<DiagnosticsReport> run(
    String businessId, {
    bool full = false,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final checks = <DiagnosticCheck>[];

    await _safeGroup(
      checks,
      fallbackId: 'DB-000',
      category: 'Local database',
      title: 'Local database access',
      action: () => _checkDatabase(businessId, checks),
    );
    await _safeGroup(
      checks,
      fallbackId: 'DB-003',
      category: 'Local database',
      title: 'ExpenseIQ schema migration',
      action: () => _checkExpenseIqSchema(checks),
    );
    await _safeGroup(
      checks,
      fallbackId: 'PHOTOIQ-000',
      category: 'ExpenseIQ photo sync',
      title: 'ExpenseIQ local queue',
      action: () => _checkExpenseIqQueue(businessId, checks, full: full),
    );
    await _safeGroup(
      checks,
      fallbackId: 'OFF-000',
      category: 'Offline readiness',
      title: 'Offline cache readiness',
      action: () => _checkOfflineReadiness(businessId, checks),
    );
    await _safeGroup(
      checks,
      fallbackId: 'SYNC-000',
      category: 'Sync',
      title: 'Sync health',
      action: () => _checkSync(businessId, checks),
    );
    await _safeGroup(
      checks,
      fallbackId: 'REL-000',
      category: 'Relationships',
      title: 'Local relationship integrity',
      action: () => _checkRelationships(businessId, checks),
    );
    await _safeGroup(
      checks,
      fallbackId: 'SET-000',
      category: 'Offline settings',
      title: 'Offline settings cache',
      action: () => _checkSettingsCaches(businessId, checks),
    );

    if (full) {
      await _safeGroup(
        checks,
        fallbackId: 'DOC-000',
        category: 'Documents',
        title: 'Document cache integrity',
        action: () => _checkDocuments(businessId, checks),
      );
      await _safeGroup(
        checks,
        fallbackId: 'DOC-004',
        category: 'Documents',
        title: 'All invoice and estimate offline detail coverage',
        action: () => _checkAllDocumentDetailCoverage(businessId, checks),
      );
      if (!_connectionMode.forceOffline) {
        await _safeGroup(
          checks,
          fallbackId: 'EXP-001',
          category: 'Linked expenses',
          title: 'Invoice/job expense allocation integrity',
          action: () => _checkExpenseLinkIntegrity(businessId, checks),
        );
      }
      await _safeGroup(
        checks,
        fallbackId: 'PHOTO-000',
        category: 'Photos',
        title: 'Photo queue integrity',
        action: () => _checkPhotos(businessId, checks),
      );
      await _safeGroup(
        checks,
        fallbackId: 'ID-000',
        category: 'Local IDs',
        title: 'Local ID remapping',
        action: () => _checkLocalIdRemapping(businessId, checks),
      );
    }

    checks.add(
      DiagnosticCheck(
        id: 'NET-001',
        category: 'Connection',
        title: 'Connection mode',
        level: BriskersDiagnosticLevel.pass,
        summary: 'Current mode: ' + _connectionMode.label,
        details: [
          if (_connectionMode.forceOffline)
            'Force Offline is active; Briskers server calls are blocked.',
          if (_connectionMode.forceOnline)
            'Force Online is active; server/API failures will be exposed.',
          if (!_connectionMode.forceOffline &&
              !_connectionMode.forceOnline)
            'Auto is active; normal local-first behavior is enabled.',
        ],
      ),
    );

    return DiagnosticsReport(
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      full: full,
      connectionMode: _connectionMode.label,
      checks: checks,
    );
  }

  Future<void> _safeGroup(
    List<DiagnosticCheck> checks, {
    required String fallbackId,
    required String category,
    required String title,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
    } catch (error) {
      checks.add(
        DiagnosticCheck(
          id: fallbackId,
          category: category,
          title: title,
          level: BriskersDiagnosticLevel.fail,
          summary: 'The diagnostic check itself could not complete.',
          details: [error.toString()],
        ),
      );
    }
  }

  Future<int> _count(
    String sql,
    List<Variable<Object>> variables,
  ) async {
    final row = await _database.customSelect(
      sql,
      variables: variables,
    ).getSingle();
    return row.read<int>('count');
  }

  Future<void> _checkDatabase(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final ready =
        await _database.customSelect('SELECT 1 AS ready').getSingle();

    checks.add(
      DiagnosticCheck(
        id: 'DB-001',
        category: 'Local database',
        title: 'Database opens',
        level: ready.read<int>('ready') == 1
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: 'Local database schema version ' +
            _database.schemaVersion.toString() +
            ' is accessible.',
      ),
    );

    final counts = <String, int>{
      'Customers': await _count(
        'SELECT COUNT(*) AS count FROM local_customers WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Vehicles': await _count(
        'SELECT COUNT(*) AS count FROM local_vehicles WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Appointments': await _count(
        'SELECT COUNT(*) AS count FROM local_appointments WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Jobs': await _count(
        'SELECT COUNT(*) AS count FROM local_jobs WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Catalog items': await _count(
        'SELECT COUNT(*) AS count FROM local_catalog_items WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Documents': await _count(
        'SELECT COUNT(*) AS count FROM local_documents WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Findings': await _count(
        'SELECT COUNT(*) AS count FROM local_findings WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
      'Pre-inspections': await _count(
        'SELECT COUNT(*) AS count FROM local_pre_inspections WHERE business_id = ?',
        [Variable<String>(businessId)],
      ),
    };

    checks.add(
      DiagnosticCheck(
        id: 'DB-002',
        category: 'Local database',
        title: 'Local data inventory',
        level: BriskersDiagnosticLevel.pass,
        summary: 'Local record counts were read successfully.',
        details: counts.entries
            .map((entry) => entry.key + ': ' + entry.value.toString())
            .toList(),
      ),
    );
  }

  // This runs in QUICK and FULL diagnostics. Schema version alone is not
  // proof of a successful upgrade: v18 previously omitted both queue tables.
  Future<void> _checkExpenseIqSchema(List<DiagnosticCheck> checks) async {
    const names = [
      'local_expense_iq_photos',
      'local_expense_iq_sync_settings',
    ];
    final rows = await _database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('local_expense_iq_photos', "
      "'local_expense_iq_sync_settings')",
    ).get();
    final existing = rows.map((row) => row.read<String>('name')).toSet();
    final missing = names.where((name) => !existing.contains(name)).toList();

    final missingColumns = <String>[];
    if (existing.contains('local_expense_iq_photos')) {
      final columns = await _database.customSelect(
        'PRAGMA table_info(local_expense_iq_photos)',
      ).get();
      final present = columns
          .map((row) => row.read<String>('name')).toSet();
      for (final required in const [
        'business_id', 'transaction_id', 'photo_id', 'filename',
        'source_uri', 'state', 'attempts', 'claimed_at',
        'last_error', 'updated_at',
      ]) {
        if (!present.contains(required)) {
          missingColumns.add('local_expense_iq_photos.$required');
        }
      }
    }
    if (existing.contains('local_expense_iq_sync_settings')) {
      final columns = await _database.customSelect(
        'PRAGMA table_info(local_expense_iq_sync_settings)',
      ).get();
      final present = columns
          .map((row) => row.read<String>('name')).toSet();
      for (final required in const [
        'business_id', 'enabled', 'wifi_only',
      ]) {
        if (!present.contains(required)) {
          missingColumns.add('local_expense_iq_sync_settings.$required');
        }
      }
    }
    final versionRow = await _database.customSelect(
      'PRAGMA user_version',
    ).getSingle();
    final actualVersion = versionRow.read<int>('user_version');
    final healthy = missing.isEmpty && missingColumns.isEmpty &&
        actualVersion == _database.schemaVersion;
    checks.add(DiagnosticCheck(
      id: 'DB-003',
      category: 'Local database',
      title: 'ExpenseIQ photo queue schema',
      level: healthy
          ? BriskersDiagnosticLevel.pass
          : BriskersDiagnosticLevel.fail,
      summary: healthy
          ? 'Both ExpenseIQ queue tables and required columns are available.'
          : 'ExpenseIQ queue schema is incomplete or the migration version '
              'does not match.',
      details: [
        'SQLite user_version: $actualVersion; expected: '
            '${_database.schemaVersion}',
        if (missing.isNotEmpty) 'Missing tables: ${missing.join(', ')}',
        if (missingColumns.isNotEmpty)
          'Missing columns: ${missingColumns.join(', ')}',
        if (!healthy)
          'Do not clear app data. Install the migration repair build; '
              'the queue tables can be recreated without deleting records.',
      ],
    ));
  }

  Future<void> _checkExpenseIqQueue(
    String businessId,
    List<DiagnosticCheck> checks, {
    required bool full,
  }) async {
    final table = await _database.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' "
      "AND name='local_expense_iq_photos' LIMIT 1",
    ).get();
    if (table.isEmpty) {
      checks.add(const DiagnosticCheck(
        id: 'PHOTOIQ-001',
        category: 'ExpenseIQ photo sync',
        title: 'Local ExpenseIQ queue health',
        level: BriskersDiagnosticLevel.fail,
        summary: 'ExpenseIQ queue table is missing.',
        details: ['Run DB-003 and install the non-destructive migration fix.'],
      ));
      return;
    }
    final rows = await _database.customSelect(
      '''
      SELECT state, COUNT(*) AS quantity
      FROM local_expense_iq_photos
      WHERE business_id = ?
      GROUP BY state
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    final states = <String, int>{
      for (final row in rows)
        row.read<String>('state'): row.read<int>('quantity'),
    };
    const validStates = <String>{
      'pending','uploading','uploaded','failed','missing',
    };
    final unknown = states.entries
        .where((entry) => !validStates.contains(entry.key))
        .toList();
    final failed = states['failed'] ?? 0;
    final missing = states['missing'] ?? 0;
    final pending = states['pending'] ?? 0;
    final uploading = states['uploading'] ?? 0;
    final uploaded = states['uploaded'] ?? 0;
    final total = states.values.fold<int>(0,(sum,count)=>sum+count);
    checks.add(DiagnosticCheck(
      id: 'PHOTOIQ-001',
      category: 'ExpenseIQ photo sync',
      title: 'Local ExpenseIQ upload queue',
      level: unknown.isNotEmpty
          ? BriskersDiagnosticLevel.fail
          : (failed > 0 || missing > 0
              ? BriskersDiagnosticLevel.warning
              : BriskersDiagnosticLevel.pass),
      summary: total == 0
          ? 'ExpenseIQ photo queue has no indexed records yet.'
          : '$total receipt references indexed locally.',
      details: [
        'Pending: $pending; uploading: $uploading; uploaded: $uploaded; '
            'failed: $failed; unmatched: $missing',
        if (unknown.isNotEmpty)
          'Invalid states: ${unknown.map((row)=>row.key).join(', ')}',
      ],
    ));

    if (!full) return;
    final invalid = await _database.customSelect(
      '''
      SELECT
        SUM(CASE WHEN state IN ('pending','uploading','failed')
                     AND (source_uri IS NULL OR TRIM(source_uri) = '')
                  THEN 1 ELSE 0 END) AS bad_uri,
        SUM(CASE WHEN state = 'uploading' AND
                     (claimed_at IS NULL OR claimed_at < ?)
                  THEN 1 ELSE 0 END) AS stale_claim,
        SUM(CASE WHEN photo_id = '' OR transaction_id = ''
                  THEN 1 ELSE 0 END) AS missing_identity
      FROM local_expense_iq_photos WHERE business_id = ?
      ''',
      variables: [
        Variable<int>(
          DateTime.now().toUtc().microsecondsSinceEpoch -
              20 * 60 * 1000000,
        ),
        Variable<String>(businessId),
      ],
    ).getSingle();
    final badUri = invalid.readNullable<int>('bad_uri') ?? 0;
    final staleClaims = invalid.readNullable<int>('stale_claim') ?? 0;
    final missingId = invalid.readNullable<int>('missing_identity') ?? 0;
    checks.add(DiagnosticCheck(
      id: 'PHOTOIQ-002',
      category: 'ExpenseIQ photo sync',
      title: 'ExpenseIQ queue integrity and stuck uploads',
      level: badUri > 0 || missingId > 0
          ? BriskersDiagnosticLevel.fail
          : staleClaims > 0
              ? BriskersDiagnosticLevel.warning
              : BriskersDiagnosticLevel.pass,
      summary: badUri + staleClaims + missingId == 0
          ? 'No broken photo references or stale upload claims.'
          : 'ExpenseIQ queue needs attention.',
      details: [
        'Queued photos missing source URI: $badUri',
        'Expired upload claims: $staleClaims',
        'References missing transaction/photo IDs: $missingId',
      ],
    ));
  }

  Future<void> _checkOfflineReadiness(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT scope, last_pull_at, last_error, bootstrapped
      FROM local_sync_states
      WHERE business_id = ?
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    final byScope = <String, QueryRow>{
      for (final row in rows) row.read<String>('scope'): row,
    };
    const requiredScopes = <String>[
      'customers_vehicles',
      'appointments',
      'jobs',
      'catalog',
      'documents',
    ];

    final missing = <String>[];
    final details = <String>[];
    for (final scope in requiredScopes) {
      final row = byScope[scope];
      final bootstrapped =
          row != null && row.read<int>('bootstrapped') == 1;
      if (!bootstrapped) missing.add(scope);
      final pulled = row?.readNullable<DateTime>('last_pull_at');
      details.add(
        scope +
            ': ' +
            (bootstrapped ? 'ready' : 'NOT READY') +
            (pulled == null
                ? ''
                : ' • last pull ' + pulled.toLocal().toIso8601String()),
      );
    }

    checks.add(
      DiagnosticCheck(
        id: 'OFF-001',
        category: 'Offline readiness',
        title: 'Core offline datasets',
        level: missing.isEmpty
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: missing.isEmpty
            ? 'All core datasets report a completed local bootstrap.'
            : 'Offline data is incomplete for ' +
                missing.length.toString() +
                ' core dataset(s).',
        details: details,
      ),
    );
  }

  Future<void> _checkSync(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final conflictCount = await _count(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE business_id = ? AND state = 'conflict'
      ''',
      [Variable<String>(businessId)],
    );
    final pendingCount = await _count(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE business_id = ? AND state = 'pending'
      ''',
      [Variable<String>(businessId)],
    );
    final retryingCount = await _count(
      '''
      SELECT COUNT(*) AS count
      FROM sync_outbox
      WHERE business_id = ?
        AND state = 'pending'
        AND (attempt_count > 0 OR COALESCE(last_error, '') <> '')
      ''',
      [Variable<String>(businessId)],
    );

    checks.add(
      DiagnosticCheck(
        id: 'SYNC-001',
        category: 'Sync',
        title: 'Sync conflicts',
        level: conflictCount == 0
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: conflictCount == 0
            ? 'No unresolved sync conflicts.'
            : conflictCount.toString() +
                ' unresolved sync conflict(s) require attention.',
      ),
    );

    checks.add(
      DiagnosticCheck(
        id: 'SYNC-002',
        category: 'Sync',
        title: 'Pending changes',
        level: retryingCount > 0
            ? BriskersDiagnosticLevel.warning
            : (pendingCount > 0
                ? BriskersDiagnosticLevel.warning
                : BriskersDiagnosticLevel.pass),
        summary: pendingCount == 0
            ? 'No local changes are waiting to sync.'
            : pendingCount.toString() +
                ' local change(s) are waiting to sync.',
        details: [
          if (retryingCount > 0)
            retryingCount.toString() +
                ' pending operation(s) have already failed at least once.',
        ],
      ),
    );

    final stateErrors = await _database.customSelect(
      '''
      SELECT scope, last_error
      FROM local_sync_states
      WHERE business_id = ?
        AND COALESCE(last_error, '') <> ''
      ORDER BY scope
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    checks.add(
      DiagnosticCheck(
        id: 'SYNC-003',
        category: 'Sync',
        title: 'Dataset sync errors',
        level: stateErrors.isEmpty
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: stateErrors.isEmpty
            ? 'No dataset-level sync errors are recorded.'
            : stateErrors.length.toString() +
                ' dataset sync error(s) are recorded.',
        details: stateErrors
            .map(
              (row) =>
                  row.read<String>('scope') +
                  ': ' +
                  (row.readNullable<String>('last_error') ??
                      'Unknown error'),
            )
            .toList(),
      ),
    );
  }

  Future<void> _checkRelationships(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final problems = <String, int>{
      'Jobs missing customer': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_jobs j
        LEFT JOIN local_customers c
          ON c.business_id = j.business_id AND c.id = j.customer_id
        WHERE j.business_id = ?
          AND j.customer_id IS NOT NULL
          AND c.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Jobs missing vehicle': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_jobs j
        LEFT JOIN local_vehicles v
          ON v.business_id = j.business_id AND v.id = j.vehicle_id
        WHERE j.business_id = ?
          AND j.vehicle_id IS NOT NULL
          AND v.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Documents missing job': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_documents d
        LEFT JOIN local_jobs j
          ON j.business_id = d.business_id AND j.id = d.job_id
        WHERE d.business_id = ?
          AND d.job_id IS NOT NULL
          AND j.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Documents missing customer': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_documents d
        LEFT JOIN local_customers c
          ON c.business_id = d.business_id AND c.id = d.customer_id
        WHERE d.business_id = ?
          AND d.customer_id IS NOT NULL
          AND c.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Appointments missing customer': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_appointments a
        LEFT JOIN local_customers c
          ON c.business_id = a.business_id AND c.id = a.customer_id
        WHERE a.business_id = ? AND c.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Appointments missing vehicle': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_appointments a
        LEFT JOIN local_vehicles v
          ON v.business_id = a.business_id AND v.id = a.vehicle_id
        WHERE a.business_id = ?
          AND a.vehicle_id IS NOT NULL
          AND v.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
      'Pre-inspections missing job': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_pre_inspections p
        LEFT JOIN local_jobs j
          ON j.business_id = p.business_id AND j.id = p.job_id
        WHERE p.business_id = ? AND j.id IS NULL
        ''',
        [Variable<String>(businessId)],
      ),
    };

    final total = problems.values.fold<int>(0, (sum, value) => sum + value);
    checks.add(
      DiagnosticCheck(
        id: 'REL-001',
        category: 'Relationships',
        title: 'Customer, vehicle and job links',
        level: total == 0 ? BriskersDiagnosticLevel.pass : BriskersDiagnosticLevel.fail,
        summary: total == 0
            ? 'No broken core relationships were found.'
            : total.toString() +
                ' broken local relationship(s) were found.',
        details: problems.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key + ': ' + entry.value.toString())
            .toList(),
      ),
    );
  }

  Future<void> _checkSettingsCaches(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final tax = await _taxSettingsCache.load(businessId);
    final styles = await _invoiceStatusStylesCache.load(businessId);

    final rate = num.tryParse(tax?['sales_tax_rate']?.toString() ?? '');
    checks.add(
      DiagnosticCheck(
        id: 'SET-001',
        category: 'Offline settings',
        title: 'Tax settings cache',
        level: tax != null && rate != null
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: tax != null && rate != null
            ? 'Tax settings are available offline.'
            : 'Tax settings are not safely cached for offline use.',
        details: [
          if (rate != null)
            'Cached sales tax rate: ' +
                (rate * 100).toStringAsFixed(3) +
                '%',
        ],
      ),
    );

    checks.add(
      DiagnosticCheck(
        id: 'SET-002',
        category: 'Offline settings',
        title: 'Invoice status styles cache',
        level: styles.isNotEmpty
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.warning,
        summary: styles.isNotEmpty
            ? styles.length.toString() +
                ' invoice status style(s) are cached.'
            : 'No invoice status styles are cached; fallback colors will be used.',
      ),
    );
  }

  Future<void> _checkDocuments(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT id, kind, job_id, customer_id, total
      FROM local_documents
      WHERE business_id = ?
        AND (
          (kind = 'estimate'
            AND converted = 0
            AND lower(COALESCE(status, 'draft'))
                NOT IN ('accepted','declined','expired','void'))
          OR
          (kind = 'invoice'
            AND closed_at IS NULL
            AND lower(COALESCE(status, '')) <> 'void')
        )
      ORDER BY created_at DESC, id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    var missingCache = 0;
    var relationshipMismatch = 0;
    var mathMismatch = 0;

    for (final row in rows) {
      final id = row.read<String>('id');
      final detail = await _detailCache.load(businessId, id);
      if (detail == null) {
        missingCache++;
        continue;
      }

      final indexJobId = row.readNullable<String>('job_id') ?? '';
      final detailJobId = detail['job_id']?.toString() ?? '';
      final indexCustomerId =
          row.readNullable<String>('customer_id') ?? '';
      final detailCustomerId = detail['customer_id']?.toString() ?? '';
      if ((indexJobId.isNotEmpty &&
              detailJobId.isNotEmpty &&
              indexJobId != detailJobId) ||
          (indexCustomerId.isNotEmpty &&
              detailCustomerId.isNotEmpty &&
              indexCustomerId != detailCustomerId) ||
          (indexJobId.isEmpty && detailJobId.isNotEmpty) ||
          (indexCustomerId.isEmpty && detailCustomerId.isNotEmpty)) {
        relationshipMismatch++;
      }

      final lines = List<dynamic>.from(detail['lines'] ?? const []);
      var lineNet = 0.0;
      var lineTax = 0.0;
      var completeMath = true;
      for (final raw in lines) {
        if (raw is! Map) continue;
        final line = Map<String, dynamic>.from(raw);
        final net = num.tryParse(line['net_amount']?.toString() ?? '');
        final tax = num.tryParse(line['tax_amount']?.toString() ?? '');
        if (net == null || tax == null) {
          completeMath = false;
          break;
        }
        lineNet += net.toDouble();
        lineTax += tax.toDouble();
      }

      if (completeMath) {
        final documentNet =
            num.tryParse(detail['net_amount']?.toString() ?? '');
        final documentTax =
            num.tryParse(detail['tax_amount']?.toString() ?? '');
        final documentTotal =
            num.tryParse(detail['total_amount']?.toString() ?? '');
        if (documentNet != null &&
            documentTax != null &&
            documentTotal != null) {
          final mismatch =
              (lineNet - documentNet.toDouble()).abs() > 0.05 ||
              (lineTax - documentTax.toDouble()).abs() > 0.05 ||
              ((lineNet + lineTax) - documentTotal.toDouble()).abs() >
                  0.05;
          if (mismatch) mathMismatch++;
        }
      }
    }

    checks.add(
      DiagnosticCheck(
        id: 'DOC-001',
        category: 'Documents',
        title: 'Active document cache coverage',
        level: missingCache == 0
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: missingCache == 0
            ? 'All ' +
                rows.length.toString() +
                ' active document(s) have offline detail caches.'
            : missingCache.toString() +
                ' active document(s) cannot be opened fully offline.',
      ),
    );

    checks.add(
      DiagnosticCheck(
        id: 'DOC-002',
        category: 'Documents',
        title: 'Document relationship consistency',
        level: relationshipMismatch == 0
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.fail,
        summary: relationshipMismatch == 0
            ? 'Cached document links agree with the local document index.'
            : relationshipMismatch.toString() +
                ' document(s) disagree with the local index on job/customer links.',
      ),
    );

    checks.add(
      DiagnosticCheck(
        id: 'DOC-003',
        category: 'Documents',
        title: 'Document math consistency',
        level: mathMismatch == 0
            ? BriskersDiagnosticLevel.pass
            : BriskersDiagnosticLevel.warning,
        summary: mathMismatch == 0
            ? 'Cached line totals agree with document totals.'
            : mathMismatch.toString() +
                ' cached document(s) have line/net/tax total differences.',
      ),
    );
  }

  // The older DOC-001 checks only open documents. That missed the actual
  // production bug: closed historical invoices appear in the list but cannot
  // be opened offline. Count every record, including closed and converted.
  // No network access or data modifications are performed here.
  Future<void> _checkExpenseLinkIntegrity(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final result = await const BriskersApi().expenseLinkIntegrity(businessId);
    int count(String key) => (result[key] as num?)?.toInt() ?? 0;
    final total = count('total');
    final missingJob = count('missing_job');
    final missingInvoice = count('missing_invoice');
    final mismatch = count('invoice_wrong_job');
    final unlinked = count('unlinked');
    final bad = missingJob + missingInvoice + mismatch;
    checks.add(DiagnosticCheck(
      id: 'EXP-001',
      category: 'Linked expenses',
      title: 'Invoice/job expense allocation integrity',
      level: bad == 0
          ? BriskersDiagnosticLevel.pass
          : BriskersDiagnosticLevel.fail,
      summary: bad == 0
          ? 'All $total expense allocations have valid linked IDs.'
          : '$bad broken expense relationships require investigation.',
      details: [
        'Missing linked jobs: $missingJob',
        'Missing linked invoices: $missingInvoice',
        'Invoice linked to another job: $mismatch',
        'Unassigned allocations: $unlinked',
        if (bad != 0) 'Affected rows: ${result['sample']}',
        'Run only online; the job screen must retrieve allocations '
            'by job ID, not by filtering a limited transaction list.',
      ],
    ));
  }

  Future<void> _checkAllDocumentDetailCoverage(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final documents = await _database.customSelect(
      '''
      SELECT id, kind, document_number, closed_at, sync_state
      FROM local_documents
      WHERE business_id = ? AND kind IN ('estimate','invoice')
      ORDER BY kind, document_number DESC
      ''',
      variables: [Variable<String>(businessId)],
    ).get();

    var cached = 0;
    var missing = 0;
    var invalid = 0;
    var closedMissing = 0;
    var invoicesMissing = 0;
    var estimatesMissing = 0;
    final examples = <String>[];

    for (final row in documents) {
      final id = row.read<String>('id');
      final kind = row.read<String>('kind');
      final number = row.readNullable<String>('document_number') ?? id;
      final snapshot = await _detailCache.load(businessId, id);
      if (snapshot == null) {
        missing++;
        if (kind == 'invoice') {
          invoicesMissing++;
        } else {
          estimatesMissing++;
        }
        if (kind == 'invoice' &&
            row.data['closed_at'] != null) {
          closedMissing++;
        }
        if (examples.length < 12) examples.add('$kind #$number');
        continue;
      }
      final lines = snapshot['lines'];
      if (snapshot['id']?.toString() != id ||
          snapshot['kind']?.toString() != kind ||
          lines is! List) {
        invalid++;
        if (examples.length < 12) examples.add('$kind #$number (invalid)');
        continue;
      }
      cached++;
    }

    final complete = missing == 0 && invalid == 0;
    final indexed = documents.length;
    checks.add(DiagnosticCheck(
      id: 'DOC-004',
      category: 'Documents',
      title: 'Full offline invoice and estimate coverage',
      level: complete
          ? BriskersDiagnosticLevel.pass
          : BriskersDiagnosticLevel.fail,
      summary: complete
          ? 'All $indexed indexed document(s) have usable local detail.'
          : '${missing + invalid} of $indexed indexed document(s) cannot '
              'be opened reliably offline.',
      details: [
        'Cached and valid: $cached / $indexed',
        'Missing detail: $missing (invoices: $invoicesMissing; '
            'estimates: $estimatesMissing)',
        'Closed invoices missing detail: $closedMissing',
        'Invalid/incomplete detail: $invalid',
        if (examples.isNotEmpty)
          'Examples: ${examples.join(', ')}',
        if (!complete)
          'Offline document index sync is not sufficient. '
              'Full invoice/estimate detail download must finish '
              'before offline coverage is reported complete.',
      ],
    ));
  }

  Future<void> _checkPhotos(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT 'preinspection' AS source, id, local_file_path,
             upload_state, last_error
      FROM local_pre_inspection_photos
      WHERE business_id = ? AND upload_state <> 'synced'
      UNION ALL
      SELECT 'finding' AS source, id, local_file_path,
             upload_state, last_error
      FROM local_finding_photos
      WHERE business_id = ? AND upload_state <> 'synced'
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(businessId),
      ],
    ).get();

    var missingFiles = 0;
    var withErrors = 0;
    for (final row in rows) {
      final path = row.readNullable<String>('local_file_path') ?? '';
      if (path.isEmpty || !File(path).existsSync()) {
        missingFiles++;
      }
      if ((row.readNullable<String>('last_error') ?? '').trim().isNotEmpty) {
        withErrors++;
      }
    }

    final level = missingFiles > 0
        ? BriskersDiagnosticLevel.fail
        : (withErrors > 0
            ? BriskersDiagnosticLevel.warning
            : BriskersDiagnosticLevel.pass);
    checks.add(
      DiagnosticCheck(
        id: 'PHOTO-001',
        category: 'Photos',
        title: 'Preinspection and finding photo uploads',
        level: level,
        summary: rows.isEmpty
            ? 'No preinspection or finding photos are waiting to upload.'
            : rows.length.toString() + ' photo(s) are waiting to upload.',
        details: [
          if (missingFiles > 0)
            missingFiles.toString() +
                ' pending photo(s) are missing their local file.',
          if (withErrors > 0)
            withErrors.toString() +
                ' pending photo(s) have a recorded upload error.',
        ],
      ),
    );
  }

  Future<void> _checkLocalIdRemapping(
    String businessId,
    List<DiagnosticCheck> checks,
  ) async {
    final problems = <String, int>{
      'Jobs': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_jobs
        WHERE business_id = ?
          AND sync_state = 'synced'
          AND id LIKE 'local-%'
        ''',
        [Variable<String>(businessId)],
      ),
      'Appointments': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_appointments
        WHERE business_id = ?
          AND sync_state = 'synced'
          AND id LIKE 'local-%'
        ''',
        [Variable<String>(businessId)],
      ),
      'Documents': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_documents
        WHERE business_id = ?
          AND sync_state = 'synced'
          AND id LIKE 'local-%'
        ''',
        [Variable<String>(businessId)],
      ),
      'Catalog items': await _count(
        '''
        SELECT COUNT(*) AS count
        FROM local_catalog_items
        WHERE business_id = ?
          AND sync_state = 'synced'
          AND id LIKE 'local-%'
        ''',
        [Variable<String>(businessId)],
      ),
    };

    final total = problems.values.fold<int>(0, (sum, value) => sum + value);
    checks.add(
      DiagnosticCheck(
        id: 'ID-001',
        category: 'Local IDs',
        title: 'Server ID remapping',
        level: total == 0 ? BriskersDiagnosticLevel.pass : BriskersDiagnosticLevel.fail,
        summary: total == 0
            ? 'No synced records are stranded with temporary local IDs.'
            : total.toString() +
                ' synced record(s) still use a temporary local ID.',
        details: problems.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key + ': ' + entry.value.toString())
            .toList(),
      ),
    );
  }
}
