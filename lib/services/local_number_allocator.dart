import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';

/// Device-local numbering. Call from the same transaction as record creation or
/// deletion. A released old number is available only by explicit assignment.
class LocalNumberAllocator {
  LocalNumberAllocator(this.db);
  final BriskersLocalDatabase db;

  Future<void> ensureSchema() async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS local_number_counters '
      '(business_id TEXT NOT NULL, kind TEXT NOT NULL, next_number INTEGER NOT NULL, '
      'PRIMARY KEY(business_id,kind))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS local_number_reservations '
      '(business_id TEXT NOT NULL, kind TEXT NOT NULL, number INTEGER NOT NULL, '
      'entity_id TEXT NOT NULL, active INTEGER NOT NULL, '
      'PRIMARY KEY(business_id,kind,number))');
  }

  (String, String, String) _table(String kind) => switch(kind) {
    'invoice' => ('local_documents','document_number'," AND kind='invoice'"),
    'job' => ('local_jobs','job_number',''),
    _ => throw ArgumentError('Unsupported number kind'),
  };
  int? _parse(Object? raw, String kind) {
    var value = raw?.toString().trim() ?? '';
    if (kind == 'job') {
      value = value.toUpperCase().replaceFirst(RegExp(r'^J-?'), '');
    } else if (kind == 'invoice') {
      value = value.toUpperCase().replaceFirst(RegExp(r'^(?:I-|MB-)'), '');
    }
    return RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
  }
  String display(String kind, int number) => kind == 'job' ? 'J-$number' : '$number';

  Future<Map<int,Set<String>>> _used(String business, String kind) async {
    final (table,column,predicate)=_table(kind);
    final rows=await db.customSelect('SELECT id,$column AS number FROM $table '
      'WHERE business_id=?$predicate', variables:[Variable<String>(business)]).get();
    final used=<int,Set<String>>{};
    for(final row in rows) {
      final number=_parse(row.data['number'],kind);
      if(number!=null) (used[number] ??= <String>{}).add(row.read<String>('id'));
    }
    return used;
  }
  Future<int> _next(String business,String kind) async {
    final rows=await db.customSelect('SELECT next_number FROM local_number_counters '
      'WHERE business_id=? AND kind=?',variables:[Variable<String>(business),Variable<String>(kind)]).get();
    if(rows.isNotEmpty) return rows.single.read<int>('next_number');
    final used=await _used(business,kind);
    var next=1;
    for(final number in used.keys) { if(number>=next) next=number+1; }
    await db.customStatement('INSERT INTO local_number_counters VALUES (?,?,?)',[business,kind,next]);
    return next;
  }
  /// Only explicit releases are offered; a gap alone is never evidence.
  Future<List<int>> availableNumbers(String business, String kind) async {
    await ensureSchema();
    final used = await _used(business, kind);
    final rows = await db.customSelect(
      'SELECT number FROM local_number_reservations '
      'WHERE business_id=? AND kind=? AND active=0 ORDER BY number',
      variables: [Variable<String>(business), Variable<String>(kind)],
    ).get();
    return [
      for (final row in rows)
        if (row.read<int>('number') > 0 &&
            row.read<int>('number') <= 999999999 &&
            !used.containsKey(row.read<int>('number')))
          row.read<int>('number'),
    ];
  }

  Future<int> nextNumber(String business,String kind) async => db.transaction(() async {
    await ensureSchema();
    var value=await _next(business,kind);
    while(await _occupied(business,kind,value,'')) { value++; }
    return value;
  });
  Future<void> setNextNumber(String business,String kind,int value) async {
    if(value<1 || value>999999999) throw StateError('Enter a number from 1 to 999,999,999.');
    await db.transaction(() async {
      await ensureSchema();
      _table(kind);
      await db.customStatement('INSERT INTO local_number_counters VALUES (?,?,?) '
        'ON CONFLICT(business_id,kind) DO UPDATE SET next_number=excluded.next_number',[business,kind,value]);
    });
  }
  Future<bool> _occupied(String business,String kind,int number,String entity) async {
    final used=await _used(business,kind);
    if(used[number]?.any((id)=>id!=entity) == true) return true;
    final rows=await db.customSelect('SELECT entity_id FROM local_number_reservations '
      'WHERE business_id=? AND kind=? AND number=? AND active=1',variables:[
        Variable<String>(business),Variable<String>(kind),Variable<int>(number)]).get();
    return rows.any((r)=>r.read<String>('entity_id')!=entity);
  }
  Future<int> allocate(String business,String kind,String entity,{int? requested}) async {
    return db.transaction(() async {
      await ensureSchema();
      var next=await _next(business,kind);
      var number=requested ?? next;
      if(number<1 || number>999999999) throw StateError('Enter a number from 1 to 999,999,999.');
      if(requested!=null && await _occupied(business,kind,number,entity)) {
        throw StateError('That number is already used by another $kind.');
      }
      while(await _occupied(business,kind,number,entity)) { number++; }
      if(number>999999999) throw StateError('No invoice numbers remain in the supported range.');
      await db.customStatement('INSERT INTO local_number_reservations '
        '(business_id,kind,number,entity_id,active) VALUES (?,?,?,?,1) '
        'ON CONFLICT(business_id,kind,number) DO UPDATE SET entity_id=excluded.entity_id,active=1',
        [business,kind,number,entity]);
      if(number>=next) {
        next=number+1;
        await db.customStatement('UPDATE local_number_counters SET next_number=? WHERE business_id=? AND kind=?',
          [next,business,kind]);
      }
      return number;
    });
  }
  /// Release the removed record's number, including pre-upgrade records. Only
  /// a free suffix at the current next number moves the automatic counter back.
  Future<void> release(String business,String kind,String entity,{Object? previousNumber}) async {
    await ensureSchema();
    final existing=await _used(business,kind);
    var prior=_parse(previousNumber,kind);
    for(final entry in existing.entries) { if(entry.value.contains(entity)) { prior ??= entry.key; } }
    if(prior!=null && !await _occupied(business,kind,prior,entity)) {
      await db.customStatement('INSERT INTO local_number_reservations '
        '(business_id,kind,number,entity_id,active) VALUES (?,?,?,?,1) '
        'ON CONFLICT(business_id,kind,number) DO UPDATE SET entity_id=excluded.entity_id,active=1',[business,kind,prior,entity]);
    }
    final rows=await db.customSelect('SELECT number FROM local_number_reservations '
      'WHERE business_id=? AND kind=? AND entity_id=? AND active=1',variables:[
        Variable<String>(business),Variable<String>(kind),Variable<String>(entity)]).get();
    var next=await _next(business,kind);
    for(final row in rows) {
      final number=row.read<int>('number');
      await db.customStatement('UPDATE local_number_reservations SET active=0 '
        'WHERE business_id=? AND kind=? AND number=?',[business,kind,number]);
      if(number==next-1) next=number;
    }
    final used=await _used(business,kind);
    while(next>1) {
      final candidate=next-1;
      if(used[candidate]?.any((id)=>id!=entity)==true) break;
      final released=await db.customSelect('SELECT active FROM local_number_reservations '
        'WHERE business_id=? AND kind=? AND number=?',variables:[
          Variable<String>(business),Variable<String>(kind),Variable<int>(candidate)]).get();
      if(released.isEmpty || released.single.read<int>('active')!=0) break;
      next=candidate;
    }
    await db.customStatement('UPDATE local_number_counters SET next_number=? WHERE business_id=? AND kind=?',
      [next,business,kind]);
  }
}
