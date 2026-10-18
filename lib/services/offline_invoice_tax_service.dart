import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'invoice_tax_proposal.dart';
import 'local_document_detail_cache.dart';
import 'local_job_quarantine.dart';

/// A durable offline proposal, NOT an accepted server invoice adjustment.
/// Its outbox identity survives restarts and ambiguous server replies. No
/// payment is created, modified, deleted or finalized by this service.
class OfflineInvoiceTaxService {
  // Auto bootstrap and the manual Settings sync share a single replay per
  // local database and shop. One tax proposal may never be sent twice.
  static final Expando<Map<String, Future<void>>> _activeFlushes = Expando();
  OfflineInvoiceTaxService({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    LocalDocumentDetailCache? cache,
    bool Function()? canSend,
  })  : _api = api,
        _db = database ?? localDatabase,
        _cache = cache ?? LocalDocumentDetailCache(database: database),
        _canSend = canSend ??
            (() => !BriskersConnectionModeController.instance.forceOffline);

  final BriskersApi _api;
  final BriskersLocalDatabase _db;
  final LocalDocumentDetailCache _cache;
  final bool Function() _canSend;

  static const entityType = 'invoice_tax_edit';
  static const operation = 'change_tax_rate';

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  num _value(Object? raw) =>
      num.tryParse(raw?.toString() ?? '') ?? double.nan;
  int _cents(num n) => (n * 100).round();
  double _money(int cents) => cents / 100;

  List<Map<String, dynamic>> _lines(Map<String, dynamic> detail) =>
      List<dynamic>.from(detail['lines'] ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();

  List<Map<String, dynamic>> _fingerprint(List<Map<String, dynamic>> lines) =>
      lines.map((line) => <String, dynamic>{
        'id': line['id']?.toString(),
        'kind': line['line_kind']?.toString(),
        'quantity': line['quantity'],
        'unit_price': line['unit_price'],
        'tax_rate': line['tax_rate'],
      }).toList();

  bool _sameLines(
    List<Map<String, dynamic>> actual,
    List<dynamic> expected, {
    required bool compareRates,
  }) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      final line = actual[i];
      final reference = Map<String, dynamic>.from(expected[i] as Map);
      if (line['id']?.toString() != reference['id']?.toString() ||
          line['line_kind']?.toString() != reference['kind']?.toString()) {
        return false;
      }
      for (final key in const ['quantity', 'unit_price']) {
        final a = _value(line[key]);
        final b = _value(reference[key]);
        if (!a.isFinite || !b.isFinite || (a - b).abs() > 0.0000001) {
          return false;
        }
      }
      if (compareRates) {
        final a = _value(line['tax_rate']);
        final b = _value(reference['tax_rate']);
        if (!a.isFinite || !b.isFinite || (a - b).abs() > 0.0000001) {
          return false;
        }
      }
    }
    return true;
  }

  Map<String, dynamic> _proposal(
    Map<String, dynamic> detail, {
    required num oldRate,
    required num newRate,
    required int expectedVersion,
  }) {
    if (detail['kind'] != 'invoice' ||
        detail['origin'] != 'native' ||
        detail['legacy_read_only'] == true ||
        detail['closed_at'] != null ||
        const ['closed', 'void', 'paid'].contains(detail['status']?.toString())) {
      throw StateError('Historical, closed or finalized invoices cannot have tax changed offline.');
    }
    if (expectedVersion <= 0 ||
        int.tryParse(detail['row_version']?.toString() ?? '') != expectedVersion) {
      throw StateError('Invoice version changed. Reload before changing tax.');
    }
    if (!oldRate.isFinite || !newRate.isFinite ||
        oldRate <= 0 || oldRate > 1 || newRate <= 0 || newRate > 1 ||
        (oldRate - newRate).abs() < 0.0000001) {
      throw StateError('Enter a different, valid sales tax percentage.');
    }
    final finalized = _value(detail['paid_amount'] ?? 0);
    if (!finalized.isFinite || finalized > 0.005) {
      throw StateError('This invoice has posted payments and cannot be repriced offline.');
    }
    final lines = _lines(detail);
    if (lines.isEmpty || lines.any((line) =>
        line['line_kind'] == 'discount' ||
        line['id']?.toString().isNotEmpty != true ||
        _value(line['tax_rate']) < 0 ||
        _value(line['tax_rate']) > 1)) {
      throw StateError('Tax lines are incomplete or discounted; review online.');
    }
    final positive = lines
        .where((line) => _value(line['tax_rate']) > 0).toList();
    if (positive.isEmpty ||
        positive.any((line) =>
            (_value(line['tax_rate']) - oldRate).abs() > 0.0000001)) {
      throw StateError('Mixed or unknown positive tax rates require review.');
    }
    final classified = lines.map((line) => <String, dynamic>{
      ...line,
      'tax_mode': _value(line['tax_rate']) == 0 ? 'exempt' : 'default',
    }).toList();
    final result = InvoiceTaxProposal.preview(lines: classified, rate: newRate);
    final currentTax = _value(detail['tax_amount']);
    final currentTotal = _value(detail['total_amount']);
    if (!currentTax.isFinite || !currentTotal.isFinite ||
        (_cents(currentTax) - _cents(_value(result['old_tax']))).abs() > 1) {
      throw StateError('Cached invoice tax disagrees with its line items.');
    }
    final newTotal = _value(result['new_total']);
    final pendingPaid = _value(detail['pending_payment'] ?? 0);
    if (!pendingPaid.isFinite || pendingPaid > newTotal + 0.005) {
      throw StateError('The corrected total would be below recorded pending payments.');
    }
    return result;
  }

  Map<String, dynamic> _project(
    Map<String, dynamic> base, Map<String, dynamic> payload,
    int outboxId, String state,
  ) {
    final oldRate = _value(payload['old_rate']);
    final newRate = _value(payload['new_rate']);
    final lines = _lines(base);
    if (!_sameLines(lines, List<dynamic>.from(payload['lines'] as List),
        compareRates: true)) {
      throw StateError('Cached invoice lines changed while tax correction was queued.');
    }
    final updatedLines = lines.map((line) {
      if (_value(line['tax_rate']) <= 0) return line;
      final amount = _cents(_value(line['quantity']) * _value(line['unit_price']));
      final tax = _cents(_money(amount) * newRate);
      return <String, dynamic>{
        ...line,
        'tax_rate': newRate,
        'tax_amount': _money(tax),
        'net_amount': _money(amount),
        'total_amount': _money(amount + tax),
      };
    }).toList();
    return <String, dynamic>{
      ...base,
      'lines': updatedLines,
      'tax_amount': payload['new_tax'],
      'total_amount': payload['new_total'],
      'sync_state': 'pending',
      '_local_pending_tax': true,
      '_local_tax_original_rate': oldRate,
      '_local_tax_desired_rate': newRate,
      '_local_tax_operation_id': outboxId,
      '_local_tax_sync_state': state,
      // Existing payment and pending-receipt fields are deliberately untouched.
    };
  }

  Future<List<QueryRow>> _queued(String businessId, String invoiceId) =>
      _db.customSelect(
        "SELECT * FROM sync_outbox WHERE business_id=? AND entity_id=? "
        "AND entity_type=? AND state IN ('pending','inflight','conflict') "
        "ORDER BY id",
        variables: [
          Variable<String>(businessId),
          Variable<String>(invoiceId),
          const Variable<String>(entityType),
        ],
      ).get();

  /// Reconstruct the displayed correction from SQLite after a device restart,
  /// even if SharedPreferences was interrupted before caching the projection.
  Future<Map<String, dynamic>> projectPending(
    String businessId, String invoiceId,
    Map<String, dynamic> snapshot,
  ) async {
    final queued = await _queued(businessId, invoiceId);
    if (queued.isEmpty) return snapshot;
    if (queued.length != 1) {
      throw StateError('Multiple pending invoice tax corrections need review.');
    }
    final row = queued.single;
    final payload = Map<String, dynamic>.from(
        jsonDecode(row.read<String>('payload_json')) as Map);
    if (snapshot['_local_pending_tax'] == true &&
        snapshot['_local_tax_operation_id'] == row.read<int>('id')) {
      return <String, dynamic>{
        ...snapshot,
        '_local_tax_sync_state': row.read<String>('state'),
      };
    }
    final version = int.tryParse(snapshot['row_version']?.toString() ?? '');
    if (version != payload['expected_version'] ||
        (_value(snapshot['total_amount']) - _value(payload['old_total'])).abs() > 0.011) {
      return <String, dynamic>{
        ...snapshot,
        '_local_tax_sync_state': 'conflict',
      };
    }
    return _project(snapshot, payload, row.read<int>('id'), row.read<String>('state'));
  }

  /// SQLite outbox and the document index are committed together. The local
  /// detail cache is a replaceable projection, never the authority for replay.
  Future<Map<String, dynamic>> saveOffline(
    String businessId, String invoiceId, {
    required int expectedVersion,
    required num oldRate,
    required num newRate,
  }) async {
    if (invoiceId.isEmpty || invoiceId.startsWith('local-')) {
      throw StateError('Save a numbered invoice before correcting tax.');
    }
    final base = await _cache.load(businessId, invoiceId);
    if (base == null) {
      throw StateError('Open this invoice once while online to cache it.');
    }

    final queued = await _queued(businessId, invoiceId);
    if (queued.isNotEmpty) {
      if (queued.length != 1) {
        throw StateError('Multiple tax corrections already require review.');
      }
      final payload = Map<String, dynamic>.from(
        jsonDecode(queued.single.read<String>('payload_json')) as Map);
      if ((_value(payload['new_rate']) - newRate).abs() < 0.0000001) {
        return projectPending(businessId, invoiceId, base);
      }
      throw StateError('A different tax correction is already queued. Do not overwrite it.');
    }

    final editingRows = await _db.customSelect(
      "SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? "
      "AND entity_type='document_edit' AND state<>'done' LIMIT 1",
      variables: [Variable<String>(businessId), Variable<String>(invoiceId)],
    ).get();
    if (editingRows.isNotEmpty) {
      throw StateError('Sync or reconcile other invoice edits before changing its tax.');
    }

    final preview = _proposal(base, oldRate: oldRate, newRate: newRate,
        expectedVersion: expectedVersion);
    final payload = <String, dynamic>{
      'expected_version': expectedVersion,
      'old_rate': oldRate,
      'new_rate': newRate,
      'old_total': base['total_amount'],
      'new_total': preview['new_total'],
      'new_tax': preview['new_tax'],
      'lines': _fingerprint(_lines(base)),
    };
    late int outboxId;
    await _db.transaction(() async {
      await LocalJobQuarantine.assertReplayAllowed(_db, businessId);
      final prior = await _queued(businessId, invoiceId);
      if (prior.isNotEmpty) {
        throw StateError('Another tax correction was queued while this editor was open.');
      }
      final row = await _db.customSelect(
        'SELECT row_version,kind,sync_state FROM local_documents '
        'WHERE business_id=? AND id=? LIMIT 1',
        variables: [Variable<String>(businessId), Variable<String>(invoiceId)],
      ).getSingleOrNull();
      if (row == null || row.read<String>('kind') != 'invoice' ||
          row.readNullable<int>('row_version') != expectedVersion ||
          row.read<String>('sync_state') != 'synced') {
        throw StateError('Invoice index is not synchronized; correction was not saved.');
      }
      await _db.customStatement(
        "INSERT INTO sync_outbox(business_id,entity_type,entity_id,"
        "operation,payload_json,state,attempt_count,created_at) "
        "VALUES (?, ?, ?, ?, ?, 'pending', 0, ?)",
        [businessId, entityType, invoiceId, operation, jsonEncode(payload), _now],
      );
      final saved = await _queued(businessId, invoiceId);
      if (saved.length != 1) {
        throw StateError('Could not verify durable invoice tax operation.');
      }
      outboxId = saved.single.read<int>('id');
      await _db.customStatement(
        "UPDATE local_documents SET total=?,sync_state='pending' "
        "WHERE business_id=? AND id=?",
        [preview['new_total'], businessId, invoiceId],
      );
    });

    final projected = _project(base, payload, outboxId, 'pending');
    try {
      await _cache.save(businessId, invoiceId, projected);
    } catch (_) {
      // Queue and index already committed. projectPending reconstructs the
      // local change from SQLite; never remove the saved intent here.
    }
    return projected;
  }

  Future<void> flush(String businessId) {
    if (!_canSend()) return Future<void>.value();
    final active = _activeFlushes[_db] ??= <String, Future<void>>{};
    final existing = active[businessId];
    if (existing != null) return existing;
    final work = _flushInternal(businessId);
    active[businessId] = work;
    return work.whenComplete(() {
      if (identical(active[businessId], work)) active.remove(businessId);
    });
  }

  Future<void> _flushInternal(String businessId) async {
    final queued = await _db.customSelect(
      "SELECT * FROM sync_outbox WHERE business_id=? AND entity_type=? "
      "AND state='pending' ORDER BY id",
      variables: [
        Variable<String>(businessId),
        const Variable<String>(entityType),
      ],
    ).get();

    for (final row in queued) {
      if (!_canSend()) return;
      final id = row.read<int>('id');
      final invoiceId = row.read<String>('entity_id');
      final payload = Map<String, dynamic>.from(
          jsonDecode(row.read<String>('payload_json')) as Map);
      final expected = (payload['expected_version'] as num).toInt();
      final oldRate = _value(payload['old_rate']);
      final newRate = _value(payload['new_rate']);
      final actual = await _api.documentDetail(businessId, invoiceId);
      if (int.tryParse(actual['row_version']?.toString() ?? '') != expected ||
          (_value(actual['total_amount']) -
              _value(payload['old_total'])).abs() > 0.011 ||
          !_sameLines(_lines(actual), List<dynamic>.from(payload['lines'] as List),
              compareRates: true)) {
        await _db.customStatement(
          "UPDATE sync_outbox SET state='conflict',last_error=? WHERE id=?",
          ['Server invoice changed. Tax correction needs owner review.', id],
        );
        continue;
      }
      try {
        // Recheck every server-side guard locally before attempting RPC.
        final proposed = _proposal(actual, oldRate: oldRate, newRate: newRate,
            expectedVersion: expected);
        if ((_value(proposed['new_total']) -
                _value(payload['new_total'])).abs() > 0.011) {
          throw StateError('Invoice tax calculation changed; review required.');
        }
        await LocalJobQuarantine.assertReplayAllowed(
            _db, businessId, outboxId: id);
        // Durably claim the send BEFORE the network request. If a response is
        // lost, never automatically issue this non-idempotent RPC twice.
        final claimed = await _db.customUpdate(
          "UPDATE sync_outbox SET state='inflight',"
          "attempt_count=attempt_count+1,last_attempt_at=? WHERE id=? "
          "AND state='pending'",
          variables: [Variable<int>(_now), Variable<int>(id)],
        );
        // A second trigger cannot claim a row already in-flight.
        if (claimed != 1) continue;
        if (!_canSend()) {
          // Mode changed before any RPC was called. No request was sent;
          // release the send fence so the original intent may retry later.
          await _db.customStatement(
            "UPDATE sync_outbox SET state='pending' WHERE id=? "
            "AND state='inflight'",
            [id],
          );
          return;
        }
        await LocalJobQuarantine.guardReplay(
          _db, businessId,
          () => _api.updateInvoiceTaxRate(
            businessId, invoiceId, expectedVersion: expected,
            oldRate: oldRate, newRate: newRate,
          ),
          outboxId: id,
        );
        final after = await _api.documentDetail(businessId, invoiceId);
        if ((int.tryParse(after['row_version']?.toString() ?? '') ?? 0) <= expected ||
            (_value(after['total_amount']) -
                _value(payload['new_total'])).abs() > 0.011 ||
            !_sameLines(_lines(after), List<dynamic>.from(payload['lines'] as List),
                compareRates: false) ||
            _lines(after).any((line) {
              final rate = _value(line['tax_rate']);
              return rate > 0 && (rate - newRate).abs() > 0.0000001;
            })) {
          throw StateError('Remote tax acknowledgement needs reconciliation.');
        }
        // Keep the durable outbox until the reconciled server detail is
        // written locally. A crash leaves an inflight fence, not a duplicate.
        await _cache.save(businessId, invoiceId, after);
        await _db.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
              _db, businessId, outboxId: id);
          await _db.customStatement(
            'UPDATE local_documents SET total=?,row_version=?,'
            "sync_state='synced' WHERE business_id=? AND id=?",
            [after['total_amount'], after['row_version'], businessId, invoiceId],
          );
          await _db.customStatement('DELETE FROM sync_outbox WHERE id=?', [id]);
        });
      } catch (error) {
        await _db.customStatement(
          'UPDATE sync_outbox SET last_error=? WHERE id=?',
          ['Tax correction outcome uncertain; review before any retry: $error', id],
        );
        rethrow;
      }
    }
  }
}
