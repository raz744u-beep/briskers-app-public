// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'briskers_local_database.dart';

// ignore_for_file: type=lint
class $LocalSyncStatesTable extends LocalSyncStates
    with TableInfo<$LocalSyncStatesTable, LocalSyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastServerCursorMeta = const VerificationMeta(
    'lastServerCursor',
  );
  @override
  late final GeneratedColumn<int> lastServerCursor = GeneratedColumn<int>(
    'last_server_cursor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPullAtMeta = const VerificationMeta(
    'lastPullAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPullAt = GeneratedColumn<DateTime>(
    'last_pull_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPushAtMeta = const VerificationMeta(
    'lastPushAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPushAt = GeneratedColumn<DateTime>(
    'last_push_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bootstrappedMeta = const VerificationMeta(
    'bootstrapped',
  );
  @override
  late final GeneratedColumn<bool> bootstrapped = GeneratedColumn<bool>(
    'bootstrapped',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bootstrapped" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    scope,
    lastServerCursor,
    lastPullAt,
    lastPushAt,
    lastError,
    bootstrapped,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('last_server_cursor')) {
      context.handle(
        _lastServerCursorMeta,
        lastServerCursor.isAcceptableOrUnknown(
          data['last_server_cursor']!,
          _lastServerCursorMeta,
        ),
      );
    }
    if (data.containsKey('last_pull_at')) {
      context.handle(
        _lastPullAtMeta,
        lastPullAt.isAcceptableOrUnknown(
          data['last_pull_at']!,
          _lastPullAtMeta,
        ),
      );
    }
    if (data.containsKey('last_push_at')) {
      context.handle(
        _lastPushAtMeta,
        lastPushAt.isAcceptableOrUnknown(
          data['last_push_at']!,
          _lastPushAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('bootstrapped')) {
      context.handle(
        _bootstrappedMeta,
        bootstrapped.isAcceptableOrUnknown(
          data['bootstrapped']!,
          _bootstrappedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, scope};
  @override
  LocalSyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncState(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      lastServerCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_server_cursor'],
      ),
      lastPullAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pull_at'],
      ),
      lastPushAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_push_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      bootstrapped: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bootstrapped'],
      )!,
    );
  }

  @override
  $LocalSyncStatesTable createAlias(String alias) {
    return $LocalSyncStatesTable(attachedDatabase, alias);
  }
}

class LocalSyncState extends DataClass implements Insertable<LocalSyncState> {
  final String businessId;
  final String scope;
  final int? lastServerCursor;
  final DateTime? lastPullAt;
  final DateTime? lastPushAt;
  final String? lastError;
  final bool bootstrapped;
  const LocalSyncState({
    required this.businessId,
    required this.scope,
    this.lastServerCursor,
    this.lastPullAt,
    this.lastPushAt,
    this.lastError,
    required this.bootstrapped,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['scope'] = Variable<String>(scope);
    if (!nullToAbsent || lastServerCursor != null) {
      map['last_server_cursor'] = Variable<int>(lastServerCursor);
    }
    if (!nullToAbsent || lastPullAt != null) {
      map['last_pull_at'] = Variable<DateTime>(lastPullAt);
    }
    if (!nullToAbsent || lastPushAt != null) {
      map['last_push_at'] = Variable<DateTime>(lastPushAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['bootstrapped'] = Variable<bool>(bootstrapped);
    return map;
  }

  LocalSyncStatesCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncStatesCompanion(
      businessId: Value(businessId),
      scope: Value(scope),
      lastServerCursor: lastServerCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServerCursor),
      lastPullAt: lastPullAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPullAt),
      lastPushAt: lastPushAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPushAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      bootstrapped: Value(bootstrapped),
    );
  }

  factory LocalSyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncState(
      businessId: serializer.fromJson<String>(json['businessId']),
      scope: serializer.fromJson<String>(json['scope']),
      lastServerCursor: serializer.fromJson<int?>(json['lastServerCursor']),
      lastPullAt: serializer.fromJson<DateTime?>(json['lastPullAt']),
      lastPushAt: serializer.fromJson<DateTime?>(json['lastPushAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      bootstrapped: serializer.fromJson<bool>(json['bootstrapped']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'scope': serializer.toJson<String>(scope),
      'lastServerCursor': serializer.toJson<int?>(lastServerCursor),
      'lastPullAt': serializer.toJson<DateTime?>(lastPullAt),
      'lastPushAt': serializer.toJson<DateTime?>(lastPushAt),
      'lastError': serializer.toJson<String?>(lastError),
      'bootstrapped': serializer.toJson<bool>(bootstrapped),
    };
  }

  LocalSyncState copyWith({
    String? businessId,
    String? scope,
    Value<int?> lastServerCursor = const Value.absent(),
    Value<DateTime?> lastPullAt = const Value.absent(),
    Value<DateTime?> lastPushAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    bool? bootstrapped,
  }) => LocalSyncState(
    businessId: businessId ?? this.businessId,
    scope: scope ?? this.scope,
    lastServerCursor: lastServerCursor.present
        ? lastServerCursor.value
        : this.lastServerCursor,
    lastPullAt: lastPullAt.present ? lastPullAt.value : this.lastPullAt,
    lastPushAt: lastPushAt.present ? lastPushAt.value : this.lastPushAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    bootstrapped: bootstrapped ?? this.bootstrapped,
  );
  LocalSyncState copyWithCompanion(LocalSyncStatesCompanion data) {
    return LocalSyncState(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      scope: data.scope.present ? data.scope.value : this.scope,
      lastServerCursor: data.lastServerCursor.present
          ? data.lastServerCursor.value
          : this.lastServerCursor,
      lastPullAt: data.lastPullAt.present
          ? data.lastPullAt.value
          : this.lastPullAt,
      lastPushAt: data.lastPushAt.present
          ? data.lastPushAt.value
          : this.lastPushAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      bootstrapped: data.bootstrapped.present
          ? data.bootstrapped.value
          : this.bootstrapped,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncState(')
          ..write('businessId: $businessId, ')
          ..write('scope: $scope, ')
          ..write('lastServerCursor: $lastServerCursor, ')
          ..write('lastPullAt: $lastPullAt, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastError: $lastError, ')
          ..write('bootstrapped: $bootstrapped')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    businessId,
    scope,
    lastServerCursor,
    lastPullAt,
    lastPushAt,
    lastError,
    bootstrapped,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncState &&
          other.businessId == this.businessId &&
          other.scope == this.scope &&
          other.lastServerCursor == this.lastServerCursor &&
          other.lastPullAt == this.lastPullAt &&
          other.lastPushAt == this.lastPushAt &&
          other.lastError == this.lastError &&
          other.bootstrapped == this.bootstrapped);
}

class LocalSyncStatesCompanion extends UpdateCompanion<LocalSyncState> {
  final Value<String> businessId;
  final Value<String> scope;
  final Value<int?> lastServerCursor;
  final Value<DateTime?> lastPullAt;
  final Value<DateTime?> lastPushAt;
  final Value<String?> lastError;
  final Value<bool> bootstrapped;
  final Value<int> rowid;
  const LocalSyncStatesCompanion({
    this.businessId = const Value.absent(),
    this.scope = const Value.absent(),
    this.lastServerCursor = const Value.absent(),
    this.lastPullAt = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.bootstrapped = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncStatesCompanion.insert({
    required String businessId,
    required String scope,
    this.lastServerCursor = const Value.absent(),
    this.lastPullAt = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.bootstrapped = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       scope = Value(scope);
  static Insertable<LocalSyncState> custom({
    Expression<String>? businessId,
    Expression<String>? scope,
    Expression<int>? lastServerCursor,
    Expression<DateTime>? lastPullAt,
    Expression<DateTime>? lastPushAt,
    Expression<String>? lastError,
    Expression<bool>? bootstrapped,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (scope != null) 'scope': scope,
      if (lastServerCursor != null) 'last_server_cursor': lastServerCursor,
      if (lastPullAt != null) 'last_pull_at': lastPullAt,
      if (lastPushAt != null) 'last_push_at': lastPushAt,
      if (lastError != null) 'last_error': lastError,
      if (bootstrapped != null) 'bootstrapped': bootstrapped,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncStatesCompanion copyWith({
    Value<String>? businessId,
    Value<String>? scope,
    Value<int?>? lastServerCursor,
    Value<DateTime?>? lastPullAt,
    Value<DateTime?>? lastPushAt,
    Value<String?>? lastError,
    Value<bool>? bootstrapped,
    Value<int>? rowid,
  }) {
    return LocalSyncStatesCompanion(
      businessId: businessId ?? this.businessId,
      scope: scope ?? this.scope,
      lastServerCursor: lastServerCursor ?? this.lastServerCursor,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastError: lastError ?? this.lastError,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (lastServerCursor.present) {
      map['last_server_cursor'] = Variable<int>(lastServerCursor.value);
    }
    if (lastPullAt.present) {
      map['last_pull_at'] = Variable<DateTime>(lastPullAt.value);
    }
    if (lastPushAt.present) {
      map['last_push_at'] = Variable<DateTime>(lastPushAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (bootstrapped.present) {
      map['bootstrapped'] = Variable<bool>(bootstrapped.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncStatesCompanion(')
          ..write('businessId: $businessId, ')
          ..write('scope: $scope, ')
          ..write('lastServerCursor: $lastServerCursor, ')
          ..write('lastPullAt: $lastPullAt, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastError: $lastError, ')
          ..write('bootstrapped: $bootstrapped, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRowVersionMeta = const VerificationMeta(
    'baseRowVersion',
  );
  @override
  late final GeneratedColumn<int> baseRowVersion = GeneratedColumn<int>(
    'base_row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    entityType,
    entityId,
    operation,
    payloadJson,
    baseRowVersion,
    state,
    attemptCount,
    createdAt,
    lastAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('base_row_version')) {
      context.handle(
        _baseRowVersionMeta,
        baseRowVersion.isAcceptableOrUnknown(
          data['base_row_version']!,
          _baseRowVersionMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      baseRowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_row_version'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  final int id;
  final String businessId;
  final String entityType;
  final String entityId;
  final String operation;
  final String payloadJson;
  final int? baseRowVersion;
  final String state;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  const SyncOutboxData({
    required this.id,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    this.baseRowVersion,
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    this.lastAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['business_id'] = Variable<String>(businessId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || baseRowVersion != null) {
      map['base_row_version'] = Variable<int>(baseRowVersion);
    }
    map['state'] = Variable<String>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      businessId: Value(businessId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payloadJson: Value(payloadJson),
      baseRowVersion: baseRowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRowVersion),
      state: Value(state),
      attemptCount: Value(attemptCount),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      id: serializer.fromJson<int>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      baseRowVersion: serializer.fromJson<int?>(json['baseRowVersion']),
      state: serializer.fromJson<String>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'businessId': serializer.toJson<String>(businessId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'baseRowVersion': serializer.toJson<int?>(baseRowVersion),
      'state': serializer.toJson<String>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncOutboxData copyWith({
    int? id,
    String? businessId,
    String? entityType,
    String? entityId,
    String? operation,
    String? payloadJson,
    Value<int?> baseRowVersion = const Value.absent(),
    String? state,
    int? attemptCount,
    DateTime? createdAt,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => SyncOutboxData(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payloadJson: payloadJson ?? this.payloadJson,
    baseRowVersion: baseRowVersion.present
        ? baseRowVersion.value
        : this.baseRowVersion,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      baseRowVersion: data.baseRowVersion.present
          ? data.baseRowVersion.value
          : this.baseRowVersion,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('baseRowVersion: $baseRowVersion, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    entityType,
    entityId,
    operation,
    payloadJson,
    baseRowVersion,
    state,
    attemptCount,
    createdAt,
    lastAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.baseRowVersion == this.baseRowVersion &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<int> id;
  final Value<String> businessId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payloadJson;
  final Value<int?> baseRowVersion;
  final Value<String> state;
  final Value<int> attemptCount;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.baseRowVersion = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String businessId,
    required String entityType,
    required String entityId,
    required String operation,
    required String payloadJson,
    this.baseRowVersion = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : businessId = Value(businessId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       payloadJson = Value(payloadJson);
  static Insertable<SyncOutboxData> custom({
    Expression<int>? id,
    Expression<String>? businessId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<int>? baseRowVersion,
    Expression<String>? state,
    Expression<int>? attemptCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (baseRowVersion != null) 'base_row_version': baseRowVersion,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? businessId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payloadJson,
    Value<int?>? baseRowVersion,
    Value<String>? state,
    Value<int>? attemptCount,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastError,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      baseRowVersion: baseRowVersion ?? this.baseRowVersion,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (baseRowVersion.present) {
      map['base_row_version'] = Variable<int>(baseRowVersion.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('baseRowVersion: $baseRowVersion, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $LocalCustomersTable extends LocalCustomers
    with TableInfo<$LocalCustomersTable, LocalCustomer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCompanyMeta = const VerificationMeta(
    'isCompany',
  );
  @override
  late final GeneratedColumn<bool> isCompany = GeneratedColumn<bool>(
    'is_company',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_company" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _listEmailMeta = const VerificationMeta(
    'listEmail',
  );
  @override
  late final GeneratedColumn<String> listEmail = GeneratedColumn<String>(
    'list_email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _listPhoneMeta = const VerificationMeta(
    'listPhone',
  );
  @override
  late final GeneratedColumn<String> listPhone = GeneratedColumn<String>(
    'list_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _billingAddressJsonMeta =
      const VerificationMeta('billingAddressJson');
  @override
  late final GeneratedColumn<String> billingAddressJson =
      GeneratedColumn<String>(
        'billing_address_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _taxableMeta = const VerificationMeta(
    'taxable',
  );
  @override
  late final GeneratedColumn<bool> taxable = GeneratedColumn<bool>(
    'taxable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("taxable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _problemFlagMeta = const VerificationMeta(
    'problemFlag',
  );
  @override
  late final GeneratedColumn<bool> problemFlag = GeneratedColumn<bool>(
    'problem_flag',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("problem_flag" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _problemFlagNoteMeta = const VerificationMeta(
    'problemFlagNote',
  );
  @override
  late final GeneratedColumn<String> problemFlagNote = GeneratedColumn<String>(
    'problem_flag_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contactsJsonMeta = const VerificationMeta(
    'contactsJson',
  );
  @override
  late final GeneratedColumn<String> contactsJson = GeneratedColumn<String>(
    'contacts_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    displayName,
    isCompany,
    email,
    phone,
    listEmail,
    listPhone,
    billingAddressJson,
    taxable,
    problemFlag,
    problemFlagNote,
    contactsJson,
    createdAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCustomer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_company')) {
      context.handle(
        _isCompanyMeta,
        isCompany.isAcceptableOrUnknown(data['is_company']!, _isCompanyMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('list_email')) {
      context.handle(
        _listEmailMeta,
        listEmail.isAcceptableOrUnknown(data['list_email']!, _listEmailMeta),
      );
    }
    if (data.containsKey('list_phone')) {
      context.handle(
        _listPhoneMeta,
        listPhone.isAcceptableOrUnknown(data['list_phone']!, _listPhoneMeta),
      );
    }
    if (data.containsKey('billing_address_json')) {
      context.handle(
        _billingAddressJsonMeta,
        billingAddressJson.isAcceptableOrUnknown(
          data['billing_address_json']!,
          _billingAddressJsonMeta,
        ),
      );
    }
    if (data.containsKey('taxable')) {
      context.handle(
        _taxableMeta,
        taxable.isAcceptableOrUnknown(data['taxable']!, _taxableMeta),
      );
    }
    if (data.containsKey('problem_flag')) {
      context.handle(
        _problemFlagMeta,
        problemFlag.isAcceptableOrUnknown(
          data['problem_flag']!,
          _problemFlagMeta,
        ),
      );
    }
    if (data.containsKey('problem_flag_note')) {
      context.handle(
        _problemFlagNoteMeta,
        problemFlagNote.isAcceptableOrUnknown(
          data['problem_flag_note']!,
          _problemFlagNoteMeta,
        ),
      );
    }
    if (data.containsKey('contacts_json')) {
      context.handle(
        _contactsJsonMeta,
        contactsJson.isAcceptableOrUnknown(
          data['contacts_json']!,
          _contactsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCustomer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCustomer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      isCompany: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_company'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      listEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_email'],
      ),
      listPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_phone'],
      ),
      billingAddressJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}billing_address_json'],
      )!,
      taxable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}taxable'],
      )!,
      problemFlag: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}problem_flag'],
      )!,
      problemFlagNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}problem_flag_note'],
      ),
      contactsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contacts_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalCustomersTable createAlias(String alias) {
    return $LocalCustomersTable(attachedDatabase, alias);
  }
}

class LocalCustomer extends DataClass implements Insertable<LocalCustomer> {
  final String id;
  final String businessId;
  final String displayName;
  final bool isCompany;
  final String? email;
  final String? phone;
  final String? listEmail;
  final String? listPhone;
  final String billingAddressJson;
  final bool taxable;
  final bool problemFlag;
  final String? problemFlagNote;
  final String contactsJson;
  final DateTime? createdAt;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalCustomer({
    required this.id,
    required this.businessId,
    required this.displayName,
    required this.isCompany,
    this.email,
    this.phone,
    this.listEmail,
    this.listPhone,
    required this.billingAddressJson,
    required this.taxable,
    required this.problemFlag,
    this.problemFlagNote,
    required this.contactsJson,
    this.createdAt,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['display_name'] = Variable<String>(displayName);
    map['is_company'] = Variable<bool>(isCompany);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || listEmail != null) {
      map['list_email'] = Variable<String>(listEmail);
    }
    if (!nullToAbsent || listPhone != null) {
      map['list_phone'] = Variable<String>(listPhone);
    }
    map['billing_address_json'] = Variable<String>(billingAddressJson);
    map['taxable'] = Variable<bool>(taxable);
    map['problem_flag'] = Variable<bool>(problemFlag);
    if (!nullToAbsent || problemFlagNote != null) {
      map['problem_flag_note'] = Variable<String>(problemFlagNote);
    }
    map['contacts_json'] = Variable<String>(contactsJson);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalCustomersCompanion toCompanion(bool nullToAbsent) {
    return LocalCustomersCompanion(
      id: Value(id),
      businessId: Value(businessId),
      displayName: Value(displayName),
      isCompany: Value(isCompany),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      listEmail: listEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(listEmail),
      listPhone: listPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(listPhone),
      billingAddressJson: Value(billingAddressJson),
      taxable: Value(taxable),
      problemFlag: Value(problemFlag),
      problemFlagNote: problemFlagNote == null && nullToAbsent
          ? const Value.absent()
          : Value(problemFlagNote),
      contactsJson: Value(contactsJson),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalCustomer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCustomer(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isCompany: serializer.fromJson<bool>(json['isCompany']),
      email: serializer.fromJson<String?>(json['email']),
      phone: serializer.fromJson<String?>(json['phone']),
      listEmail: serializer.fromJson<String?>(json['listEmail']),
      listPhone: serializer.fromJson<String?>(json['listPhone']),
      billingAddressJson: serializer.fromJson<String>(
        json['billingAddressJson'],
      ),
      taxable: serializer.fromJson<bool>(json['taxable']),
      problemFlag: serializer.fromJson<bool>(json['problemFlag']),
      problemFlagNote: serializer.fromJson<String?>(json['problemFlagNote']),
      contactsJson: serializer.fromJson<String>(json['contactsJson']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'displayName': serializer.toJson<String>(displayName),
      'isCompany': serializer.toJson<bool>(isCompany),
      'email': serializer.toJson<String?>(email),
      'phone': serializer.toJson<String?>(phone),
      'listEmail': serializer.toJson<String?>(listEmail),
      'listPhone': serializer.toJson<String?>(listPhone),
      'billingAddressJson': serializer.toJson<String>(billingAddressJson),
      'taxable': serializer.toJson<bool>(taxable),
      'problemFlag': serializer.toJson<bool>(problemFlag),
      'problemFlagNote': serializer.toJson<String?>(problemFlagNote),
      'contactsJson': serializer.toJson<String>(contactsJson),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalCustomer copyWith({
    String? id,
    String? businessId,
    String? displayName,
    bool? isCompany,
    Value<String?> email = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> listEmail = const Value.absent(),
    Value<String?> listPhone = const Value.absent(),
    String? billingAddressJson,
    bool? taxable,
    bool? problemFlag,
    Value<String?> problemFlagNote = const Value.absent(),
    String? contactsJson,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalCustomer(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    displayName: displayName ?? this.displayName,
    isCompany: isCompany ?? this.isCompany,
    email: email.present ? email.value : this.email,
    phone: phone.present ? phone.value : this.phone,
    listEmail: listEmail.present ? listEmail.value : this.listEmail,
    listPhone: listPhone.present ? listPhone.value : this.listPhone,
    billingAddressJson: billingAddressJson ?? this.billingAddressJson,
    taxable: taxable ?? this.taxable,
    problemFlag: problemFlag ?? this.problemFlag,
    problemFlagNote: problemFlagNote.present
        ? problemFlagNote.value
        : this.problemFlagNote,
    contactsJson: contactsJson ?? this.contactsJson,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalCustomer copyWithCompanion(LocalCustomersCompanion data) {
    return LocalCustomer(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      isCompany: data.isCompany.present ? data.isCompany.value : this.isCompany,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      listEmail: data.listEmail.present ? data.listEmail.value : this.listEmail,
      listPhone: data.listPhone.present ? data.listPhone.value : this.listPhone,
      billingAddressJson: data.billingAddressJson.present
          ? data.billingAddressJson.value
          : this.billingAddressJson,
      taxable: data.taxable.present ? data.taxable.value : this.taxable,
      problemFlag: data.problemFlag.present
          ? data.problemFlag.value
          : this.problemFlag,
      problemFlagNote: data.problemFlagNote.present
          ? data.problemFlagNote.value
          : this.problemFlagNote,
      contactsJson: data.contactsJson.present
          ? data.contactsJson.value
          : this.contactsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCustomer(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('displayName: $displayName, ')
          ..write('isCompany: $isCompany, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('listEmail: $listEmail, ')
          ..write('listPhone: $listPhone, ')
          ..write('billingAddressJson: $billingAddressJson, ')
          ..write('taxable: $taxable, ')
          ..write('problemFlag: $problemFlag, ')
          ..write('problemFlagNote: $problemFlagNote, ')
          ..write('contactsJson: $contactsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    displayName,
    isCompany,
    email,
    phone,
    listEmail,
    listPhone,
    billingAddressJson,
    taxable,
    problemFlag,
    problemFlagNote,
    contactsJson,
    createdAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCustomer &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.displayName == this.displayName &&
          other.isCompany == this.isCompany &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.listEmail == this.listEmail &&
          other.listPhone == this.listPhone &&
          other.billingAddressJson == this.billingAddressJson &&
          other.taxable == this.taxable &&
          other.problemFlag == this.problemFlag &&
          other.problemFlagNote == this.problemFlagNote &&
          other.contactsJson == this.contactsJson &&
          other.createdAt == this.createdAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalCustomersCompanion extends UpdateCompanion<LocalCustomer> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> displayName;
  final Value<bool> isCompany;
  final Value<String?> email;
  final Value<String?> phone;
  final Value<String?> listEmail;
  final Value<String?> listPhone;
  final Value<String> billingAddressJson;
  final Value<bool> taxable;
  final Value<bool> problemFlag;
  final Value<String?> problemFlagNote;
  final Value<String> contactsJson;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalCustomersCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isCompany = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.listEmail = const Value.absent(),
    this.listPhone = const Value.absent(),
    this.billingAddressJson = const Value.absent(),
    this.taxable = const Value.absent(),
    this.problemFlag = const Value.absent(),
    this.problemFlagNote = const Value.absent(),
    this.contactsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCustomersCompanion.insert({
    required String id,
    required String businessId,
    required String displayName,
    this.isCompany = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.listEmail = const Value.absent(),
    this.listPhone = const Value.absent(),
    this.billingAddressJson = const Value.absent(),
    this.taxable = const Value.absent(),
    this.problemFlag = const Value.absent(),
    this.problemFlagNote = const Value.absent(),
    this.contactsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       displayName = Value(displayName);
  static Insertable<LocalCustomer> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? displayName,
    Expression<bool>? isCompany,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<String>? listEmail,
    Expression<String>? listPhone,
    Expression<String>? billingAddressJson,
    Expression<bool>? taxable,
    Expression<bool>? problemFlag,
    Expression<String>? problemFlagNote,
    Expression<String>? contactsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (displayName != null) 'display_name': displayName,
      if (isCompany != null) 'is_company': isCompany,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (listEmail != null) 'list_email': listEmail,
      if (listPhone != null) 'list_phone': listPhone,
      if (billingAddressJson != null)
        'billing_address_json': billingAddressJson,
      if (taxable != null) 'taxable': taxable,
      if (problemFlag != null) 'problem_flag': problemFlag,
      if (problemFlagNote != null) 'problem_flag_note': problemFlagNote,
      if (contactsJson != null) 'contacts_json': contactsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCustomersCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? displayName,
    Value<bool>? isCompany,
    Value<String?>? email,
    Value<String?>? phone,
    Value<String?>? listEmail,
    Value<String?>? listPhone,
    Value<String>? billingAddressJson,
    Value<bool>? taxable,
    Value<bool>? problemFlag,
    Value<String?>? problemFlagNote,
    Value<String>? contactsJson,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalCustomersCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      displayName: displayName ?? this.displayName,
      isCompany: isCompany ?? this.isCompany,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      listEmail: listEmail ?? this.listEmail,
      listPhone: listPhone ?? this.listPhone,
      billingAddressJson: billingAddressJson ?? this.billingAddressJson,
      taxable: taxable ?? this.taxable,
      problemFlag: problemFlag ?? this.problemFlag,
      problemFlagNote: problemFlagNote ?? this.problemFlagNote,
      contactsJson: contactsJson ?? this.contactsJson,
      createdAt: createdAt ?? this.createdAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isCompany.present) {
      map['is_company'] = Variable<bool>(isCompany.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (listEmail.present) {
      map['list_email'] = Variable<String>(listEmail.value);
    }
    if (listPhone.present) {
      map['list_phone'] = Variable<String>(listPhone.value);
    }
    if (billingAddressJson.present) {
      map['billing_address_json'] = Variable<String>(billingAddressJson.value);
    }
    if (taxable.present) {
      map['taxable'] = Variable<bool>(taxable.value);
    }
    if (problemFlag.present) {
      map['problem_flag'] = Variable<bool>(problemFlag.value);
    }
    if (problemFlagNote.present) {
      map['problem_flag_note'] = Variable<String>(problemFlagNote.value);
    }
    if (contactsJson.present) {
      map['contacts_json'] = Variable<String>(contactsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCustomersCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('displayName: $displayName, ')
          ..write('isCompany: $isCompany, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('listEmail: $listEmail, ')
          ..write('listPhone: $listPhone, ')
          ..write('billingAddressJson: $billingAddressJson, ')
          ..write('taxable: $taxable, ')
          ..write('problemFlag: $problemFlag, ')
          ..write('problemFlagNote: $problemFlagNote, ')
          ..write('contactsJson: $contactsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalVehiclesTable extends LocalVehicles
    with TableInfo<$LocalVehiclesTable, LocalVehicle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalVehiclesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _makeMeta = const VerificationMeta('make');
  @override
  late final GeneratedColumn<String> make = GeneratedColumn<String>(
    'make',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vinMeta = const VerificationMeta('vin');
  @override
  late final GeneratedColumn<String> vin = GeneratedColumn<String>(
    'vin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _licensePlateMeta = const VerificationMeta(
    'licensePlate',
  );
  @override
  late final GeneratedColumn<String> licensePlate = GeneratedColumn<String>(
    'license_plate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _licenseStateMeta = const VerificationMeta(
    'licenseState',
  );
  @override
  late final GeneratedColumn<String> licenseState = GeneratedColumn<String>(
    'license_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mileageMeta = const VerificationMeta(
    'mileage',
  );
  @override
  late final GeneratedColumn<double> mileage = GeneratedColumn<double>(
    'mileage',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mileageRecordedDateMeta =
      const VerificationMeta('mileageRecordedDate');
  @override
  late final GeneratedColumn<String> mileageRecordedDate =
      GeneratedColumn<String>(
        'mileage_recorded_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _mileageSourceInvoiceIdMeta =
      const VerificationMeta('mileageSourceInvoiceId');
  @override
  late final GeneratedColumn<String> mileageSourceInvoiceId =
      GeneratedColumn<String>(
        'mileage_source_invoice_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _keyPasswordMeta = const VerificationMeta(
    'keyPassword',
  );
  @override
  late final GeneratedColumn<String> keyPassword = GeneratedColumn<String>(
    'key_password',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    year,
    make,
    model,
    vin,
    licensePlate,
    licenseState,
    mileage,
    mileageRecordedDate,
    mileageSourceInvoiceId,
    color,
    keyPassword,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_vehicles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalVehicle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('make')) {
      context.handle(
        _makeMeta,
        make.isAcceptableOrUnknown(data['make']!, _makeMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('vin')) {
      context.handle(
        _vinMeta,
        vin.isAcceptableOrUnknown(data['vin']!, _vinMeta),
      );
    }
    if (data.containsKey('license_plate')) {
      context.handle(
        _licensePlateMeta,
        licensePlate.isAcceptableOrUnknown(
          data['license_plate']!,
          _licensePlateMeta,
        ),
      );
    }
    if (data.containsKey('license_state')) {
      context.handle(
        _licenseStateMeta,
        licenseState.isAcceptableOrUnknown(
          data['license_state']!,
          _licenseStateMeta,
        ),
      );
    }
    if (data.containsKey('mileage')) {
      context.handle(
        _mileageMeta,
        mileage.isAcceptableOrUnknown(data['mileage']!, _mileageMeta),
      );
    }
    if (data.containsKey('mileage_recorded_date')) {
      context.handle(
        _mileageRecordedDateMeta,
        mileageRecordedDate.isAcceptableOrUnknown(
          data['mileage_recorded_date']!,
          _mileageRecordedDateMeta,
        ),
      );
    }
    if (data.containsKey('mileage_source_invoice_id')) {
      context.handle(
        _mileageSourceInvoiceIdMeta,
        mileageSourceInvoiceId.isAcceptableOrUnknown(
          data['mileage_source_invoice_id']!,
          _mileageSourceInvoiceIdMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('key_password')) {
      context.handle(
        _keyPasswordMeta,
        keyPassword.isAcceptableOrUnknown(
          data['key_password']!,
          _keyPasswordMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalVehicle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalVehicle(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      make: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}make'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      vin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vin'],
      ),
      licensePlate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_plate'],
      ),
      licenseState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_state'],
      ),
      mileage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mileage'],
      ),
      mileageRecordedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mileage_recorded_date'],
      ),
      mileageSourceInvoiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mileage_source_invoice_id'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      keyPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_password'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalVehiclesTable createAlias(String alias) {
    return $LocalVehiclesTable(attachedDatabase, alias);
  }
}

class LocalVehicle extends DataClass implements Insertable<LocalVehicle> {
  final String id;
  final String businessId;
  final int? year;
  final String? make;
  final String? model;
  final String? vin;
  final String? licensePlate;
  final String? licenseState;
  final double? mileage;
  final String? mileageRecordedDate;
  final String? mileageSourceInvoiceId;
  final String? color;
  final String? keyPassword;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalVehicle({
    required this.id,
    required this.businessId,
    this.year,
    this.make,
    this.model,
    this.vin,
    this.licensePlate,
    this.licenseState,
    this.mileage,
    this.mileageRecordedDate,
    this.mileageSourceInvoiceId,
    this.color,
    this.keyPassword,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || make != null) {
      map['make'] = Variable<String>(make);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || vin != null) {
      map['vin'] = Variable<String>(vin);
    }
    if (!nullToAbsent || licensePlate != null) {
      map['license_plate'] = Variable<String>(licensePlate);
    }
    if (!nullToAbsent || licenseState != null) {
      map['license_state'] = Variable<String>(licenseState);
    }
    if (!nullToAbsent || mileage != null) {
      map['mileage'] = Variable<double>(mileage);
    }
    if (!nullToAbsent || mileageRecordedDate != null) {
      map['mileage_recorded_date'] = Variable<String>(mileageRecordedDate);
    }
    if (!nullToAbsent || mileageSourceInvoiceId != null) {
      map['mileage_source_invoice_id'] = Variable<String>(
        mileageSourceInvoiceId,
      );
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    if (!nullToAbsent || keyPassword != null) {
      map['key_password'] = Variable<String>(keyPassword);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalVehiclesCompanion toCompanion(bool nullToAbsent) {
    return LocalVehiclesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      make: make == null && nullToAbsent ? const Value.absent() : Value(make),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      vin: vin == null && nullToAbsent ? const Value.absent() : Value(vin),
      licensePlate: licensePlate == null && nullToAbsent
          ? const Value.absent()
          : Value(licensePlate),
      licenseState: licenseState == null && nullToAbsent
          ? const Value.absent()
          : Value(licenseState),
      mileage: mileage == null && nullToAbsent
          ? const Value.absent()
          : Value(mileage),
      mileageRecordedDate: mileageRecordedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(mileageRecordedDate),
      mileageSourceInvoiceId: mileageSourceInvoiceId == null && nullToAbsent
          ? const Value.absent()
          : Value(mileageSourceInvoiceId),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      keyPassword: keyPassword == null && nullToAbsent
          ? const Value.absent()
          : Value(keyPassword),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalVehicle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalVehicle(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      year: serializer.fromJson<int?>(json['year']),
      make: serializer.fromJson<String?>(json['make']),
      model: serializer.fromJson<String?>(json['model']),
      vin: serializer.fromJson<String?>(json['vin']),
      licensePlate: serializer.fromJson<String?>(json['licensePlate']),
      licenseState: serializer.fromJson<String?>(json['licenseState']),
      mileage: serializer.fromJson<double?>(json['mileage']),
      mileageRecordedDate: serializer.fromJson<String?>(
        json['mileageRecordedDate'],
      ),
      mileageSourceInvoiceId: serializer.fromJson<String?>(
        json['mileageSourceInvoiceId'],
      ),
      color: serializer.fromJson<String?>(json['color']),
      keyPassword: serializer.fromJson<String?>(json['keyPassword']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'year': serializer.toJson<int?>(year),
      'make': serializer.toJson<String?>(make),
      'model': serializer.toJson<String?>(model),
      'vin': serializer.toJson<String?>(vin),
      'licensePlate': serializer.toJson<String?>(licensePlate),
      'licenseState': serializer.toJson<String?>(licenseState),
      'mileage': serializer.toJson<double?>(mileage),
      'mileageRecordedDate': serializer.toJson<String?>(mileageRecordedDate),
      'mileageSourceInvoiceId': serializer.toJson<String?>(
        mileageSourceInvoiceId,
      ),
      'color': serializer.toJson<String?>(color),
      'keyPassword': serializer.toJson<String?>(keyPassword),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalVehicle copyWith({
    String? id,
    String? businessId,
    Value<int?> year = const Value.absent(),
    Value<String?> make = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<String?> vin = const Value.absent(),
    Value<String?> licensePlate = const Value.absent(),
    Value<String?> licenseState = const Value.absent(),
    Value<double?> mileage = const Value.absent(),
    Value<String?> mileageRecordedDate = const Value.absent(),
    Value<String?> mileageSourceInvoiceId = const Value.absent(),
    Value<String?> color = const Value.absent(),
    Value<String?> keyPassword = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalVehicle(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    year: year.present ? year.value : this.year,
    make: make.present ? make.value : this.make,
    model: model.present ? model.value : this.model,
    vin: vin.present ? vin.value : this.vin,
    licensePlate: licensePlate.present ? licensePlate.value : this.licensePlate,
    licenseState: licenseState.present ? licenseState.value : this.licenseState,
    mileage: mileage.present ? mileage.value : this.mileage,
    mileageRecordedDate: mileageRecordedDate.present
        ? mileageRecordedDate.value
        : this.mileageRecordedDate,
    mileageSourceInvoiceId: mileageSourceInvoiceId.present
        ? mileageSourceInvoiceId.value
        : this.mileageSourceInvoiceId,
    color: color.present ? color.value : this.color,
    keyPassword: keyPassword.present ? keyPassword.value : this.keyPassword,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalVehicle copyWithCompanion(LocalVehiclesCompanion data) {
    return LocalVehicle(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      year: data.year.present ? data.year.value : this.year,
      make: data.make.present ? data.make.value : this.make,
      model: data.model.present ? data.model.value : this.model,
      vin: data.vin.present ? data.vin.value : this.vin,
      licensePlate: data.licensePlate.present
          ? data.licensePlate.value
          : this.licensePlate,
      licenseState: data.licenseState.present
          ? data.licenseState.value
          : this.licenseState,
      mileage: data.mileage.present ? data.mileage.value : this.mileage,
      mileageRecordedDate: data.mileageRecordedDate.present
          ? data.mileageRecordedDate.value
          : this.mileageRecordedDate,
      mileageSourceInvoiceId: data.mileageSourceInvoiceId.present
          ? data.mileageSourceInvoiceId.value
          : this.mileageSourceInvoiceId,
      color: data.color.present ? data.color.value : this.color,
      keyPassword: data.keyPassword.present
          ? data.keyPassword.value
          : this.keyPassword,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalVehicle(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('year: $year, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('vin: $vin, ')
          ..write('licensePlate: $licensePlate, ')
          ..write('licenseState: $licenseState, ')
          ..write('mileage: $mileage, ')
          ..write('mileageRecordedDate: $mileageRecordedDate, ')
          ..write('mileageSourceInvoiceId: $mileageSourceInvoiceId, ')
          ..write('color: $color, ')
          ..write('keyPassword: $keyPassword, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    year,
    make,
    model,
    vin,
    licensePlate,
    licenseState,
    mileage,
    mileageRecordedDate,
    mileageSourceInvoiceId,
    color,
    keyPassword,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalVehicle &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.year == this.year &&
          other.make == this.make &&
          other.model == this.model &&
          other.vin == this.vin &&
          other.licensePlate == this.licensePlate &&
          other.licenseState == this.licenseState &&
          other.mileage == this.mileage &&
          other.mileageRecordedDate == this.mileageRecordedDate &&
          other.mileageSourceInvoiceId == this.mileageSourceInvoiceId &&
          other.color == this.color &&
          other.keyPassword == this.keyPassword &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalVehiclesCompanion extends UpdateCompanion<LocalVehicle> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<int?> year;
  final Value<String?> make;
  final Value<String?> model;
  final Value<String?> vin;
  final Value<String?> licensePlate;
  final Value<String?> licenseState;
  final Value<double?> mileage;
  final Value<String?> mileageRecordedDate;
  final Value<String?> mileageSourceInvoiceId;
  final Value<String?> color;
  final Value<String?> keyPassword;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalVehiclesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.year = const Value.absent(),
    this.make = const Value.absent(),
    this.model = const Value.absent(),
    this.vin = const Value.absent(),
    this.licensePlate = const Value.absent(),
    this.licenseState = const Value.absent(),
    this.mileage = const Value.absent(),
    this.mileageRecordedDate = const Value.absent(),
    this.mileageSourceInvoiceId = const Value.absent(),
    this.color = const Value.absent(),
    this.keyPassword = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalVehiclesCompanion.insert({
    required String id,
    required String businessId,
    this.year = const Value.absent(),
    this.make = const Value.absent(),
    this.model = const Value.absent(),
    this.vin = const Value.absent(),
    this.licensePlate = const Value.absent(),
    this.licenseState = const Value.absent(),
    this.mileage = const Value.absent(),
    this.mileageRecordedDate = const Value.absent(),
    this.mileageSourceInvoiceId = const Value.absent(),
    this.color = const Value.absent(),
    this.keyPassword = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId);
  static Insertable<LocalVehicle> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<int>? year,
    Expression<String>? make,
    Expression<String>? model,
    Expression<String>? vin,
    Expression<String>? licensePlate,
    Expression<String>? licenseState,
    Expression<double>? mileage,
    Expression<String>? mileageRecordedDate,
    Expression<String>? mileageSourceInvoiceId,
    Expression<String>? color,
    Expression<String>? keyPassword,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (year != null) 'year': year,
      if (make != null) 'make': make,
      if (model != null) 'model': model,
      if (vin != null) 'vin': vin,
      if (licensePlate != null) 'license_plate': licensePlate,
      if (licenseState != null) 'license_state': licenseState,
      if (mileage != null) 'mileage': mileage,
      if (mileageRecordedDate != null)
        'mileage_recorded_date': mileageRecordedDate,
      if (mileageSourceInvoiceId != null)
        'mileage_source_invoice_id': mileageSourceInvoiceId,
      if (color != null) 'color': color,
      if (keyPassword != null) 'key_password': keyPassword,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalVehiclesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<int?>? year,
    Value<String?>? make,
    Value<String?>? model,
    Value<String?>? vin,
    Value<String?>? licensePlate,
    Value<String?>? licenseState,
    Value<double?>? mileage,
    Value<String?>? mileageRecordedDate,
    Value<String?>? mileageSourceInvoiceId,
    Value<String?>? color,
    Value<String?>? keyPassword,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalVehiclesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      year: year ?? this.year,
      make: make ?? this.make,
      model: model ?? this.model,
      vin: vin ?? this.vin,
      licensePlate: licensePlate ?? this.licensePlate,
      licenseState: licenseState ?? this.licenseState,
      mileage: mileage ?? this.mileage,
      mileageRecordedDate: mileageRecordedDate ?? this.mileageRecordedDate,
      mileageSourceInvoiceId:
          mileageSourceInvoiceId ?? this.mileageSourceInvoiceId,
      color: color ?? this.color,
      keyPassword: keyPassword ?? this.keyPassword,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (make.present) {
      map['make'] = Variable<String>(make.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (vin.present) {
      map['vin'] = Variable<String>(vin.value);
    }
    if (licensePlate.present) {
      map['license_plate'] = Variable<String>(licensePlate.value);
    }
    if (licenseState.present) {
      map['license_state'] = Variable<String>(licenseState.value);
    }
    if (mileage.present) {
      map['mileage'] = Variable<double>(mileage.value);
    }
    if (mileageRecordedDate.present) {
      map['mileage_recorded_date'] = Variable<String>(
        mileageRecordedDate.value,
      );
    }
    if (mileageSourceInvoiceId.present) {
      map['mileage_source_invoice_id'] = Variable<String>(
        mileageSourceInvoiceId.value,
      );
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (keyPassword.present) {
      map['key_password'] = Variable<String>(keyPassword.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalVehiclesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('year: $year, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('vin: $vin, ')
          ..write('licensePlate: $licensePlate, ')
          ..write('licenseState: $licenseState, ')
          ..write('mileage: $mileage, ')
          ..write('mileageRecordedDate: $mileageRecordedDate, ')
          ..write('mileageSourceInvoiceId: $mileageSourceInvoiceId, ')
          ..write('color: $color, ')
          ..write('keyPassword: $keyPassword, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCustomerVehiclesTable extends LocalCustomerVehicles
    with TableInfo<$LocalCustomerVehiclesTable, LocalCustomerVehicle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCustomerVehiclesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    customerId,
    vehicleId,
    isPrimary,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_customer_vehicles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCustomerVehicle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_vehicleIdMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, customerId, vehicleId};
  @override
  LocalCustomerVehicle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCustomerVehicle(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      )!,
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
    );
  }

  @override
  $LocalCustomerVehiclesTable createAlias(String alias) {
    return $LocalCustomerVehiclesTable(attachedDatabase, alias);
  }
}

class LocalCustomerVehicle extends DataClass
    implements Insertable<LocalCustomerVehicle> {
  final String businessId;
  final String customerId;
  final String vehicleId;
  final bool isPrimary;
  const LocalCustomerVehicle({
    required this.businessId,
    required this.customerId,
    required this.vehicleId,
    required this.isPrimary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['customer_id'] = Variable<String>(customerId);
    map['vehicle_id'] = Variable<String>(vehicleId);
    map['is_primary'] = Variable<bool>(isPrimary);
    return map;
  }

  LocalCustomerVehiclesCompanion toCompanion(bool nullToAbsent) {
    return LocalCustomerVehiclesCompanion(
      businessId: Value(businessId),
      customerId: Value(customerId),
      vehicleId: Value(vehicleId),
      isPrimary: Value(isPrimary),
    );
  }

  factory LocalCustomerVehicle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCustomerVehicle(
      businessId: serializer.fromJson<String>(json['businessId']),
      customerId: serializer.fromJson<String>(json['customerId']),
      vehicleId: serializer.fromJson<String>(json['vehicleId']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'customerId': serializer.toJson<String>(customerId),
      'vehicleId': serializer.toJson<String>(vehicleId),
      'isPrimary': serializer.toJson<bool>(isPrimary),
    };
  }

  LocalCustomerVehicle copyWith({
    String? businessId,
    String? customerId,
    String? vehicleId,
    bool? isPrimary,
  }) => LocalCustomerVehicle(
    businessId: businessId ?? this.businessId,
    customerId: customerId ?? this.customerId,
    vehicleId: vehicleId ?? this.vehicleId,
    isPrimary: isPrimary ?? this.isPrimary,
  );
  LocalCustomerVehicle copyWithCompanion(LocalCustomerVehiclesCompanion data) {
    return LocalCustomerVehicle(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCustomerVehicle(')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('isPrimary: $isPrimary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(businessId, customerId, vehicleId, isPrimary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCustomerVehicle &&
          other.businessId == this.businessId &&
          other.customerId == this.customerId &&
          other.vehicleId == this.vehicleId &&
          other.isPrimary == this.isPrimary);
}

class LocalCustomerVehiclesCompanion
    extends UpdateCompanion<LocalCustomerVehicle> {
  final Value<String> businessId;
  final Value<String> customerId;
  final Value<String> vehicleId;
  final Value<bool> isPrimary;
  final Value<int> rowid;
  const LocalCustomerVehiclesCompanion({
    this.businessId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCustomerVehiclesCompanion.insert({
    required String businessId,
    required String customerId,
    required String vehicleId,
    this.isPrimary = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       customerId = Value(customerId),
       vehicleId = Value(vehicleId);
  static Insertable<LocalCustomerVehicle> custom({
    Expression<String>? businessId,
    Expression<String>? customerId,
    Expression<String>? vehicleId,
    Expression<bool>? isPrimary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (customerId != null) 'customer_id': customerId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCustomerVehiclesCompanion copyWith({
    Value<String>? businessId,
    Value<String>? customerId,
    Value<String>? vehicleId,
    Value<bool>? isPrimary,
    Value<int>? rowid,
  }) {
    return LocalCustomerVehiclesCompanion(
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      vehicleId: vehicleId ?? this.vehicleId,
      isPrimary: isPrimary ?? this.isPrimary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCustomerVehiclesCompanion(')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAppointmentsTable extends LocalAppointments
    with TableInfo<$LocalAppointmentsTable, LocalAppointment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAppointmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _employeeIdMeta = const VerificationMeta(
    'employeeId',
  );
  @override
  late final GeneratedColumn<String> employeeId = GeneratedColumn<String>(
    'employee_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startsAtMeta = const VerificationMeta(
    'startsAt',
  );
  @override
  late final GeneratedColumn<DateTime> startsAt = GeneratedColumn<DateTime>(
    'starts_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<DateTime> endsAt = GeneratedColumn<DateTime>(
    'ends_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerNameMeta = const VerificationMeta(
    'customerName',
  );
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
    'customer_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerPhoneNormMeta = const VerificationMeta(
    'customerPhoneNorm',
  );
  @override
  late final GeneratedColumn<String> customerPhoneNorm =
      GeneratedColumn<String>(
        'customer_phone_norm',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _vehicleYearMeta = const VerificationMeta(
    'vehicleYear',
  );
  @override
  late final GeneratedColumn<int> vehicleYear = GeneratedColumn<int>(
    'vehicle_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleMakeMeta = const VerificationMeta(
    'vehicleMake',
  );
  @override
  late final GeneratedColumn<String> vehicleMake = GeneratedColumn<String>(
    'vehicle_make',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleModelMeta = const VerificationMeta(
    'vehicleModel',
  );
  @override
  late final GeneratedColumn<String> vehicleModel = GeneratedColumn<String>(
    'vehicle_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleLabelMeta = const VerificationMeta(
    'vehicleLabel',
  );
  @override
  late final GeneratedColumn<String> vehicleLabel = GeneratedColumn<String>(
    'vehicle_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mechanicNameMeta = const VerificationMeta(
    'mechanicName',
  );
  @override
  late final GeneratedColumn<String> mechanicName = GeneratedColumn<String>(
    'mechanic_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canCheckInMeta = const VerificationMeta(
    'canCheckIn',
  );
  @override
  late final GeneratedColumn<bool> canCheckIn = GeneratedColumn<bool>(
    'can_check_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_check_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    customerId,
    vehicleId,
    employeeId,
    jobId,
    requestId,
    startsAt,
    endsAt,
    status,
    title,
    description,
    customerName,
    customerPhoneNorm,
    vehicleYear,
    vehicleMake,
    vehicleModel,
    vehicleLabel,
    mechanicName,
    canCheckIn,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_appointments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAppointment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    }
    if (data.containsKey('employee_id')) {
      context.handle(
        _employeeIdMeta,
        employeeId.isAcceptableOrUnknown(data['employee_id']!, _employeeIdMeta),
      );
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('starts_at')) {
      context.handle(
        _startsAtMeta,
        startsAt.isAcceptableOrUnknown(data['starts_at']!, _startsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startsAtMeta);
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('customer_name')) {
      context.handle(
        _customerNameMeta,
        customerName.isAcceptableOrUnknown(
          data['customer_name']!,
          _customerNameMeta,
        ),
      );
    }
    if (data.containsKey('customer_phone_norm')) {
      context.handle(
        _customerPhoneNormMeta,
        customerPhoneNorm.isAcceptableOrUnknown(
          data['customer_phone_norm']!,
          _customerPhoneNormMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_year')) {
      context.handle(
        _vehicleYearMeta,
        vehicleYear.isAcceptableOrUnknown(
          data['vehicle_year']!,
          _vehicleYearMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_make')) {
      context.handle(
        _vehicleMakeMeta,
        vehicleMake.isAcceptableOrUnknown(
          data['vehicle_make']!,
          _vehicleMakeMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_model')) {
      context.handle(
        _vehicleModelMeta,
        vehicleModel.isAcceptableOrUnknown(
          data['vehicle_model']!,
          _vehicleModelMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_label')) {
      context.handle(
        _vehicleLabelMeta,
        vehicleLabel.isAcceptableOrUnknown(
          data['vehicle_label']!,
          _vehicleLabelMeta,
        ),
      );
    }
    if (data.containsKey('mechanic_name')) {
      context.handle(
        _mechanicNameMeta,
        mechanicName.isAcceptableOrUnknown(
          data['mechanic_name']!,
          _mechanicNameMeta,
        ),
      );
    }
    if (data.containsKey('can_check_in')) {
      context.handle(
        _canCheckInMeta,
        canCheckIn.isAcceptableOrUnknown(
          data['can_check_in']!,
          _canCheckInMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAppointment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAppointment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      ),
      employeeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}employee_id'],
      ),
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      ),
      startsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}starts_at'],
      )!,
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ends_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      customerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_name'],
      ),
      customerPhoneNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_phone_norm'],
      ),
      vehicleYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vehicle_year'],
      ),
      vehicleMake: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_make'],
      ),
      vehicleModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_model'],
      ),
      vehicleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_label'],
      ),
      mechanicName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mechanic_name'],
      ),
      canCheckIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_check_in'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalAppointmentsTable createAlias(String alias) {
    return $LocalAppointmentsTable(attachedDatabase, alias);
  }
}

class LocalAppointment extends DataClass
    implements Insertable<LocalAppointment> {
  final String id;
  final String businessId;
  final String customerId;
  final String? vehicleId;
  final String? employeeId;
  final String? jobId;
  final String? requestId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String title;
  final String? description;
  final String? customerName;
  final String? customerPhoneNorm;
  final int? vehicleYear;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleLabel;
  final String? mechanicName;
  final bool canCheckIn;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalAppointment({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.vehicleId,
    this.employeeId,
    this.jobId,
    this.requestId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.title,
    this.description,
    this.customerName,
    this.customerPhoneNorm,
    this.vehicleYear,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleLabel,
    this.mechanicName,
    required this.canCheckIn,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['customer_id'] = Variable<String>(customerId);
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    if (!nullToAbsent || employeeId != null) {
      map['employee_id'] = Variable<String>(employeeId);
    }
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    map['starts_at'] = Variable<DateTime>(startsAt);
    map['ends_at'] = Variable<DateTime>(endsAt);
    map['status'] = Variable<String>(status);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || customerName != null) {
      map['customer_name'] = Variable<String>(customerName);
    }
    if (!nullToAbsent || customerPhoneNorm != null) {
      map['customer_phone_norm'] = Variable<String>(customerPhoneNorm);
    }
    if (!nullToAbsent || vehicleYear != null) {
      map['vehicle_year'] = Variable<int>(vehicleYear);
    }
    if (!nullToAbsent || vehicleMake != null) {
      map['vehicle_make'] = Variable<String>(vehicleMake);
    }
    if (!nullToAbsent || vehicleModel != null) {
      map['vehicle_model'] = Variable<String>(vehicleModel);
    }
    if (!nullToAbsent || vehicleLabel != null) {
      map['vehicle_label'] = Variable<String>(vehicleLabel);
    }
    if (!nullToAbsent || mechanicName != null) {
      map['mechanic_name'] = Variable<String>(mechanicName);
    }
    map['can_check_in'] = Variable<bool>(canCheckIn);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalAppointmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalAppointmentsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      customerId: Value(customerId),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      employeeId: employeeId == null && nullToAbsent
          ? const Value.absent()
          : Value(employeeId),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      startsAt: Value(startsAt),
      endsAt: Value(endsAt),
      status: Value(status),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      customerName: customerName == null && nullToAbsent
          ? const Value.absent()
          : Value(customerName),
      customerPhoneNorm: customerPhoneNorm == null && nullToAbsent
          ? const Value.absent()
          : Value(customerPhoneNorm),
      vehicleYear: vehicleYear == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleYear),
      vehicleMake: vehicleMake == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleMake),
      vehicleModel: vehicleModel == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleModel),
      vehicleLabel: vehicleLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleLabel),
      mechanicName: mechanicName == null && nullToAbsent
          ? const Value.absent()
          : Value(mechanicName),
      canCheckIn: Value(canCheckIn),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalAppointment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAppointment(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      customerId: serializer.fromJson<String>(json['customerId']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      employeeId: serializer.fromJson<String?>(json['employeeId']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      startsAt: serializer.fromJson<DateTime>(json['startsAt']),
      endsAt: serializer.fromJson<DateTime>(json['endsAt']),
      status: serializer.fromJson<String>(json['status']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      customerName: serializer.fromJson<String?>(json['customerName']),
      customerPhoneNorm: serializer.fromJson<String?>(
        json['customerPhoneNorm'],
      ),
      vehicleYear: serializer.fromJson<int?>(json['vehicleYear']),
      vehicleMake: serializer.fromJson<String?>(json['vehicleMake']),
      vehicleModel: serializer.fromJson<String?>(json['vehicleModel']),
      vehicleLabel: serializer.fromJson<String?>(json['vehicleLabel']),
      mechanicName: serializer.fromJson<String?>(json['mechanicName']),
      canCheckIn: serializer.fromJson<bool>(json['canCheckIn']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'customerId': serializer.toJson<String>(customerId),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'employeeId': serializer.toJson<String?>(employeeId),
      'jobId': serializer.toJson<String?>(jobId),
      'requestId': serializer.toJson<String?>(requestId),
      'startsAt': serializer.toJson<DateTime>(startsAt),
      'endsAt': serializer.toJson<DateTime>(endsAt),
      'status': serializer.toJson<String>(status),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'customerName': serializer.toJson<String?>(customerName),
      'customerPhoneNorm': serializer.toJson<String?>(customerPhoneNorm),
      'vehicleYear': serializer.toJson<int?>(vehicleYear),
      'vehicleMake': serializer.toJson<String?>(vehicleMake),
      'vehicleModel': serializer.toJson<String?>(vehicleModel),
      'vehicleLabel': serializer.toJson<String?>(vehicleLabel),
      'mechanicName': serializer.toJson<String?>(mechanicName),
      'canCheckIn': serializer.toJson<bool>(canCheckIn),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalAppointment copyWith({
    String? id,
    String? businessId,
    String? customerId,
    Value<String?> vehicleId = const Value.absent(),
    Value<String?> employeeId = const Value.absent(),
    Value<String?> jobId = const Value.absent(),
    Value<String?> requestId = const Value.absent(),
    DateTime? startsAt,
    DateTime? endsAt,
    String? status,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> customerName = const Value.absent(),
    Value<String?> customerPhoneNorm = const Value.absent(),
    Value<int?> vehicleYear = const Value.absent(),
    Value<String?> vehicleMake = const Value.absent(),
    Value<String?> vehicleModel = const Value.absent(),
    Value<String?> vehicleLabel = const Value.absent(),
    Value<String?> mechanicName = const Value.absent(),
    bool? canCheckIn,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalAppointment(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    customerId: customerId ?? this.customerId,
    vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
    employeeId: employeeId.present ? employeeId.value : this.employeeId,
    jobId: jobId.present ? jobId.value : this.jobId,
    requestId: requestId.present ? requestId.value : this.requestId,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    status: status ?? this.status,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    customerName: customerName.present ? customerName.value : this.customerName,
    customerPhoneNorm: customerPhoneNorm.present
        ? customerPhoneNorm.value
        : this.customerPhoneNorm,
    vehicleYear: vehicleYear.present ? vehicleYear.value : this.vehicleYear,
    vehicleMake: vehicleMake.present ? vehicleMake.value : this.vehicleMake,
    vehicleModel: vehicleModel.present ? vehicleModel.value : this.vehicleModel,
    vehicleLabel: vehicleLabel.present ? vehicleLabel.value : this.vehicleLabel,
    mechanicName: mechanicName.present ? mechanicName.value : this.mechanicName,
    canCheckIn: canCheckIn ?? this.canCheckIn,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalAppointment copyWithCompanion(LocalAppointmentsCompanion data) {
    return LocalAppointment(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      employeeId: data.employeeId.present
          ? data.employeeId.value
          : this.employeeId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      startsAt: data.startsAt.present ? data.startsAt.value : this.startsAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      status: data.status.present ? data.status.value : this.status,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      customerPhoneNorm: data.customerPhoneNorm.present
          ? data.customerPhoneNorm.value
          : this.customerPhoneNorm,
      vehicleYear: data.vehicleYear.present
          ? data.vehicleYear.value
          : this.vehicleYear,
      vehicleMake: data.vehicleMake.present
          ? data.vehicleMake.value
          : this.vehicleMake,
      vehicleModel: data.vehicleModel.present
          ? data.vehicleModel.value
          : this.vehicleModel,
      vehicleLabel: data.vehicleLabel.present
          ? data.vehicleLabel.value
          : this.vehicleLabel,
      mechanicName: data.mechanicName.present
          ? data.mechanicName.value
          : this.mechanicName,
      canCheckIn: data.canCheckIn.present
          ? data.canCheckIn.value
          : this.canCheckIn,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAppointment(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('employeeId: $employeeId, ')
          ..write('jobId: $jobId, ')
          ..write('requestId: $requestId, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhoneNorm: $customerPhoneNorm, ')
          ..write('vehicleYear: $vehicleYear, ')
          ..write('vehicleMake: $vehicleMake, ')
          ..write('vehicleModel: $vehicleModel, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('mechanicName: $mechanicName, ')
          ..write('canCheckIn: $canCheckIn, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    businessId,
    customerId,
    vehicleId,
    employeeId,
    jobId,
    requestId,
    startsAt,
    endsAt,
    status,
    title,
    description,
    customerName,
    customerPhoneNorm,
    vehicleYear,
    vehicleMake,
    vehicleModel,
    vehicleLabel,
    mechanicName,
    canCheckIn,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAppointment &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.customerId == this.customerId &&
          other.vehicleId == this.vehicleId &&
          other.employeeId == this.employeeId &&
          other.jobId == this.jobId &&
          other.requestId == this.requestId &&
          other.startsAt == this.startsAt &&
          other.endsAt == this.endsAt &&
          other.status == this.status &&
          other.title == this.title &&
          other.description == this.description &&
          other.customerName == this.customerName &&
          other.customerPhoneNorm == this.customerPhoneNorm &&
          other.vehicleYear == this.vehicleYear &&
          other.vehicleMake == this.vehicleMake &&
          other.vehicleModel == this.vehicleModel &&
          other.vehicleLabel == this.vehicleLabel &&
          other.mechanicName == this.mechanicName &&
          other.canCheckIn == this.canCheckIn &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalAppointmentsCompanion extends UpdateCompanion<LocalAppointment> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> customerId;
  final Value<String?> vehicleId;
  final Value<String?> employeeId;
  final Value<String?> jobId;
  final Value<String?> requestId;
  final Value<DateTime> startsAt;
  final Value<DateTime> endsAt;
  final Value<String> status;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> customerName;
  final Value<String?> customerPhoneNorm;
  final Value<int?> vehicleYear;
  final Value<String?> vehicleMake;
  final Value<String?> vehicleModel;
  final Value<String?> vehicleLabel;
  final Value<String?> mechanicName;
  final Value<bool> canCheckIn;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalAppointmentsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.employeeId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.requestId = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.status = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhoneNorm = const Value.absent(),
    this.vehicleYear = const Value.absent(),
    this.vehicleMake = const Value.absent(),
    this.vehicleModel = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.mechanicName = const Value.absent(),
    this.canCheckIn = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAppointmentsCompanion.insert({
    required String id,
    required String businessId,
    required String customerId,
    this.vehicleId = const Value.absent(),
    this.employeeId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.requestId = const Value.absent(),
    required DateTime startsAt,
    required DateTime endsAt,
    required String status,
    required String title,
    this.description = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhoneNorm = const Value.absent(),
    this.vehicleYear = const Value.absent(),
    this.vehicleMake = const Value.absent(),
    this.vehicleModel = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.mechanicName = const Value.absent(),
    this.canCheckIn = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       customerId = Value(customerId),
       startsAt = Value(startsAt),
       endsAt = Value(endsAt),
       status = Value(status),
       title = Value(title);
  static Insertable<LocalAppointment> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? customerId,
    Expression<String>? vehicleId,
    Expression<String>? employeeId,
    Expression<String>? jobId,
    Expression<String>? requestId,
    Expression<DateTime>? startsAt,
    Expression<DateTime>? endsAt,
    Expression<String>? status,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? customerName,
    Expression<String>? customerPhoneNorm,
    Expression<int>? vehicleYear,
    Expression<String>? vehicleMake,
    Expression<String>? vehicleModel,
    Expression<String>? vehicleLabel,
    Expression<String>? mechanicName,
    Expression<bool>? canCheckIn,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (customerId != null) 'customer_id': customerId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (employeeId != null) 'employee_id': employeeId,
      if (jobId != null) 'job_id': jobId,
      if (requestId != null) 'request_id': requestId,
      if (startsAt != null) 'starts_at': startsAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (status != null) 'status': status,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhoneNorm != null) 'customer_phone_norm': customerPhoneNorm,
      if (vehicleYear != null) 'vehicle_year': vehicleYear,
      if (vehicleMake != null) 'vehicle_make': vehicleMake,
      if (vehicleModel != null) 'vehicle_model': vehicleModel,
      if (vehicleLabel != null) 'vehicle_label': vehicleLabel,
      if (mechanicName != null) 'mechanic_name': mechanicName,
      if (canCheckIn != null) 'can_check_in': canCheckIn,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAppointmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? customerId,
    Value<String?>? vehicleId,
    Value<String?>? employeeId,
    Value<String?>? jobId,
    Value<String?>? requestId,
    Value<DateTime>? startsAt,
    Value<DateTime>? endsAt,
    Value<String>? status,
    Value<String>? title,
    Value<String?>? description,
    Value<String?>? customerName,
    Value<String?>? customerPhoneNorm,
    Value<int?>? vehicleYear,
    Value<String?>? vehicleMake,
    Value<String?>? vehicleModel,
    Value<String?>? vehicleLabel,
    Value<String?>? mechanicName,
    Value<bool>? canCheckIn,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalAppointmentsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      vehicleId: vehicleId ?? this.vehicleId,
      employeeId: employeeId ?? this.employeeId,
      jobId: jobId ?? this.jobId,
      requestId: requestId ?? this.requestId,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      status: status ?? this.status,
      title: title ?? this.title,
      description: description ?? this.description,
      customerName: customerName ?? this.customerName,
      customerPhoneNorm: customerPhoneNorm ?? this.customerPhoneNorm,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      mechanicName: mechanicName ?? this.mechanicName,
      canCheckIn: canCheckIn ?? this.canCheckIn,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (employeeId.present) {
      map['employee_id'] = Variable<String>(employeeId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (startsAt.present) {
      map['starts_at'] = Variable<DateTime>(startsAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (customerPhoneNorm.present) {
      map['customer_phone_norm'] = Variable<String>(customerPhoneNorm.value);
    }
    if (vehicleYear.present) {
      map['vehicle_year'] = Variable<int>(vehicleYear.value);
    }
    if (vehicleMake.present) {
      map['vehicle_make'] = Variable<String>(vehicleMake.value);
    }
    if (vehicleModel.present) {
      map['vehicle_model'] = Variable<String>(vehicleModel.value);
    }
    if (vehicleLabel.present) {
      map['vehicle_label'] = Variable<String>(vehicleLabel.value);
    }
    if (mechanicName.present) {
      map['mechanic_name'] = Variable<String>(mechanicName.value);
    }
    if (canCheckIn.present) {
      map['can_check_in'] = Variable<bool>(canCheckIn.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAppointmentsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('employeeId: $employeeId, ')
          ..write('jobId: $jobId, ')
          ..write('requestId: $requestId, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhoneNorm: $customerPhoneNorm, ')
          ..write('vehicleYear: $vehicleYear, ')
          ..write('vehicleMake: $vehicleMake, ')
          ..write('vehicleModel: $vehicleModel, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('mechanicName: $mechanicName, ')
          ..write('canCheckIn: $canCheckIn, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalKioskSettingsTable extends LocalKioskSettings
    with TableInfo<$LocalKioskSettingsTable, LocalKioskSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalKioskSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _disclaimerIdMeta = const VerificationMeta(
    'disclaimerId',
  );
  @override
  late final GeneratedColumn<String> disclaimerId = GeneratedColumn<String>(
    'disclaimer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _disclaimerVersionMeta = const VerificationMeta(
    'disclaimerVersion',
  );
  @override
  late final GeneratedColumn<int> disclaimerVersion = GeneratedColumn<int>(
    'disclaimer_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _disclaimerTextMeta = const VerificationMeta(
    'disclaimerText',
  );
  @override
  late final GeneratedColumn<String> disclaimerText = GeneratedColumn<String>(
    'disclaimer_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    disclaimerId,
    disclaimerVersion,
    disclaimerText,
    serverUpdatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_kiosk_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalKioskSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('disclaimer_id')) {
      context.handle(
        _disclaimerIdMeta,
        disclaimerId.isAcceptableOrUnknown(
          data['disclaimer_id']!,
          _disclaimerIdMeta,
        ),
      );
    }
    if (data.containsKey('disclaimer_version')) {
      context.handle(
        _disclaimerVersionMeta,
        disclaimerVersion.isAcceptableOrUnknown(
          data['disclaimer_version']!,
          _disclaimerVersionMeta,
        ),
      );
    }
    if (data.containsKey('disclaimer_text')) {
      context.handle(
        _disclaimerTextMeta,
        disclaimerText.isAcceptableOrUnknown(
          data['disclaimer_text']!,
          _disclaimerTextMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId};
  @override
  LocalKioskSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalKioskSetting(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      disclaimerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disclaimer_id'],
      ),
      disclaimerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disclaimer_version'],
      ),
      disclaimerText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disclaimer_text'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
    );
  }

  @override
  $LocalKioskSettingsTable createAlias(String alias) {
    return $LocalKioskSettingsTable(attachedDatabase, alias);
  }
}

class LocalKioskSetting extends DataClass
    implements Insertable<LocalKioskSetting> {
  final String businessId;
  final String? disclaimerId;
  final int? disclaimerVersion;
  final String? disclaimerText;
  final DateTime? serverUpdatedAt;
  const LocalKioskSetting({
    required this.businessId,
    this.disclaimerId,
    this.disclaimerVersion,
    this.disclaimerText,
    this.serverUpdatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || disclaimerId != null) {
      map['disclaimer_id'] = Variable<String>(disclaimerId);
    }
    if (!nullToAbsent || disclaimerVersion != null) {
      map['disclaimer_version'] = Variable<int>(disclaimerVersion);
    }
    if (!nullToAbsent || disclaimerText != null) {
      map['disclaimer_text'] = Variable<String>(disclaimerText);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    return map;
  }

  LocalKioskSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalKioskSettingsCompanion(
      businessId: Value(businessId),
      disclaimerId: disclaimerId == null && nullToAbsent
          ? const Value.absent()
          : Value(disclaimerId),
      disclaimerVersion: disclaimerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(disclaimerVersion),
      disclaimerText: disclaimerText == null && nullToAbsent
          ? const Value.absent()
          : Value(disclaimerText),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
    );
  }

  factory LocalKioskSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalKioskSetting(
      businessId: serializer.fromJson<String>(json['businessId']),
      disclaimerId: serializer.fromJson<String?>(json['disclaimerId']),
      disclaimerVersion: serializer.fromJson<int?>(json['disclaimerVersion']),
      disclaimerText: serializer.fromJson<String?>(json['disclaimerText']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'disclaimerId': serializer.toJson<String?>(disclaimerId),
      'disclaimerVersion': serializer.toJson<int?>(disclaimerVersion),
      'disclaimerText': serializer.toJson<String?>(disclaimerText),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
    };
  }

  LocalKioskSetting copyWith({
    String? businessId,
    Value<String?> disclaimerId = const Value.absent(),
    Value<int?> disclaimerVersion = const Value.absent(),
    Value<String?> disclaimerText = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
  }) => LocalKioskSetting(
    businessId: businessId ?? this.businessId,
    disclaimerId: disclaimerId.present ? disclaimerId.value : this.disclaimerId,
    disclaimerVersion: disclaimerVersion.present
        ? disclaimerVersion.value
        : this.disclaimerVersion,
    disclaimerText: disclaimerText.present
        ? disclaimerText.value
        : this.disclaimerText,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
  );
  LocalKioskSetting copyWithCompanion(LocalKioskSettingsCompanion data) {
    return LocalKioskSetting(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      disclaimerId: data.disclaimerId.present
          ? data.disclaimerId.value
          : this.disclaimerId,
      disclaimerVersion: data.disclaimerVersion.present
          ? data.disclaimerVersion.value
          : this.disclaimerVersion,
      disclaimerText: data.disclaimerText.present
          ? data.disclaimerText.value
          : this.disclaimerText,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalKioskSetting(')
          ..write('businessId: $businessId, ')
          ..write('disclaimerId: $disclaimerId, ')
          ..write('disclaimerVersion: $disclaimerVersion, ')
          ..write('disclaimerText: $disclaimerText, ')
          ..write('serverUpdatedAt: $serverUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    businessId,
    disclaimerId,
    disclaimerVersion,
    disclaimerText,
    serverUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalKioskSetting &&
          other.businessId == this.businessId &&
          other.disclaimerId == this.disclaimerId &&
          other.disclaimerVersion == this.disclaimerVersion &&
          other.disclaimerText == this.disclaimerText &&
          other.serverUpdatedAt == this.serverUpdatedAt);
}

class LocalKioskSettingsCompanion extends UpdateCompanion<LocalKioskSetting> {
  final Value<String> businessId;
  final Value<String?> disclaimerId;
  final Value<int?> disclaimerVersion;
  final Value<String?> disclaimerText;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int> rowid;
  const LocalKioskSettingsCompanion({
    this.businessId = const Value.absent(),
    this.disclaimerId = const Value.absent(),
    this.disclaimerVersion = const Value.absent(),
    this.disclaimerText = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalKioskSettingsCompanion.insert({
    required String businessId,
    this.disclaimerId = const Value.absent(),
    this.disclaimerVersion = const Value.absent(),
    this.disclaimerText = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId);
  static Insertable<LocalKioskSetting> custom({
    Expression<String>? businessId,
    Expression<String>? disclaimerId,
    Expression<int>? disclaimerVersion,
    Expression<String>? disclaimerText,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (disclaimerId != null) 'disclaimer_id': disclaimerId,
      if (disclaimerVersion != null) 'disclaimer_version': disclaimerVersion,
      if (disclaimerText != null) 'disclaimer_text': disclaimerText,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalKioskSettingsCompanion copyWith({
    Value<String>? businessId,
    Value<String?>? disclaimerId,
    Value<int?>? disclaimerVersion,
    Value<String?>? disclaimerText,
    Value<DateTime?>? serverUpdatedAt,
    Value<int>? rowid,
  }) {
    return LocalKioskSettingsCompanion(
      businessId: businessId ?? this.businessId,
      disclaimerId: disclaimerId ?? this.disclaimerId,
      disclaimerVersion: disclaimerVersion ?? this.disclaimerVersion,
      disclaimerText: disclaimerText ?? this.disclaimerText,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (disclaimerId.present) {
      map['disclaimer_id'] = Variable<String>(disclaimerId.value);
    }
    if (disclaimerVersion.present) {
      map['disclaimer_version'] = Variable<int>(disclaimerVersion.value);
    }
    if (disclaimerText.present) {
      map['disclaimer_text'] = Variable<String>(disclaimerText.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalKioskSettingsCompanion(')
          ..write('businessId: $businessId, ')
          ..write('disclaimerId: $disclaimerId, ')
          ..write('disclaimerVersion: $disclaimerVersion, ')
          ..write('disclaimerText: $disclaimerText, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalJobsTable extends LocalJobs
    with TableInfo<$LocalJobsTable, LocalJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accessScopeMeta = const VerificationMeta(
    'accessScope',
  );
  @override
  late final GeneratedColumn<String> accessScope = GeneratedColumn<String>(
    'access_scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobNumberMeta = const VerificationMeta(
    'jobNumber',
  );
  @override
  late final GeneratedColumn<String> jobNumber = GeneratedColumn<String>(
    'job_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestedWorkMeta = const VerificationMeta(
    'requestedWork',
  );
  @override
  late final GeneratedColumn<String> requestedWork = GeneratedColumn<String>(
    'requested_work',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusNameMeta = const VerificationMeta(
    'statusName',
  );
  @override
  late final GeneratedColumn<String> statusName = GeneratedColumn<String>(
    'status_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusColorMeta = const VerificationMeta(
    'statusColor',
  );
  @override
  late final GeneratedColumn<String> statusColor = GeneratedColumn<String>(
    'status_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusIconMeta = const VerificationMeta(
    'statusIcon',
  );
  @override
  late final GeneratedColumn<String> statusIcon = GeneratedColumn<String>(
    'status_icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerNameMeta = const VerificationMeta(
    'customerName',
  );
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
    'customer_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerProblemFlagMeta =
      const VerificationMeta('customerProblemFlag');
  @override
  late final GeneratedColumn<bool> customerProblemFlag = GeneratedColumn<bool>(
    'customer_problem_flag',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("customer_problem_flag" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _customerProblemFlagNoteMeta =
      const VerificationMeta('customerProblemFlagNote');
  @override
  late final GeneratedColumn<String> customerProblemFlagNote =
      GeneratedColumn<String>(
        'customer_problem_flag_note',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _capabilitiesJsonMeta = const VerificationMeta(
    'capabilitiesJson',
  );
  @override
  late final GeneratedColumn<String> capabilitiesJson = GeneratedColumn<String>(
    'capabilities_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _pendingRequestCountMeta =
      const VerificationMeta('pendingRequestCount');
  @override
  late final GeneratedColumn<int> pendingRequestCount = GeneratedColumn<int>(
    'pending_request_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _paymentStateMeta = const VerificationMeta(
    'paymentState',
  );
  @override
  late final GeneratedColumn<String> paymentState = GeneratedColumn<String>(
    'payment_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleLabelMeta = const VerificationMeta(
    'vehicleLabel',
  );
  @override
  late final GeneratedColumn<String> vehicleLabel = GeneratedColumn<String>(
    'vehicle_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleVinMeta = const VerificationMeta(
    'vehicleVin',
  );
  @override
  late final GeneratedColumn<String> vehicleVin = GeneratedColumn<String>(
    'vehicle_vin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehiclePlateMeta = const VerificationMeta(
    'vehiclePlate',
  );
  @override
  late final GeneratedColumn<String> vehiclePlate = GeneratedColumn<String>(
    'vehicle_plate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedHoursMeta = const VerificationMeta(
    'plannedHours',
  );
  @override
  late final GeneratedColumn<double> plannedHours = GeneratedColumn<double>(
    'planned_hours',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _odometerInMeta = const VerificationMeta(
    'odometerIn',
  );
  @override
  late final GeneratedColumn<double> odometerIn = GeneratedColumn<double>(
    'odometer_in',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assignedEmployeeIdMeta =
      const VerificationMeta('assignedEmployeeId');
  @override
  late final GeneratedColumn<String> assignedEmployeeId =
      GeneratedColumn<String>(
        'assigned_employee_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _assignedEmployeeNameMeta =
      const VerificationMeta('assignedEmployeeName');
  @override
  late final GeneratedColumn<String> assignedEmployeeName =
      GeneratedColumn<String>(
        'assigned_employee_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _assignedPositionMeta = const VerificationMeta(
    'assignedPosition',
  );
  @override
  late final GeneratedColumn<String> assignedPosition = GeneratedColumn<String>(
    'assigned_position',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isUnassignedMeta = const VerificationMeta(
    'isUnassigned',
  );
  @override
  late final GeneratedColumn<bool> isUnassigned = GeneratedColumn<bool>(
    'is_unassigned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_unassigned" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    accessScope,
    jobNumber,
    title,
    requestedWork,
    status,
    statusName,
    statusColor,
    statusIcon,
    customerId,
    customerName,
    customerProblemFlag,
    customerProblemFlagNote,
    capabilitiesJson,
    pendingRequestCount,
    paymentState,
    vehicleId,
    vehicleLabel,
    vehicleVin,
    vehiclePlate,
    plannedHours,
    odometerIn,
    assignedEmployeeId,
    assignedEmployeeName,
    assignedPosition,
    isUnassigned,
    createdAt,
    completedAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('access_scope')) {
      context.handle(
        _accessScopeMeta,
        accessScope.isAcceptableOrUnknown(
          data['access_scope']!,
          _accessScopeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accessScopeMeta);
    }
    if (data.containsKey('job_number')) {
      context.handle(
        _jobNumberMeta,
        jobNumber.isAcceptableOrUnknown(data['job_number']!, _jobNumberMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('requested_work')) {
      context.handle(
        _requestedWorkMeta,
        requestedWork.isAcceptableOrUnknown(
          data['requested_work']!,
          _requestedWorkMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('status_name')) {
      context.handle(
        _statusNameMeta,
        statusName.isAcceptableOrUnknown(data['status_name']!, _statusNameMeta),
      );
    }
    if (data.containsKey('status_color')) {
      context.handle(
        _statusColorMeta,
        statusColor.isAcceptableOrUnknown(
          data['status_color']!,
          _statusColorMeta,
        ),
      );
    }
    if (data.containsKey('status_icon')) {
      context.handle(
        _statusIconMeta,
        statusIcon.isAcceptableOrUnknown(data['status_icon']!, _statusIconMeta),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('customer_name')) {
      context.handle(
        _customerNameMeta,
        customerName.isAcceptableOrUnknown(
          data['customer_name']!,
          _customerNameMeta,
        ),
      );
    }
    if (data.containsKey('customer_problem_flag')) {
      context.handle(
        _customerProblemFlagMeta,
        customerProblemFlag.isAcceptableOrUnknown(
          data['customer_problem_flag']!,
          _customerProblemFlagMeta,
        ),
      );
    }
    if (data.containsKey('customer_problem_flag_note')) {
      context.handle(
        _customerProblemFlagNoteMeta,
        customerProblemFlagNote.isAcceptableOrUnknown(
          data['customer_problem_flag_note']!,
          _customerProblemFlagNoteMeta,
        ),
      );
    }
    if (data.containsKey('capabilities_json')) {
      context.handle(
        _capabilitiesJsonMeta,
        capabilitiesJson.isAcceptableOrUnknown(
          data['capabilities_json']!,
          _capabilitiesJsonMeta,
        ),
      );
    }
    if (data.containsKey('pending_request_count')) {
      context.handle(
        _pendingRequestCountMeta,
        pendingRequestCount.isAcceptableOrUnknown(
          data['pending_request_count']!,
          _pendingRequestCountMeta,
        ),
      );
    }
    if (data.containsKey('payment_state')) {
      context.handle(
        _paymentStateMeta,
        paymentState.isAcceptableOrUnknown(
          data['payment_state']!,
          _paymentStateMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    }
    if (data.containsKey('vehicle_label')) {
      context.handle(
        _vehicleLabelMeta,
        vehicleLabel.isAcceptableOrUnknown(
          data['vehicle_label']!,
          _vehicleLabelMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_vin')) {
      context.handle(
        _vehicleVinMeta,
        vehicleVin.isAcceptableOrUnknown(data['vehicle_vin']!, _vehicleVinMeta),
      );
    }
    if (data.containsKey('vehicle_plate')) {
      context.handle(
        _vehiclePlateMeta,
        vehiclePlate.isAcceptableOrUnknown(
          data['vehicle_plate']!,
          _vehiclePlateMeta,
        ),
      );
    }
    if (data.containsKey('planned_hours')) {
      context.handle(
        _plannedHoursMeta,
        plannedHours.isAcceptableOrUnknown(
          data['planned_hours']!,
          _plannedHoursMeta,
        ),
      );
    }
    if (data.containsKey('odometer_in')) {
      context.handle(
        _odometerInMeta,
        odometerIn.isAcceptableOrUnknown(data['odometer_in']!, _odometerInMeta),
      );
    }
    if (data.containsKey('assigned_employee_id')) {
      context.handle(
        _assignedEmployeeIdMeta,
        assignedEmployeeId.isAcceptableOrUnknown(
          data['assigned_employee_id']!,
          _assignedEmployeeIdMeta,
        ),
      );
    }
    if (data.containsKey('assigned_employee_name')) {
      context.handle(
        _assignedEmployeeNameMeta,
        assignedEmployeeName.isAcceptableOrUnknown(
          data['assigned_employee_name']!,
          _assignedEmployeeNameMeta,
        ),
      );
    }
    if (data.containsKey('assigned_position')) {
      context.handle(
        _assignedPositionMeta,
        assignedPosition.isAcceptableOrUnknown(
          data['assigned_position']!,
          _assignedPositionMeta,
        ),
      );
    }
    if (data.containsKey('is_unassigned')) {
      context.handle(
        _isUnassignedMeta,
        isUnassigned.isAcceptableOrUnknown(
          data['is_unassigned']!,
          _isUnassignedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      accessScope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}access_scope'],
      )!,
      jobNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_number'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      requestedWork: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_work'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      statusName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_name'],
      ),
      statusColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_color'],
      ),
      statusIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_icon'],
      ),
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      customerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_name'],
      ),
      customerProblemFlag: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}customer_problem_flag'],
      )!,
      customerProblemFlagNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_problem_flag_note'],
      ),
      capabilitiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities_json'],
      )!,
      pendingRequestCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_request_count'],
      )!,
      paymentState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_state'],
      ),
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      ),
      vehicleLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_label'],
      ),
      vehicleVin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_vin'],
      ),
      vehiclePlate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_plate'],
      ),
      plannedHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}planned_hours'],
      )!,
      odometerIn: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}odometer_in'],
      ),
      assignedEmployeeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_employee_id'],
      ),
      assignedEmployeeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_employee_name'],
      ),
      assignedPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_position'],
      ),
      isUnassigned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_unassigned'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalJobsTable createAlias(String alias) {
    return $LocalJobsTable(attachedDatabase, alias);
  }
}

class LocalJob extends DataClass implements Insertable<LocalJob> {
  final String id;
  final String businessId;
  final String accessScope;
  final String? jobNumber;
  final String title;
  final String? requestedWork;
  final String status;
  final String? statusName;
  final String? statusColor;
  final String? statusIcon;
  final String? customerId;
  final String? customerName;
  final bool customerProblemFlag;
  final String? customerProblemFlagNote;
  final String capabilitiesJson;
  final int pendingRequestCount;
  final String? paymentState;
  final String? vehicleId;
  final String? vehicleLabel;
  final String? vehicleVin;
  final String? vehiclePlate;
  final double plannedHours;
  final double? odometerIn;
  final String? assignedEmployeeId;
  final String? assignedEmployeeName;
  final String? assignedPosition;
  final bool isUnassigned;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalJob({
    required this.id,
    required this.businessId,
    required this.accessScope,
    this.jobNumber,
    required this.title,
    this.requestedWork,
    required this.status,
    this.statusName,
    this.statusColor,
    this.statusIcon,
    this.customerId,
    this.customerName,
    required this.customerProblemFlag,
    this.customerProblemFlagNote,
    required this.capabilitiesJson,
    required this.pendingRequestCount,
    this.paymentState,
    this.vehicleId,
    this.vehicleLabel,
    this.vehicleVin,
    this.vehiclePlate,
    required this.plannedHours,
    this.odometerIn,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.assignedPosition,
    required this.isUnassigned,
    this.createdAt,
    this.completedAt,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['access_scope'] = Variable<String>(accessScope);
    if (!nullToAbsent || jobNumber != null) {
      map['job_number'] = Variable<String>(jobNumber);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || requestedWork != null) {
      map['requested_work'] = Variable<String>(requestedWork);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || statusName != null) {
      map['status_name'] = Variable<String>(statusName);
    }
    if (!nullToAbsent || statusColor != null) {
      map['status_color'] = Variable<String>(statusColor);
    }
    if (!nullToAbsent || statusIcon != null) {
      map['status_icon'] = Variable<String>(statusIcon);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    if (!nullToAbsent || customerName != null) {
      map['customer_name'] = Variable<String>(customerName);
    }
    map['customer_problem_flag'] = Variable<bool>(customerProblemFlag);
    if (!nullToAbsent || customerProblemFlagNote != null) {
      map['customer_problem_flag_note'] = Variable<String>(
        customerProblemFlagNote,
      );
    }
    map['capabilities_json'] = Variable<String>(capabilitiesJson);
    map['pending_request_count'] = Variable<int>(pendingRequestCount);
    if (!nullToAbsent || paymentState != null) {
      map['payment_state'] = Variable<String>(paymentState);
    }
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    if (!nullToAbsent || vehicleLabel != null) {
      map['vehicle_label'] = Variable<String>(vehicleLabel);
    }
    if (!nullToAbsent || vehicleVin != null) {
      map['vehicle_vin'] = Variable<String>(vehicleVin);
    }
    if (!nullToAbsent || vehiclePlate != null) {
      map['vehicle_plate'] = Variable<String>(vehiclePlate);
    }
    map['planned_hours'] = Variable<double>(plannedHours);
    if (!nullToAbsent || odometerIn != null) {
      map['odometer_in'] = Variable<double>(odometerIn);
    }
    if (!nullToAbsent || assignedEmployeeId != null) {
      map['assigned_employee_id'] = Variable<String>(assignedEmployeeId);
    }
    if (!nullToAbsent || assignedEmployeeName != null) {
      map['assigned_employee_name'] = Variable<String>(assignedEmployeeName);
    }
    if (!nullToAbsent || assignedPosition != null) {
      map['assigned_position'] = Variable<String>(assignedPosition);
    }
    map['is_unassigned'] = Variable<bool>(isUnassigned);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalJobsCompanion toCompanion(bool nullToAbsent) {
    return LocalJobsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      accessScope: Value(accessScope),
      jobNumber: jobNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(jobNumber),
      title: Value(title),
      requestedWork: requestedWork == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedWork),
      status: Value(status),
      statusName: statusName == null && nullToAbsent
          ? const Value.absent()
          : Value(statusName),
      statusColor: statusColor == null && nullToAbsent
          ? const Value.absent()
          : Value(statusColor),
      statusIcon: statusIcon == null && nullToAbsent
          ? const Value.absent()
          : Value(statusIcon),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      customerName: customerName == null && nullToAbsent
          ? const Value.absent()
          : Value(customerName),
      customerProblemFlag: Value(customerProblemFlag),
      customerProblemFlagNote: customerProblemFlagNote == null && nullToAbsent
          ? const Value.absent()
          : Value(customerProblemFlagNote),
      capabilitiesJson: Value(capabilitiesJson),
      pendingRequestCount: Value(pendingRequestCount),
      paymentState: paymentState == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentState),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      vehicleLabel: vehicleLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleLabel),
      vehicleVin: vehicleVin == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleVin),
      vehiclePlate: vehiclePlate == null && nullToAbsent
          ? const Value.absent()
          : Value(vehiclePlate),
      plannedHours: Value(plannedHours),
      odometerIn: odometerIn == null && nullToAbsent
          ? const Value.absent()
          : Value(odometerIn),
      assignedEmployeeId: assignedEmployeeId == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedEmployeeId),
      assignedEmployeeName: assignedEmployeeName == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedEmployeeName),
      assignedPosition: assignedPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedPosition),
      isUnassigned: Value(isUnassigned),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJob(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      accessScope: serializer.fromJson<String>(json['accessScope']),
      jobNumber: serializer.fromJson<String?>(json['jobNumber']),
      title: serializer.fromJson<String>(json['title']),
      requestedWork: serializer.fromJson<String?>(json['requestedWork']),
      status: serializer.fromJson<String>(json['status']),
      statusName: serializer.fromJson<String?>(json['statusName']),
      statusColor: serializer.fromJson<String?>(json['statusColor']),
      statusIcon: serializer.fromJson<String?>(json['statusIcon']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      customerName: serializer.fromJson<String?>(json['customerName']),
      customerProblemFlag: serializer.fromJson<bool>(
        json['customerProblemFlag'],
      ),
      customerProblemFlagNote: serializer.fromJson<String?>(
        json['customerProblemFlagNote'],
      ),
      capabilitiesJson: serializer.fromJson<String>(json['capabilitiesJson']),
      pendingRequestCount: serializer.fromJson<int>(
        json['pendingRequestCount'],
      ),
      paymentState: serializer.fromJson<String?>(json['paymentState']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      vehicleLabel: serializer.fromJson<String?>(json['vehicleLabel']),
      vehicleVin: serializer.fromJson<String?>(json['vehicleVin']),
      vehiclePlate: serializer.fromJson<String?>(json['vehiclePlate']),
      plannedHours: serializer.fromJson<double>(json['plannedHours']),
      odometerIn: serializer.fromJson<double?>(json['odometerIn']),
      assignedEmployeeId: serializer.fromJson<String?>(
        json['assignedEmployeeId'],
      ),
      assignedEmployeeName: serializer.fromJson<String?>(
        json['assignedEmployeeName'],
      ),
      assignedPosition: serializer.fromJson<String?>(json['assignedPosition']),
      isUnassigned: serializer.fromJson<bool>(json['isUnassigned']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'accessScope': serializer.toJson<String>(accessScope),
      'jobNumber': serializer.toJson<String?>(jobNumber),
      'title': serializer.toJson<String>(title),
      'requestedWork': serializer.toJson<String?>(requestedWork),
      'status': serializer.toJson<String>(status),
      'statusName': serializer.toJson<String?>(statusName),
      'statusColor': serializer.toJson<String?>(statusColor),
      'statusIcon': serializer.toJson<String?>(statusIcon),
      'customerId': serializer.toJson<String?>(customerId),
      'customerName': serializer.toJson<String?>(customerName),
      'customerProblemFlag': serializer.toJson<bool>(customerProblemFlag),
      'customerProblemFlagNote': serializer.toJson<String?>(
        customerProblemFlagNote,
      ),
      'capabilitiesJson': serializer.toJson<String>(capabilitiesJson),
      'pendingRequestCount': serializer.toJson<int>(pendingRequestCount),
      'paymentState': serializer.toJson<String?>(paymentState),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'vehicleLabel': serializer.toJson<String?>(vehicleLabel),
      'vehicleVin': serializer.toJson<String?>(vehicleVin),
      'vehiclePlate': serializer.toJson<String?>(vehiclePlate),
      'plannedHours': serializer.toJson<double>(plannedHours),
      'odometerIn': serializer.toJson<double?>(odometerIn),
      'assignedEmployeeId': serializer.toJson<String?>(assignedEmployeeId),
      'assignedEmployeeName': serializer.toJson<String?>(assignedEmployeeName),
      'assignedPosition': serializer.toJson<String?>(assignedPosition),
      'isUnassigned': serializer.toJson<bool>(isUnassigned),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalJob copyWith({
    String? id,
    String? businessId,
    String? accessScope,
    Value<String?> jobNumber = const Value.absent(),
    String? title,
    Value<String?> requestedWork = const Value.absent(),
    String? status,
    Value<String?> statusName = const Value.absent(),
    Value<String?> statusColor = const Value.absent(),
    Value<String?> statusIcon = const Value.absent(),
    Value<String?> customerId = const Value.absent(),
    Value<String?> customerName = const Value.absent(),
    bool? customerProblemFlag,
    Value<String?> customerProblemFlagNote = const Value.absent(),
    String? capabilitiesJson,
    int? pendingRequestCount,
    Value<String?> paymentState = const Value.absent(),
    Value<String?> vehicleId = const Value.absent(),
    Value<String?> vehicleLabel = const Value.absent(),
    Value<String?> vehicleVin = const Value.absent(),
    Value<String?> vehiclePlate = const Value.absent(),
    double? plannedHours,
    Value<double?> odometerIn = const Value.absent(),
    Value<String?> assignedEmployeeId = const Value.absent(),
    Value<String?> assignedEmployeeName = const Value.absent(),
    Value<String?> assignedPosition = const Value.absent(),
    bool? isUnassigned,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalJob(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    accessScope: accessScope ?? this.accessScope,
    jobNumber: jobNumber.present ? jobNumber.value : this.jobNumber,
    title: title ?? this.title,
    requestedWork: requestedWork.present
        ? requestedWork.value
        : this.requestedWork,
    status: status ?? this.status,
    statusName: statusName.present ? statusName.value : this.statusName,
    statusColor: statusColor.present ? statusColor.value : this.statusColor,
    statusIcon: statusIcon.present ? statusIcon.value : this.statusIcon,
    customerId: customerId.present ? customerId.value : this.customerId,
    customerName: customerName.present ? customerName.value : this.customerName,
    customerProblemFlag: customerProblemFlag ?? this.customerProblemFlag,
    customerProblemFlagNote: customerProblemFlagNote.present
        ? customerProblemFlagNote.value
        : this.customerProblemFlagNote,
    capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
    pendingRequestCount: pendingRequestCount ?? this.pendingRequestCount,
    paymentState: paymentState.present ? paymentState.value : this.paymentState,
    vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
    vehicleLabel: vehicleLabel.present ? vehicleLabel.value : this.vehicleLabel,
    vehicleVin: vehicleVin.present ? vehicleVin.value : this.vehicleVin,
    vehiclePlate: vehiclePlate.present ? vehiclePlate.value : this.vehiclePlate,
    plannedHours: plannedHours ?? this.plannedHours,
    odometerIn: odometerIn.present ? odometerIn.value : this.odometerIn,
    assignedEmployeeId: assignedEmployeeId.present
        ? assignedEmployeeId.value
        : this.assignedEmployeeId,
    assignedEmployeeName: assignedEmployeeName.present
        ? assignedEmployeeName.value
        : this.assignedEmployeeName,
    assignedPosition: assignedPosition.present
        ? assignedPosition.value
        : this.assignedPosition,
    isUnassigned: isUnassigned ?? this.isUnassigned,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalJob copyWithCompanion(LocalJobsCompanion data) {
    return LocalJob(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      accessScope: data.accessScope.present
          ? data.accessScope.value
          : this.accessScope,
      jobNumber: data.jobNumber.present ? data.jobNumber.value : this.jobNumber,
      title: data.title.present ? data.title.value : this.title,
      requestedWork: data.requestedWork.present
          ? data.requestedWork.value
          : this.requestedWork,
      status: data.status.present ? data.status.value : this.status,
      statusName: data.statusName.present
          ? data.statusName.value
          : this.statusName,
      statusColor: data.statusColor.present
          ? data.statusColor.value
          : this.statusColor,
      statusIcon: data.statusIcon.present
          ? data.statusIcon.value
          : this.statusIcon,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      customerProblemFlag: data.customerProblemFlag.present
          ? data.customerProblemFlag.value
          : this.customerProblemFlag,
      customerProblemFlagNote: data.customerProblemFlagNote.present
          ? data.customerProblemFlagNote.value
          : this.customerProblemFlagNote,
      capabilitiesJson: data.capabilitiesJson.present
          ? data.capabilitiesJson.value
          : this.capabilitiesJson,
      pendingRequestCount: data.pendingRequestCount.present
          ? data.pendingRequestCount.value
          : this.pendingRequestCount,
      paymentState: data.paymentState.present
          ? data.paymentState.value
          : this.paymentState,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      vehicleLabel: data.vehicleLabel.present
          ? data.vehicleLabel.value
          : this.vehicleLabel,
      vehicleVin: data.vehicleVin.present
          ? data.vehicleVin.value
          : this.vehicleVin,
      vehiclePlate: data.vehiclePlate.present
          ? data.vehiclePlate.value
          : this.vehiclePlate,
      plannedHours: data.plannedHours.present
          ? data.plannedHours.value
          : this.plannedHours,
      odometerIn: data.odometerIn.present
          ? data.odometerIn.value
          : this.odometerIn,
      assignedEmployeeId: data.assignedEmployeeId.present
          ? data.assignedEmployeeId.value
          : this.assignedEmployeeId,
      assignedEmployeeName: data.assignedEmployeeName.present
          ? data.assignedEmployeeName.value
          : this.assignedEmployeeName,
      assignedPosition: data.assignedPosition.present
          ? data.assignedPosition.value
          : this.assignedPosition,
      isUnassigned: data.isUnassigned.present
          ? data.isUnassigned.value
          : this.isUnassigned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJob(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('accessScope: $accessScope, ')
          ..write('jobNumber: $jobNumber, ')
          ..write('title: $title, ')
          ..write('requestedWork: $requestedWork, ')
          ..write('status: $status, ')
          ..write('statusName: $statusName, ')
          ..write('statusColor: $statusColor, ')
          ..write('statusIcon: $statusIcon, ')
          ..write('customerId: $customerId, ')
          ..write('customerName: $customerName, ')
          ..write('customerProblemFlag: $customerProblemFlag, ')
          ..write('customerProblemFlagNote: $customerProblemFlagNote, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('pendingRequestCount: $pendingRequestCount, ')
          ..write('paymentState: $paymentState, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('vehicleVin: $vehicleVin, ')
          ..write('vehiclePlate: $vehiclePlate, ')
          ..write('plannedHours: $plannedHours, ')
          ..write('odometerIn: $odometerIn, ')
          ..write('assignedEmployeeId: $assignedEmployeeId, ')
          ..write('assignedEmployeeName: $assignedEmployeeName, ')
          ..write('assignedPosition: $assignedPosition, ')
          ..write('isUnassigned: $isUnassigned, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    businessId,
    accessScope,
    jobNumber,
    title,
    requestedWork,
    status,
    statusName,
    statusColor,
    statusIcon,
    customerId,
    customerName,
    customerProblemFlag,
    customerProblemFlagNote,
    capabilitiesJson,
    pendingRequestCount,
    paymentState,
    vehicleId,
    vehicleLabel,
    vehicleVin,
    vehiclePlate,
    plannedHours,
    odometerIn,
    assignedEmployeeId,
    assignedEmployeeName,
    assignedPosition,
    isUnassigned,
    createdAt,
    completedAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJob &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.accessScope == this.accessScope &&
          other.jobNumber == this.jobNumber &&
          other.title == this.title &&
          other.requestedWork == this.requestedWork &&
          other.status == this.status &&
          other.statusName == this.statusName &&
          other.statusColor == this.statusColor &&
          other.statusIcon == this.statusIcon &&
          other.customerId == this.customerId &&
          other.customerName == this.customerName &&
          other.customerProblemFlag == this.customerProblemFlag &&
          other.customerProblemFlagNote == this.customerProblemFlagNote &&
          other.capabilitiesJson == this.capabilitiesJson &&
          other.pendingRequestCount == this.pendingRequestCount &&
          other.paymentState == this.paymentState &&
          other.vehicleId == this.vehicleId &&
          other.vehicleLabel == this.vehicleLabel &&
          other.vehicleVin == this.vehicleVin &&
          other.vehiclePlate == this.vehiclePlate &&
          other.plannedHours == this.plannedHours &&
          other.odometerIn == this.odometerIn &&
          other.assignedEmployeeId == this.assignedEmployeeId &&
          other.assignedEmployeeName == this.assignedEmployeeName &&
          other.assignedPosition == this.assignedPosition &&
          other.isUnassigned == this.isUnassigned &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalJobsCompanion extends UpdateCompanion<LocalJob> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> accessScope;
  final Value<String?> jobNumber;
  final Value<String> title;
  final Value<String?> requestedWork;
  final Value<String> status;
  final Value<String?> statusName;
  final Value<String?> statusColor;
  final Value<String?> statusIcon;
  final Value<String?> customerId;
  final Value<String?> customerName;
  final Value<bool> customerProblemFlag;
  final Value<String?> customerProblemFlagNote;
  final Value<String> capabilitiesJson;
  final Value<int> pendingRequestCount;
  final Value<String?> paymentState;
  final Value<String?> vehicleId;
  final Value<String?> vehicleLabel;
  final Value<String?> vehicleVin;
  final Value<String?> vehiclePlate;
  final Value<double> plannedHours;
  final Value<double?> odometerIn;
  final Value<String?> assignedEmployeeId;
  final Value<String?> assignedEmployeeName;
  final Value<String?> assignedPosition;
  final Value<bool> isUnassigned;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> completedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalJobsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.accessScope = const Value.absent(),
    this.jobNumber = const Value.absent(),
    this.title = const Value.absent(),
    this.requestedWork = const Value.absent(),
    this.status = const Value.absent(),
    this.statusName = const Value.absent(),
    this.statusColor = const Value.absent(),
    this.statusIcon = const Value.absent(),
    this.customerId = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerProblemFlag = const Value.absent(),
    this.customerProblemFlagNote = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.pendingRequestCount = const Value.absent(),
    this.paymentState = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.vehicleVin = const Value.absent(),
    this.vehiclePlate = const Value.absent(),
    this.plannedHours = const Value.absent(),
    this.odometerIn = const Value.absent(),
    this.assignedEmployeeId = const Value.absent(),
    this.assignedEmployeeName = const Value.absent(),
    this.assignedPosition = const Value.absent(),
    this.isUnassigned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobsCompanion.insert({
    required String id,
    required String businessId,
    required String accessScope,
    this.jobNumber = const Value.absent(),
    required String title,
    this.requestedWork = const Value.absent(),
    required String status,
    this.statusName = const Value.absent(),
    this.statusColor = const Value.absent(),
    this.statusIcon = const Value.absent(),
    this.customerId = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerProblemFlag = const Value.absent(),
    this.customerProblemFlagNote = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.pendingRequestCount = const Value.absent(),
    this.paymentState = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.vehicleLabel = const Value.absent(),
    this.vehicleVin = const Value.absent(),
    this.vehiclePlate = const Value.absent(),
    this.plannedHours = const Value.absent(),
    this.odometerIn = const Value.absent(),
    this.assignedEmployeeId = const Value.absent(),
    this.assignedEmployeeName = const Value.absent(),
    this.assignedPosition = const Value.absent(),
    this.isUnassigned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       accessScope = Value(accessScope),
       title = Value(title),
       status = Value(status);
  static Insertable<LocalJob> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? accessScope,
    Expression<String>? jobNumber,
    Expression<String>? title,
    Expression<String>? requestedWork,
    Expression<String>? status,
    Expression<String>? statusName,
    Expression<String>? statusColor,
    Expression<String>? statusIcon,
    Expression<String>? customerId,
    Expression<String>? customerName,
    Expression<bool>? customerProblemFlag,
    Expression<String>? customerProblemFlagNote,
    Expression<String>? capabilitiesJson,
    Expression<int>? pendingRequestCount,
    Expression<String>? paymentState,
    Expression<String>? vehicleId,
    Expression<String>? vehicleLabel,
    Expression<String>? vehicleVin,
    Expression<String>? vehiclePlate,
    Expression<double>? plannedHours,
    Expression<double>? odometerIn,
    Expression<String>? assignedEmployeeId,
    Expression<String>? assignedEmployeeName,
    Expression<String>? assignedPosition,
    Expression<bool>? isUnassigned,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (accessScope != null) 'access_scope': accessScope,
      if (jobNumber != null) 'job_number': jobNumber,
      if (title != null) 'title': title,
      if (requestedWork != null) 'requested_work': requestedWork,
      if (status != null) 'status': status,
      if (statusName != null) 'status_name': statusName,
      if (statusColor != null) 'status_color': statusColor,
      if (statusIcon != null) 'status_icon': statusIcon,
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (customerProblemFlag != null)
        'customer_problem_flag': customerProblemFlag,
      if (customerProblemFlagNote != null)
        'customer_problem_flag_note': customerProblemFlagNote,
      if (capabilitiesJson != null) 'capabilities_json': capabilitiesJson,
      if (pendingRequestCount != null)
        'pending_request_count': pendingRequestCount,
      if (paymentState != null) 'payment_state': paymentState,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (vehicleLabel != null) 'vehicle_label': vehicleLabel,
      if (vehicleVin != null) 'vehicle_vin': vehicleVin,
      if (vehiclePlate != null) 'vehicle_plate': vehiclePlate,
      if (plannedHours != null) 'planned_hours': plannedHours,
      if (odometerIn != null) 'odometer_in': odometerIn,
      if (assignedEmployeeId != null)
        'assigned_employee_id': assignedEmployeeId,
      if (assignedEmployeeName != null)
        'assigned_employee_name': assignedEmployeeName,
      if (assignedPosition != null) 'assigned_position': assignedPosition,
      if (isUnassigned != null) 'is_unassigned': isUnassigned,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? accessScope,
    Value<String?>? jobNumber,
    Value<String>? title,
    Value<String?>? requestedWork,
    Value<String>? status,
    Value<String?>? statusName,
    Value<String?>? statusColor,
    Value<String?>? statusIcon,
    Value<String?>? customerId,
    Value<String?>? customerName,
    Value<bool>? customerProblemFlag,
    Value<String?>? customerProblemFlagNote,
    Value<String>? capabilitiesJson,
    Value<int>? pendingRequestCount,
    Value<String?>? paymentState,
    Value<String?>? vehicleId,
    Value<String?>? vehicleLabel,
    Value<String?>? vehicleVin,
    Value<String?>? vehiclePlate,
    Value<double>? plannedHours,
    Value<double?>? odometerIn,
    Value<String?>? assignedEmployeeId,
    Value<String?>? assignedEmployeeName,
    Value<String?>? assignedPosition,
    Value<bool>? isUnassigned,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? completedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalJobsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      accessScope: accessScope ?? this.accessScope,
      jobNumber: jobNumber ?? this.jobNumber,
      title: title ?? this.title,
      requestedWork: requestedWork ?? this.requestedWork,
      status: status ?? this.status,
      statusName: statusName ?? this.statusName,
      statusColor: statusColor ?? this.statusColor,
      statusIcon: statusIcon ?? this.statusIcon,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerProblemFlag: customerProblemFlag ?? this.customerProblemFlag,
      customerProblemFlagNote:
          customerProblemFlagNote ?? this.customerProblemFlagNote,
      capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
      pendingRequestCount: pendingRequestCount ?? this.pendingRequestCount,
      paymentState: paymentState ?? this.paymentState,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      vehicleVin: vehicleVin ?? this.vehicleVin,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      plannedHours: plannedHours ?? this.plannedHours,
      odometerIn: odometerIn ?? this.odometerIn,
      assignedEmployeeId: assignedEmployeeId ?? this.assignedEmployeeId,
      assignedEmployeeName: assignedEmployeeName ?? this.assignedEmployeeName,
      assignedPosition: assignedPosition ?? this.assignedPosition,
      isUnassigned: isUnassigned ?? this.isUnassigned,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (accessScope.present) {
      map['access_scope'] = Variable<String>(accessScope.value);
    }
    if (jobNumber.present) {
      map['job_number'] = Variable<String>(jobNumber.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (requestedWork.present) {
      map['requested_work'] = Variable<String>(requestedWork.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (statusName.present) {
      map['status_name'] = Variable<String>(statusName.value);
    }
    if (statusColor.present) {
      map['status_color'] = Variable<String>(statusColor.value);
    }
    if (statusIcon.present) {
      map['status_icon'] = Variable<String>(statusIcon.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (customerProblemFlag.present) {
      map['customer_problem_flag'] = Variable<bool>(customerProblemFlag.value);
    }
    if (customerProblemFlagNote.present) {
      map['customer_problem_flag_note'] = Variable<String>(
        customerProblemFlagNote.value,
      );
    }
    if (capabilitiesJson.present) {
      map['capabilities_json'] = Variable<String>(capabilitiesJson.value);
    }
    if (pendingRequestCount.present) {
      map['pending_request_count'] = Variable<int>(pendingRequestCount.value);
    }
    if (paymentState.present) {
      map['payment_state'] = Variable<String>(paymentState.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (vehicleLabel.present) {
      map['vehicle_label'] = Variable<String>(vehicleLabel.value);
    }
    if (vehicleVin.present) {
      map['vehicle_vin'] = Variable<String>(vehicleVin.value);
    }
    if (vehiclePlate.present) {
      map['vehicle_plate'] = Variable<String>(vehiclePlate.value);
    }
    if (plannedHours.present) {
      map['planned_hours'] = Variable<double>(plannedHours.value);
    }
    if (odometerIn.present) {
      map['odometer_in'] = Variable<double>(odometerIn.value);
    }
    if (assignedEmployeeId.present) {
      map['assigned_employee_id'] = Variable<String>(assignedEmployeeId.value);
    }
    if (assignedEmployeeName.present) {
      map['assigned_employee_name'] = Variable<String>(
        assignedEmployeeName.value,
      );
    }
    if (assignedPosition.present) {
      map['assigned_position'] = Variable<String>(assignedPosition.value);
    }
    if (isUnassigned.present) {
      map['is_unassigned'] = Variable<bool>(isUnassigned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('accessScope: $accessScope, ')
          ..write('jobNumber: $jobNumber, ')
          ..write('title: $title, ')
          ..write('requestedWork: $requestedWork, ')
          ..write('status: $status, ')
          ..write('statusName: $statusName, ')
          ..write('statusColor: $statusColor, ')
          ..write('statusIcon: $statusIcon, ')
          ..write('customerId: $customerId, ')
          ..write('customerName: $customerName, ')
          ..write('customerProblemFlag: $customerProblemFlag, ')
          ..write('customerProblemFlagNote: $customerProblemFlagNote, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('pendingRequestCount: $pendingRequestCount, ')
          ..write('paymentState: $paymentState, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('vehicleLabel: $vehicleLabel, ')
          ..write('vehicleVin: $vehicleVin, ')
          ..write('vehiclePlate: $vehiclePlate, ')
          ..write('plannedHours: $plannedHours, ')
          ..write('odometerIn: $odometerIn, ')
          ..write('assignedEmployeeId: $assignedEmployeeId, ')
          ..write('assignedEmployeeName: $assignedEmployeeName, ')
          ..write('assignedPosition: $assignedPosition, ')
          ..write('isUnassigned: $isUnassigned, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalJobStatusesTable extends LocalJobStatuses
    with TableInfo<$LocalJobStatusesTable, LocalJobStatuse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobStatusesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconKeyMeta = const VerificationMeta(
    'iconKey',
  );
  @override
  late final GeneratedColumn<String> iconKey = GeneratedColumn<String>(
    'icon_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    code,
    name,
    colorHex,
    iconKey,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_job_statuses';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalJobStatuse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('icon_key')) {
      context.handle(
        _iconKeyMeta,
        iconKey.isAcceptableOrUnknown(data['icon_key']!, _iconKeyMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, code};
  @override
  LocalJobStatuse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJobStatuse(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      ),
      iconKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_key'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $LocalJobStatusesTable createAlias(String alias) {
    return $LocalJobStatusesTable(attachedDatabase, alias);
  }
}

class LocalJobStatuse extends DataClass implements Insertable<LocalJobStatuse> {
  final String businessId;
  final String code;
  final String name;
  final String? colorHex;
  final String? iconKey;
  final int sortOrder;
  const LocalJobStatuse({
    required this.businessId,
    required this.code,
    required this.name,
    this.colorHex,
    this.iconKey,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || colorHex != null) {
      map['color_hex'] = Variable<String>(colorHex);
    }
    if (!nullToAbsent || iconKey != null) {
      map['icon_key'] = Variable<String>(iconKey);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  LocalJobStatusesCompanion toCompanion(bool nullToAbsent) {
    return LocalJobStatusesCompanion(
      businessId: Value(businessId),
      code: Value(code),
      name: Value(name),
      colorHex: colorHex == null && nullToAbsent
          ? const Value.absent()
          : Value(colorHex),
      iconKey: iconKey == null && nullToAbsent
          ? const Value.absent()
          : Value(iconKey),
      sortOrder: Value(sortOrder),
    );
  }

  factory LocalJobStatuse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJobStatuse(
      businessId: serializer.fromJson<String>(json['businessId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String?>(json['colorHex']),
      iconKey: serializer.fromJson<String?>(json['iconKey']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String?>(colorHex),
      'iconKey': serializer.toJson<String?>(iconKey),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  LocalJobStatuse copyWith({
    String? businessId,
    String? code,
    String? name,
    Value<String?> colorHex = const Value.absent(),
    Value<String?> iconKey = const Value.absent(),
    int? sortOrder,
  }) => LocalJobStatuse(
    businessId: businessId ?? this.businessId,
    code: code ?? this.code,
    name: name ?? this.name,
    colorHex: colorHex.present ? colorHex.value : this.colorHex,
    iconKey: iconKey.present ? iconKey.value : this.iconKey,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  LocalJobStatuse copyWithCompanion(LocalJobStatusesCompanion data) {
    return LocalJobStatuse(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      iconKey: data.iconKey.present ? data.iconKey.value : this.iconKey,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobStatuse(')
          ..write('businessId: $businessId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('iconKey: $iconKey, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(businessId, code, name, colorHex, iconKey, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJobStatuse &&
          other.businessId == this.businessId &&
          other.code == this.code &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.iconKey == this.iconKey &&
          other.sortOrder == this.sortOrder);
}

class LocalJobStatusesCompanion extends UpdateCompanion<LocalJobStatuse> {
  final Value<String> businessId;
  final Value<String> code;
  final Value<String> name;
  final Value<String?> colorHex;
  final Value<String?> iconKey;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const LocalJobStatusesCompanion({
    this.businessId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobStatusesCompanion.insert({
    required String businessId,
    required String code,
    required String name,
    this.colorHex = const Value.absent(),
    this.iconKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       code = Value(code),
       name = Value(name);
  static Insertable<LocalJobStatuse> custom({
    Expression<String>? businessId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<String>? iconKey,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (iconKey != null) 'icon_key': iconKey,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobStatusesCompanion copyWith({
    Value<String>? businessId,
    Value<String>? code,
    Value<String>? name,
    Value<String?>? colorHex,
    Value<String?>? iconKey,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return LocalJobStatusesCompanion(
      businessId: businessId ?? this.businessId,
      code: code ?? this.code,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (iconKey.present) {
      map['icon_key'] = Variable<String>(iconKey.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobStatusesCompanion(')
          ..write('businessId: $businessId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('iconKey: $iconKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalJobAssignmentsTable extends LocalJobAssignments
    with TableInfo<$LocalJobAssignmentsTable, LocalJobAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobAssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assignmentIdMeta = const VerificationMeta(
    'assignmentId',
  );
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
    'assignment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _employeeIdMeta = const VerificationMeta(
    'employeeId',
  );
  @override
  late final GeneratedColumn<String> employeeId = GeneratedColumn<String>(
    'employee_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _employeeNameMeta = const VerificationMeta(
    'employeeName',
  );
  @override
  late final GeneratedColumn<String> employeeName = GeneratedColumn<String>(
    'employee_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _assignedAtMeta = const VerificationMeta(
    'assignedAt',
  );
  @override
  late final GeneratedColumn<DateTime> assignedAt = GeneratedColumn<DateTime>(
    'assigned_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releasedAtMeta = const VerificationMeta(
    'releasedAt',
  );
  @override
  late final GeneratedColumn<DateTime> releasedAt = GeneratedColumn<DateTime>(
    'released_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assignmentId,
    businessId,
    jobId,
    employeeId,
    employeeName,
    position,
    active,
    assignedAt,
    releasedAt,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_job_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalJobAssignment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('assignment_id')) {
      context.handle(
        _assignmentIdMeta,
        assignmentId.isAcceptableOrUnknown(
          data['assignment_id']!,
          _assignmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('employee_id')) {
      context.handle(
        _employeeIdMeta,
        employeeId.isAcceptableOrUnknown(data['employee_id']!, _employeeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_employeeIdMeta);
    }
    if (data.containsKey('employee_name')) {
      context.handle(
        _employeeNameMeta,
        employeeName.isAcceptableOrUnknown(
          data['employee_name']!,
          _employeeNameMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('assigned_at')) {
      context.handle(
        _assignedAtMeta,
        assignedAt.isAcceptableOrUnknown(data['assigned_at']!, _assignedAtMeta),
      );
    }
    if (data.containsKey('released_at')) {
      context.handle(
        _releasedAtMeta,
        releasedAt.isAcceptableOrUnknown(data['released_at']!, _releasedAtMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assignmentId};
  @override
  LocalJobAssignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJobAssignment(
      assignmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignment_id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      employeeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}employee_id'],
      )!,
      employeeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}employee_name'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      assignedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}assigned_at'],
      ),
      releasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}released_at'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
    );
  }

  @override
  $LocalJobAssignmentsTable createAlias(String alias) {
    return $LocalJobAssignmentsTable(attachedDatabase, alias);
  }
}

class LocalJobAssignment extends DataClass
    implements Insertable<LocalJobAssignment> {
  final String assignmentId;
  final String businessId;
  final String jobId;
  final String employeeId;
  final String? employeeName;
  final String? position;
  final bool active;
  final DateTime? assignedAt;
  final DateTime? releasedAt;
  final String? source;
  const LocalJobAssignment({
    required this.assignmentId,
    required this.businessId,
    required this.jobId,
    required this.employeeId,
    this.employeeName,
    this.position,
    required this.active,
    this.assignedAt,
    this.releasedAt,
    this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['assignment_id'] = Variable<String>(assignmentId);
    map['business_id'] = Variable<String>(businessId);
    map['job_id'] = Variable<String>(jobId);
    map['employee_id'] = Variable<String>(employeeId);
    if (!nullToAbsent || employeeName != null) {
      map['employee_name'] = Variable<String>(employeeName);
    }
    if (!nullToAbsent || position != null) {
      map['position'] = Variable<String>(position);
    }
    map['active'] = Variable<bool>(active);
    if (!nullToAbsent || assignedAt != null) {
      map['assigned_at'] = Variable<DateTime>(assignedAt);
    }
    if (!nullToAbsent || releasedAt != null) {
      map['released_at'] = Variable<DateTime>(releasedAt);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    return map;
  }

  LocalJobAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalJobAssignmentsCompanion(
      assignmentId: Value(assignmentId),
      businessId: Value(businessId),
      jobId: Value(jobId),
      employeeId: Value(employeeId),
      employeeName: employeeName == null && nullToAbsent
          ? const Value.absent()
          : Value(employeeName),
      position: position == null && nullToAbsent
          ? const Value.absent()
          : Value(position),
      active: Value(active),
      assignedAt: assignedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedAt),
      releasedAt: releasedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedAt),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
    );
  }

  factory LocalJobAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJobAssignment(
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      businessId: serializer.fromJson<String>(json['businessId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      employeeId: serializer.fromJson<String>(json['employeeId']),
      employeeName: serializer.fromJson<String?>(json['employeeName']),
      position: serializer.fromJson<String?>(json['position']),
      active: serializer.fromJson<bool>(json['active']),
      assignedAt: serializer.fromJson<DateTime?>(json['assignedAt']),
      releasedAt: serializer.fromJson<DateTime?>(json['releasedAt']),
      source: serializer.fromJson<String?>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assignmentId': serializer.toJson<String>(assignmentId),
      'businessId': serializer.toJson<String>(businessId),
      'jobId': serializer.toJson<String>(jobId),
      'employeeId': serializer.toJson<String>(employeeId),
      'employeeName': serializer.toJson<String?>(employeeName),
      'position': serializer.toJson<String?>(position),
      'active': serializer.toJson<bool>(active),
      'assignedAt': serializer.toJson<DateTime?>(assignedAt),
      'releasedAt': serializer.toJson<DateTime?>(releasedAt),
      'source': serializer.toJson<String?>(source),
    };
  }

  LocalJobAssignment copyWith({
    String? assignmentId,
    String? businessId,
    String? jobId,
    String? employeeId,
    Value<String?> employeeName = const Value.absent(),
    Value<String?> position = const Value.absent(),
    bool? active,
    Value<DateTime?> assignedAt = const Value.absent(),
    Value<DateTime?> releasedAt = const Value.absent(),
    Value<String?> source = const Value.absent(),
  }) => LocalJobAssignment(
    assignmentId: assignmentId ?? this.assignmentId,
    businessId: businessId ?? this.businessId,
    jobId: jobId ?? this.jobId,
    employeeId: employeeId ?? this.employeeId,
    employeeName: employeeName.present ? employeeName.value : this.employeeName,
    position: position.present ? position.value : this.position,
    active: active ?? this.active,
    assignedAt: assignedAt.present ? assignedAt.value : this.assignedAt,
    releasedAt: releasedAt.present ? releasedAt.value : this.releasedAt,
    source: source.present ? source.value : this.source,
  );
  LocalJobAssignment copyWithCompanion(LocalJobAssignmentsCompanion data) {
    return LocalJobAssignment(
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      employeeId: data.employeeId.present
          ? data.employeeId.value
          : this.employeeId,
      employeeName: data.employeeName.present
          ? data.employeeName.value
          : this.employeeName,
      position: data.position.present ? data.position.value : this.position,
      active: data.active.present ? data.active.value : this.active,
      assignedAt: data.assignedAt.present
          ? data.assignedAt.value
          : this.assignedAt,
      releasedAt: data.releasedAt.present
          ? data.releasedAt.value
          : this.releasedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobAssignment(')
          ..write('assignmentId: $assignmentId, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('employeeId: $employeeId, ')
          ..write('employeeName: $employeeName, ')
          ..write('position: $position, ')
          ..write('active: $active, ')
          ..write('assignedAt: $assignedAt, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assignmentId,
    businessId,
    jobId,
    employeeId,
    employeeName,
    position,
    active,
    assignedAt,
    releasedAt,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJobAssignment &&
          other.assignmentId == this.assignmentId &&
          other.businessId == this.businessId &&
          other.jobId == this.jobId &&
          other.employeeId == this.employeeId &&
          other.employeeName == this.employeeName &&
          other.position == this.position &&
          other.active == this.active &&
          other.assignedAt == this.assignedAt &&
          other.releasedAt == this.releasedAt &&
          other.source == this.source);
}

class LocalJobAssignmentsCompanion extends UpdateCompanion<LocalJobAssignment> {
  final Value<String> assignmentId;
  final Value<String> businessId;
  final Value<String> jobId;
  final Value<String> employeeId;
  final Value<String?> employeeName;
  final Value<String?> position;
  final Value<bool> active;
  final Value<DateTime?> assignedAt;
  final Value<DateTime?> releasedAt;
  final Value<String?> source;
  final Value<int> rowid;
  const LocalJobAssignmentsCompanion({
    this.assignmentId = const Value.absent(),
    this.businessId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.employeeId = const Value.absent(),
    this.employeeName = const Value.absent(),
    this.position = const Value.absent(),
    this.active = const Value.absent(),
    this.assignedAt = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobAssignmentsCompanion.insert({
    required String assignmentId,
    required String businessId,
    required String jobId,
    required String employeeId,
    this.employeeName = const Value.absent(),
    this.position = const Value.absent(),
    this.active = const Value.absent(),
    this.assignedAt = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assignmentId = Value(assignmentId),
       businessId = Value(businessId),
       jobId = Value(jobId),
       employeeId = Value(employeeId);
  static Insertable<LocalJobAssignment> custom({
    Expression<String>? assignmentId,
    Expression<String>? businessId,
    Expression<String>? jobId,
    Expression<String>? employeeId,
    Expression<String>? employeeName,
    Expression<String>? position,
    Expression<bool>? active,
    Expression<DateTime>? assignedAt,
    Expression<DateTime>? releasedAt,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (businessId != null) 'business_id': businessId,
      if (jobId != null) 'job_id': jobId,
      if (employeeId != null) 'employee_id': employeeId,
      if (employeeName != null) 'employee_name': employeeName,
      if (position != null) 'position': position,
      if (active != null) 'active': active,
      if (assignedAt != null) 'assigned_at': assignedAt,
      if (releasedAt != null) 'released_at': releasedAt,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobAssignmentsCompanion copyWith({
    Value<String>? assignmentId,
    Value<String>? businessId,
    Value<String>? jobId,
    Value<String>? employeeId,
    Value<String?>? employeeName,
    Value<String?>? position,
    Value<bool>? active,
    Value<DateTime?>? assignedAt,
    Value<DateTime?>? releasedAt,
    Value<String?>? source,
    Value<int>? rowid,
  }) {
    return LocalJobAssignmentsCompanion(
      assignmentId: assignmentId ?? this.assignmentId,
      businessId: businessId ?? this.businessId,
      jobId: jobId ?? this.jobId,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      position: position ?? this.position,
      active: active ?? this.active,
      assignedAt: assignedAt ?? this.assignedAt,
      releasedAt: releasedAt ?? this.releasedAt,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (employeeId.present) {
      map['employee_id'] = Variable<String>(employeeId.value);
    }
    if (employeeName.present) {
      map['employee_name'] = Variable<String>(employeeName.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (assignedAt.present) {
      map['assigned_at'] = Variable<DateTime>(assignedAt.value);
    }
    if (releasedAt.present) {
      map['released_at'] = Variable<DateTime>(releasedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobAssignmentsCompanion(')
          ..write('assignmentId: $assignmentId, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('employeeId: $employeeId, ')
          ..write('employeeName: $employeeName, ')
          ..write('position: $position, ')
          ..write('active: $active, ')
          ..write('assignedAt: $assignedAt, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalJobVisitsTable extends LocalJobVisits
    with TableInfo<$LocalJobVisitsTable, LocalJobVisit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobVisitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _visitNumberMeta = const VerificationMeta(
    'visitNumber',
  );
  @override
  late final GeneratedColumn<int> visitNumber = GeneratedColumn<int>(
    'visit_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedHoursMeta = const VerificationMeta(
    'plannedHours',
  );
  @override
  late final GeneratedColumn<double> plannedHours = GeneratedColumn<double>(
    'planned_hours',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _workSummaryMeta = const VerificationMeta(
    'workSummary',
  );
  @override
  late final GeneratedColumn<String> workSummary = GeneratedColumn<String>(
    'work_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    jobId,
    visitNumber,
    reason,
    plannedHours,
    workSummary,
    openedAt,
    closedAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_job_visits';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalJobVisit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('visit_number')) {
      context.handle(
        _visitNumberMeta,
        visitNumber.isAcceptableOrUnknown(
          data['visit_number']!,
          _visitNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_visitNumberMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('planned_hours')) {
      context.handle(
        _plannedHoursMeta,
        plannedHours.isAcceptableOrUnknown(
          data['planned_hours']!,
          _plannedHoursMeta,
        ),
      );
    }
    if (data.containsKey('work_summary')) {
      context.handle(
        _workSummaryMeta,
        workSummary.isAcceptableOrUnknown(
          data['work_summary']!,
          _workSummaryMeta,
        ),
      );
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalJobVisit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJobVisit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      visitNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}visit_number'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      plannedHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}planned_hours'],
      )!,
      workSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_summary'],
      ),
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      ),
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalJobVisitsTable createAlias(String alias) {
    return $LocalJobVisitsTable(attachedDatabase, alias);
  }
}

class LocalJobVisit extends DataClass implements Insertable<LocalJobVisit> {
  final String id;
  final String businessId;
  final String jobId;
  final int visitNumber;
  final String? reason;
  final double plannedHours;
  final String? workSummary;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalJobVisit({
    required this.id,
    required this.businessId,
    required this.jobId,
    required this.visitNumber,
    this.reason,
    required this.plannedHours,
    this.workSummary,
    this.openedAt,
    this.closedAt,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['job_id'] = Variable<String>(jobId);
    map['visit_number'] = Variable<int>(visitNumber);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['planned_hours'] = Variable<double>(plannedHours);
    if (!nullToAbsent || workSummary != null) {
      map['work_summary'] = Variable<String>(workSummary);
    }
    if (!nullToAbsent || openedAt != null) {
      map['opened_at'] = Variable<DateTime>(openedAt);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalJobVisitsCompanion toCompanion(bool nullToAbsent) {
    return LocalJobVisitsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      jobId: Value(jobId),
      visitNumber: Value(visitNumber),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      plannedHours: Value(plannedHours),
      workSummary: workSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(workSummary),
      openedAt: openedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(openedAt),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalJobVisit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJobVisit(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      visitNumber: serializer.fromJson<int>(json['visitNumber']),
      reason: serializer.fromJson<String?>(json['reason']),
      plannedHours: serializer.fromJson<double>(json['plannedHours']),
      workSummary: serializer.fromJson<String?>(json['workSummary']),
      openedAt: serializer.fromJson<DateTime?>(json['openedAt']),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'jobId': serializer.toJson<String>(jobId),
      'visitNumber': serializer.toJson<int>(visitNumber),
      'reason': serializer.toJson<String?>(reason),
      'plannedHours': serializer.toJson<double>(plannedHours),
      'workSummary': serializer.toJson<String?>(workSummary),
      'openedAt': serializer.toJson<DateTime?>(openedAt),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalJobVisit copyWith({
    String? id,
    String? businessId,
    String? jobId,
    int? visitNumber,
    Value<String?> reason = const Value.absent(),
    double? plannedHours,
    Value<String?> workSummary = const Value.absent(),
    Value<DateTime?> openedAt = const Value.absent(),
    Value<DateTime?> closedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalJobVisit(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    jobId: jobId ?? this.jobId,
    visitNumber: visitNumber ?? this.visitNumber,
    reason: reason.present ? reason.value : this.reason,
    plannedHours: plannedHours ?? this.plannedHours,
    workSummary: workSummary.present ? workSummary.value : this.workSummary,
    openedAt: openedAt.present ? openedAt.value : this.openedAt,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalJobVisit copyWithCompanion(LocalJobVisitsCompanion data) {
    return LocalJobVisit(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      visitNumber: data.visitNumber.present
          ? data.visitNumber.value
          : this.visitNumber,
      reason: data.reason.present ? data.reason.value : this.reason,
      plannedHours: data.plannedHours.present
          ? data.plannedHours.value
          : this.plannedHours,
      workSummary: data.workSummary.present
          ? data.workSummary.value
          : this.workSummary,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobVisit(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('visitNumber: $visitNumber, ')
          ..write('reason: $reason, ')
          ..write('plannedHours: $plannedHours, ')
          ..write('workSummary: $workSummary, ')
          ..write('openedAt: $openedAt, ')
          ..write('closedAt: $closedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    jobId,
    visitNumber,
    reason,
    plannedHours,
    workSummary,
    openedAt,
    closedAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJobVisit &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.jobId == this.jobId &&
          other.visitNumber == this.visitNumber &&
          other.reason == this.reason &&
          other.plannedHours == this.plannedHours &&
          other.workSummary == this.workSummary &&
          other.openedAt == this.openedAt &&
          other.closedAt == this.closedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalJobVisitsCompanion extends UpdateCompanion<LocalJobVisit> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> jobId;
  final Value<int> visitNumber;
  final Value<String?> reason;
  final Value<double> plannedHours;
  final Value<String?> workSummary;
  final Value<DateTime?> openedAt;
  final Value<DateTime?> closedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalJobVisitsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.visitNumber = const Value.absent(),
    this.reason = const Value.absent(),
    this.plannedHours = const Value.absent(),
    this.workSummary = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobVisitsCompanion.insert({
    required String id,
    required String businessId,
    required String jobId,
    required int visitNumber,
    this.reason = const Value.absent(),
    this.plannedHours = const Value.absent(),
    this.workSummary = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       jobId = Value(jobId),
       visitNumber = Value(visitNumber);
  static Insertable<LocalJobVisit> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? jobId,
    Expression<int>? visitNumber,
    Expression<String>? reason,
    Expression<double>? plannedHours,
    Expression<String>? workSummary,
    Expression<DateTime>? openedAt,
    Expression<DateTime>? closedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (jobId != null) 'job_id': jobId,
      if (visitNumber != null) 'visit_number': visitNumber,
      if (reason != null) 'reason': reason,
      if (plannedHours != null) 'planned_hours': plannedHours,
      if (workSummary != null) 'work_summary': workSummary,
      if (openedAt != null) 'opened_at': openedAt,
      if (closedAt != null) 'closed_at': closedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobVisitsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? jobId,
    Value<int>? visitNumber,
    Value<String?>? reason,
    Value<double>? plannedHours,
    Value<String?>? workSummary,
    Value<DateTime?>? openedAt,
    Value<DateTime?>? closedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalJobVisitsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      jobId: jobId ?? this.jobId,
      visitNumber: visitNumber ?? this.visitNumber,
      reason: reason ?? this.reason,
      plannedHours: plannedHours ?? this.plannedHours,
      workSummary: workSummary ?? this.workSummary,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt ?? this.closedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (visitNumber.present) {
      map['visit_number'] = Variable<int>(visitNumber.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (plannedHours.present) {
      map['planned_hours'] = Variable<double>(plannedHours.value);
    }
    if (workSummary.present) {
      map['work_summary'] = Variable<String>(workSummary.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobVisitsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('visitNumber: $visitNumber, ')
          ..write('reason: $reason, ')
          ..write('plannedHours: $plannedHours, ')
          ..write('workSummary: $workSummary, ')
          ..write('openedAt: $openedAt, ')
          ..write('closedAt: $closedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPreInspectionsTable extends LocalPreInspections
    with TableInfo<$LocalPreInspectionsTable, LocalPreInspection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPreInspectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inspectedAtMeta = const VerificationMeta(
    'inspectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> inspectedAt = GeneratedColumn<DateTime>(
    'inspected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _odometerMeta = const VerificationMeta(
    'odometer',
  );
  @override
  late final GeneratedColumn<double> odometer = GeneratedColumn<double>(
    'odometer',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    jobId,
    vehicleId,
    inspectedAt,
    odometer,
    notes,
    createdBy,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_pre_inspections';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPreInspection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    }
    if (data.containsKey('inspected_at')) {
      context.handle(
        _inspectedAtMeta,
        inspectedAt.isAcceptableOrUnknown(
          data['inspected_at']!,
          _inspectedAtMeta,
        ),
      );
    }
    if (data.containsKey('odometer')) {
      context.handle(
        _odometerMeta,
        odometer.isAcceptableOrUnknown(data['odometer']!, _odometerMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPreInspection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPreInspection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      ),
      inspectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}inspected_at'],
      ),
      odometer: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}odometer'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalPreInspectionsTable createAlias(String alias) {
    return $LocalPreInspectionsTable(attachedDatabase, alias);
  }
}

class LocalPreInspection extends DataClass
    implements Insertable<LocalPreInspection> {
  final String id;
  final String businessId;
  final String jobId;
  final String? vehicleId;
  final DateTime? inspectedAt;
  final double? odometer;
  final String? notes;
  final String? createdBy;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalPreInspection({
    required this.id,
    required this.businessId,
    required this.jobId,
    this.vehicleId,
    this.inspectedAt,
    this.odometer,
    this.notes,
    this.createdBy,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['job_id'] = Variable<String>(jobId);
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    if (!nullToAbsent || inspectedAt != null) {
      map['inspected_at'] = Variable<DateTime>(inspectedAt);
    }
    if (!nullToAbsent || odometer != null) {
      map['odometer'] = Variable<double>(odometer);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalPreInspectionsCompanion toCompanion(bool nullToAbsent) {
    return LocalPreInspectionsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      jobId: Value(jobId),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      inspectedAt: inspectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(inspectedAt),
      odometer: odometer == null && nullToAbsent
          ? const Value.absent()
          : Value(odometer),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalPreInspection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPreInspection(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      inspectedAt: serializer.fromJson<DateTime?>(json['inspectedAt']),
      odometer: serializer.fromJson<double?>(json['odometer']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'jobId': serializer.toJson<String>(jobId),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'inspectedAt': serializer.toJson<DateTime?>(inspectedAt),
      'odometer': serializer.toJson<double?>(odometer),
      'notes': serializer.toJson<String?>(notes),
      'createdBy': serializer.toJson<String?>(createdBy),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalPreInspection copyWith({
    String? id,
    String? businessId,
    String? jobId,
    Value<String?> vehicleId = const Value.absent(),
    Value<DateTime?> inspectedAt = const Value.absent(),
    Value<double?> odometer = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalPreInspection(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    jobId: jobId ?? this.jobId,
    vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
    inspectedAt: inspectedAt.present ? inspectedAt.value : this.inspectedAt,
    odometer: odometer.present ? odometer.value : this.odometer,
    notes: notes.present ? notes.value : this.notes,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalPreInspection copyWithCompanion(LocalPreInspectionsCompanion data) {
    return LocalPreInspection(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      inspectedAt: data.inspectedAt.present
          ? data.inspectedAt.value
          : this.inspectedAt,
      odometer: data.odometer.present ? data.odometer.value : this.odometer,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreInspection(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('inspectedAt: $inspectedAt, ')
          ..write('odometer: $odometer, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    jobId,
    vehicleId,
    inspectedAt,
    odometer,
    notes,
    createdBy,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPreInspection &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.jobId == this.jobId &&
          other.vehicleId == this.vehicleId &&
          other.inspectedAt == this.inspectedAt &&
          other.odometer == this.odometer &&
          other.notes == this.notes &&
          other.createdBy == this.createdBy &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalPreInspectionsCompanion extends UpdateCompanion<LocalPreInspection> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> jobId;
  final Value<String?> vehicleId;
  final Value<DateTime?> inspectedAt;
  final Value<double?> odometer;
  final Value<String?> notes;
  final Value<String?> createdBy;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalPreInspectionsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.inspectedAt = const Value.absent(),
    this.odometer = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPreInspectionsCompanion.insert({
    required String id,
    required String businessId,
    required String jobId,
    this.vehicleId = const Value.absent(),
    this.inspectedAt = const Value.absent(),
    this.odometer = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       jobId = Value(jobId);
  static Insertable<LocalPreInspection> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? jobId,
    Expression<String>? vehicleId,
    Expression<DateTime>? inspectedAt,
    Expression<double>? odometer,
    Expression<String>? notes,
    Expression<String>? createdBy,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (jobId != null) 'job_id': jobId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (inspectedAt != null) 'inspected_at': inspectedAt,
      if (odometer != null) 'odometer': odometer,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPreInspectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? jobId,
    Value<String?>? vehicleId,
    Value<DateTime?>? inspectedAt,
    Value<double?>? odometer,
    Value<String?>? notes,
    Value<String?>? createdBy,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalPreInspectionsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      jobId: jobId ?? this.jobId,
      vehicleId: vehicleId ?? this.vehicleId,
      inspectedAt: inspectedAt ?? this.inspectedAt,
      odometer: odometer ?? this.odometer,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (inspectedAt.present) {
      map['inspected_at'] = Variable<DateTime>(inspectedAt.value);
    }
    if (odometer.present) {
      map['odometer'] = Variable<double>(odometer.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreInspectionsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('inspectedAt: $inspectedAt, ')
          ..write('odometer: $odometer, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPreInspectionPhotosTable extends LocalPreInspectionPhotos
    with TableInfo<$LocalPreInspectionPhotosTable, LocalPreInspectionPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPreInspectionPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inspectionIdMeta = const VerificationMeta(
    'inspectionId',
  );
  @override
  late final GeneratedColumn<String> inspectionId = GeneratedColumn<String>(
    'inspection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachmentIdMeta = const VerificationMeta(
    'attachmentId',
  );
  @override
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageBucketMeta = const VerificationMeta(
    'storageBucket',
  );
  @override
  late final GeneratedColumn<String> storageBucket = GeneratedColumn<String>(
    'storage_bucket',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageKeyMeta = const VerificationMeta(
    'storageKey',
  );
  @override
  late final GeneratedColumn<String> storageKey = GeneratedColumn<String>(
    'storage_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canEditNoteMeta = const VerificationMeta(
    'canEditNote',
  );
  @override
  late final GeneratedColumn<bool> canEditNote = GeneratedColumn<bool>(
    'can_edit_note',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_edit_note" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _canDeleteMeta = const VerificationMeta(
    'canDelete',
  );
  @override
  late final GeneratedColumn<bool> canDelete = GeneratedColumn<bool>(
    'can_delete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_delete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<String> uploadState = GeneratedColumn<String>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    inspectionId,
    attachmentId,
    localFilePath,
    storageBucket,
    storageKey,
    filename,
    mimeType,
    byteSize,
    capturedAt,
    note,
    createdBy,
    canEditNote,
    canDelete,
    uploadState,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_pre_inspection_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPreInspectionPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('inspection_id')) {
      context.handle(
        _inspectionIdMeta,
        inspectionId.isAcceptableOrUnknown(
          data['inspection_id']!,
          _inspectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inspectionIdMeta);
    }
    if (data.containsKey('attachment_id')) {
      context.handle(
        _attachmentIdMeta,
        attachmentId.isAcceptableOrUnknown(
          data['attachment_id']!,
          _attachmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentIdMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    }
    if (data.containsKey('storage_bucket')) {
      context.handle(
        _storageBucketMeta,
        storageBucket.isAcceptableOrUnknown(
          data['storage_bucket']!,
          _storageBucketMeta,
        ),
      );
    }
    if (data.containsKey('storage_key')) {
      context.handle(
        _storageKeyMeta,
        storageKey.isAcceptableOrUnknown(data['storage_key']!, _storageKeyMeta),
      );
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('can_edit_note')) {
      context.handle(
        _canEditNoteMeta,
        canEditNote.isAcceptableOrUnknown(
          data['can_edit_note']!,
          _canEditNoteMeta,
        ),
      );
    }
    if (data.containsKey('can_delete')) {
      context.handle(
        _canDeleteMeta,
        canDelete.isAcceptableOrUnknown(data['can_delete']!, _canDeleteMeta),
      );
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPreInspectionPhoto map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPreInspectionPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      inspectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inspection_id'],
      )!,
      attachmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_id'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      ),
      storageBucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_bucket'],
      ),
      storageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_key'],
      ),
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      canEditNote: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_edit_note'],
      )!,
      canDelete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_delete'],
      )!,
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $LocalPreInspectionPhotosTable createAlias(String alias) {
    return $LocalPreInspectionPhotosTable(attachedDatabase, alias);
  }
}

class LocalPreInspectionPhoto extends DataClass
    implements Insertable<LocalPreInspectionPhoto> {
  final String id;
  final String businessId;
  final String inspectionId;
  final String attachmentId;
  final String? localFilePath;
  final String? storageBucket;
  final String? storageKey;
  final String? filename;
  final String? mimeType;
  final int? byteSize;
  final DateTime? capturedAt;
  final String? note;
  final String? createdBy;
  final bool canEditNote;
  final bool canDelete;
  final String uploadState;
  final String? lastError;
  const LocalPreInspectionPhoto({
    required this.id,
    required this.businessId,
    required this.inspectionId,
    required this.attachmentId,
    this.localFilePath,
    this.storageBucket,
    this.storageKey,
    this.filename,
    this.mimeType,
    this.byteSize,
    this.capturedAt,
    this.note,
    this.createdBy,
    required this.canEditNote,
    required this.canDelete,
    required this.uploadState,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['inspection_id'] = Variable<String>(inspectionId);
    map['attachment_id'] = Variable<String>(attachmentId);
    if (!nullToAbsent || localFilePath != null) {
      map['local_file_path'] = Variable<String>(localFilePath);
    }
    if (!nullToAbsent || storageBucket != null) {
      map['storage_bucket'] = Variable<String>(storageBucket);
    }
    if (!nullToAbsent || storageKey != null) {
      map['storage_key'] = Variable<String>(storageKey);
    }
    if (!nullToAbsent || filename != null) {
      map['filename'] = Variable<String>(filename);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || byteSize != null) {
      map['byte_size'] = Variable<int>(byteSize);
    }
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['can_edit_note'] = Variable<bool>(canEditNote);
    map['can_delete'] = Variable<bool>(canDelete);
    map['upload_state'] = Variable<String>(uploadState);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  LocalPreInspectionPhotosCompanion toCompanion(bool nullToAbsent) {
    return LocalPreInspectionPhotosCompanion(
      id: Value(id),
      businessId: Value(businessId),
      inspectionId: Value(inspectionId),
      attachmentId: Value(attachmentId),
      localFilePath: localFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localFilePath),
      storageBucket: storageBucket == null && nullToAbsent
          ? const Value.absent()
          : Value(storageBucket),
      storageKey: storageKey == null && nullToAbsent
          ? const Value.absent()
          : Value(storageKey),
      filename: filename == null && nullToAbsent
          ? const Value.absent()
          : Value(filename),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      byteSize: byteSize == null && nullToAbsent
          ? const Value.absent()
          : Value(byteSize),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      canEditNote: Value(canEditNote),
      canDelete: Value(canDelete),
      uploadState: Value(uploadState),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory LocalPreInspectionPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPreInspectionPhoto(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      inspectionId: serializer.fromJson<String>(json['inspectionId']),
      attachmentId: serializer.fromJson<String>(json['attachmentId']),
      localFilePath: serializer.fromJson<String?>(json['localFilePath']),
      storageBucket: serializer.fromJson<String?>(json['storageBucket']),
      storageKey: serializer.fromJson<String?>(json['storageKey']),
      filename: serializer.fromJson<String?>(json['filename']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      byteSize: serializer.fromJson<int?>(json['byteSize']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      note: serializer.fromJson<String?>(json['note']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      canEditNote: serializer.fromJson<bool>(json['canEditNote']),
      canDelete: serializer.fromJson<bool>(json['canDelete']),
      uploadState: serializer.fromJson<String>(json['uploadState']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'inspectionId': serializer.toJson<String>(inspectionId),
      'attachmentId': serializer.toJson<String>(attachmentId),
      'localFilePath': serializer.toJson<String?>(localFilePath),
      'storageBucket': serializer.toJson<String?>(storageBucket),
      'storageKey': serializer.toJson<String?>(storageKey),
      'filename': serializer.toJson<String?>(filename),
      'mimeType': serializer.toJson<String?>(mimeType),
      'byteSize': serializer.toJson<int?>(byteSize),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'note': serializer.toJson<String?>(note),
      'createdBy': serializer.toJson<String?>(createdBy),
      'canEditNote': serializer.toJson<bool>(canEditNote),
      'canDelete': serializer.toJson<bool>(canDelete),
      'uploadState': serializer.toJson<String>(uploadState),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  LocalPreInspectionPhoto copyWith({
    String? id,
    String? businessId,
    String? inspectionId,
    String? attachmentId,
    Value<String?> localFilePath = const Value.absent(),
    Value<String?> storageBucket = const Value.absent(),
    Value<String?> storageKey = const Value.absent(),
    Value<String?> filename = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<int?> byteSize = const Value.absent(),
    Value<DateTime?> capturedAt = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    bool? canEditNote,
    bool? canDelete,
    String? uploadState,
    Value<String?> lastError = const Value.absent(),
  }) => LocalPreInspectionPhoto(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    inspectionId: inspectionId ?? this.inspectionId,
    attachmentId: attachmentId ?? this.attachmentId,
    localFilePath: localFilePath.present
        ? localFilePath.value
        : this.localFilePath,
    storageBucket: storageBucket.present
        ? storageBucket.value
        : this.storageBucket,
    storageKey: storageKey.present ? storageKey.value : this.storageKey,
    filename: filename.present ? filename.value : this.filename,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    byteSize: byteSize.present ? byteSize.value : this.byteSize,
    capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
    note: note.present ? note.value : this.note,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    canEditNote: canEditNote ?? this.canEditNote,
    canDelete: canDelete ?? this.canDelete,
    uploadState: uploadState ?? this.uploadState,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  LocalPreInspectionPhoto copyWithCompanion(
    LocalPreInspectionPhotosCompanion data,
  ) {
    return LocalPreInspectionPhoto(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      inspectionId: data.inspectionId.present
          ? data.inspectionId.value
          : this.inspectionId,
      attachmentId: data.attachmentId.present
          ? data.attachmentId.value
          : this.attachmentId,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      storageBucket: data.storageBucket.present
          ? data.storageBucket.value
          : this.storageBucket,
      storageKey: data.storageKey.present
          ? data.storageKey.value
          : this.storageKey,
      filename: data.filename.present ? data.filename.value : this.filename,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      note: data.note.present ? data.note.value : this.note,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      canEditNote: data.canEditNote.present
          ? data.canEditNote.value
          : this.canEditNote,
      canDelete: data.canDelete.present ? data.canDelete.value : this.canDelete,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreInspectionPhoto(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('inspectionId: $inspectionId, ')
          ..write('attachmentId: $attachmentId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storageKey: $storageKey, ')
          ..write('filename: $filename, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('note: $note, ')
          ..write('createdBy: $createdBy, ')
          ..write('canEditNote: $canEditNote, ')
          ..write('canDelete: $canDelete, ')
          ..write('uploadState: $uploadState, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    inspectionId,
    attachmentId,
    localFilePath,
    storageBucket,
    storageKey,
    filename,
    mimeType,
    byteSize,
    capturedAt,
    note,
    createdBy,
    canEditNote,
    canDelete,
    uploadState,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPreInspectionPhoto &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.inspectionId == this.inspectionId &&
          other.attachmentId == this.attachmentId &&
          other.localFilePath == this.localFilePath &&
          other.storageBucket == this.storageBucket &&
          other.storageKey == this.storageKey &&
          other.filename == this.filename &&
          other.mimeType == this.mimeType &&
          other.byteSize == this.byteSize &&
          other.capturedAt == this.capturedAt &&
          other.note == this.note &&
          other.createdBy == this.createdBy &&
          other.canEditNote == this.canEditNote &&
          other.canDelete == this.canDelete &&
          other.uploadState == this.uploadState &&
          other.lastError == this.lastError);
}

class LocalPreInspectionPhotosCompanion
    extends UpdateCompanion<LocalPreInspectionPhoto> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> inspectionId;
  final Value<String> attachmentId;
  final Value<String?> localFilePath;
  final Value<String?> storageBucket;
  final Value<String?> storageKey;
  final Value<String?> filename;
  final Value<String?> mimeType;
  final Value<int?> byteSize;
  final Value<DateTime?> capturedAt;
  final Value<String?> note;
  final Value<String?> createdBy;
  final Value<bool> canEditNote;
  final Value<bool> canDelete;
  final Value<String> uploadState;
  final Value<String?> lastError;
  final Value<int> rowid;
  const LocalPreInspectionPhotosCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.inspectionId = const Value.absent(),
    this.attachmentId = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.filename = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.canEditNote = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPreInspectionPhotosCompanion.insert({
    required String id,
    required String businessId,
    required String inspectionId,
    required String attachmentId,
    this.localFilePath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.filename = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.canEditNote = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       inspectionId = Value(inspectionId),
       attachmentId = Value(attachmentId);
  static Insertable<LocalPreInspectionPhoto> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? inspectionId,
    Expression<String>? attachmentId,
    Expression<String>? localFilePath,
    Expression<String>? storageBucket,
    Expression<String>? storageKey,
    Expression<String>? filename,
    Expression<String>? mimeType,
    Expression<int>? byteSize,
    Expression<DateTime>? capturedAt,
    Expression<String>? note,
    Expression<String>? createdBy,
    Expression<bool>? canEditNote,
    Expression<bool>? canDelete,
    Expression<String>? uploadState,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (inspectionId != null) 'inspection_id': inspectionId,
      if (attachmentId != null) 'attachment_id': attachmentId,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (storageBucket != null) 'storage_bucket': storageBucket,
      if (storageKey != null) 'storage_key': storageKey,
      if (filename != null) 'filename': filename,
      if (mimeType != null) 'mime_type': mimeType,
      if (byteSize != null) 'byte_size': byteSize,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (note != null) 'note': note,
      if (createdBy != null) 'created_by': createdBy,
      if (canEditNote != null) 'can_edit_note': canEditNote,
      if (canDelete != null) 'can_delete': canDelete,
      if (uploadState != null) 'upload_state': uploadState,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPreInspectionPhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? inspectionId,
    Value<String>? attachmentId,
    Value<String?>? localFilePath,
    Value<String?>? storageBucket,
    Value<String?>? storageKey,
    Value<String?>? filename,
    Value<String?>? mimeType,
    Value<int?>? byteSize,
    Value<DateTime?>? capturedAt,
    Value<String?>? note,
    Value<String?>? createdBy,
    Value<bool>? canEditNote,
    Value<bool>? canDelete,
    Value<String>? uploadState,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return LocalPreInspectionPhotosCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      inspectionId: inspectionId ?? this.inspectionId,
      attachmentId: attachmentId ?? this.attachmentId,
      localFilePath: localFilePath ?? this.localFilePath,
      storageBucket: storageBucket ?? this.storageBucket,
      storageKey: storageKey ?? this.storageKey,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      capturedAt: capturedAt ?? this.capturedAt,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
      canEditNote: canEditNote ?? this.canEditNote,
      canDelete: canDelete ?? this.canDelete,
      uploadState: uploadState ?? this.uploadState,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (inspectionId.present) {
      map['inspection_id'] = Variable<String>(inspectionId.value);
    }
    if (attachmentId.present) {
      map['attachment_id'] = Variable<String>(attachmentId.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (storageBucket.present) {
      map['storage_bucket'] = Variable<String>(storageBucket.value);
    }
    if (storageKey.present) {
      map['storage_key'] = Variable<String>(storageKey.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (canEditNote.present) {
      map['can_edit_note'] = Variable<bool>(canEditNote.value);
    }
    if (canDelete.present) {
      map['can_delete'] = Variable<bool>(canDelete.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<String>(uploadState.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPreInspectionPhotosCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('inspectionId: $inspectionId, ')
          ..write('attachmentId: $attachmentId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storageKey: $storageKey, ')
          ..write('filename: $filename, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('note: $note, ')
          ..write('createdBy: $createdBy, ')
          ..write('canEditNote: $canEditNote, ')
          ..write('canDelete: $canDelete, ')
          ..write('uploadState: $uploadState, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFindingsTable extends LocalFindings
    with TableInfo<$LocalFindingsTable, LocalFinding> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFindingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _foundJobIdMeta = const VerificationMeta(
    'foundJobId',
  );
  @override
  late final GeneratedColumn<String> foundJobId = GeneratedColumn<String>(
    'found_job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repairJobIdMeta = const VerificationMeta(
    'repairJobId',
  );
  @override
  late final GeneratedColumn<String> repairJobId = GeneratedColumn<String>(
    'repair_job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _includeOnInvoiceMeta = const VerificationMeta(
    'includeOnInvoice',
  );
  @override
  late final GeneratedColumn<bool> includeOnInvoice = GeneratedColumn<bool>(
    'include_on_invoice',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_on_invoice" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canEditMeta = const VerificationMeta(
    'canEdit',
  );
  @override
  late final GeneratedColumn<bool> canEdit = GeneratedColumn<bool>(
    'can_edit',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_edit" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _canDeleteMeta = const VerificationMeta(
    'canDelete',
  );
  @override
  late final GeneratedColumn<bool> canDelete = GeneratedColumn<bool>(
    'can_delete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_delete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    vehicleId,
    foundJobId,
    repairJobId,
    body,
    status,
    includeOnInvoice,
    createdAt,
    resolvedAt,
    createdBy,
    canEdit,
    canDelete,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_findings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFinding> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    }
    if (data.containsKey('found_job_id')) {
      context.handle(
        _foundJobIdMeta,
        foundJobId.isAcceptableOrUnknown(
          data['found_job_id']!,
          _foundJobIdMeta,
        ),
      );
    }
    if (data.containsKey('repair_job_id')) {
      context.handle(
        _repairJobIdMeta,
        repairJobId.isAcceptableOrUnknown(
          data['repair_job_id']!,
          _repairJobIdMeta,
        ),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('include_on_invoice')) {
      context.handle(
        _includeOnInvoiceMeta,
        includeOnInvoice.isAcceptableOrUnknown(
          data['include_on_invoice']!,
          _includeOnInvoiceMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('can_edit')) {
      context.handle(
        _canEditMeta,
        canEdit.isAcceptableOrUnknown(data['can_edit']!, _canEditMeta),
      );
    }
    if (data.containsKey('can_delete')) {
      context.handle(
        _canDeleteMeta,
        canDelete.isAcceptableOrUnknown(data['can_delete']!, _canDeleteMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalFinding map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFinding(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      ),
      foundJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}found_job_id'],
      ),
      repairJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repair_job_id'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      includeOnInvoice: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_on_invoice'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      canEdit: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_edit'],
      )!,
      canDelete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_delete'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalFindingsTable createAlias(String alias) {
    return $LocalFindingsTable(attachedDatabase, alias);
  }
}

class LocalFinding extends DataClass implements Insertable<LocalFinding> {
  final String id;
  final String businessId;
  final String? vehicleId;
  final String? foundJobId;
  final String? repairJobId;
  final String body;
  final String status;
  final bool includeOnInvoice;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? createdBy;
  final bool canEdit;
  final bool canDelete;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalFinding({
    required this.id,
    required this.businessId,
    this.vehicleId,
    this.foundJobId,
    this.repairJobId,
    required this.body,
    required this.status,
    required this.includeOnInvoice,
    this.createdAt,
    this.resolvedAt,
    this.createdBy,
    required this.canEdit,
    required this.canDelete,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    if (!nullToAbsent || foundJobId != null) {
      map['found_job_id'] = Variable<String>(foundJobId);
    }
    if (!nullToAbsent || repairJobId != null) {
      map['repair_job_id'] = Variable<String>(repairJobId);
    }
    map['body'] = Variable<String>(body);
    map['status'] = Variable<String>(status);
    map['include_on_invoice'] = Variable<bool>(includeOnInvoice);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['can_edit'] = Variable<bool>(canEdit);
    map['can_delete'] = Variable<bool>(canDelete);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalFindingsCompanion toCompanion(bool nullToAbsent) {
    return LocalFindingsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      foundJobId: foundJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(foundJobId),
      repairJobId: repairJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(repairJobId),
      body: Value(body),
      status: Value(status),
      includeOnInvoice: Value(includeOnInvoice),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      canEdit: Value(canEdit),
      canDelete: Value(canDelete),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalFinding.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFinding(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      foundJobId: serializer.fromJson<String?>(json['foundJobId']),
      repairJobId: serializer.fromJson<String?>(json['repairJobId']),
      body: serializer.fromJson<String>(json['body']),
      status: serializer.fromJson<String>(json['status']),
      includeOnInvoice: serializer.fromJson<bool>(json['includeOnInvoice']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      canEdit: serializer.fromJson<bool>(json['canEdit']),
      canDelete: serializer.fromJson<bool>(json['canDelete']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'foundJobId': serializer.toJson<String?>(foundJobId),
      'repairJobId': serializer.toJson<String?>(repairJobId),
      'body': serializer.toJson<String>(body),
      'status': serializer.toJson<String>(status),
      'includeOnInvoice': serializer.toJson<bool>(includeOnInvoice),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'createdBy': serializer.toJson<String?>(createdBy),
      'canEdit': serializer.toJson<bool>(canEdit),
      'canDelete': serializer.toJson<bool>(canDelete),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalFinding copyWith({
    String? id,
    String? businessId,
    Value<String?> vehicleId = const Value.absent(),
    Value<String?> foundJobId = const Value.absent(),
    Value<String?> repairJobId = const Value.absent(),
    String? body,
    String? status,
    bool? includeOnInvoice,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> resolvedAt = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    bool? canEdit,
    bool? canDelete,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalFinding(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
    foundJobId: foundJobId.present ? foundJobId.value : this.foundJobId,
    repairJobId: repairJobId.present ? repairJobId.value : this.repairJobId,
    body: body ?? this.body,
    status: status ?? this.status,
    includeOnInvoice: includeOnInvoice ?? this.includeOnInvoice,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    canEdit: canEdit ?? this.canEdit,
    canDelete: canDelete ?? this.canDelete,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalFinding copyWithCompanion(LocalFindingsCompanion data) {
    return LocalFinding(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      foundJobId: data.foundJobId.present
          ? data.foundJobId.value
          : this.foundJobId,
      repairJobId: data.repairJobId.present
          ? data.repairJobId.value
          : this.repairJobId,
      body: data.body.present ? data.body.value : this.body,
      status: data.status.present ? data.status.value : this.status,
      includeOnInvoice: data.includeOnInvoice.present
          ? data.includeOnInvoice.value
          : this.includeOnInvoice,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      canEdit: data.canEdit.present ? data.canEdit.value : this.canEdit,
      canDelete: data.canDelete.present ? data.canDelete.value : this.canDelete,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFinding(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('foundJobId: $foundJobId, ')
          ..write('repairJobId: $repairJobId, ')
          ..write('body: $body, ')
          ..write('status: $status, ')
          ..write('includeOnInvoice: $includeOnInvoice, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('canEdit: $canEdit, ')
          ..write('canDelete: $canDelete, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    vehicleId,
    foundJobId,
    repairJobId,
    body,
    status,
    includeOnInvoice,
    createdAt,
    resolvedAt,
    createdBy,
    canEdit,
    canDelete,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFinding &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.vehicleId == this.vehicleId &&
          other.foundJobId == this.foundJobId &&
          other.repairJobId == this.repairJobId &&
          other.body == this.body &&
          other.status == this.status &&
          other.includeOnInvoice == this.includeOnInvoice &&
          other.createdAt == this.createdAt &&
          other.resolvedAt == this.resolvedAt &&
          other.createdBy == this.createdBy &&
          other.canEdit == this.canEdit &&
          other.canDelete == this.canDelete &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalFindingsCompanion extends UpdateCompanion<LocalFinding> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String?> vehicleId;
  final Value<String?> foundJobId;
  final Value<String?> repairJobId;
  final Value<String> body;
  final Value<String> status;
  final Value<bool> includeOnInvoice;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> resolvedAt;
  final Value<String?> createdBy;
  final Value<bool> canEdit;
  final Value<bool> canDelete;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalFindingsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.foundJobId = const Value.absent(),
    this.repairJobId = const Value.absent(),
    this.body = const Value.absent(),
    this.status = const Value.absent(),
    this.includeOnInvoice = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.canEdit = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFindingsCompanion.insert({
    required String id,
    required String businessId,
    this.vehicleId = const Value.absent(),
    this.foundJobId = const Value.absent(),
    this.repairJobId = const Value.absent(),
    required String body,
    required String status,
    this.includeOnInvoice = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.canEdit = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       body = Value(body),
       status = Value(status);
  static Insertable<LocalFinding> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? vehicleId,
    Expression<String>? foundJobId,
    Expression<String>? repairJobId,
    Expression<String>? body,
    Expression<String>? status,
    Expression<bool>? includeOnInvoice,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? resolvedAt,
    Expression<String>? createdBy,
    Expression<bool>? canEdit,
    Expression<bool>? canDelete,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (foundJobId != null) 'found_job_id': foundJobId,
      if (repairJobId != null) 'repair_job_id': repairJobId,
      if (body != null) 'body': body,
      if (status != null) 'status': status,
      if (includeOnInvoice != null) 'include_on_invoice': includeOnInvoice,
      if (createdAt != null) 'created_at': createdAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (createdBy != null) 'created_by': createdBy,
      if (canEdit != null) 'can_edit': canEdit,
      if (canDelete != null) 'can_delete': canDelete,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFindingsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String?>? vehicleId,
    Value<String?>? foundJobId,
    Value<String?>? repairJobId,
    Value<String>? body,
    Value<String>? status,
    Value<bool>? includeOnInvoice,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? resolvedAt,
    Value<String?>? createdBy,
    Value<bool>? canEdit,
    Value<bool>? canDelete,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalFindingsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      vehicleId: vehicleId ?? this.vehicleId,
      foundJobId: foundJobId ?? this.foundJobId,
      repairJobId: repairJobId ?? this.repairJobId,
      body: body ?? this.body,
      status: status ?? this.status,
      includeOnInvoice: includeOnInvoice ?? this.includeOnInvoice,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdBy: createdBy ?? this.createdBy,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (foundJobId.present) {
      map['found_job_id'] = Variable<String>(foundJobId.value);
    }
    if (repairJobId.present) {
      map['repair_job_id'] = Variable<String>(repairJobId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (includeOnInvoice.present) {
      map['include_on_invoice'] = Variable<bool>(includeOnInvoice.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (canEdit.present) {
      map['can_edit'] = Variable<bool>(canEdit.value);
    }
    if (canDelete.present) {
      map['can_delete'] = Variable<bool>(canDelete.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFindingsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('foundJobId: $foundJobId, ')
          ..write('repairJobId: $repairJobId, ')
          ..write('body: $body, ')
          ..write('status: $status, ')
          ..write('includeOnInvoice: $includeOnInvoice, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('canEdit: $canEdit, ')
          ..write('canDelete: $canDelete, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFindingPhotosTable extends LocalFindingPhotos
    with TableInfo<$LocalFindingPhotosTable, LocalFindingPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFindingPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _findingIdMeta = const VerificationMeta(
    'findingId',
  );
  @override
  late final GeneratedColumn<String> findingId = GeneratedColumn<String>(
    'finding_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachmentIdMeta = const VerificationMeta(
    'attachmentId',
  );
  @override
  late final GeneratedColumn<String> attachmentId = GeneratedColumn<String>(
    'attachment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageBucketMeta = const VerificationMeta(
    'storageBucket',
  );
  @override
  late final GeneratedColumn<String> storageBucket = GeneratedColumn<String>(
    'storage_bucket',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageKeyMeta = const VerificationMeta(
    'storageKey',
  );
  @override
  late final GeneratedColumn<String> storageKey = GeneratedColumn<String>(
    'storage_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canDeleteMeta = const VerificationMeta(
    'canDelete',
  );
  @override
  late final GeneratedColumn<bool> canDelete = GeneratedColumn<bool>(
    'can_delete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_delete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<String> uploadState = GeneratedColumn<String>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    findingId,
    attachmentId,
    localFilePath,
    storageBucket,
    storageKey,
    filename,
    mimeType,
    byteSize,
    capturedAt,
    canDelete,
    uploadState,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_finding_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFindingPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('finding_id')) {
      context.handle(
        _findingIdMeta,
        findingId.isAcceptableOrUnknown(data['finding_id']!, _findingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_findingIdMeta);
    }
    if (data.containsKey('attachment_id')) {
      context.handle(
        _attachmentIdMeta,
        attachmentId.isAcceptableOrUnknown(
          data['attachment_id']!,
          _attachmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentIdMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    }
    if (data.containsKey('storage_bucket')) {
      context.handle(
        _storageBucketMeta,
        storageBucket.isAcceptableOrUnknown(
          data['storage_bucket']!,
          _storageBucketMeta,
        ),
      );
    }
    if (data.containsKey('storage_key')) {
      context.handle(
        _storageKeyMeta,
        storageKey.isAcceptableOrUnknown(data['storage_key']!, _storageKeyMeta),
      );
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    }
    if (data.containsKey('can_delete')) {
      context.handle(
        _canDeleteMeta,
        canDelete.isAcceptableOrUnknown(data['can_delete']!, _canDeleteMeta),
      );
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalFindingPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFindingPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      findingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finding_id'],
      )!,
      attachmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_id'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      ),
      storageBucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_bucket'],
      ),
      storageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_key'],
      ),
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      ),
      canDelete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_delete'],
      )!,
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $LocalFindingPhotosTable createAlias(String alias) {
    return $LocalFindingPhotosTable(attachedDatabase, alias);
  }
}

class LocalFindingPhoto extends DataClass
    implements Insertable<LocalFindingPhoto> {
  final String id;
  final String businessId;
  final String findingId;
  final String attachmentId;
  final String? localFilePath;
  final String? storageBucket;
  final String? storageKey;
  final String? filename;
  final String? mimeType;
  final int? byteSize;
  final DateTime? capturedAt;
  final bool canDelete;
  final String uploadState;
  final String? lastError;
  const LocalFindingPhoto({
    required this.id,
    required this.businessId,
    required this.findingId,
    required this.attachmentId,
    this.localFilePath,
    this.storageBucket,
    this.storageKey,
    this.filename,
    this.mimeType,
    this.byteSize,
    this.capturedAt,
    required this.canDelete,
    required this.uploadState,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['finding_id'] = Variable<String>(findingId);
    map['attachment_id'] = Variable<String>(attachmentId);
    if (!nullToAbsent || localFilePath != null) {
      map['local_file_path'] = Variable<String>(localFilePath);
    }
    if (!nullToAbsent || storageBucket != null) {
      map['storage_bucket'] = Variable<String>(storageBucket);
    }
    if (!nullToAbsent || storageKey != null) {
      map['storage_key'] = Variable<String>(storageKey);
    }
    if (!nullToAbsent || filename != null) {
      map['filename'] = Variable<String>(filename);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || byteSize != null) {
      map['byte_size'] = Variable<int>(byteSize);
    }
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    map['can_delete'] = Variable<bool>(canDelete);
    map['upload_state'] = Variable<String>(uploadState);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  LocalFindingPhotosCompanion toCompanion(bool nullToAbsent) {
    return LocalFindingPhotosCompanion(
      id: Value(id),
      businessId: Value(businessId),
      findingId: Value(findingId),
      attachmentId: Value(attachmentId),
      localFilePath: localFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localFilePath),
      storageBucket: storageBucket == null && nullToAbsent
          ? const Value.absent()
          : Value(storageBucket),
      storageKey: storageKey == null && nullToAbsent
          ? const Value.absent()
          : Value(storageKey),
      filename: filename == null && nullToAbsent
          ? const Value.absent()
          : Value(filename),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      byteSize: byteSize == null && nullToAbsent
          ? const Value.absent()
          : Value(byteSize),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      canDelete: Value(canDelete),
      uploadState: Value(uploadState),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory LocalFindingPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFindingPhoto(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      findingId: serializer.fromJson<String>(json['findingId']),
      attachmentId: serializer.fromJson<String>(json['attachmentId']),
      localFilePath: serializer.fromJson<String?>(json['localFilePath']),
      storageBucket: serializer.fromJson<String?>(json['storageBucket']),
      storageKey: serializer.fromJson<String?>(json['storageKey']),
      filename: serializer.fromJson<String?>(json['filename']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      byteSize: serializer.fromJson<int?>(json['byteSize']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      canDelete: serializer.fromJson<bool>(json['canDelete']),
      uploadState: serializer.fromJson<String>(json['uploadState']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'findingId': serializer.toJson<String>(findingId),
      'attachmentId': serializer.toJson<String>(attachmentId),
      'localFilePath': serializer.toJson<String?>(localFilePath),
      'storageBucket': serializer.toJson<String?>(storageBucket),
      'storageKey': serializer.toJson<String?>(storageKey),
      'filename': serializer.toJson<String?>(filename),
      'mimeType': serializer.toJson<String?>(mimeType),
      'byteSize': serializer.toJson<int?>(byteSize),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'canDelete': serializer.toJson<bool>(canDelete),
      'uploadState': serializer.toJson<String>(uploadState),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  LocalFindingPhoto copyWith({
    String? id,
    String? businessId,
    String? findingId,
    String? attachmentId,
    Value<String?> localFilePath = const Value.absent(),
    Value<String?> storageBucket = const Value.absent(),
    Value<String?> storageKey = const Value.absent(),
    Value<String?> filename = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<int?> byteSize = const Value.absent(),
    Value<DateTime?> capturedAt = const Value.absent(),
    bool? canDelete,
    String? uploadState,
    Value<String?> lastError = const Value.absent(),
  }) => LocalFindingPhoto(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    findingId: findingId ?? this.findingId,
    attachmentId: attachmentId ?? this.attachmentId,
    localFilePath: localFilePath.present
        ? localFilePath.value
        : this.localFilePath,
    storageBucket: storageBucket.present
        ? storageBucket.value
        : this.storageBucket,
    storageKey: storageKey.present ? storageKey.value : this.storageKey,
    filename: filename.present ? filename.value : this.filename,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    byteSize: byteSize.present ? byteSize.value : this.byteSize,
    capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
    canDelete: canDelete ?? this.canDelete,
    uploadState: uploadState ?? this.uploadState,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  LocalFindingPhoto copyWithCompanion(LocalFindingPhotosCompanion data) {
    return LocalFindingPhoto(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      findingId: data.findingId.present ? data.findingId.value : this.findingId,
      attachmentId: data.attachmentId.present
          ? data.attachmentId.value
          : this.attachmentId,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      storageBucket: data.storageBucket.present
          ? data.storageBucket.value
          : this.storageBucket,
      storageKey: data.storageKey.present
          ? data.storageKey.value
          : this.storageKey,
      filename: data.filename.present ? data.filename.value : this.filename,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      canDelete: data.canDelete.present ? data.canDelete.value : this.canDelete,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFindingPhoto(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('findingId: $findingId, ')
          ..write('attachmentId: $attachmentId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storageKey: $storageKey, ')
          ..write('filename: $filename, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('canDelete: $canDelete, ')
          ..write('uploadState: $uploadState, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    findingId,
    attachmentId,
    localFilePath,
    storageBucket,
    storageKey,
    filename,
    mimeType,
    byteSize,
    capturedAt,
    canDelete,
    uploadState,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFindingPhoto &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.findingId == this.findingId &&
          other.attachmentId == this.attachmentId &&
          other.localFilePath == this.localFilePath &&
          other.storageBucket == this.storageBucket &&
          other.storageKey == this.storageKey &&
          other.filename == this.filename &&
          other.mimeType == this.mimeType &&
          other.byteSize == this.byteSize &&
          other.capturedAt == this.capturedAt &&
          other.canDelete == this.canDelete &&
          other.uploadState == this.uploadState &&
          other.lastError == this.lastError);
}

class LocalFindingPhotosCompanion extends UpdateCompanion<LocalFindingPhoto> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> findingId;
  final Value<String> attachmentId;
  final Value<String?> localFilePath;
  final Value<String?> storageBucket;
  final Value<String?> storageKey;
  final Value<String?> filename;
  final Value<String?> mimeType;
  final Value<int?> byteSize;
  final Value<DateTime?> capturedAt;
  final Value<bool> canDelete;
  final Value<String> uploadState;
  final Value<String?> lastError;
  final Value<int> rowid;
  const LocalFindingPhotosCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.findingId = const Value.absent(),
    this.attachmentId = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.filename = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFindingPhotosCompanion.insert({
    required String id,
    required String businessId,
    required String findingId,
    required String attachmentId,
    this.localFilePath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.filename = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.canDelete = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       findingId = Value(findingId),
       attachmentId = Value(attachmentId);
  static Insertable<LocalFindingPhoto> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? findingId,
    Expression<String>? attachmentId,
    Expression<String>? localFilePath,
    Expression<String>? storageBucket,
    Expression<String>? storageKey,
    Expression<String>? filename,
    Expression<String>? mimeType,
    Expression<int>? byteSize,
    Expression<DateTime>? capturedAt,
    Expression<bool>? canDelete,
    Expression<String>? uploadState,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (findingId != null) 'finding_id': findingId,
      if (attachmentId != null) 'attachment_id': attachmentId,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (storageBucket != null) 'storage_bucket': storageBucket,
      if (storageKey != null) 'storage_key': storageKey,
      if (filename != null) 'filename': filename,
      if (mimeType != null) 'mime_type': mimeType,
      if (byteSize != null) 'byte_size': byteSize,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (canDelete != null) 'can_delete': canDelete,
      if (uploadState != null) 'upload_state': uploadState,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFindingPhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? findingId,
    Value<String>? attachmentId,
    Value<String?>? localFilePath,
    Value<String?>? storageBucket,
    Value<String?>? storageKey,
    Value<String?>? filename,
    Value<String?>? mimeType,
    Value<int?>? byteSize,
    Value<DateTime?>? capturedAt,
    Value<bool>? canDelete,
    Value<String>? uploadState,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return LocalFindingPhotosCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      findingId: findingId ?? this.findingId,
      attachmentId: attachmentId ?? this.attachmentId,
      localFilePath: localFilePath ?? this.localFilePath,
      storageBucket: storageBucket ?? this.storageBucket,
      storageKey: storageKey ?? this.storageKey,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      capturedAt: capturedAt ?? this.capturedAt,
      canDelete: canDelete ?? this.canDelete,
      uploadState: uploadState ?? this.uploadState,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (findingId.present) {
      map['finding_id'] = Variable<String>(findingId.value);
    }
    if (attachmentId.present) {
      map['attachment_id'] = Variable<String>(attachmentId.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (storageBucket.present) {
      map['storage_bucket'] = Variable<String>(storageBucket.value);
    }
    if (storageKey.present) {
      map['storage_key'] = Variable<String>(storageKey.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (canDelete.present) {
      map['can_delete'] = Variable<bool>(canDelete.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<String>(uploadState.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFindingPhotosCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('findingId: $findingId, ')
          ..write('attachmentId: $attachmentId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storageKey: $storageKey, ')
          ..write('filename: $filename, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteSize: $byteSize, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('canDelete: $canDelete, ')
          ..write('uploadState: $uploadState, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFinancialCacheTable extends LocalFinancialCache
    with TableInfo<$LocalFinancialCacheTable, LocalFinancialCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFinancialCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    cacheKey,
    payloadJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_financial_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFinancialCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, cacheKey};
  @override
  LocalFinancialCacheData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFinancialCacheData(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalFinancialCacheTable createAlias(String alias) {
    return $LocalFinancialCacheTable(attachedDatabase, alias);
  }
}

class LocalFinancialCacheData extends DataClass
    implements Insertable<LocalFinancialCacheData> {
  final String businessId;
  final String cacheKey;
  final String payloadJson;
  final DateTime updatedAt;
  const LocalFinancialCacheData({
    required this.businessId,
    required this.cacheKey,
    required this.payloadJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['cache_key'] = Variable<String>(cacheKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalFinancialCacheCompanion toCompanion(bool nullToAbsent) {
    return LocalFinancialCacheCompanion(
      businessId: Value(businessId),
      cacheKey: Value(cacheKey),
      payloadJson: Value(payloadJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalFinancialCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFinancialCacheData(
      businessId: serializer.fromJson<String>(json['businessId']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalFinancialCacheData copyWith({
    String? businessId,
    String? cacheKey,
    String? payloadJson,
    DateTime? updatedAt,
  }) => LocalFinancialCacheData(
    businessId: businessId ?? this.businessId,
    cacheKey: cacheKey ?? this.cacheKey,
    payloadJson: payloadJson ?? this.payloadJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalFinancialCacheData copyWithCompanion(LocalFinancialCacheCompanion data) {
    return LocalFinancialCacheData(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFinancialCacheData(')
          ..write('businessId: $businessId, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(businessId, cacheKey, payloadJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFinancialCacheData &&
          other.businessId == this.businessId &&
          other.cacheKey == this.cacheKey &&
          other.payloadJson == this.payloadJson &&
          other.updatedAt == this.updatedAt);
}

class LocalFinancialCacheCompanion
    extends UpdateCompanion<LocalFinancialCacheData> {
  final Value<String> businessId;
  final Value<String> cacheKey;
  final Value<String> payloadJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalFinancialCacheCompanion({
    this.businessId = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFinancialCacheCompanion.insert({
    required String businessId,
    required String cacheKey,
    required String payloadJson,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       cacheKey = Value(cacheKey),
       payloadJson = Value(payloadJson);
  static Insertable<LocalFinancialCacheData> custom({
    Expression<String>? businessId,
    Expression<String>? cacheKey,
    Expression<String>? payloadJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFinancialCacheCompanion copyWith({
    Value<String>? businessId,
    Value<String>? cacheKey,
    Value<String>? payloadJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalFinancialCacheCompanion(
      businessId: businessId ?? this.businessId,
      cacheKey: cacheKey ?? this.cacheKey,
      payloadJson: payloadJson ?? this.payloadJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFinancialCacheCompanion(')
          ..write('businessId: $businessId, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCatalogItemsTable extends LocalCatalogItems
    with TableInfo<$LocalCatalogItemsTable, LocalCatalogItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCatalogItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('non_inventory'),
  );
  static const VerificationMeta _sellingPriceMeta = const VerificationMeta(
    'sellingPrice',
  );
  @override
  late final GeneratedColumn<double> sellingPrice = GeneratedColumn<double>(
    'selling_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pricingUnitMeta = const VerificationMeta(
    'pricingUnit',
  );
  @override
  late final GeneratedColumn<String> pricingUnit = GeneratedColumn<String>(
    'pricing_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<double> cost = GeneratedColumn<double>(
    'cost',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _taxableMeta = const VerificationMeta(
    'taxable',
  );
  @override
  late final GeneratedColumn<bool> taxable = GeneratedColumn<bool>(
    'taxable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("taxable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    description,
    itemType,
    sellingPrice,
    pricingUnit,
    cost,
    taxable,
    category,
    barcode,
    active,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_catalog_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCatalogItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    }
    if (data.containsKey('selling_price')) {
      context.handle(
        _sellingPriceMeta,
        sellingPrice.isAcceptableOrUnknown(
          data['selling_price']!,
          _sellingPriceMeta,
        ),
      );
    }
    if (data.containsKey('pricing_unit')) {
      context.handle(
        _pricingUnitMeta,
        pricingUnit.isAcceptableOrUnknown(
          data['pricing_unit']!,
          _pricingUnitMeta,
        ),
      );
    }
    if (data.containsKey('cost')) {
      context.handle(
        _costMeta,
        cost.isAcceptableOrUnknown(data['cost']!, _costMeta),
      );
    }
    if (data.containsKey('taxable')) {
      context.handle(
        _taxableMeta,
        taxable.isAcceptableOrUnknown(data['taxable']!, _taxableMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCatalogItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCatalogItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      itemType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_type'],
      )!,
      sellingPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}selling_price'],
      )!,
      pricingUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pricing_unit'],
      ),
      cost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost'],
      )!,
      taxable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}taxable'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalCatalogItemsTable createAlias(String alias) {
    return $LocalCatalogItemsTable(attachedDatabase, alias);
  }
}

class LocalCatalogItem extends DataClass
    implements Insertable<LocalCatalogItem> {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final String itemType;
  final double sellingPrice;
  final String? pricingUnit;
  final double cost;
  final bool taxable;
  final String? category;
  final String? barcode;
  final bool active;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalCatalogItem({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    required this.itemType,
    required this.sellingPrice,
    this.pricingUnit,
    required this.cost,
    required this.taxable,
    this.category,
    this.barcode,
    required this.active,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['item_type'] = Variable<String>(itemType);
    map['selling_price'] = Variable<double>(sellingPrice);
    if (!nullToAbsent || pricingUnit != null) {
      map['pricing_unit'] = Variable<String>(pricingUnit);
    }
    map['cost'] = Variable<double>(cost);
    map['taxable'] = Variable<bool>(taxable);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['active'] = Variable<bool>(active);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalCatalogItemsCompanion toCompanion(bool nullToAbsent) {
    return LocalCatalogItemsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      itemType: Value(itemType),
      sellingPrice: Value(sellingPrice),
      pricingUnit: pricingUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(pricingUnit),
      cost: Value(cost),
      taxable: Value(taxable),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      active: Value(active),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalCatalogItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCatalogItem(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      itemType: serializer.fromJson<String>(json['itemType']),
      sellingPrice: serializer.fromJson<double>(json['sellingPrice']),
      pricingUnit: serializer.fromJson<String?>(json['pricingUnit']),
      cost: serializer.fromJson<double>(json['cost']),
      taxable: serializer.fromJson<bool>(json['taxable']),
      category: serializer.fromJson<String?>(json['category']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      active: serializer.fromJson<bool>(json['active']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'itemType': serializer.toJson<String>(itemType),
      'sellingPrice': serializer.toJson<double>(sellingPrice),
      'pricingUnit': serializer.toJson<String?>(pricingUnit),
      'cost': serializer.toJson<double>(cost),
      'taxable': serializer.toJson<bool>(taxable),
      'category': serializer.toJson<String?>(category),
      'barcode': serializer.toJson<String?>(barcode),
      'active': serializer.toJson<bool>(active),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalCatalogItem copyWith({
    String? id,
    String? businessId,
    String? name,
    Value<String?> description = const Value.absent(),
    String? itemType,
    double? sellingPrice,
    Value<String?> pricingUnit = const Value.absent(),
    double? cost,
    bool? taxable,
    Value<String?> category = const Value.absent(),
    Value<String?> barcode = const Value.absent(),
    bool? active,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalCatalogItem(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    itemType: itemType ?? this.itemType,
    sellingPrice: sellingPrice ?? this.sellingPrice,
    pricingUnit: pricingUnit.present ? pricingUnit.value : this.pricingUnit,
    cost: cost ?? this.cost,
    taxable: taxable ?? this.taxable,
    category: category.present ? category.value : this.category,
    barcode: barcode.present ? barcode.value : this.barcode,
    active: active ?? this.active,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalCatalogItem copyWithCompanion(LocalCatalogItemsCompanion data) {
    return LocalCatalogItem(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      sellingPrice: data.sellingPrice.present
          ? data.sellingPrice.value
          : this.sellingPrice,
      pricingUnit: data.pricingUnit.present
          ? data.pricingUnit.value
          : this.pricingUnit,
      cost: data.cost.present ? data.cost.value : this.cost,
      taxable: data.taxable.present ? data.taxable.value : this.taxable,
      category: data.category.present ? data.category.value : this.category,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      active: data.active.present ? data.active.value : this.active,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogItem(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('itemType: $itemType, ')
          ..write('sellingPrice: $sellingPrice, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('cost: $cost, ')
          ..write('taxable: $taxable, ')
          ..write('category: $category, ')
          ..write('barcode: $barcode, ')
          ..write('active: $active, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    name,
    description,
    itemType,
    sellingPrice,
    pricingUnit,
    cost,
    taxable,
    category,
    barcode,
    active,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCatalogItem &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.description == this.description &&
          other.itemType == this.itemType &&
          other.sellingPrice == this.sellingPrice &&
          other.pricingUnit == this.pricingUnit &&
          other.cost == this.cost &&
          other.taxable == this.taxable &&
          other.category == this.category &&
          other.barcode == this.barcode &&
          other.active == this.active &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalCatalogItemsCompanion extends UpdateCompanion<LocalCatalogItem> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> itemType;
  final Value<double> sellingPrice;
  final Value<String?> pricingUnit;
  final Value<double> cost;
  final Value<bool> taxable;
  final Value<String?> category;
  final Value<String?> barcode;
  final Value<bool> active;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalCatalogItemsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.itemType = const Value.absent(),
    this.sellingPrice = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.cost = const Value.absent(),
    this.taxable = const Value.absent(),
    this.category = const Value.absent(),
    this.barcode = const Value.absent(),
    this.active = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCatalogItemsCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    this.description = const Value.absent(),
    this.itemType = const Value.absent(),
    this.sellingPrice = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.cost = const Value.absent(),
    this.taxable = const Value.absent(),
    this.category = const Value.absent(),
    this.barcode = const Value.absent(),
    this.active = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name);
  static Insertable<LocalCatalogItem> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? itemType,
    Expression<double>? sellingPrice,
    Expression<String>? pricingUnit,
    Expression<double>? cost,
    Expression<bool>? taxable,
    Expression<String>? category,
    Expression<String>? barcode,
    Expression<bool>? active,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (itemType != null) 'item_type': itemType,
      if (sellingPrice != null) 'selling_price': sellingPrice,
      if (pricingUnit != null) 'pricing_unit': pricingUnit,
      if (cost != null) 'cost': cost,
      if (taxable != null) 'taxable': taxable,
      if (category != null) 'category': category,
      if (barcode != null) 'barcode': barcode,
      if (active != null) 'active': active,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCatalogItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? itemType,
    Value<double>? sellingPrice,
    Value<String?>? pricingUnit,
    Value<double>? cost,
    Value<bool>? taxable,
    Value<String?>? category,
    Value<String?>? barcode,
    Value<bool>? active,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalCatalogItemsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      description: description ?? this.description,
      itemType: itemType ?? this.itemType,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      pricingUnit: pricingUnit ?? this.pricingUnit,
      cost: cost ?? this.cost,
      taxable: taxable ?? this.taxable,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      active: active ?? this.active,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (sellingPrice.present) {
      map['selling_price'] = Variable<double>(sellingPrice.value);
    }
    if (pricingUnit.present) {
      map['pricing_unit'] = Variable<String>(pricingUnit.value);
    }
    if (cost.present) {
      map['cost'] = Variable<double>(cost.value);
    }
    if (taxable.present) {
      map['taxable'] = Variable<bool>(taxable.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogItemsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('itemType: $itemType, ')
          ..write('sellingPrice: $sellingPrice, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('cost: $cost, ')
          ..write('taxable: $taxable, ')
          ..write('category: $category, ')
          ..write('barcode: $barcode, ')
          ..write('active: $active, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalDocumentsTable extends LocalDocuments
    with TableInfo<$LocalDocumentsTable, LocalDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentNumberMeta = const VerificationMeta(
    'documentNumber',
  );
  @override
  late final GeneratedColumn<String> documentNumber = GeneratedColumn<String>(
    'document_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayStatusCodeMeta = const VerificationMeta(
    'displayStatusCode',
  );
  @override
  late final GeneratedColumn<String> displayStatusCode =
      GeneratedColumn<String>(
        'display_status_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _convertedMeta = const VerificationMeta(
    'converted',
  );
  @override
  late final GeneratedColumn<bool> converted = GeneratedColumn<bool>(
    'converted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("converted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _documentDateMeta = const VerificationMeta(
    'documentDate',
  );
  @override
  late final GeneratedColumn<String> documentDate = GeneratedColumn<String>(
    'document_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _futureDateFlagMeta = const VerificationMeta(
    'futureDateFlag',
  );
  @override
  late final GeneratedColumn<bool> futureDateFlag = GeneratedColumn<bool>(
    'future_date_flag',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("future_date_flag" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    jobId,
    customerId,
    kind,
    documentNumber,
    status,
    displayStatusCode,
    closedAt,
    converted,
    total,
    documentDate,
    futureDateFlag,
    createdAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('document_number')) {
      context.handle(
        _documentNumberMeta,
        documentNumber.isAcceptableOrUnknown(
          data['document_number']!,
          _documentNumberMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('display_status_code')) {
      context.handle(
        _displayStatusCodeMeta,
        displayStatusCode.isAcceptableOrUnknown(
          data['display_status_code']!,
          _displayStatusCodeMeta,
        ),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('converted')) {
      context.handle(
        _convertedMeta,
        converted.isAcceptableOrUnknown(data['converted']!, _convertedMeta),
      );
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    }
    if (data.containsKey('document_date')) {
      context.handle(
        _documentDateMeta,
        documentDate.isAcceptableOrUnknown(
          data['document_date']!,
          _documentDateMeta,
        ),
      );
    }
    if (data.containsKey('future_date_flag')) {
      context.handle(
        _futureDateFlagMeta,
        futureDateFlag.isAcceptableOrUnknown(
          data['future_date_flag']!,
          _futureDateFlagMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDocument(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      documentNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_number'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      displayStatusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_status_code'],
      ),
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      ),
      converted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}converted'],
      )!,
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total'],
      )!,
      documentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_date'],
      ),
      futureDateFlag: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}future_date_flag'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
    );
  }

  @override
  $LocalDocumentsTable createAlias(String alias) {
    return $LocalDocumentsTable(attachedDatabase, alias);
  }
}

class LocalDocument extends DataClass implements Insertable<LocalDocument> {
  final String id;
  final String businessId;
  final String? jobId;
  final String? customerId;
  final String kind;
  final String? documentNumber;
  final String? status;
  final String? displayStatusCode;
  final DateTime? closedAt;
  final bool converted;
  final double total;
  final String? documentDate;
  final bool futureDateFlag;
  final DateTime? createdAt;
  final DateTime? serverUpdatedAt;
  final int? rowVersion;
  final String syncState;
  const LocalDocument({
    required this.id,
    required this.businessId,
    this.jobId,
    this.customerId,
    required this.kind,
    this.documentNumber,
    this.status,
    this.displayStatusCode,
    this.closedAt,
    required this.converted,
    required this.total,
    this.documentDate,
    required this.futureDateFlag,
    this.createdAt,
    this.serverUpdatedAt,
    this.rowVersion,
    required this.syncState,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || documentNumber != null) {
      map['document_number'] = Variable<String>(documentNumber);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || displayStatusCode != null) {
      map['display_status_code'] = Variable<String>(displayStatusCode);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    map['converted'] = Variable<bool>(converted);
    map['total'] = Variable<double>(total);
    if (!nullToAbsent || documentDate != null) {
      map['document_date'] = Variable<String>(documentDate);
    }
    map['future_date_flag'] = Variable<bool>(futureDateFlag);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    if (!nullToAbsent || rowVersion != null) {
      map['row_version'] = Variable<int>(rowVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    return map;
  }

  LocalDocumentsCompanion toCompanion(bool nullToAbsent) {
    return LocalDocumentsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      kind: Value(kind),
      documentNumber: documentNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(documentNumber),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      displayStatusCode: displayStatusCode == null && nullToAbsent
          ? const Value.absent()
          : Value(displayStatusCode),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      converted: Value(converted),
      total: Value(total),
      documentDate: documentDate == null && nullToAbsent
          ? const Value.absent()
          : Value(documentDate),
      futureDateFlag: Value(futureDateFlag),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      rowVersion: rowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rowVersion),
      syncState: Value(syncState),
    );
  }

  factory LocalDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDocument(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      kind: serializer.fromJson<String>(json['kind']),
      documentNumber: serializer.fromJson<String?>(json['documentNumber']),
      status: serializer.fromJson<String?>(json['status']),
      displayStatusCode: serializer.fromJson<String?>(
        json['displayStatusCode'],
      ),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      converted: serializer.fromJson<bool>(json['converted']),
      total: serializer.fromJson<double>(json['total']),
      documentDate: serializer.fromJson<String?>(json['documentDate']),
      futureDateFlag: serializer.fromJson<bool>(json['futureDateFlag']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      rowVersion: serializer.fromJson<int?>(json['rowVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'jobId': serializer.toJson<String?>(jobId),
      'customerId': serializer.toJson<String?>(customerId),
      'kind': serializer.toJson<String>(kind),
      'documentNumber': serializer.toJson<String?>(documentNumber),
      'status': serializer.toJson<String?>(status),
      'displayStatusCode': serializer.toJson<String?>(displayStatusCode),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'converted': serializer.toJson<bool>(converted),
      'total': serializer.toJson<double>(total),
      'documentDate': serializer.toJson<String?>(documentDate),
      'futureDateFlag': serializer.toJson<bool>(futureDateFlag),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'rowVersion': serializer.toJson<int?>(rowVersion),
      'syncState': serializer.toJson<String>(syncState),
    };
  }

  LocalDocument copyWith({
    String? id,
    String? businessId,
    Value<String?> jobId = const Value.absent(),
    Value<String?> customerId = const Value.absent(),
    String? kind,
    Value<String?> documentNumber = const Value.absent(),
    Value<String?> status = const Value.absent(),
    Value<String?> displayStatusCode = const Value.absent(),
    Value<DateTime?> closedAt = const Value.absent(),
    bool? converted,
    double? total,
    Value<String?> documentDate = const Value.absent(),
    bool? futureDateFlag,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    Value<int?> rowVersion = const Value.absent(),
    String? syncState,
  }) => LocalDocument(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    jobId: jobId.present ? jobId.value : this.jobId,
    customerId: customerId.present ? customerId.value : this.customerId,
    kind: kind ?? this.kind,
    documentNumber: documentNumber.present
        ? documentNumber.value
        : this.documentNumber,
    status: status.present ? status.value : this.status,
    displayStatusCode: displayStatusCode.present
        ? displayStatusCode.value
        : this.displayStatusCode,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    converted: converted ?? this.converted,
    total: total ?? this.total,
    documentDate: documentDate.present ? documentDate.value : this.documentDate,
    futureDateFlag: futureDateFlag ?? this.futureDateFlag,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    rowVersion: rowVersion.present ? rowVersion.value : this.rowVersion,
    syncState: syncState ?? this.syncState,
  );
  LocalDocument copyWithCompanion(LocalDocumentsCompanion data) {
    return LocalDocument(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      kind: data.kind.present ? data.kind.value : this.kind,
      documentNumber: data.documentNumber.present
          ? data.documentNumber.value
          : this.documentNumber,
      status: data.status.present ? data.status.value : this.status,
      displayStatusCode: data.displayStatusCode.present
          ? data.displayStatusCode.value
          : this.displayStatusCode,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      converted: data.converted.present ? data.converted.value : this.converted,
      total: data.total.present ? data.total.value : this.total,
      documentDate: data.documentDate.present
          ? data.documentDate.value
          : this.documentDate,
      futureDateFlag: data.futureDateFlag.present
          ? data.futureDateFlag.value
          : this.futureDateFlag,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDocument(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('customerId: $customerId, ')
          ..write('kind: $kind, ')
          ..write('documentNumber: $documentNumber, ')
          ..write('status: $status, ')
          ..write('displayStatusCode: $displayStatusCode, ')
          ..write('closedAt: $closedAt, ')
          ..write('converted: $converted, ')
          ..write('total: $total, ')
          ..write('documentDate: $documentDate, ')
          ..write('futureDateFlag: $futureDateFlag, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    jobId,
    customerId,
    kind,
    documentNumber,
    status,
    displayStatusCode,
    closedAt,
    converted,
    total,
    documentDate,
    futureDateFlag,
    createdAt,
    serverUpdatedAt,
    rowVersion,
    syncState,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDocument &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.jobId == this.jobId &&
          other.customerId == this.customerId &&
          other.kind == this.kind &&
          other.documentNumber == this.documentNumber &&
          other.status == this.status &&
          other.displayStatusCode == this.displayStatusCode &&
          other.closedAt == this.closedAt &&
          other.converted == this.converted &&
          other.total == this.total &&
          other.documentDate == this.documentDate &&
          other.futureDateFlag == this.futureDateFlag &&
          other.createdAt == this.createdAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.rowVersion == this.rowVersion &&
          other.syncState == this.syncState);
}

class LocalDocumentsCompanion extends UpdateCompanion<LocalDocument> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String?> jobId;
  final Value<String?> customerId;
  final Value<String> kind;
  final Value<String?> documentNumber;
  final Value<String?> status;
  final Value<String?> displayStatusCode;
  final Value<DateTime?> closedAt;
  final Value<bool> converted;
  final Value<double> total;
  final Value<String?> documentDate;
  final Value<bool> futureDateFlag;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<int?> rowVersion;
  final Value<String> syncState;
  final Value<int> rowid;
  const LocalDocumentsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.kind = const Value.absent(),
    this.documentNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.displayStatusCode = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.converted = const Value.absent(),
    this.total = const Value.absent(),
    this.documentDate = const Value.absent(),
    this.futureDateFlag = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalDocumentsCompanion.insert({
    required String id,
    required String businessId,
    this.jobId = const Value.absent(),
    this.customerId = const Value.absent(),
    required String kind,
    this.documentNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.displayStatusCode = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.converted = const Value.absent(),
    this.total = const Value.absent(),
    this.documentDate = const Value.absent(),
    this.futureDateFlag = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       kind = Value(kind);
  static Insertable<LocalDocument> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? jobId,
    Expression<String>? customerId,
    Expression<String>? kind,
    Expression<String>? documentNumber,
    Expression<String>? status,
    Expression<String>? displayStatusCode,
    Expression<DateTime>? closedAt,
    Expression<bool>? converted,
    Expression<double>? total,
    Expression<String>? documentDate,
    Expression<bool>? futureDateFlag,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<int>? rowVersion,
    Expression<String>? syncState,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (jobId != null) 'job_id': jobId,
      if (customerId != null) 'customer_id': customerId,
      if (kind != null) 'kind': kind,
      if (documentNumber != null) 'document_number': documentNumber,
      if (status != null) 'status': status,
      if (displayStatusCode != null) 'display_status_code': displayStatusCode,
      if (closedAt != null) 'closed_at': closedAt,
      if (converted != null) 'converted': converted,
      if (total != null) 'total': total,
      if (documentDate != null) 'document_date': documentDate,
      if (futureDateFlag != null) 'future_date_flag': futureDateFlag,
      if (createdAt != null) 'created_at': createdAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (syncState != null) 'sync_state': syncState,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalDocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String?>? jobId,
    Value<String?>? customerId,
    Value<String>? kind,
    Value<String?>? documentNumber,
    Value<String?>? status,
    Value<String?>? displayStatusCode,
    Value<DateTime?>? closedAt,
    Value<bool>? converted,
    Value<double>? total,
    Value<String?>? documentDate,
    Value<bool>? futureDateFlag,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<int?>? rowVersion,
    Value<String>? syncState,
    Value<int>? rowid,
  }) {
    return LocalDocumentsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      jobId: jobId ?? this.jobId,
      customerId: customerId ?? this.customerId,
      kind: kind ?? this.kind,
      documentNumber: documentNumber ?? this.documentNumber,
      status: status ?? this.status,
      displayStatusCode: displayStatusCode ?? this.displayStatusCode,
      closedAt: closedAt ?? this.closedAt,
      converted: converted ?? this.converted,
      total: total ?? this.total,
      documentDate: documentDate ?? this.documentDate,
      futureDateFlag: futureDateFlag ?? this.futureDateFlag,
      createdAt: createdAt ?? this.createdAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      syncState: syncState ?? this.syncState,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (documentNumber.present) {
      map['document_number'] = Variable<String>(documentNumber.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (displayStatusCode.present) {
      map['display_status_code'] = Variable<String>(displayStatusCode.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (converted.present) {
      map['converted'] = Variable<bool>(converted.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (documentDate.present) {
      map['document_date'] = Variable<String>(documentDate.value);
    }
    if (futureDateFlag.present) {
      map['future_date_flag'] = Variable<bool>(futureDateFlag.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('customerId: $customerId, ')
          ..write('kind: $kind, ')
          ..write('documentNumber: $documentNumber, ')
          ..write('status: $status, ')
          ..write('displayStatusCode: $displayStatusCode, ')
          ..write('closedAt: $closedAt, ')
          ..write('converted: $converted, ')
          ..write('total: $total, ')
          ..write('documentDate: $documentDate, ')
          ..write('futureDateFlag: $futureDateFlag, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('syncState: $syncState, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalExpenseIqPhotosTable extends LocalExpenseIqPhotos
    with TableInfo<$LocalExpenseIqPhotosTable, LocalExpenseIqPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalExpenseIqPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoIdMeta = const VerificationMeta(
    'photoId',
  );
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
    'photo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceUriMeta = const VerificationMeta(
    'sourceUri',
  );
  @override
  late final GeneratedColumn<String> sourceUri = GeneratedColumn<String>(
    'source_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _claimedAtMeta = const VerificationMeta(
    'claimedAt',
  );
  @override
  late final GeneratedColumn<int> claimedAt = GeneratedColumn<int>(
    'claimed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    businessId,
    transactionId,
    photoId,
    filename,
    sourceUri,
    state,
    attempts,
    claimedAt,
    lastError,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_expense_iq_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalExpenseIqPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(
        _photoIdMeta,
        photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_photoIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('source_uri')) {
      context.handle(
        _sourceUriMeta,
        sourceUri.isAcceptableOrUnknown(data['source_uri']!, _sourceUriMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('claimed_at')) {
      context.handle(
        _claimedAtMeta,
        claimedAt.isAcceptableOrUnknown(data['claimed_at']!, _claimedAtMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, transactionId};
  @override
  LocalExpenseIqPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalExpenseIqPhoto(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      )!,
      photoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_id'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      sourceUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_uri'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      claimedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}claimed_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalExpenseIqPhotosTable createAlias(String alias) {
    return $LocalExpenseIqPhotosTable(attachedDatabase, alias);
  }
}

class LocalExpenseIqPhoto extends DataClass
    implements Insertable<LocalExpenseIqPhoto> {
  final String businessId;
  final String transactionId;
  final String photoId;
  final String filename;
  final String? sourceUri;
  final String state;
  final int attempts;
  final int? claimedAt;
  final String? lastError;
  final int updatedAt;
  const LocalExpenseIqPhoto({
    required this.businessId,
    required this.transactionId,
    required this.photoId,
    required this.filename,
    this.sourceUri,
    required this.state,
    required this.attempts,
    this.claimedAt,
    this.lastError,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['transaction_id'] = Variable<String>(transactionId);
    map['photo_id'] = Variable<String>(photoId);
    map['filename'] = Variable<String>(filename);
    if (!nullToAbsent || sourceUri != null) {
      map['source_uri'] = Variable<String>(sourceUri);
    }
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || claimedAt != null) {
      map['claimed_at'] = Variable<int>(claimedAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  LocalExpenseIqPhotosCompanion toCompanion(bool nullToAbsent) {
    return LocalExpenseIqPhotosCompanion(
      businessId: Value(businessId),
      transactionId: Value(transactionId),
      photoId: Value(photoId),
      filename: Value(filename),
      sourceUri: sourceUri == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceUri),
      state: Value(state),
      attempts: Value(attempts),
      claimedAt: claimedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(claimedAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalExpenseIqPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalExpenseIqPhoto(
      businessId: serializer.fromJson<String>(json['businessId']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      photoId: serializer.fromJson<String>(json['photoId']),
      filename: serializer.fromJson<String>(json['filename']),
      sourceUri: serializer.fromJson<String?>(json['sourceUri']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      claimedAt: serializer.fromJson<int?>(json['claimedAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'transactionId': serializer.toJson<String>(transactionId),
      'photoId': serializer.toJson<String>(photoId),
      'filename': serializer.toJson<String>(filename),
      'sourceUri': serializer.toJson<String?>(sourceUri),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'claimedAt': serializer.toJson<int?>(claimedAt),
      'lastError': serializer.toJson<String?>(lastError),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  LocalExpenseIqPhoto copyWith({
    String? businessId,
    String? transactionId,
    String? photoId,
    String? filename,
    Value<String?> sourceUri = const Value.absent(),
    String? state,
    int? attempts,
    Value<int?> claimedAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    int? updatedAt,
  }) => LocalExpenseIqPhoto(
    businessId: businessId ?? this.businessId,
    transactionId: transactionId ?? this.transactionId,
    photoId: photoId ?? this.photoId,
    filename: filename ?? this.filename,
    sourceUri: sourceUri.present ? sourceUri.value : this.sourceUri,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    claimedAt: claimedAt.present ? claimedAt.value : this.claimedAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalExpenseIqPhoto copyWithCompanion(LocalExpenseIqPhotosCompanion data) {
    return LocalExpenseIqPhoto(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      photoId: data.photoId.present ? data.photoId.value : this.photoId,
      filename: data.filename.present ? data.filename.value : this.filename,
      sourceUri: data.sourceUri.present ? data.sourceUri.value : this.sourceUri,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      claimedAt: data.claimedAt.present ? data.claimedAt.value : this.claimedAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpenseIqPhoto(')
          ..write('businessId: $businessId, ')
          ..write('transactionId: $transactionId, ')
          ..write('photoId: $photoId, ')
          ..write('filename: $filename, ')
          ..write('sourceUri: $sourceUri, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    businessId,
    transactionId,
    photoId,
    filename,
    sourceUri,
    state,
    attempts,
    claimedAt,
    lastError,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalExpenseIqPhoto &&
          other.businessId == this.businessId &&
          other.transactionId == this.transactionId &&
          other.photoId == this.photoId &&
          other.filename == this.filename &&
          other.sourceUri == this.sourceUri &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.claimedAt == this.claimedAt &&
          other.lastError == this.lastError &&
          other.updatedAt == this.updatedAt);
}

class LocalExpenseIqPhotosCompanion
    extends UpdateCompanion<LocalExpenseIqPhoto> {
  final Value<String> businessId;
  final Value<String> transactionId;
  final Value<String> photoId;
  final Value<String> filename;
  final Value<String?> sourceUri;
  final Value<String> state;
  final Value<int> attempts;
  final Value<int?> claimedAt;
  final Value<String?> lastError;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const LocalExpenseIqPhotosCompanion({
    this.businessId = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.photoId = const Value.absent(),
    this.filename = const Value.absent(),
    this.sourceUri = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalExpenseIqPhotosCompanion.insert({
    required String businessId,
    required String transactionId,
    required String photoId,
    required String filename,
    this.sourceUri = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       transactionId = Value(transactionId),
       photoId = Value(photoId),
       filename = Value(filename),
       updatedAt = Value(updatedAt);
  static Insertable<LocalExpenseIqPhoto> custom({
    Expression<String>? businessId,
    Expression<String>? transactionId,
    Expression<String>? photoId,
    Expression<String>? filename,
    Expression<String>? sourceUri,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? claimedAt,
    Expression<String>? lastError,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (photoId != null) 'photo_id': photoId,
      if (filename != null) 'filename': filename,
      if (sourceUri != null) 'source_uri': sourceUri,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (claimedAt != null) 'claimed_at': claimedAt,
      if (lastError != null) 'last_error': lastError,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalExpenseIqPhotosCompanion copyWith({
    Value<String>? businessId,
    Value<String>? transactionId,
    Value<String>? photoId,
    Value<String>? filename,
    Value<String?>? sourceUri,
    Value<String>? state,
    Value<int>? attempts,
    Value<int?>? claimedAt,
    Value<String?>? lastError,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalExpenseIqPhotosCompanion(
      businessId: businessId ?? this.businessId,
      transactionId: transactionId ?? this.transactionId,
      photoId: photoId ?? this.photoId,
      filename: filename ?? this.filename,
      sourceUri: sourceUri ?? this.sourceUri,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      claimedAt: claimedAt ?? this.claimedAt,
      lastError: lastError ?? this.lastError,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (sourceUri.present) {
      map['source_uri'] = Variable<String>(sourceUri.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (claimedAt.present) {
      map['claimed_at'] = Variable<int>(claimedAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpenseIqPhotosCompanion(')
          ..write('businessId: $businessId, ')
          ..write('transactionId: $transactionId, ')
          ..write('photoId: $photoId, ')
          ..write('filename: $filename, ')
          ..write('sourceUri: $sourceUri, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('lastError: $lastError, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalExpenseIqSyncSettingsTable extends LocalExpenseIqSyncSettings
    with
        TableInfo<$LocalExpenseIqSyncSettingsTable, LocalExpenseIqSyncSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalExpenseIqSyncSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _wifiOnlyMeta = const VerificationMeta(
    'wifiOnly',
  );
  @override
  late final GeneratedColumn<bool> wifiOnly = GeneratedColumn<bool>(
    'wifi_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("wifi_only" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [businessId, enabled, wifiOnly];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_expense_iq_sync_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalExpenseIqSyncSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('wifi_only')) {
      context.handle(
        _wifiOnlyMeta,
        wifiOnly.isAcceptableOrUnknown(data['wifi_only']!, _wifiOnlyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId};
  @override
  LocalExpenseIqSyncSetting map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalExpenseIqSyncSetting(
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      wifiOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}wifi_only'],
      )!,
    );
  }

  @override
  $LocalExpenseIqSyncSettingsTable createAlias(String alias) {
    return $LocalExpenseIqSyncSettingsTable(attachedDatabase, alias);
  }
}

class LocalExpenseIqSyncSetting extends DataClass
    implements Insertable<LocalExpenseIqSyncSetting> {
  final String businessId;
  final bool enabled;
  final bool wifiOnly;
  const LocalExpenseIqSyncSetting({
    required this.businessId,
    required this.enabled,
    required this.wifiOnly,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['enabled'] = Variable<bool>(enabled);
    map['wifi_only'] = Variable<bool>(wifiOnly);
    return map;
  }

  LocalExpenseIqSyncSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalExpenseIqSyncSettingsCompanion(
      businessId: Value(businessId),
      enabled: Value(enabled),
      wifiOnly: Value(wifiOnly),
    );
  }

  factory LocalExpenseIqSyncSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalExpenseIqSyncSetting(
      businessId: serializer.fromJson<String>(json['businessId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      wifiOnly: serializer.fromJson<bool>(json['wifiOnly']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'enabled': serializer.toJson<bool>(enabled),
      'wifiOnly': serializer.toJson<bool>(wifiOnly),
    };
  }

  LocalExpenseIqSyncSetting copyWith({
    String? businessId,
    bool? enabled,
    bool? wifiOnly,
  }) => LocalExpenseIqSyncSetting(
    businessId: businessId ?? this.businessId,
    enabled: enabled ?? this.enabled,
    wifiOnly: wifiOnly ?? this.wifiOnly,
  );
  LocalExpenseIqSyncSetting copyWithCompanion(
    LocalExpenseIqSyncSettingsCompanion data,
  ) {
    return LocalExpenseIqSyncSetting(
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      wifiOnly: data.wifiOnly.present ? data.wifiOnly.value : this.wifiOnly,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpenseIqSyncSetting(')
          ..write('businessId: $businessId, ')
          ..write('enabled: $enabled, ')
          ..write('wifiOnly: $wifiOnly')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(businessId, enabled, wifiOnly);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalExpenseIqSyncSetting &&
          other.businessId == this.businessId &&
          other.enabled == this.enabled &&
          other.wifiOnly == this.wifiOnly);
}

class LocalExpenseIqSyncSettingsCompanion
    extends UpdateCompanion<LocalExpenseIqSyncSetting> {
  final Value<String> businessId;
  final Value<bool> enabled;
  final Value<bool> wifiOnly;
  final Value<int> rowid;
  const LocalExpenseIqSyncSettingsCompanion({
    this.businessId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.wifiOnly = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalExpenseIqSyncSettingsCompanion.insert({
    required String businessId,
    this.enabled = const Value.absent(),
    this.wifiOnly = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId);
  static Insertable<LocalExpenseIqSyncSetting> custom({
    Expression<String>? businessId,
    Expression<bool>? enabled,
    Expression<bool>? wifiOnly,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (enabled != null) 'enabled': enabled,
      if (wifiOnly != null) 'wifi_only': wifiOnly,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalExpenseIqSyncSettingsCompanion copyWith({
    Value<String>? businessId,
    Value<bool>? enabled,
    Value<bool>? wifiOnly,
    Value<int>? rowid,
  }) {
    return LocalExpenseIqSyncSettingsCompanion(
      businessId: businessId ?? this.businessId,
      enabled: enabled ?? this.enabled,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (wifiOnly.present) {
      map['wifi_only'] = Variable<bool>(wifiOnly.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpenseIqSyncSettingsCompanion(')
          ..write('businessId: $businessId, ')
          ..write('enabled: $enabled, ')
          ..write('wifiOnly: $wifiOnly, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BriskersLocalDatabase extends GeneratedDatabase {
  _$BriskersLocalDatabase(QueryExecutor e) : super(e);
  $BriskersLocalDatabaseManager get managers =>
      $BriskersLocalDatabaseManager(this);
  late final $LocalSyncStatesTable localSyncStates = $LocalSyncStatesTable(
    this,
  );
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $LocalCustomersTable localCustomers = $LocalCustomersTable(this);
  late final $LocalVehiclesTable localVehicles = $LocalVehiclesTable(this);
  late final $LocalCustomerVehiclesTable localCustomerVehicles =
      $LocalCustomerVehiclesTable(this);
  late final $LocalAppointmentsTable localAppointments =
      $LocalAppointmentsTable(this);
  late final $LocalKioskSettingsTable localKioskSettings =
      $LocalKioskSettingsTable(this);
  late final $LocalJobsTable localJobs = $LocalJobsTable(this);
  late final $LocalJobStatusesTable localJobStatuses = $LocalJobStatusesTable(
    this,
  );
  late final $LocalJobAssignmentsTable localJobAssignments =
      $LocalJobAssignmentsTable(this);
  late final $LocalJobVisitsTable localJobVisits = $LocalJobVisitsTable(this);
  late final $LocalPreInspectionsTable localPreInspections =
      $LocalPreInspectionsTable(this);
  late final $LocalPreInspectionPhotosTable localPreInspectionPhotos =
      $LocalPreInspectionPhotosTable(this);
  late final $LocalFindingsTable localFindings = $LocalFindingsTable(this);
  late final $LocalFindingPhotosTable localFindingPhotos =
      $LocalFindingPhotosTable(this);
  late final $LocalFinancialCacheTable localFinancialCache =
      $LocalFinancialCacheTable(this);
  late final $LocalCatalogItemsTable localCatalogItems =
      $LocalCatalogItemsTable(this);
  late final $LocalDocumentsTable localDocuments = $LocalDocumentsTable(this);
  late final $LocalExpenseIqPhotosTable localExpenseIqPhotos =
      $LocalExpenseIqPhotosTable(this);
  late final $LocalExpenseIqSyncSettingsTable localExpenseIqSyncSettings =
      $LocalExpenseIqSyncSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localSyncStates,
    syncOutbox,
    localCustomers,
    localVehicles,
    localCustomerVehicles,
    localAppointments,
    localKioskSettings,
    localJobs,
    localJobStatuses,
    localJobAssignments,
    localJobVisits,
    localPreInspections,
    localPreInspectionPhotos,
    localFindings,
    localFindingPhotos,
    localFinancialCache,
    localCatalogItems,
    localDocuments,
    localExpenseIqPhotos,
    localExpenseIqSyncSettings,
  ];
}

typedef $$LocalSyncStatesTableCreateCompanionBuilder =
    LocalSyncStatesCompanion Function({
      required String businessId,
      required String scope,
      Value<int?> lastServerCursor,
      Value<DateTime?> lastPullAt,
      Value<DateTime?> lastPushAt,
      Value<String?> lastError,
      Value<bool> bootstrapped,
      Value<int> rowid,
    });
typedef $$LocalSyncStatesTableUpdateCompanionBuilder =
    LocalSyncStatesCompanion Function({
      Value<String> businessId,
      Value<String> scope,
      Value<int?> lastServerCursor,
      Value<DateTime?> lastPullAt,
      Value<DateTime?> lastPushAt,
      Value<String?> lastError,
      Value<bool> bootstrapped,
      Value<int> rowid,
    });

class $$LocalSyncStatesTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastServerCursor => $composableBuilder(
    column: $table.lastServerCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPullAt => $composableBuilder(
    column: $table.lastPullAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get bootstrapped => $composableBuilder(
    column: $table.bootstrapped,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSyncStatesTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastServerCursor => $composableBuilder(
    column: $table.lastServerCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPullAt => $composableBuilder(
    column: $table.lastPullAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get bootstrapped => $composableBuilder(
    column: $table.bootstrapped,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSyncStatesTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get lastServerCursor => $composableBuilder(
    column: $table.lastServerCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPullAt => $composableBuilder(
    column: $table.lastPullAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<bool> get bootstrapped => $composableBuilder(
    column: $table.bootstrapped,
    builder: (column) => column,
  );
}

class $$LocalSyncStatesTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalSyncStatesTable,
          LocalSyncState,
          $$LocalSyncStatesTableFilterComposer,
          $$LocalSyncStatesTableOrderingComposer,
          $$LocalSyncStatesTableAnnotationComposer,
          $$LocalSyncStatesTableCreateCompanionBuilder,
          $$LocalSyncStatesTableUpdateCompanionBuilder,
          (
            LocalSyncState,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalSyncStatesTable,
              LocalSyncState
            >,
          ),
          LocalSyncState,
          PrefetchHooks Function()
        > {
  $$LocalSyncStatesTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalSyncStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int?> lastServerCursor = const Value.absent(),
                Value<DateTime?> lastPullAt = const Value.absent(),
                Value<DateTime?> lastPushAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<bool> bootstrapped = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncStatesCompanion(
                businessId: businessId,
                scope: scope,
                lastServerCursor: lastServerCursor,
                lastPullAt: lastPullAt,
                lastPushAt: lastPushAt,
                lastError: lastError,
                bootstrapped: bootstrapped,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String scope,
                Value<int?> lastServerCursor = const Value.absent(),
                Value<DateTime?> lastPullAt = const Value.absent(),
                Value<DateTime?> lastPushAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<bool> bootstrapped = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncStatesCompanion.insert(
                businessId: businessId,
                scope: scope,
                lastServerCursor: lastServerCursor,
                lastPullAt: lastPullAt,
                lastPushAt: lastPushAt,
                lastError: lastError,
                bootstrapped: bootstrapped,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalSyncStatesTable,
      LocalSyncState,
      $$LocalSyncStatesTableFilterComposer,
      $$LocalSyncStatesTableOrderingComposer,
      $$LocalSyncStatesTableAnnotationComposer,
      $$LocalSyncStatesTableCreateCompanionBuilder,
      $$LocalSyncStatesTableUpdateCompanionBuilder,
      (
        LocalSyncState,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalSyncStatesTable,
          LocalSyncState
        >,
      ),
      LocalSyncState,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      required String businessId,
      required String entityType,
      required String entityId,
      required String operation,
      required String payloadJson,
      Value<int?> baseRowVersion,
      Value<String> state,
      Value<int> attemptCount,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      Value<String> businessId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payloadJson,
      Value<int?> baseRowVersion,
      Value<String> state,
      Value<int> attemptCount,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastError,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<
              _$BriskersLocalDatabase,
              $SyncOutboxTable,
              SyncOutboxData
            >,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(
    _$BriskersLocalDatabase db,
    $SyncOutboxTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int?> baseRowVersion = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                businessId: businessId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                baseRowVersion: baseRowVersion,
                state: state,
                attemptCount: attemptCount,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String businessId,
                required String entityType,
                required String entityId,
                required String operation,
                required String payloadJson,
                Value<int?> baseRowVersion = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                id: id,
                businessId: businessId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                baseRowVersion: baseRowVersion,
                state: state,
                attemptCount: attemptCount,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<
          _$BriskersLocalDatabase,
          $SyncOutboxTable,
          SyncOutboxData
        >,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$LocalCustomersTableCreateCompanionBuilder =
    LocalCustomersCompanion Function({
      required String id,
      required String businessId,
      required String displayName,
      Value<bool> isCompany,
      Value<String?> email,
      Value<String?> phone,
      Value<String?> listEmail,
      Value<String?> listPhone,
      Value<String> billingAddressJson,
      Value<bool> taxable,
      Value<bool> problemFlag,
      Value<String?> problemFlagNote,
      Value<String> contactsJson,
      Value<DateTime?> createdAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalCustomersTableUpdateCompanionBuilder =
    LocalCustomersCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> displayName,
      Value<bool> isCompany,
      Value<String?> email,
      Value<String?> phone,
      Value<String?> listEmail,
      Value<String?> listPhone,
      Value<String> billingAddressJson,
      Value<bool> taxable,
      Value<bool> problemFlag,
      Value<String?> problemFlagNote,
      Value<String> contactsJson,
      Value<DateTime?> createdAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalCustomersTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompany => $composableBuilder(
    column: $table.isCompany,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listEmail => $composableBuilder(
    column: $table.listEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listPhone => $composableBuilder(
    column: $table.listPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get billingAddressJson => $composableBuilder(
    column: $table.billingAddressJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get taxable => $composableBuilder(
    column: $table.taxable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get problemFlag => $composableBuilder(
    column: $table.problemFlag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get problemFlagNote => $composableBuilder(
    column: $table.problemFlagNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactsJson => $composableBuilder(
    column: $table.contactsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCustomersTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompany => $composableBuilder(
    column: $table.isCompany,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listEmail => $composableBuilder(
    column: $table.listEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listPhone => $composableBuilder(
    column: $table.listPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get billingAddressJson => $composableBuilder(
    column: $table.billingAddressJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get taxable => $composableBuilder(
    column: $table.taxable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get problemFlag => $composableBuilder(
    column: $table.problemFlag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get problemFlagNote => $composableBuilder(
    column: $table.problemFlagNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactsJson => $composableBuilder(
    column: $table.contactsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCustomersTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompany =>
      $composableBuilder(column: $table.isCompany, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get listEmail =>
      $composableBuilder(column: $table.listEmail, builder: (column) => column);

  GeneratedColumn<String> get listPhone =>
      $composableBuilder(column: $table.listPhone, builder: (column) => column);

  GeneratedColumn<String> get billingAddressJson => $composableBuilder(
    column: $table.billingAddressJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get taxable =>
      $composableBuilder(column: $table.taxable, builder: (column) => column);

  GeneratedColumn<bool> get problemFlag => $composableBuilder(
    column: $table.problemFlag,
    builder: (column) => column,
  );

  GeneratedColumn<String> get problemFlagNote => $composableBuilder(
    column: $table.problemFlagNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contactsJson => $composableBuilder(
    column: $table.contactsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalCustomersTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalCustomersTable,
          LocalCustomer,
          $$LocalCustomersTableFilterComposer,
          $$LocalCustomersTableOrderingComposer,
          $$LocalCustomersTableAnnotationComposer,
          $$LocalCustomersTableCreateCompanionBuilder,
          $$LocalCustomersTableUpdateCompanionBuilder,
          (
            LocalCustomer,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalCustomersTable,
              LocalCustomer
            >,
          ),
          LocalCustomer,
          PrefetchHooks Function()
        > {
  $$LocalCustomersTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalCustomersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<bool> isCompany = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> listEmail = const Value.absent(),
                Value<String?> listPhone = const Value.absent(),
                Value<String> billingAddressJson = const Value.absent(),
                Value<bool> taxable = const Value.absent(),
                Value<bool> problemFlag = const Value.absent(),
                Value<String?> problemFlagNote = const Value.absent(),
                Value<String> contactsJson = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomersCompanion(
                id: id,
                businessId: businessId,
                displayName: displayName,
                isCompany: isCompany,
                email: email,
                phone: phone,
                listEmail: listEmail,
                listPhone: listPhone,
                billingAddressJson: billingAddressJson,
                taxable: taxable,
                problemFlag: problemFlag,
                problemFlagNote: problemFlagNote,
                contactsJson: contactsJson,
                createdAt: createdAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String displayName,
                Value<bool> isCompany = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> listEmail = const Value.absent(),
                Value<String?> listPhone = const Value.absent(),
                Value<String> billingAddressJson = const Value.absent(),
                Value<bool> taxable = const Value.absent(),
                Value<bool> problemFlag = const Value.absent(),
                Value<String?> problemFlagNote = const Value.absent(),
                Value<String> contactsJson = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomersCompanion.insert(
                id: id,
                businessId: businessId,
                displayName: displayName,
                isCompany: isCompany,
                email: email,
                phone: phone,
                listEmail: listEmail,
                listPhone: listPhone,
                billingAddressJson: billingAddressJson,
                taxable: taxable,
                problemFlag: problemFlag,
                problemFlagNote: problemFlagNote,
                contactsJson: contactsJson,
                createdAt: createdAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalCustomersTable,
      LocalCustomer,
      $$LocalCustomersTableFilterComposer,
      $$LocalCustomersTableOrderingComposer,
      $$LocalCustomersTableAnnotationComposer,
      $$LocalCustomersTableCreateCompanionBuilder,
      $$LocalCustomersTableUpdateCompanionBuilder,
      (
        LocalCustomer,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalCustomersTable,
          LocalCustomer
        >,
      ),
      LocalCustomer,
      PrefetchHooks Function()
    >;
typedef $$LocalVehiclesTableCreateCompanionBuilder =
    LocalVehiclesCompanion Function({
      required String id,
      required String businessId,
      Value<int?> year,
      Value<String?> make,
      Value<String?> model,
      Value<String?> vin,
      Value<String?> licensePlate,
      Value<String?> licenseState,
      Value<double?> mileage,
      Value<String?> mileageRecordedDate,
      Value<String?> mileageSourceInvoiceId,
      Value<String?> color,
      Value<String?> keyPassword,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalVehiclesTableUpdateCompanionBuilder =
    LocalVehiclesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<int?> year,
      Value<String?> make,
      Value<String?> model,
      Value<String?> vin,
      Value<String?> licensePlate,
      Value<String?> licenseState,
      Value<double?> mileage,
      Value<String?> mileageRecordedDate,
      Value<String?> mileageSourceInvoiceId,
      Value<String?> color,
      Value<String?> keyPassword,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalVehiclesTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalVehiclesTable> {
  $$LocalVehiclesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get make => $composableBuilder(
    column: $table.make,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vin => $composableBuilder(
    column: $table.vin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get licensePlate => $composableBuilder(
    column: $table.licensePlate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get licenseState => $composableBuilder(
    column: $table.licenseState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get mileage => $composableBuilder(
    column: $table.mileage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mileageRecordedDate => $composableBuilder(
    column: $table.mileageRecordedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mileageSourceInvoiceId => $composableBuilder(
    column: $table.mileageSourceInvoiceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyPassword => $composableBuilder(
    column: $table.keyPassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalVehiclesTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalVehiclesTable> {
  $$LocalVehiclesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get make => $composableBuilder(
    column: $table.make,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vin => $composableBuilder(
    column: $table.vin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get licensePlate => $composableBuilder(
    column: $table.licensePlate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get licenseState => $composableBuilder(
    column: $table.licenseState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get mileage => $composableBuilder(
    column: $table.mileage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mileageRecordedDate => $composableBuilder(
    column: $table.mileageRecordedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mileageSourceInvoiceId => $composableBuilder(
    column: $table.mileageSourceInvoiceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyPassword => $composableBuilder(
    column: $table.keyPassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalVehiclesTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalVehiclesTable> {
  $$LocalVehiclesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get make =>
      $composableBuilder(column: $table.make, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get vin =>
      $composableBuilder(column: $table.vin, builder: (column) => column);

  GeneratedColumn<String> get licensePlate => $composableBuilder(
    column: $table.licensePlate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get licenseState => $composableBuilder(
    column: $table.licenseState,
    builder: (column) => column,
  );

  GeneratedColumn<double> get mileage =>
      $composableBuilder(column: $table.mileage, builder: (column) => column);

  GeneratedColumn<String> get mileageRecordedDate => $composableBuilder(
    column: $table.mileageRecordedDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mileageSourceInvoiceId => $composableBuilder(
    column: $table.mileageSourceInvoiceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get keyPassword => $composableBuilder(
    column: $table.keyPassword,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalVehiclesTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalVehiclesTable,
          LocalVehicle,
          $$LocalVehiclesTableFilterComposer,
          $$LocalVehiclesTableOrderingComposer,
          $$LocalVehiclesTableAnnotationComposer,
          $$LocalVehiclesTableCreateCompanionBuilder,
          $$LocalVehiclesTableUpdateCompanionBuilder,
          (
            LocalVehicle,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalVehiclesTable,
              LocalVehicle
            >,
          ),
          LocalVehicle,
          PrefetchHooks Function()
        > {
  $$LocalVehiclesTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalVehiclesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalVehiclesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalVehiclesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalVehiclesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> make = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> vin = const Value.absent(),
                Value<String?> licensePlate = const Value.absent(),
                Value<String?> licenseState = const Value.absent(),
                Value<double?> mileage = const Value.absent(),
                Value<String?> mileageRecordedDate = const Value.absent(),
                Value<String?> mileageSourceInvoiceId = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> keyPassword = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalVehiclesCompanion(
                id: id,
                businessId: businessId,
                year: year,
                make: make,
                model: model,
                vin: vin,
                licensePlate: licensePlate,
                licenseState: licenseState,
                mileage: mileage,
                mileageRecordedDate: mileageRecordedDate,
                mileageSourceInvoiceId: mileageSourceInvoiceId,
                color: color,
                keyPassword: keyPassword,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                Value<int?> year = const Value.absent(),
                Value<String?> make = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> vin = const Value.absent(),
                Value<String?> licensePlate = const Value.absent(),
                Value<String?> licenseState = const Value.absent(),
                Value<double?> mileage = const Value.absent(),
                Value<String?> mileageRecordedDate = const Value.absent(),
                Value<String?> mileageSourceInvoiceId = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> keyPassword = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalVehiclesCompanion.insert(
                id: id,
                businessId: businessId,
                year: year,
                make: make,
                model: model,
                vin: vin,
                licensePlate: licensePlate,
                licenseState: licenseState,
                mileage: mileage,
                mileageRecordedDate: mileageRecordedDate,
                mileageSourceInvoiceId: mileageSourceInvoiceId,
                color: color,
                keyPassword: keyPassword,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalVehiclesTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalVehiclesTable,
      LocalVehicle,
      $$LocalVehiclesTableFilterComposer,
      $$LocalVehiclesTableOrderingComposer,
      $$LocalVehiclesTableAnnotationComposer,
      $$LocalVehiclesTableCreateCompanionBuilder,
      $$LocalVehiclesTableUpdateCompanionBuilder,
      (
        LocalVehicle,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalVehiclesTable,
          LocalVehicle
        >,
      ),
      LocalVehicle,
      PrefetchHooks Function()
    >;
typedef $$LocalCustomerVehiclesTableCreateCompanionBuilder =
    LocalCustomerVehiclesCompanion Function({
      required String businessId,
      required String customerId,
      required String vehicleId,
      Value<bool> isPrimary,
      Value<int> rowid,
    });
typedef $$LocalCustomerVehiclesTableUpdateCompanionBuilder =
    LocalCustomerVehiclesCompanion Function({
      Value<String> businessId,
      Value<String> customerId,
      Value<String> vehicleId,
      Value<bool> isPrimary,
      Value<int> rowid,
    });

class $$LocalCustomerVehiclesTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomerVehiclesTable> {
  $$LocalCustomerVehiclesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCustomerVehiclesTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomerVehiclesTable> {
  $$LocalCustomerVehiclesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCustomerVehiclesTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCustomerVehiclesTable> {
  $$LocalCustomerVehiclesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);
}

class $$LocalCustomerVehiclesTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalCustomerVehiclesTable,
          LocalCustomerVehicle,
          $$LocalCustomerVehiclesTableFilterComposer,
          $$LocalCustomerVehiclesTableOrderingComposer,
          $$LocalCustomerVehiclesTableAnnotationComposer,
          $$LocalCustomerVehiclesTableCreateCompanionBuilder,
          $$LocalCustomerVehiclesTableUpdateCompanionBuilder,
          (
            LocalCustomerVehicle,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalCustomerVehiclesTable,
              LocalCustomerVehicle
            >,
          ),
          LocalCustomerVehicle,
          PrefetchHooks Function()
        > {
  $$LocalCustomerVehiclesTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalCustomerVehiclesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCustomerVehiclesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalCustomerVehiclesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCustomerVehiclesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<String> vehicleId = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomerVehiclesCompanion(
                businessId: businessId,
                customerId: customerId,
                vehicleId: vehicleId,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String customerId,
                required String vehicleId,
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomerVehiclesCompanion.insert(
                businessId: businessId,
                customerId: customerId,
                vehicleId: vehicleId,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCustomerVehiclesTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalCustomerVehiclesTable,
      LocalCustomerVehicle,
      $$LocalCustomerVehiclesTableFilterComposer,
      $$LocalCustomerVehiclesTableOrderingComposer,
      $$LocalCustomerVehiclesTableAnnotationComposer,
      $$LocalCustomerVehiclesTableCreateCompanionBuilder,
      $$LocalCustomerVehiclesTableUpdateCompanionBuilder,
      (
        LocalCustomerVehicle,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalCustomerVehiclesTable,
          LocalCustomerVehicle
        >,
      ),
      LocalCustomerVehicle,
      PrefetchHooks Function()
    >;
typedef $$LocalAppointmentsTableCreateCompanionBuilder =
    LocalAppointmentsCompanion Function({
      required String id,
      required String businessId,
      required String customerId,
      Value<String?> vehicleId,
      Value<String?> employeeId,
      Value<String?> jobId,
      Value<String?> requestId,
      required DateTime startsAt,
      required DateTime endsAt,
      required String status,
      required String title,
      Value<String?> description,
      Value<String?> customerName,
      Value<String?> customerPhoneNorm,
      Value<int?> vehicleYear,
      Value<String?> vehicleMake,
      Value<String?> vehicleModel,
      Value<String?> vehicleLabel,
      Value<String?> mechanicName,
      Value<bool> canCheckIn,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalAppointmentsTableUpdateCompanionBuilder =
    LocalAppointmentsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> customerId,
      Value<String?> vehicleId,
      Value<String?> employeeId,
      Value<String?> jobId,
      Value<String?> requestId,
      Value<DateTime> startsAt,
      Value<DateTime> endsAt,
      Value<String> status,
      Value<String> title,
      Value<String?> description,
      Value<String?> customerName,
      Value<String?> customerPhoneNorm,
      Value<int?> vehicleYear,
      Value<String?> vehicleMake,
      Value<String?> vehicleModel,
      Value<String?> vehicleLabel,
      Value<String?> mechanicName,
      Value<bool> canCheckIn,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalAppointmentsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalAppointmentsTable> {
  $$LocalAppointmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerPhoneNorm => $composableBuilder(
    column: $table.customerPhoneNorm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vehicleYear => $composableBuilder(
    column: $table.vehicleYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleMake => $composableBuilder(
    column: $table.vehicleMake,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mechanicName => $composableBuilder(
    column: $table.mechanicName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canCheckIn => $composableBuilder(
    column: $table.canCheckIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAppointmentsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalAppointmentsTable> {
  $$LocalAppointmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerPhoneNorm => $composableBuilder(
    column: $table.customerPhoneNorm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vehicleYear => $composableBuilder(
    column: $table.vehicleYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleMake => $composableBuilder(
    column: $table.vehicleMake,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mechanicName => $composableBuilder(
    column: $table.mechanicName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canCheckIn => $composableBuilder(
    column: $table.canCheckIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAppointmentsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalAppointmentsTable> {
  $$LocalAppointmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<DateTime> get startsAt =>
      $composableBuilder(column: $table.startsAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerPhoneNorm => $composableBuilder(
    column: $table.customerPhoneNorm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vehicleYear => $composableBuilder(
    column: $table.vehicleYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleMake => $composableBuilder(
    column: $table.vehicleMake,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mechanicName => $composableBuilder(
    column: $table.mechanicName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get canCheckIn => $composableBuilder(
    column: $table.canCheckIn,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalAppointmentsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalAppointmentsTable,
          LocalAppointment,
          $$LocalAppointmentsTableFilterComposer,
          $$LocalAppointmentsTableOrderingComposer,
          $$LocalAppointmentsTableAnnotationComposer,
          $$LocalAppointmentsTableCreateCompanionBuilder,
          $$LocalAppointmentsTableUpdateCompanionBuilder,
          (
            LocalAppointment,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalAppointmentsTable,
              LocalAppointment
            >,
          ),
          LocalAppointment,
          PrefetchHooks Function()
        > {
  $$LocalAppointmentsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalAppointmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAppointmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAppointmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAppointmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> employeeId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                Value<DateTime> startsAt = const Value.absent(),
                Value<DateTime> endsAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<String?> customerPhoneNorm = const Value.absent(),
                Value<int?> vehicleYear = const Value.absent(),
                Value<String?> vehicleMake = const Value.absent(),
                Value<String?> vehicleModel = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> mechanicName = const Value.absent(),
                Value<bool> canCheckIn = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAppointmentsCompanion(
                id: id,
                businessId: businessId,
                customerId: customerId,
                vehicleId: vehicleId,
                employeeId: employeeId,
                jobId: jobId,
                requestId: requestId,
                startsAt: startsAt,
                endsAt: endsAt,
                status: status,
                title: title,
                description: description,
                customerName: customerName,
                customerPhoneNorm: customerPhoneNorm,
                vehicleYear: vehicleYear,
                vehicleMake: vehicleMake,
                vehicleModel: vehicleModel,
                vehicleLabel: vehicleLabel,
                mechanicName: mechanicName,
                canCheckIn: canCheckIn,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String customerId,
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> employeeId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                required DateTime startsAt,
                required DateTime endsAt,
                required String status,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<String?> customerPhoneNorm = const Value.absent(),
                Value<int?> vehicleYear = const Value.absent(),
                Value<String?> vehicleMake = const Value.absent(),
                Value<String?> vehicleModel = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> mechanicName = const Value.absent(),
                Value<bool> canCheckIn = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAppointmentsCompanion.insert(
                id: id,
                businessId: businessId,
                customerId: customerId,
                vehicleId: vehicleId,
                employeeId: employeeId,
                jobId: jobId,
                requestId: requestId,
                startsAt: startsAt,
                endsAt: endsAt,
                status: status,
                title: title,
                description: description,
                customerName: customerName,
                customerPhoneNorm: customerPhoneNorm,
                vehicleYear: vehicleYear,
                vehicleMake: vehicleMake,
                vehicleModel: vehicleModel,
                vehicleLabel: vehicleLabel,
                mechanicName: mechanicName,
                canCheckIn: canCheckIn,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAppointmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalAppointmentsTable,
      LocalAppointment,
      $$LocalAppointmentsTableFilterComposer,
      $$LocalAppointmentsTableOrderingComposer,
      $$LocalAppointmentsTableAnnotationComposer,
      $$LocalAppointmentsTableCreateCompanionBuilder,
      $$LocalAppointmentsTableUpdateCompanionBuilder,
      (
        LocalAppointment,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalAppointmentsTable,
          LocalAppointment
        >,
      ),
      LocalAppointment,
      PrefetchHooks Function()
    >;
typedef $$LocalKioskSettingsTableCreateCompanionBuilder =
    LocalKioskSettingsCompanion Function({
      required String businessId,
      Value<String?> disclaimerId,
      Value<int?> disclaimerVersion,
      Value<String?> disclaimerText,
      Value<DateTime?> serverUpdatedAt,
      Value<int> rowid,
    });
typedef $$LocalKioskSettingsTableUpdateCompanionBuilder =
    LocalKioskSettingsCompanion Function({
      Value<String> businessId,
      Value<String?> disclaimerId,
      Value<int?> disclaimerVersion,
      Value<String?> disclaimerText,
      Value<DateTime?> serverUpdatedAt,
      Value<int> rowid,
    });

class $$LocalKioskSettingsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalKioskSettingsTable> {
  $$LocalKioskSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get disclaimerId => $composableBuilder(
    column: $table.disclaimerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get disclaimerVersion => $composableBuilder(
    column: $table.disclaimerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get disclaimerText => $composableBuilder(
    column: $table.disclaimerText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalKioskSettingsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalKioskSettingsTable> {
  $$LocalKioskSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get disclaimerId => $composableBuilder(
    column: $table.disclaimerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get disclaimerVersion => $composableBuilder(
    column: $table.disclaimerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get disclaimerText => $composableBuilder(
    column: $table.disclaimerText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalKioskSettingsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalKioskSettingsTable> {
  $$LocalKioskSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get disclaimerId => $composableBuilder(
    column: $table.disclaimerId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get disclaimerVersion => $composableBuilder(
    column: $table.disclaimerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get disclaimerText => $composableBuilder(
    column: $table.disclaimerText,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );
}

class $$LocalKioskSettingsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalKioskSettingsTable,
          LocalKioskSetting,
          $$LocalKioskSettingsTableFilterComposer,
          $$LocalKioskSettingsTableOrderingComposer,
          $$LocalKioskSettingsTableAnnotationComposer,
          $$LocalKioskSettingsTableCreateCompanionBuilder,
          $$LocalKioskSettingsTableUpdateCompanionBuilder,
          (
            LocalKioskSetting,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalKioskSettingsTable,
              LocalKioskSetting
            >,
          ),
          LocalKioskSetting,
          PrefetchHooks Function()
        > {
  $$LocalKioskSettingsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalKioskSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalKioskSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalKioskSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalKioskSettingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String?> disclaimerId = const Value.absent(),
                Value<int?> disclaimerVersion = const Value.absent(),
                Value<String?> disclaimerText = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalKioskSettingsCompanion(
                businessId: businessId,
                disclaimerId: disclaimerId,
                disclaimerVersion: disclaimerVersion,
                disclaimerText: disclaimerText,
                serverUpdatedAt: serverUpdatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                Value<String?> disclaimerId = const Value.absent(),
                Value<int?> disclaimerVersion = const Value.absent(),
                Value<String?> disclaimerText = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalKioskSettingsCompanion.insert(
                businessId: businessId,
                disclaimerId: disclaimerId,
                disclaimerVersion: disclaimerVersion,
                disclaimerText: disclaimerText,
                serverUpdatedAt: serverUpdatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalKioskSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalKioskSettingsTable,
      LocalKioskSetting,
      $$LocalKioskSettingsTableFilterComposer,
      $$LocalKioskSettingsTableOrderingComposer,
      $$LocalKioskSettingsTableAnnotationComposer,
      $$LocalKioskSettingsTableCreateCompanionBuilder,
      $$LocalKioskSettingsTableUpdateCompanionBuilder,
      (
        LocalKioskSetting,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalKioskSettingsTable,
          LocalKioskSetting
        >,
      ),
      LocalKioskSetting,
      PrefetchHooks Function()
    >;
typedef $$LocalJobsTableCreateCompanionBuilder =
    LocalJobsCompanion Function({
      required String id,
      required String businessId,
      required String accessScope,
      Value<String?> jobNumber,
      required String title,
      Value<String?> requestedWork,
      required String status,
      Value<String?> statusName,
      Value<String?> statusColor,
      Value<String?> statusIcon,
      Value<String?> customerId,
      Value<String?> customerName,
      Value<bool> customerProblemFlag,
      Value<String?> customerProblemFlagNote,
      Value<String> capabilitiesJson,
      Value<int> pendingRequestCount,
      Value<String?> paymentState,
      Value<String?> vehicleId,
      Value<String?> vehicleLabel,
      Value<String?> vehicleVin,
      Value<String?> vehiclePlate,
      Value<double> plannedHours,
      Value<double?> odometerIn,
      Value<String?> assignedEmployeeId,
      Value<String?> assignedEmployeeName,
      Value<String?> assignedPosition,
      Value<bool> isUnassigned,
      Value<DateTime?> createdAt,
      Value<DateTime?> completedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalJobsTableUpdateCompanionBuilder =
    LocalJobsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> accessScope,
      Value<String?> jobNumber,
      Value<String> title,
      Value<String?> requestedWork,
      Value<String> status,
      Value<String?> statusName,
      Value<String?> statusColor,
      Value<String?> statusIcon,
      Value<String?> customerId,
      Value<String?> customerName,
      Value<bool> customerProblemFlag,
      Value<String?> customerProblemFlagNote,
      Value<String> capabilitiesJson,
      Value<int> pendingRequestCount,
      Value<String?> paymentState,
      Value<String?> vehicleId,
      Value<String?> vehicleLabel,
      Value<String?> vehicleVin,
      Value<String?> vehiclePlate,
      Value<double> plannedHours,
      Value<double?> odometerIn,
      Value<String?> assignedEmployeeId,
      Value<String?> assignedEmployeeName,
      Value<String?> assignedPosition,
      Value<bool> isUnassigned,
      Value<DateTime?> createdAt,
      Value<DateTime?> completedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalJobsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobsTable> {
  $$LocalJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessScope => $composableBuilder(
    column: $table.accessScope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobNumber => $composableBuilder(
    column: $table.jobNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestedWork => $composableBuilder(
    column: $table.requestedWork,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusName => $composableBuilder(
    column: $table.statusName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusColor => $composableBuilder(
    column: $table.statusColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusIcon => $composableBuilder(
    column: $table.statusIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get customerProblemFlag => $composableBuilder(
    column: $table.customerProblemFlag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerProblemFlagNote => $composableBuilder(
    column: $table.customerProblemFlagNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingRequestCount => $composableBuilder(
    column: $table.pendingRequestCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentState => $composableBuilder(
    column: $table.paymentState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleVin => $composableBuilder(
    column: $table.vehicleVin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehiclePlate => $composableBuilder(
    column: $table.vehiclePlate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get odometerIn => $composableBuilder(
    column: $table.odometerIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedEmployeeId => $composableBuilder(
    column: $table.assignedEmployeeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedEmployeeName => $composableBuilder(
    column: $table.assignedEmployeeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedPosition => $composableBuilder(
    column: $table.assignedPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUnassigned => $composableBuilder(
    column: $table.isUnassigned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalJobsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobsTable> {
  $$LocalJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessScope => $composableBuilder(
    column: $table.accessScope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobNumber => $composableBuilder(
    column: $table.jobNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedWork => $composableBuilder(
    column: $table.requestedWork,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusName => $composableBuilder(
    column: $table.statusName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusColor => $composableBuilder(
    column: $table.statusColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusIcon => $composableBuilder(
    column: $table.statusIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get customerProblemFlag => $composableBuilder(
    column: $table.customerProblemFlag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerProblemFlagNote => $composableBuilder(
    column: $table.customerProblemFlagNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingRequestCount => $composableBuilder(
    column: $table.pendingRequestCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentState => $composableBuilder(
    column: $table.paymentState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleVin => $composableBuilder(
    column: $table.vehicleVin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehiclePlate => $composableBuilder(
    column: $table.vehiclePlate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get odometerIn => $composableBuilder(
    column: $table.odometerIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedEmployeeId => $composableBuilder(
    column: $table.assignedEmployeeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedEmployeeName => $composableBuilder(
    column: $table.assignedEmployeeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedPosition => $composableBuilder(
    column: $table.assignedPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUnassigned => $composableBuilder(
    column: $table.isUnassigned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalJobsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobsTable> {
  $$LocalJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accessScope => $composableBuilder(
    column: $table.accessScope,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobNumber =>
      $composableBuilder(column: $table.jobNumber, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get requestedWork => $composableBuilder(
    column: $table.requestedWork,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get statusName => $composableBuilder(
    column: $table.statusName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusColor => $composableBuilder(
    column: $table.statusColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusIcon => $composableBuilder(
    column: $table.statusIcon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get customerProblemFlag => $composableBuilder(
    column: $table.customerProblemFlag,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerProblemFlagNote => $composableBuilder(
    column: $table.customerProblemFlagNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pendingRequestCount => $composableBuilder(
    column: $table.pendingRequestCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentState => $composableBuilder(
    column: $table.paymentState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<String> get vehicleLabel => $composableBuilder(
    column: $table.vehicleLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleVin => $composableBuilder(
    column: $table.vehicleVin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehiclePlate => $composableBuilder(
    column: $table.vehiclePlate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => column,
  );

  GeneratedColumn<double> get odometerIn => $composableBuilder(
    column: $table.odometerIn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assignedEmployeeId => $composableBuilder(
    column: $table.assignedEmployeeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assignedEmployeeName => $composableBuilder(
    column: $table.assignedEmployeeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assignedPosition => $composableBuilder(
    column: $table.assignedPosition,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isUnassigned => $composableBuilder(
    column: $table.isUnassigned,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalJobsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalJobsTable,
          LocalJob,
          $$LocalJobsTableFilterComposer,
          $$LocalJobsTableOrderingComposer,
          $$LocalJobsTableAnnotationComposer,
          $$LocalJobsTableCreateCompanionBuilder,
          $$LocalJobsTableUpdateCompanionBuilder,
          (
            LocalJob,
            BaseReferences<_$BriskersLocalDatabase, $LocalJobsTable, LocalJob>,
          ),
          LocalJob,
          PrefetchHooks Function()
        > {
  $$LocalJobsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> accessScope = const Value.absent(),
                Value<String?> jobNumber = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> requestedWork = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> statusName = const Value.absent(),
                Value<String?> statusColor = const Value.absent(),
                Value<String?> statusIcon = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<bool> customerProblemFlag = const Value.absent(),
                Value<String?> customerProblemFlagNote = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<int> pendingRequestCount = const Value.absent(),
                Value<String?> paymentState = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> vehicleVin = const Value.absent(),
                Value<String?> vehiclePlate = const Value.absent(),
                Value<double> plannedHours = const Value.absent(),
                Value<double?> odometerIn = const Value.absent(),
                Value<String?> assignedEmployeeId = const Value.absent(),
                Value<String?> assignedEmployeeName = const Value.absent(),
                Value<String?> assignedPosition = const Value.absent(),
                Value<bool> isUnassigned = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobsCompanion(
                id: id,
                businessId: businessId,
                accessScope: accessScope,
                jobNumber: jobNumber,
                title: title,
                requestedWork: requestedWork,
                status: status,
                statusName: statusName,
                statusColor: statusColor,
                statusIcon: statusIcon,
                customerId: customerId,
                customerName: customerName,
                customerProblemFlag: customerProblemFlag,
                customerProblemFlagNote: customerProblemFlagNote,
                capabilitiesJson: capabilitiesJson,
                pendingRequestCount: pendingRequestCount,
                paymentState: paymentState,
                vehicleId: vehicleId,
                vehicleLabel: vehicleLabel,
                vehicleVin: vehicleVin,
                vehiclePlate: vehiclePlate,
                plannedHours: plannedHours,
                odometerIn: odometerIn,
                assignedEmployeeId: assignedEmployeeId,
                assignedEmployeeName: assignedEmployeeName,
                assignedPosition: assignedPosition,
                isUnassigned: isUnassigned,
                createdAt: createdAt,
                completedAt: completedAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String accessScope,
                Value<String?> jobNumber = const Value.absent(),
                required String title,
                Value<String?> requestedWork = const Value.absent(),
                required String status,
                Value<String?> statusName = const Value.absent(),
                Value<String?> statusColor = const Value.absent(),
                Value<String?> statusIcon = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<bool> customerProblemFlag = const Value.absent(),
                Value<String?> customerProblemFlagNote = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<int> pendingRequestCount = const Value.absent(),
                Value<String?> paymentState = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> vehicleLabel = const Value.absent(),
                Value<String?> vehicleVin = const Value.absent(),
                Value<String?> vehiclePlate = const Value.absent(),
                Value<double> plannedHours = const Value.absent(),
                Value<double?> odometerIn = const Value.absent(),
                Value<String?> assignedEmployeeId = const Value.absent(),
                Value<String?> assignedEmployeeName = const Value.absent(),
                Value<String?> assignedPosition = const Value.absent(),
                Value<bool> isUnassigned = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobsCompanion.insert(
                id: id,
                businessId: businessId,
                accessScope: accessScope,
                jobNumber: jobNumber,
                title: title,
                requestedWork: requestedWork,
                status: status,
                statusName: statusName,
                statusColor: statusColor,
                statusIcon: statusIcon,
                customerId: customerId,
                customerName: customerName,
                customerProblemFlag: customerProblemFlag,
                customerProblemFlagNote: customerProblemFlagNote,
                capabilitiesJson: capabilitiesJson,
                pendingRequestCount: pendingRequestCount,
                paymentState: paymentState,
                vehicleId: vehicleId,
                vehicleLabel: vehicleLabel,
                vehicleVin: vehicleVin,
                vehiclePlate: vehiclePlate,
                plannedHours: plannedHours,
                odometerIn: odometerIn,
                assignedEmployeeId: assignedEmployeeId,
                assignedEmployeeName: assignedEmployeeName,
                assignedPosition: assignedPosition,
                isUnassigned: isUnassigned,
                createdAt: createdAt,
                completedAt: completedAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalJobsTable,
      LocalJob,
      $$LocalJobsTableFilterComposer,
      $$LocalJobsTableOrderingComposer,
      $$LocalJobsTableAnnotationComposer,
      $$LocalJobsTableCreateCompanionBuilder,
      $$LocalJobsTableUpdateCompanionBuilder,
      (
        LocalJob,
        BaseReferences<_$BriskersLocalDatabase, $LocalJobsTable, LocalJob>,
      ),
      LocalJob,
      PrefetchHooks Function()
    >;
typedef $$LocalJobStatusesTableCreateCompanionBuilder =
    LocalJobStatusesCompanion Function({
      required String businessId,
      required String code,
      required String name,
      Value<String?> colorHex,
      Value<String?> iconKey,
      Value<int> sortOrder,
      Value<int> rowid,
    });
typedef $$LocalJobStatusesTableUpdateCompanionBuilder =
    LocalJobStatusesCompanion Function({
      Value<String> businessId,
      Value<String> code,
      Value<String> name,
      Value<String?> colorHex,
      Value<String?> iconKey,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$LocalJobStatusesTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobStatusesTable> {
  $$LocalJobStatusesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalJobStatusesTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobStatusesTable> {
  $$LocalJobStatusesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconKey => $composableBuilder(
    column: $table.iconKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalJobStatusesTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobStatusesTable> {
  $$LocalJobStatusesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get iconKey =>
      $composableBuilder(column: $table.iconKey, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$LocalJobStatusesTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalJobStatusesTable,
          LocalJobStatuse,
          $$LocalJobStatusesTableFilterComposer,
          $$LocalJobStatusesTableOrderingComposer,
          $$LocalJobStatusesTableAnnotationComposer,
          $$LocalJobStatusesTableCreateCompanionBuilder,
          $$LocalJobStatusesTableUpdateCompanionBuilder,
          (
            LocalJobStatuse,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalJobStatusesTable,
              LocalJobStatuse
            >,
          ),
          LocalJobStatuse,
          PrefetchHooks Function()
        > {
  $$LocalJobStatusesTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalJobStatusesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobStatusesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobStatusesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalJobStatusesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> colorHex = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobStatusesCompanion(
                businessId: businessId,
                code: code,
                name: name,
                colorHex: colorHex,
                iconKey: iconKey,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String code,
                required String name,
                Value<String?> colorHex = const Value.absent(),
                Value<String?> iconKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobStatusesCompanion.insert(
                businessId: businessId,
                code: code,
                name: name,
                colorHex: colorHex,
                iconKey: iconKey,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalJobStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalJobStatusesTable,
      LocalJobStatuse,
      $$LocalJobStatusesTableFilterComposer,
      $$LocalJobStatusesTableOrderingComposer,
      $$LocalJobStatusesTableAnnotationComposer,
      $$LocalJobStatusesTableCreateCompanionBuilder,
      $$LocalJobStatusesTableUpdateCompanionBuilder,
      (
        LocalJobStatuse,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalJobStatusesTable,
          LocalJobStatuse
        >,
      ),
      LocalJobStatuse,
      PrefetchHooks Function()
    >;
typedef $$LocalJobAssignmentsTableCreateCompanionBuilder =
    LocalJobAssignmentsCompanion Function({
      required String assignmentId,
      required String businessId,
      required String jobId,
      required String employeeId,
      Value<String?> employeeName,
      Value<String?> position,
      Value<bool> active,
      Value<DateTime?> assignedAt,
      Value<DateTime?> releasedAt,
      Value<String?> source,
      Value<int> rowid,
    });
typedef $$LocalJobAssignmentsTableUpdateCompanionBuilder =
    LocalJobAssignmentsCompanion Function({
      Value<String> assignmentId,
      Value<String> businessId,
      Value<String> jobId,
      Value<String> employeeId,
      Value<String?> employeeName,
      Value<String?> position,
      Value<bool> active,
      Value<DateTime?> assignedAt,
      Value<DateTime?> releasedAt,
      Value<String?> source,
      Value<int> rowid,
    });

class $$LocalJobAssignmentsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobAssignmentsTable> {
  $$LocalJobAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get assignmentId => $composableBuilder(
    column: $table.assignmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get employeeName => $composableBuilder(
    column: $table.employeeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get assignedAt => $composableBuilder(
    column: $table.assignedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalJobAssignmentsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobAssignmentsTable> {
  $$LocalJobAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get assignmentId => $composableBuilder(
    column: $table.assignmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get employeeName => $composableBuilder(
    column: $table.employeeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get assignedAt => $composableBuilder(
    column: $table.assignedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalJobAssignmentsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobAssignmentsTable> {
  $$LocalJobAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get assignmentId => $composableBuilder(
    column: $table.assignmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get employeeId => $composableBuilder(
    column: $table.employeeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get employeeName => $composableBuilder(
    column: $table.employeeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get assignedAt => $composableBuilder(
    column: $table.assignedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$LocalJobAssignmentsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalJobAssignmentsTable,
          LocalJobAssignment,
          $$LocalJobAssignmentsTableFilterComposer,
          $$LocalJobAssignmentsTableOrderingComposer,
          $$LocalJobAssignmentsTableAnnotationComposer,
          $$LocalJobAssignmentsTableCreateCompanionBuilder,
          $$LocalJobAssignmentsTableUpdateCompanionBuilder,
          (
            LocalJobAssignment,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalJobAssignmentsTable,
              LocalJobAssignment
            >,
          ),
          LocalJobAssignment,
          PrefetchHooks Function()
        > {
  $$LocalJobAssignmentsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalJobAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobAssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobAssignmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalJobAssignmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assignmentId = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String> employeeId = const Value.absent(),
                Value<String?> employeeName = const Value.absent(),
                Value<String?> position = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime?> assignedAt = const Value.absent(),
                Value<DateTime?> releasedAt = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobAssignmentsCompanion(
                assignmentId: assignmentId,
                businessId: businessId,
                jobId: jobId,
                employeeId: employeeId,
                employeeName: employeeName,
                position: position,
                active: active,
                assignedAt: assignedAt,
                releasedAt: releasedAt,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assignmentId,
                required String businessId,
                required String jobId,
                required String employeeId,
                Value<String?> employeeName = const Value.absent(),
                Value<String?> position = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime?> assignedAt = const Value.absent(),
                Value<DateTime?> releasedAt = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobAssignmentsCompanion.insert(
                assignmentId: assignmentId,
                businessId: businessId,
                jobId: jobId,
                employeeId: employeeId,
                employeeName: employeeName,
                position: position,
                active: active,
                assignedAt: assignedAt,
                releasedAt: releasedAt,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalJobAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalJobAssignmentsTable,
      LocalJobAssignment,
      $$LocalJobAssignmentsTableFilterComposer,
      $$LocalJobAssignmentsTableOrderingComposer,
      $$LocalJobAssignmentsTableAnnotationComposer,
      $$LocalJobAssignmentsTableCreateCompanionBuilder,
      $$LocalJobAssignmentsTableUpdateCompanionBuilder,
      (
        LocalJobAssignment,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalJobAssignmentsTable,
          LocalJobAssignment
        >,
      ),
      LocalJobAssignment,
      PrefetchHooks Function()
    >;
typedef $$LocalJobVisitsTableCreateCompanionBuilder =
    LocalJobVisitsCompanion Function({
      required String id,
      required String businessId,
      required String jobId,
      required int visitNumber,
      Value<String?> reason,
      Value<double> plannedHours,
      Value<String?> workSummary,
      Value<DateTime?> openedAt,
      Value<DateTime?> closedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalJobVisitsTableUpdateCompanionBuilder =
    LocalJobVisitsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> jobId,
      Value<int> visitNumber,
      Value<String?> reason,
      Value<double> plannedHours,
      Value<String?> workSummary,
      Value<DateTime?> openedAt,
      Value<DateTime?> closedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalJobVisitsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobVisitsTable> {
  $$LocalJobVisitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get visitNumber => $composableBuilder(
    column: $table.visitNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workSummary => $composableBuilder(
    column: $table.workSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalJobVisitsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobVisitsTable> {
  $$LocalJobVisitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get visitNumber => $composableBuilder(
    column: $table.visitNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workSummary => $composableBuilder(
    column: $table.workSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalJobVisitsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalJobVisitsTable> {
  $$LocalJobVisitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<int> get visitNumber => $composableBuilder(
    column: $table.visitNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<double> get plannedHours => $composableBuilder(
    column: $table.plannedHours,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workSummary => $composableBuilder(
    column: $table.workSummary,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalJobVisitsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalJobVisitsTable,
          LocalJobVisit,
          $$LocalJobVisitsTableFilterComposer,
          $$LocalJobVisitsTableOrderingComposer,
          $$LocalJobVisitsTableAnnotationComposer,
          $$LocalJobVisitsTableCreateCompanionBuilder,
          $$LocalJobVisitsTableUpdateCompanionBuilder,
          (
            LocalJobVisit,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalJobVisitsTable,
              LocalJobVisit
            >,
          ),
          LocalJobVisit,
          PrefetchHooks Function()
        > {
  $$LocalJobVisitsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalJobVisitsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobVisitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobVisitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalJobVisitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<int> visitNumber = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<double> plannedHours = const Value.absent(),
                Value<String?> workSummary = const Value.absent(),
                Value<DateTime?> openedAt = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobVisitsCompanion(
                id: id,
                businessId: businessId,
                jobId: jobId,
                visitNumber: visitNumber,
                reason: reason,
                plannedHours: plannedHours,
                workSummary: workSummary,
                openedAt: openedAt,
                closedAt: closedAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String jobId,
                required int visitNumber,
                Value<String?> reason = const Value.absent(),
                Value<double> plannedHours = const Value.absent(),
                Value<String?> workSummary = const Value.absent(),
                Value<DateTime?> openedAt = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalJobVisitsCompanion.insert(
                id: id,
                businessId: businessId,
                jobId: jobId,
                visitNumber: visitNumber,
                reason: reason,
                plannedHours: plannedHours,
                workSummary: workSummary,
                openedAt: openedAt,
                closedAt: closedAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalJobVisitsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalJobVisitsTable,
      LocalJobVisit,
      $$LocalJobVisitsTableFilterComposer,
      $$LocalJobVisitsTableOrderingComposer,
      $$LocalJobVisitsTableAnnotationComposer,
      $$LocalJobVisitsTableCreateCompanionBuilder,
      $$LocalJobVisitsTableUpdateCompanionBuilder,
      (
        LocalJobVisit,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalJobVisitsTable,
          LocalJobVisit
        >,
      ),
      LocalJobVisit,
      PrefetchHooks Function()
    >;
typedef $$LocalPreInspectionsTableCreateCompanionBuilder =
    LocalPreInspectionsCompanion Function({
      required String id,
      required String businessId,
      required String jobId,
      Value<String?> vehicleId,
      Value<DateTime?> inspectedAt,
      Value<double?> odometer,
      Value<String?> notes,
      Value<String?> createdBy,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalPreInspectionsTableUpdateCompanionBuilder =
    LocalPreInspectionsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> jobId,
      Value<String?> vehicleId,
      Value<DateTime?> inspectedAt,
      Value<double?> odometer,
      Value<String?> notes,
      Value<String?> createdBy,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalPreInspectionsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionsTable> {
  $$LocalPreInspectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get inspectedAt => $composableBuilder(
    column: $table.inspectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get odometer => $composableBuilder(
    column: $table.odometer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPreInspectionsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionsTable> {
  $$LocalPreInspectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get inspectedAt => $composableBuilder(
    column: $table.inspectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get odometer => $composableBuilder(
    column: $table.odometer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPreInspectionsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionsTable> {
  $$LocalPreInspectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<DateTime> get inspectedAt => $composableBuilder(
    column: $table.inspectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get odometer =>
      $composableBuilder(column: $table.odometer, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalPreInspectionsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalPreInspectionsTable,
          LocalPreInspection,
          $$LocalPreInspectionsTableFilterComposer,
          $$LocalPreInspectionsTableOrderingComposer,
          $$LocalPreInspectionsTableAnnotationComposer,
          $$LocalPreInspectionsTableCreateCompanionBuilder,
          $$LocalPreInspectionsTableUpdateCompanionBuilder,
          (
            LocalPreInspection,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalPreInspectionsTable,
              LocalPreInspection
            >,
          ),
          LocalPreInspection,
          PrefetchHooks Function()
        > {
  $$LocalPreInspectionsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalPreInspectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPreInspectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPreInspectionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalPreInspectionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<DateTime?> inspectedAt = const Value.absent(),
                Value<double?> odometer = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPreInspectionsCompanion(
                id: id,
                businessId: businessId,
                jobId: jobId,
                vehicleId: vehicleId,
                inspectedAt: inspectedAt,
                odometer: odometer,
                notes: notes,
                createdBy: createdBy,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String jobId,
                Value<String?> vehicleId = const Value.absent(),
                Value<DateTime?> inspectedAt = const Value.absent(),
                Value<double?> odometer = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPreInspectionsCompanion.insert(
                id: id,
                businessId: businessId,
                jobId: jobId,
                vehicleId: vehicleId,
                inspectedAt: inspectedAt,
                odometer: odometer,
                notes: notes,
                createdBy: createdBy,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPreInspectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalPreInspectionsTable,
      LocalPreInspection,
      $$LocalPreInspectionsTableFilterComposer,
      $$LocalPreInspectionsTableOrderingComposer,
      $$LocalPreInspectionsTableAnnotationComposer,
      $$LocalPreInspectionsTableCreateCompanionBuilder,
      $$LocalPreInspectionsTableUpdateCompanionBuilder,
      (
        LocalPreInspection,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalPreInspectionsTable,
          LocalPreInspection
        >,
      ),
      LocalPreInspection,
      PrefetchHooks Function()
    >;
typedef $$LocalPreInspectionPhotosTableCreateCompanionBuilder =
    LocalPreInspectionPhotosCompanion Function({
      required String id,
      required String businessId,
      required String inspectionId,
      required String attachmentId,
      Value<String?> localFilePath,
      Value<String?> storageBucket,
      Value<String?> storageKey,
      Value<String?> filename,
      Value<String?> mimeType,
      Value<int?> byteSize,
      Value<DateTime?> capturedAt,
      Value<String?> note,
      Value<String?> createdBy,
      Value<bool> canEditNote,
      Value<bool> canDelete,
      Value<String> uploadState,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$LocalPreInspectionPhotosTableUpdateCompanionBuilder =
    LocalPreInspectionPhotosCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> inspectionId,
      Value<String> attachmentId,
      Value<String?> localFilePath,
      Value<String?> storageBucket,
      Value<String?> storageKey,
      Value<String?> filename,
      Value<String?> mimeType,
      Value<int?> byteSize,
      Value<DateTime?> capturedAt,
      Value<String?> note,
      Value<String?> createdBy,
      Value<bool> canEditNote,
      Value<bool> canDelete,
      Value<String> uploadState,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$LocalPreInspectionPhotosTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionPhotosTable> {
  $$LocalPreInspectionPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inspectionId => $composableBuilder(
    column: $table.inspectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canEditNote => $composableBuilder(
    column: $table.canEditNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPreInspectionPhotosTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionPhotosTable> {
  $$LocalPreInspectionPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inspectionId => $composableBuilder(
    column: $table.inspectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canEditNote => $composableBuilder(
    column: $table.canEditNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPreInspectionPhotosTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalPreInspectionPhotosTable> {
  $$LocalPreInspectionPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inspectionId => $composableBuilder(
    column: $table.inspectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<bool> get canEditNote => $composableBuilder(
    column: $table.canEditNote,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get canDelete =>
      $composableBuilder(column: $table.canDelete, builder: (column) => column);

  GeneratedColumn<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$LocalPreInspectionPhotosTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalPreInspectionPhotosTable,
          LocalPreInspectionPhoto,
          $$LocalPreInspectionPhotosTableFilterComposer,
          $$LocalPreInspectionPhotosTableOrderingComposer,
          $$LocalPreInspectionPhotosTableAnnotationComposer,
          $$LocalPreInspectionPhotosTableCreateCompanionBuilder,
          $$LocalPreInspectionPhotosTableUpdateCompanionBuilder,
          (
            LocalPreInspectionPhoto,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalPreInspectionPhotosTable,
              LocalPreInspectionPhoto
            >,
          ),
          LocalPreInspectionPhoto,
          PrefetchHooks Function()
        > {
  $$LocalPreInspectionPhotosTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalPreInspectionPhotosTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPreInspectionPhotosTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalPreInspectionPhotosTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalPreInspectionPhotosTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> inspectionId = const Value.absent(),
                Value<String> attachmentId = const Value.absent(),
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storageKey = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> canEditNote = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPreInspectionPhotosCompanion(
                id: id,
                businessId: businessId,
                inspectionId: inspectionId,
                attachmentId: attachmentId,
                localFilePath: localFilePath,
                storageBucket: storageBucket,
                storageKey: storageKey,
                filename: filename,
                mimeType: mimeType,
                byteSize: byteSize,
                capturedAt: capturedAt,
                note: note,
                createdBy: createdBy,
                canEditNote: canEditNote,
                canDelete: canDelete,
                uploadState: uploadState,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String inspectionId,
                required String attachmentId,
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storageKey = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> canEditNote = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPreInspectionPhotosCompanion.insert(
                id: id,
                businessId: businessId,
                inspectionId: inspectionId,
                attachmentId: attachmentId,
                localFilePath: localFilePath,
                storageBucket: storageBucket,
                storageKey: storageKey,
                filename: filename,
                mimeType: mimeType,
                byteSize: byteSize,
                capturedAt: capturedAt,
                note: note,
                createdBy: createdBy,
                canEditNote: canEditNote,
                canDelete: canDelete,
                uploadState: uploadState,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPreInspectionPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalPreInspectionPhotosTable,
      LocalPreInspectionPhoto,
      $$LocalPreInspectionPhotosTableFilterComposer,
      $$LocalPreInspectionPhotosTableOrderingComposer,
      $$LocalPreInspectionPhotosTableAnnotationComposer,
      $$LocalPreInspectionPhotosTableCreateCompanionBuilder,
      $$LocalPreInspectionPhotosTableUpdateCompanionBuilder,
      (
        LocalPreInspectionPhoto,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalPreInspectionPhotosTable,
          LocalPreInspectionPhoto
        >,
      ),
      LocalPreInspectionPhoto,
      PrefetchHooks Function()
    >;
typedef $$LocalFindingsTableCreateCompanionBuilder =
    LocalFindingsCompanion Function({
      required String id,
      required String businessId,
      Value<String?> vehicleId,
      Value<String?> foundJobId,
      Value<String?> repairJobId,
      required String body,
      required String status,
      Value<bool> includeOnInvoice,
      Value<DateTime?> createdAt,
      Value<DateTime?> resolvedAt,
      Value<String?> createdBy,
      Value<bool> canEdit,
      Value<bool> canDelete,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalFindingsTableUpdateCompanionBuilder =
    LocalFindingsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String?> vehicleId,
      Value<String?> foundJobId,
      Value<String?> repairJobId,
      Value<String> body,
      Value<String> status,
      Value<bool> includeOnInvoice,
      Value<DateTime?> createdAt,
      Value<DateTime?> resolvedAt,
      Value<String?> createdBy,
      Value<bool> canEdit,
      Value<bool> canDelete,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalFindingsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingsTable> {
  $$LocalFindingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foundJobId => $composableBuilder(
    column: $table.foundJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repairJobId => $composableBuilder(
    column: $table.repairJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeOnInvoice => $composableBuilder(
    column: $table.includeOnInvoice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canEdit => $composableBuilder(
    column: $table.canEdit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFindingsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingsTable> {
  $$LocalFindingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foundJobId => $composableBuilder(
    column: $table.foundJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repairJobId => $composableBuilder(
    column: $table.repairJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeOnInvoice => $composableBuilder(
    column: $table.includeOnInvoice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canEdit => $composableBuilder(
    column: $table.canEdit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFindingsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingsTable> {
  $$LocalFindingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<String> get foundJobId => $composableBuilder(
    column: $table.foundJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repairJobId => $composableBuilder(
    column: $table.repairJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get includeOnInvoice => $composableBuilder(
    column: $table.includeOnInvoice,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<bool> get canEdit =>
      $composableBuilder(column: $table.canEdit, builder: (column) => column);

  GeneratedColumn<bool> get canDelete =>
      $composableBuilder(column: $table.canDelete, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalFindingsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalFindingsTable,
          LocalFinding,
          $$LocalFindingsTableFilterComposer,
          $$LocalFindingsTableOrderingComposer,
          $$LocalFindingsTableAnnotationComposer,
          $$LocalFindingsTableCreateCompanionBuilder,
          $$LocalFindingsTableUpdateCompanionBuilder,
          (
            LocalFinding,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalFindingsTable,
              LocalFinding
            >,
          ),
          LocalFinding,
          PrefetchHooks Function()
        > {
  $$LocalFindingsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalFindingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFindingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFindingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFindingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> foundJobId = const Value.absent(),
                Value<String?> repairJobId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> includeOnInvoice = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> canEdit = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFindingsCompanion(
                id: id,
                businessId: businessId,
                vehicleId: vehicleId,
                foundJobId: foundJobId,
                repairJobId: repairJobId,
                body: body,
                status: status,
                includeOnInvoice: includeOnInvoice,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                createdBy: createdBy,
                canEdit: canEdit,
                canDelete: canDelete,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> foundJobId = const Value.absent(),
                Value<String?> repairJobId = const Value.absent(),
                required String body,
                required String status,
                Value<bool> includeOnInvoice = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<bool> canEdit = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFindingsCompanion.insert(
                id: id,
                businessId: businessId,
                vehicleId: vehicleId,
                foundJobId: foundJobId,
                repairJobId: repairJobId,
                body: body,
                status: status,
                includeOnInvoice: includeOnInvoice,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                createdBy: createdBy,
                canEdit: canEdit,
                canDelete: canDelete,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFindingsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalFindingsTable,
      LocalFinding,
      $$LocalFindingsTableFilterComposer,
      $$LocalFindingsTableOrderingComposer,
      $$LocalFindingsTableAnnotationComposer,
      $$LocalFindingsTableCreateCompanionBuilder,
      $$LocalFindingsTableUpdateCompanionBuilder,
      (
        LocalFinding,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalFindingsTable,
          LocalFinding
        >,
      ),
      LocalFinding,
      PrefetchHooks Function()
    >;
typedef $$LocalFindingPhotosTableCreateCompanionBuilder =
    LocalFindingPhotosCompanion Function({
      required String id,
      required String businessId,
      required String findingId,
      required String attachmentId,
      Value<String?> localFilePath,
      Value<String?> storageBucket,
      Value<String?> storageKey,
      Value<String?> filename,
      Value<String?> mimeType,
      Value<int?> byteSize,
      Value<DateTime?> capturedAt,
      Value<bool> canDelete,
      Value<String> uploadState,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$LocalFindingPhotosTableUpdateCompanionBuilder =
    LocalFindingPhotosCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> findingId,
      Value<String> attachmentId,
      Value<String?> localFilePath,
      Value<String?> storageBucket,
      Value<String?> storageKey,
      Value<String?> filename,
      Value<String?> mimeType,
      Value<int?> byteSize,
      Value<DateTime?> capturedAt,
      Value<bool> canDelete,
      Value<String> uploadState,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$LocalFindingPhotosTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingPhotosTable> {
  $$LocalFindingPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get findingId => $composableBuilder(
    column: $table.findingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFindingPhotosTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingPhotosTable> {
  $$LocalFindingPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get findingId => $composableBuilder(
    column: $table.findingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canDelete => $composableBuilder(
    column: $table.canDelete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFindingPhotosTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFindingPhotosTable> {
  $$LocalFindingPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get findingId =>
      $composableBuilder(column: $table.findingId, builder: (column) => column);

  GeneratedColumn<String> get attachmentId => $composableBuilder(
    column: $table.attachmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get canDelete =>
      $composableBuilder(column: $table.canDelete, builder: (column) => column);

  GeneratedColumn<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$LocalFindingPhotosTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalFindingPhotosTable,
          LocalFindingPhoto,
          $$LocalFindingPhotosTableFilterComposer,
          $$LocalFindingPhotosTableOrderingComposer,
          $$LocalFindingPhotosTableAnnotationComposer,
          $$LocalFindingPhotosTableCreateCompanionBuilder,
          $$LocalFindingPhotosTableUpdateCompanionBuilder,
          (
            LocalFindingPhoto,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalFindingPhotosTable,
              LocalFindingPhoto
            >,
          ),
          LocalFindingPhoto,
          PrefetchHooks Function()
        > {
  $$LocalFindingPhotosTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalFindingPhotosTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFindingPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFindingPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFindingPhotosTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> findingId = const Value.absent(),
                Value<String> attachmentId = const Value.absent(),
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storageKey = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFindingPhotosCompanion(
                id: id,
                businessId: businessId,
                findingId: findingId,
                attachmentId: attachmentId,
                localFilePath: localFilePath,
                storageBucket: storageBucket,
                storageKey: storageKey,
                filename: filename,
                mimeType: mimeType,
                byteSize: byteSize,
                capturedAt: capturedAt,
                canDelete: canDelete,
                uploadState: uploadState,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String findingId,
                required String attachmentId,
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storageKey = const Value.absent(),
                Value<String?> filename = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteSize = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<bool> canDelete = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFindingPhotosCompanion.insert(
                id: id,
                businessId: businessId,
                findingId: findingId,
                attachmentId: attachmentId,
                localFilePath: localFilePath,
                storageBucket: storageBucket,
                storageKey: storageKey,
                filename: filename,
                mimeType: mimeType,
                byteSize: byteSize,
                capturedAt: capturedAt,
                canDelete: canDelete,
                uploadState: uploadState,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFindingPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalFindingPhotosTable,
      LocalFindingPhoto,
      $$LocalFindingPhotosTableFilterComposer,
      $$LocalFindingPhotosTableOrderingComposer,
      $$LocalFindingPhotosTableAnnotationComposer,
      $$LocalFindingPhotosTableCreateCompanionBuilder,
      $$LocalFindingPhotosTableUpdateCompanionBuilder,
      (
        LocalFindingPhoto,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalFindingPhotosTable,
          LocalFindingPhoto
        >,
      ),
      LocalFindingPhoto,
      PrefetchHooks Function()
    >;
typedef $$LocalFinancialCacheTableCreateCompanionBuilder =
    LocalFinancialCacheCompanion Function({
      required String businessId,
      required String cacheKey,
      required String payloadJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalFinancialCacheTableUpdateCompanionBuilder =
    LocalFinancialCacheCompanion Function({
      Value<String> businessId,
      Value<String> cacheKey,
      Value<String> payloadJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalFinancialCacheTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFinancialCacheTable> {
  $$LocalFinancialCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFinancialCacheTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFinancialCacheTable> {
  $$LocalFinancialCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFinancialCacheTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalFinancialCacheTable> {
  $$LocalFinancialCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalFinancialCacheTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalFinancialCacheTable,
          LocalFinancialCacheData,
          $$LocalFinancialCacheTableFilterComposer,
          $$LocalFinancialCacheTableOrderingComposer,
          $$LocalFinancialCacheTableAnnotationComposer,
          $$LocalFinancialCacheTableCreateCompanionBuilder,
          $$LocalFinancialCacheTableUpdateCompanionBuilder,
          (
            LocalFinancialCacheData,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalFinancialCacheTable,
              LocalFinancialCacheData
            >,
          ),
          LocalFinancialCacheData,
          PrefetchHooks Function()
        > {
  $$LocalFinancialCacheTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalFinancialCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFinancialCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFinancialCacheTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalFinancialCacheTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFinancialCacheCompanion(
                businessId: businessId,
                cacheKey: cacheKey,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String cacheKey,
                required String payloadJson,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFinancialCacheCompanion.insert(
                businessId: businessId,
                cacheKey: cacheKey,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFinancialCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalFinancialCacheTable,
      LocalFinancialCacheData,
      $$LocalFinancialCacheTableFilterComposer,
      $$LocalFinancialCacheTableOrderingComposer,
      $$LocalFinancialCacheTableAnnotationComposer,
      $$LocalFinancialCacheTableCreateCompanionBuilder,
      $$LocalFinancialCacheTableUpdateCompanionBuilder,
      (
        LocalFinancialCacheData,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalFinancialCacheTable,
          LocalFinancialCacheData
        >,
      ),
      LocalFinancialCacheData,
      PrefetchHooks Function()
    >;
typedef $$LocalCatalogItemsTableCreateCompanionBuilder =
    LocalCatalogItemsCompanion Function({
      required String id,
      required String businessId,
      required String name,
      Value<String?> description,
      Value<String> itemType,
      Value<double> sellingPrice,
      Value<String?> pricingUnit,
      Value<double> cost,
      Value<bool> taxable,
      Value<String?> category,
      Value<String?> barcode,
      Value<bool> active,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalCatalogItemsTableUpdateCompanionBuilder =
    LocalCatalogItemsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String?> description,
      Value<String> itemType,
      Value<double> sellingPrice,
      Value<String?> pricingUnit,
      Value<double> cost,
      Value<bool> taxable,
      Value<String?> category,
      Value<String?> barcode,
      Value<bool> active,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalCatalogItemsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCatalogItemsTable> {
  $$LocalCatalogItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sellingPrice => $composableBuilder(
    column: $table.sellingPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pricingUnit => $composableBuilder(
    column: $table.pricingUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get taxable => $composableBuilder(
    column: $table.taxable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCatalogItemsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCatalogItemsTable> {
  $$LocalCatalogItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sellingPrice => $composableBuilder(
    column: $table.sellingPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pricingUnit => $composableBuilder(
    column: $table.pricingUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get taxable => $composableBuilder(
    column: $table.taxable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCatalogItemsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalCatalogItemsTable> {
  $$LocalCatalogItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<double> get sellingPrice => $composableBuilder(
    column: $table.sellingPrice,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pricingUnit => $composableBuilder(
    column: $table.pricingUnit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<bool> get taxable =>
      $composableBuilder(column: $table.taxable, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalCatalogItemsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalCatalogItemsTable,
          LocalCatalogItem,
          $$LocalCatalogItemsTableFilterComposer,
          $$LocalCatalogItemsTableOrderingComposer,
          $$LocalCatalogItemsTableAnnotationComposer,
          $$LocalCatalogItemsTableCreateCompanionBuilder,
          $$LocalCatalogItemsTableUpdateCompanionBuilder,
          (
            LocalCatalogItem,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalCatalogItemsTable,
              LocalCatalogItem
            >,
          ),
          LocalCatalogItem,
          PrefetchHooks Function()
        > {
  $$LocalCatalogItemsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalCatalogItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCatalogItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCatalogItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCatalogItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<double> sellingPrice = const Value.absent(),
                Value<String?> pricingUnit = const Value.absent(),
                Value<double> cost = const Value.absent(),
                Value<bool> taxable = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCatalogItemsCompanion(
                id: id,
                businessId: businessId,
                name: name,
                description: description,
                itemType: itemType,
                sellingPrice: sellingPrice,
                pricingUnit: pricingUnit,
                cost: cost,
                taxable: taxable,
                category: category,
                barcode: barcode,
                active: active,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<double> sellingPrice = const Value.absent(),
                Value<String?> pricingUnit = const Value.absent(),
                Value<double> cost = const Value.absent(),
                Value<bool> taxable = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCatalogItemsCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                description: description,
                itemType: itemType,
                sellingPrice: sellingPrice,
                pricingUnit: pricingUnit,
                cost: cost,
                taxable: taxable,
                category: category,
                barcode: barcode,
                active: active,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCatalogItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalCatalogItemsTable,
      LocalCatalogItem,
      $$LocalCatalogItemsTableFilterComposer,
      $$LocalCatalogItemsTableOrderingComposer,
      $$LocalCatalogItemsTableAnnotationComposer,
      $$LocalCatalogItemsTableCreateCompanionBuilder,
      $$LocalCatalogItemsTableUpdateCompanionBuilder,
      (
        LocalCatalogItem,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalCatalogItemsTable,
          LocalCatalogItem
        >,
      ),
      LocalCatalogItem,
      PrefetchHooks Function()
    >;
typedef $$LocalDocumentsTableCreateCompanionBuilder =
    LocalDocumentsCompanion Function({
      required String id,
      required String businessId,
      Value<String?> jobId,
      Value<String?> customerId,
      required String kind,
      Value<String?> documentNumber,
      Value<String?> status,
      Value<String?> displayStatusCode,
      Value<DateTime?> closedAt,
      Value<bool> converted,
      Value<double> total,
      Value<String?> documentDate,
      Value<bool> futureDateFlag,
      Value<DateTime?> createdAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });
typedef $$LocalDocumentsTableUpdateCompanionBuilder =
    LocalDocumentsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String?> jobId,
      Value<String?> customerId,
      Value<String> kind,
      Value<String?> documentNumber,
      Value<String?> status,
      Value<String?> displayStatusCode,
      Value<DateTime?> closedAt,
      Value<bool> converted,
      Value<double> total,
      Value<String?> documentDate,
      Value<bool> futureDateFlag,
      Value<DateTime?> createdAt,
      Value<DateTime?> serverUpdatedAt,
      Value<int?> rowVersion,
      Value<String> syncState,
      Value<int> rowid,
    });

class $$LocalDocumentsTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentNumber => $composableBuilder(
    column: $table.documentNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayStatusCode => $composableBuilder(
    column: $table.displayStatusCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get converted => $composableBuilder(
    column: $table.converted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get futureDateFlag => $composableBuilder(
    column: $table.futureDateFlag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDocumentsTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentNumber => $composableBuilder(
    column: $table.documentNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayStatusCode => $composableBuilder(
    column: $table.displayStatusCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get converted => $composableBuilder(
    column: $table.converted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get futureDateFlag => $composableBuilder(
    column: $table.futureDateFlag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDocumentsTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalDocumentsTable> {
  $$LocalDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get documentNumber => $composableBuilder(
    column: $table.documentNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get displayStatusCode => $composableBuilder(
    column: $table.displayStatusCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<bool> get converted =>
      $composableBuilder(column: $table.converted, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<String> get documentDate => $composableBuilder(
    column: $table.documentDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get futureDateFlag => $composableBuilder(
    column: $table.futureDateFlag,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);
}

class $$LocalDocumentsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalDocumentsTable,
          LocalDocument,
          $$LocalDocumentsTableFilterComposer,
          $$LocalDocumentsTableOrderingComposer,
          $$LocalDocumentsTableAnnotationComposer,
          $$LocalDocumentsTableCreateCompanionBuilder,
          $$LocalDocumentsTableUpdateCompanionBuilder,
          (
            LocalDocument,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalDocumentsTable,
              LocalDocument
            >,
          ),
          LocalDocument,
          PrefetchHooks Function()
        > {
  $$LocalDocumentsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> documentNumber = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> displayStatusCode = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<bool> converted = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<String?> documentDate = const Value.absent(),
                Value<bool> futureDateFlag = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDocumentsCompanion(
                id: id,
                businessId: businessId,
                jobId: jobId,
                customerId: customerId,
                kind: kind,
                documentNumber: documentNumber,
                status: status,
                displayStatusCode: displayStatusCode,
                closedAt: closedAt,
                converted: converted,
                total: total,
                documentDate: documentDate,
                futureDateFlag: futureDateFlag,
                createdAt: createdAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                Value<String?> jobId = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                required String kind,
                Value<String?> documentNumber = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> displayStatusCode = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<bool> converted = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<String?> documentDate = const Value.absent(),
                Value<bool> futureDateFlag = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<int?> rowVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDocumentsCompanion.insert(
                id: id,
                businessId: businessId,
                jobId: jobId,
                customerId: customerId,
                kind: kind,
                documentNumber: documentNumber,
                status: status,
                displayStatusCode: displayStatusCode,
                closedAt: closedAt,
                converted: converted,
                total: total,
                documentDate: documentDate,
                futureDateFlag: futureDateFlag,
                createdAt: createdAt,
                serverUpdatedAt: serverUpdatedAt,
                rowVersion: rowVersion,
                syncState: syncState,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalDocumentsTable,
      LocalDocument,
      $$LocalDocumentsTableFilterComposer,
      $$LocalDocumentsTableOrderingComposer,
      $$LocalDocumentsTableAnnotationComposer,
      $$LocalDocumentsTableCreateCompanionBuilder,
      $$LocalDocumentsTableUpdateCompanionBuilder,
      (
        LocalDocument,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalDocumentsTable,
          LocalDocument
        >,
      ),
      LocalDocument,
      PrefetchHooks Function()
    >;
typedef $$LocalExpenseIqPhotosTableCreateCompanionBuilder =
    LocalExpenseIqPhotosCompanion Function({
      required String businessId,
      required String transactionId,
      required String photoId,
      required String filename,
      Value<String?> sourceUri,
      Value<String> state,
      Value<int> attempts,
      Value<int?> claimedAt,
      Value<String?> lastError,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$LocalExpenseIqPhotosTableUpdateCompanionBuilder =
    LocalExpenseIqPhotosCompanion Function({
      Value<String> businessId,
      Value<String> transactionId,
      Value<String> photoId,
      Value<String> filename,
      Value<String?> sourceUri,
      Value<String> state,
      Value<int> attempts,
      Value<int?> claimedAt,
      Value<String?> lastError,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$LocalExpenseIqPhotosTableFilterComposer
    extends Composer<_$BriskersLocalDatabase, $LocalExpenseIqPhotosTable> {
  $$LocalExpenseIqPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUri => $composableBuilder(
    column: $table.sourceUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalExpenseIqPhotosTableOrderingComposer
    extends Composer<_$BriskersLocalDatabase, $LocalExpenseIqPhotosTable> {
  $$LocalExpenseIqPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoId => $composableBuilder(
    column: $table.photoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUri => $composableBuilder(
    column: $table.sourceUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalExpenseIqPhotosTableAnnotationComposer
    extends Composer<_$BriskersLocalDatabase, $LocalExpenseIqPhotosTable> {
  $$LocalExpenseIqPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoId =>
      $composableBuilder(column: $table.photoId, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get sourceUri =>
      $composableBuilder(column: $table.sourceUri, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get claimedAt =>
      $composableBuilder(column: $table.claimedAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalExpenseIqPhotosTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalExpenseIqPhotosTable,
          LocalExpenseIqPhoto,
          $$LocalExpenseIqPhotosTableFilterComposer,
          $$LocalExpenseIqPhotosTableOrderingComposer,
          $$LocalExpenseIqPhotosTableAnnotationComposer,
          $$LocalExpenseIqPhotosTableCreateCompanionBuilder,
          $$LocalExpenseIqPhotosTableUpdateCompanionBuilder,
          (
            LocalExpenseIqPhoto,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalExpenseIqPhotosTable,
              LocalExpenseIqPhoto
            >,
          ),
          LocalExpenseIqPhoto,
          PrefetchHooks Function()
        > {
  $$LocalExpenseIqPhotosTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalExpenseIqPhotosTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalExpenseIqPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalExpenseIqPhotosTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalExpenseIqPhotosTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> transactionId = const Value.absent(),
                Value<String> photoId = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<String?> sourceUri = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> claimedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalExpenseIqPhotosCompanion(
                businessId: businessId,
                transactionId: transactionId,
                photoId: photoId,
                filename: filename,
                sourceUri: sourceUri,
                state: state,
                attempts: attempts,
                claimedAt: claimedAt,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String transactionId,
                required String photoId,
                required String filename,
                Value<String?> sourceUri = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> claimedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalExpenseIqPhotosCompanion.insert(
                businessId: businessId,
                transactionId: transactionId,
                photoId: photoId,
                filename: filename,
                sourceUri: sourceUri,
                state: state,
                attempts: attempts,
                claimedAt: claimedAt,
                lastError: lastError,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalExpenseIqPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalExpenseIqPhotosTable,
      LocalExpenseIqPhoto,
      $$LocalExpenseIqPhotosTableFilterComposer,
      $$LocalExpenseIqPhotosTableOrderingComposer,
      $$LocalExpenseIqPhotosTableAnnotationComposer,
      $$LocalExpenseIqPhotosTableCreateCompanionBuilder,
      $$LocalExpenseIqPhotosTableUpdateCompanionBuilder,
      (
        LocalExpenseIqPhoto,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalExpenseIqPhotosTable,
          LocalExpenseIqPhoto
        >,
      ),
      LocalExpenseIqPhoto,
      PrefetchHooks Function()
    >;
typedef $$LocalExpenseIqSyncSettingsTableCreateCompanionBuilder =
    LocalExpenseIqSyncSettingsCompanion Function({
      required String businessId,
      Value<bool> enabled,
      Value<bool> wifiOnly,
      Value<int> rowid,
    });
typedef $$LocalExpenseIqSyncSettingsTableUpdateCompanionBuilder =
    LocalExpenseIqSyncSettingsCompanion Function({
      Value<String> businessId,
      Value<bool> enabled,
      Value<bool> wifiOnly,
      Value<int> rowid,
    });

class $$LocalExpenseIqSyncSettingsTableFilterComposer
    extends
        Composer<_$BriskersLocalDatabase, $LocalExpenseIqSyncSettingsTable> {
  $$LocalExpenseIqSyncSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wifiOnly => $composableBuilder(
    column: $table.wifiOnly,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalExpenseIqSyncSettingsTableOrderingComposer
    extends
        Composer<_$BriskersLocalDatabase, $LocalExpenseIqSyncSettingsTable> {
  $$LocalExpenseIqSyncSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wifiOnly => $composableBuilder(
    column: $table.wifiOnly,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalExpenseIqSyncSettingsTableAnnotationComposer
    extends
        Composer<_$BriskersLocalDatabase, $LocalExpenseIqSyncSettingsTable> {
  $$LocalExpenseIqSyncSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(
    column: $table.businessId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get wifiOnly =>
      $composableBuilder(column: $table.wifiOnly, builder: (column) => column);
}

class $$LocalExpenseIqSyncSettingsTableTableManager
    extends
        RootTableManager<
          _$BriskersLocalDatabase,
          $LocalExpenseIqSyncSettingsTable,
          LocalExpenseIqSyncSetting,
          $$LocalExpenseIqSyncSettingsTableFilterComposer,
          $$LocalExpenseIqSyncSettingsTableOrderingComposer,
          $$LocalExpenseIqSyncSettingsTableAnnotationComposer,
          $$LocalExpenseIqSyncSettingsTableCreateCompanionBuilder,
          $$LocalExpenseIqSyncSettingsTableUpdateCompanionBuilder,
          (
            LocalExpenseIqSyncSetting,
            BaseReferences<
              _$BriskersLocalDatabase,
              $LocalExpenseIqSyncSettingsTable,
              LocalExpenseIqSyncSetting
            >,
          ),
          LocalExpenseIqSyncSetting,
          PrefetchHooks Function()
        > {
  $$LocalExpenseIqSyncSettingsTableTableManager(
    _$BriskersLocalDatabase db,
    $LocalExpenseIqSyncSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalExpenseIqSyncSettingsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalExpenseIqSyncSettingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalExpenseIqSyncSettingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> wifiOnly = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalExpenseIqSyncSettingsCompanion(
                businessId: businessId,
                enabled: enabled,
                wifiOnly: wifiOnly,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                Value<bool> enabled = const Value.absent(),
                Value<bool> wifiOnly = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalExpenseIqSyncSettingsCompanion.insert(
                businessId: businessId,
                enabled: enabled,
                wifiOnly: wifiOnly,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalExpenseIqSyncSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$BriskersLocalDatabase,
      $LocalExpenseIqSyncSettingsTable,
      LocalExpenseIqSyncSetting,
      $$LocalExpenseIqSyncSettingsTableFilterComposer,
      $$LocalExpenseIqSyncSettingsTableOrderingComposer,
      $$LocalExpenseIqSyncSettingsTableAnnotationComposer,
      $$LocalExpenseIqSyncSettingsTableCreateCompanionBuilder,
      $$LocalExpenseIqSyncSettingsTableUpdateCompanionBuilder,
      (
        LocalExpenseIqSyncSetting,
        BaseReferences<
          _$BriskersLocalDatabase,
          $LocalExpenseIqSyncSettingsTable,
          LocalExpenseIqSyncSetting
        >,
      ),
      LocalExpenseIqSyncSetting,
      PrefetchHooks Function()
    >;

class $BriskersLocalDatabaseManager {
  final _$BriskersLocalDatabase _db;
  $BriskersLocalDatabaseManager(this._db);
  $$LocalSyncStatesTableTableManager get localSyncStates =>
      $$LocalSyncStatesTableTableManager(_db, _db.localSyncStates);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$LocalCustomersTableTableManager get localCustomers =>
      $$LocalCustomersTableTableManager(_db, _db.localCustomers);
  $$LocalVehiclesTableTableManager get localVehicles =>
      $$LocalVehiclesTableTableManager(_db, _db.localVehicles);
  $$LocalCustomerVehiclesTableTableManager get localCustomerVehicles =>
      $$LocalCustomerVehiclesTableTableManager(_db, _db.localCustomerVehicles);
  $$LocalAppointmentsTableTableManager get localAppointments =>
      $$LocalAppointmentsTableTableManager(_db, _db.localAppointments);
  $$LocalKioskSettingsTableTableManager get localKioskSettings =>
      $$LocalKioskSettingsTableTableManager(_db, _db.localKioskSettings);
  $$LocalJobsTableTableManager get localJobs =>
      $$LocalJobsTableTableManager(_db, _db.localJobs);
  $$LocalJobStatusesTableTableManager get localJobStatuses =>
      $$LocalJobStatusesTableTableManager(_db, _db.localJobStatuses);
  $$LocalJobAssignmentsTableTableManager get localJobAssignments =>
      $$LocalJobAssignmentsTableTableManager(_db, _db.localJobAssignments);
  $$LocalJobVisitsTableTableManager get localJobVisits =>
      $$LocalJobVisitsTableTableManager(_db, _db.localJobVisits);
  $$LocalPreInspectionsTableTableManager get localPreInspections =>
      $$LocalPreInspectionsTableTableManager(_db, _db.localPreInspections);
  $$LocalPreInspectionPhotosTableTableManager get localPreInspectionPhotos =>
      $$LocalPreInspectionPhotosTableTableManager(
        _db,
        _db.localPreInspectionPhotos,
      );
  $$LocalFindingsTableTableManager get localFindings =>
      $$LocalFindingsTableTableManager(_db, _db.localFindings);
  $$LocalFindingPhotosTableTableManager get localFindingPhotos =>
      $$LocalFindingPhotosTableTableManager(_db, _db.localFindingPhotos);
  $$LocalFinancialCacheTableTableManager get localFinancialCache =>
      $$LocalFinancialCacheTableTableManager(_db, _db.localFinancialCache);
  $$LocalCatalogItemsTableTableManager get localCatalogItems =>
      $$LocalCatalogItemsTableTableManager(_db, _db.localCatalogItems);
  $$LocalDocumentsTableTableManager get localDocuments =>
      $$LocalDocumentsTableTableManager(_db, _db.localDocuments);
  $$LocalExpenseIqPhotosTableTableManager get localExpenseIqPhotos =>
      $$LocalExpenseIqPhotosTableTableManager(_db, _db.localExpenseIqPhotos);
  $$LocalExpenseIqSyncSettingsTableTableManager
  get localExpenseIqSyncSettings =>
      $$LocalExpenseIqSyncSettingsTableTableManager(
        _db,
        _db.localExpenseIqSyncSettings,
      );
}
