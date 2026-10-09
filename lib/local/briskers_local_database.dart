import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'briskers_local_database.g.dart';

class LocalSyncStates extends Table {
  TextColumn get businessId => text()();
  TextColumn get scope => text()();
  IntColumn get lastServerCursor => integer().nullable()();
  DateTimeColumn get lastPullAt => dateTime().nullable()();
  DateTimeColumn get lastPushAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  BoolColumn get bootstrapped =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {businessId, scope};
}

class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get businessId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  IntColumn get baseRowVersion => integer().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
}

class LocalCustomers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get displayName => text()();
  BoolColumn get isCompany =>
      boolean().withDefault(const Constant(false))();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get listEmail => text().nullable()();
  TextColumn get listPhone => text().nullable()();
  TextColumn get billingAddressJson =>
      text().withDefault(const Constant('{}'))();
  BoolColumn get taxable =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get problemFlag =>
      boolean().withDefault(const Constant(false))();
  TextColumn get problemFlagNote => text().nullable()();
  TextColumn get contactsJson =>
      text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalVehicles extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get make => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get vin => text().nullable()();
  TextColumn get licensePlate => text().nullable()();
  TextColumn get licenseState => text().nullable()();
  RealColumn get mileage => real().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get keyPassword => text().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalCustomerVehicles extends Table {
  TextColumn get businessId => text()();
  TextColumn get customerId => text()();
  TextColumn get vehicleId => text()();
  BoolColumn get isPrimary =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey =>
      {businessId, customerId, vehicleId};
}

class LocalAppointments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get customerId => text()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get employeeId => text().nullable()();
  TextColumn get jobId => text().nullable()();
  TextColumn get requestId => text().nullable()();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerPhoneNorm => text().nullable()();
  IntColumn get vehicleYear => integer().nullable()();
  TextColumn get vehicleMake => text().nullable()();
  TextColumn get vehicleModel => text().nullable()();
  TextColumn get vehicleLabel => text().nullable()();
  TextColumn get mechanicName => text().nullable()();
  BoolColumn get canCheckIn =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalKioskSettings extends Table {
  TextColumn get businessId => text()();
  TextColumn get disclaimerId => text().nullable()();
  IntColumn get disclaimerVersion => integer().nullable()();
  TextColumn get disclaimerText => text().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {businessId};
}

class LocalJobs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get accessScope => text()();
  TextColumn get jobNumber => text().nullable()();
  TextColumn get title => text()();
  TextColumn get requestedWork => text().nullable()();
  TextColumn get status => text()();
  TextColumn get statusName => text().nullable()();
  TextColumn get statusColor => text().nullable()();
  TextColumn get statusIcon => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  BoolColumn get customerProblemFlag =>
      boolean().withDefault(const Constant(false))();
  TextColumn get customerProblemFlagNote => text().nullable()();
  TextColumn get capabilitiesJson =>
      text().withDefault(const Constant('{}'))();
  IntColumn get pendingRequestCount =>
      integer().withDefault(const Constant(0))();
  TextColumn get paymentState => text().nullable()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get vehicleLabel => text().nullable()();
  TextColumn get vehicleVin => text().nullable()();
  TextColumn get vehiclePlate => text().nullable()();
  RealColumn get plannedHours => real().withDefault(const Constant(0))();
  RealColumn get odometerIn => real().nullable()();
  TextColumn get assignedEmployeeId => text().nullable()();
  TextColumn get assignedEmployeeName => text().nullable()();
  TextColumn get assignedPosition => text().nullable()();
  BoolColumn get isUnassigned =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalJobStatuses extends Table {
  TextColumn get businessId => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().nullable()();
  TextColumn get iconKey => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {businessId, code};
}

class LocalJobAssignments extends Table {
  TextColumn get assignmentId => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text()();
  TextColumn get employeeId => text()();
  TextColumn get employeeName => text().nullable()();
  TextColumn get position => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get assignedAt => dateTime().nullable()();
  DateTimeColumn get releasedAt => dateTime().nullable()();
  TextColumn get source => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assignmentId};
}

class LocalJobVisits extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text()();
  IntColumn get visitNumber => integer()();
  TextColumn get reason => text().nullable()();
  RealColumn get plannedHours => real().withDefault(const Constant(0))();
  TextColumn get workSummary => text().nullable()();
  DateTimeColumn get openedAt => dateTime().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalPreInspections extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text()();
  TextColumn get vehicleId => text().nullable()();
  DateTimeColumn get inspectedAt => dateTime().nullable()();
  RealColumn get odometer => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalPreInspectionPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get inspectionId => text()();
  TextColumn get attachmentId => text()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get storageBucket => text().nullable()();
  TextColumn get storageKey => text().nullable()();
  TextColumn get filename => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get byteSize => integer().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  BoolColumn get canEditNote =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get canDelete =>
      boolean().withDefault(const Constant(false))();
  TextColumn get uploadState =>
      text().withDefault(const Constant('synced'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalFindingPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get findingId => text()();
  TextColumn get attachmentId => text()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get storageBucket => text().nullable()();
  TextColumn get storageKey => text().nullable()();
  TextColumn get filename => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get byteSize => integer().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  BoolColumn get canDelete =>
      boolean().withDefault(const Constant(false))();
  TextColumn get uploadState =>
      text().withDefault(const Constant('synced'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalFindings extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get foundJobId => text().nullable()();
  TextColumn get repairJobId => text().nullable()();
  TextColumn get body => text()();
  TextColumn get status => text()();
  BoolColumn get includeOnInvoice =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get createdBy => text().nullable()();
  BoolColumn get canEdit =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get canDelete =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}


class LocalDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get documentNumber => text().nullable()();
  TextColumn get status => text().nullable()();
  TextColumn get displayStatusCode => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  BoolColumn get converted => boolean().withDefault(const Constant(false))();
  RealColumn get total => real().withDefault(const Constant(0))();
  // Preserve the issued/business date separately from the import timestamp.
  // A YYYY-MM-DD string is timezone-independent.
  TextColumn get documentDate => text().nullable()();
  BoolColumn get futureDateFlag =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalFinancialCache extends Table {
  TextColumn get businessId => text()();
  TextColumn get cacheKey => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {businessId, cacheKey};
}

class LocalCatalogItems extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get itemType => text().withDefault(const Constant('non_inventory'))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  TextColumn get pricingUnit => text().nullable()();
  RealColumn get cost => real().withDefault(const Constant(0))();
  BoolColumn get taxable => boolean().withDefault(const Constant(true))();
  TextColumn get category => text().nullable()();
  TextColumn get barcode => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('synced'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// ExpenseIQ image bytes remain in their original Android document location.
/// Only a persisted SAF document URI and expense link live in SQLite.
class LocalExpenseIqPhotos extends Table {
  TextColumn get businessId => text()();
  TextColumn get transactionId => text()();
  TextColumn get photoId => text()();
  TextColumn get filename => text()();
  TextColumn get sourceUri => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get claimedAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {businessId, transactionId};
}

class LocalExpenseIqSyncSettings extends Table {
  TextColumn get businessId => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get wifiOnly => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {businessId};
}

@DriftDatabase(
  tables: [
    LocalSyncStates,
    SyncOutbox,
    LocalCustomers,
    LocalVehicles,
    LocalCustomerVehicles,
    LocalAppointments,
    LocalKioskSettings,
    LocalJobs,
    LocalJobStatuses,
    LocalJobAssignments,
    LocalJobVisits,
    LocalPreInspections,
    LocalPreInspectionPhotos,
    LocalFindings,
    LocalFindingPhotos,
    LocalFinancialCache,
    LocalCatalogItems,
    LocalDocuments,
    LocalExpenseIqPhotos,
    LocalExpenseIqSyncSettings,
  ],
)
class BriskersLocalDatabase extends _$BriskersLocalDatabase {
  BriskersLocalDatabase(super.e);

  BriskersLocalDatabase.defaults()
      : super(
          driftDatabase(
            name: 'briskers_local',
            native: const DriftNativeOptions(
              shareAcrossIsolates: true,
            ),
          ),
        );

  @override
  int get schemaVersion => 21;

  // v18 introduced the ExpenseIQ photo queue but omitted its onUpgrade
  // migration, so user_version may be 18 while the tables are missing.
  // Idempotent CREATEs preserve any existing queue or business data.
  Future<void> ensureExpenseIqSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_expense_iq_photos (
        business_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        photo_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        source_uri TEXT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        claimed_at INTEGER NULL,
        last_error TEXT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (business_id, transaction_id)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_expense_iq_sync_settings (
        business_id TEXT NOT NULL PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1,
        wifi_only INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_expense_iq_photos_state
        ON local_expense_iq_photos (business_id, state, updated_at)
    ''');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_status_created ON local_jobs (business_id, status, created_at DESC)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_number ON local_jobs (business_id, job_number)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_customer ON local_jobs (business_id, customer_name)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_vehicle ON local_jobs (business_id, vehicle_label)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_vin ON local_jobs (business_id, vehicle_vin)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_plate ON local_jobs (business_id, vehicle_plate)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_number ON local_documents (business_id, document_number)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_job ON local_documents (business_id, job_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_customer ON local_documents (business_id, customer_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_date ON local_documents (business_id, kind, document_date DESC)');
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(localFindingPhotos);
          }
          if (from < 3) {
            await migrator.addColumn(
              localJobs,
              localJobs.customerProblemFlag,
            );
            await migrator.addColumn(
              localJobs,
              localJobs.customerProblemFlagNote,
            );
            await migrator.addColumn(
              localJobs,
              localJobs.capabilitiesJson,
            );
            await migrator.addColumn(
              localJobs,
              localJobs.pendingRequestCount,
            );
            await migrator.addColumn(
              localJobs,
              localJobs.paymentState,
            );
            await migrator.createTable(localJobStatuses);
          }
          if (from < 4) {
            await migrator.createTable(localCustomers);
            await migrator.createTable(localVehicles);
            await migrator.createTable(localCustomerVehicles);
          }
          if (from < 5) {
            await migrator.createTable(localAppointments);
          }
          if (from < 6) {
            await migrator.addColumn(
              localAppointments,
              localAppointments.customerPhoneNorm,
            );
          }
          if (from < 7) {
            await migrator.createTable(localKioskSettings);
          }
          if (from < 8) {
            await migrator.createTable(localCatalogItems);
          }
          if (from < 9) {
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_status_created ON local_jobs (business_id, status, created_at DESC)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_number ON local_jobs (business_id, job_number)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_customer ON local_jobs (business_id, customer_name)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_vehicle ON local_jobs (business_id, vehicle_label)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_vin ON local_jobs (business_id, vehicle_vin)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_jobs_business_plate ON local_jobs (business_id, vehicle_plate)');
          }
          if (from < 10) {
            await migrator.createTable(localDocuments);
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_number ON local_documents (business_id, document_number)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_job ON local_documents (business_id, job_id)');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_local_documents_business_customer ON local_documents (business_id, customer_id)');
          }
          if (from < 11) {
            await migrator.addColumn(
              localCustomers,
              localCustomers.createdAt,
            );
          }
          if (from < 12) {
            await migrator.addColumn(
              localDocuments,
              localDocuments.converted,
            );
          }
          if (from < 13) {
            await migrator.addColumn(
              localDocuments,
              localDocuments.displayStatusCode,
            );
          }
          if (from < 14) {
            await customStatement(
              "UPDATE local_sync_states SET last_server_cursor = 0 WHERE scope = 'documents'",
            );
          }
          if (from < 15) {
            await migrator.addColumn(
              localDocuments,
              localDocuments.closedAt,
            );
            await customStatement(
              "UPDATE local_sync_states SET last_server_cursor = 0 WHERE scope = 'documents'",
            );
          }
          if (from < 16) {
            await migrator.addColumn(
              localVehicles,
              localVehicles.keyPassword,
            );
            await customStatement(
              "UPDATE local_sync_states SET last_server_cursor = NULL, bootstrapped = 0 WHERE scope = 'customers_vehicles'",
            );
          }
          if (from < 17) {
            await migrator.createTable(localFinancialCache);
          }
          if (from < 19) {
            await ensureExpenseIqSchema();
          }
          if (from < 20) {
            // Existing imported documents cannot derive their historical date
            // from created_at. Keep document_date NULL until the next pull.
            // Tolerate partially migrated devices and schema-version
            // downgrades without attempting to add an existing column.
            final existingColumns = await customSelect(
              'PRAGMA table_info(local_documents)',
            ).get();
            final hasDocumentDate = existingColumns.any(
              (row) => row.read<String>('name') == 'document_date',
            );
            if (!hasDocumentDate) {
              await migrator.addColumn(
                localDocuments,
                localDocuments.documentDate,
              );
            }
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_local_documents_business_date '
              'ON local_documents (business_id, kind, document_date DESC)',
            );
            await customStatement(
              "UPDATE local_sync_states SET bootstrapped = 0 "
              "WHERE scope = 'documents'",
            );
          }          if (from < 21) {
            final columns = await customSelect(
              'PRAGMA table_info(local_documents)',
            ).get();
            if (!columns.any(
              (row) => row.read<String>('name') == 'future_date_flag',
            )) {
              await migrator.addColumn(
                localDocuments,
                localDocuments.futureDateFlag,
              );
            }
            // A normal Auto sync fills the stored permanent tags. Existing
            // local records stay intact, including any pending offline edits.
            await customStatement(
              "UPDATE local_sync_states SET bootstrapped = 0 "
              "WHERE scope = 'documents'",
            );
          }

        },
        beforeOpen: (details) async {
          // A previous APK may have advanced user_version without making the
          // tables. Self-heal without dropping any local records.
          await ensureExpenseIqSchema();
        },
      );
}
