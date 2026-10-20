import 'dart:async';

import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/screens/appointments_screen.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:drift/native.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_summary_visibility.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> appointmentRow(String customer) => {
  'id': customer,
  'customer': customer,
  'status': 'confirmed',
  'title': 'Inspection',
  'starts_at': DateTime.now().toIso8601String(),
  'sync_state': 'synced',
};

class _Appointments extends LocalAppointmentRepository {
  _Appointments(BriskersLocalDatabase db) : super(database: db);
  final calls = <({String filter, String? search})>[];
  Completer<List<Map<String, dynamic>>>? delayedSearch;
  bool fresh = false;
  bool bootstrapped = true;
  bool canCheckIn = false;
  String syncState = 'synced';
  String? checkedInJob;

  @override
  Future<Map<String, dynamic>?> appointment(
    String businessId,
    String appointmentId,
  ) async => {
    'id': appointmentId,
    'job_id': checkedInJob,
    'sync_state': syncState,
  };

  @override
  Future<bool> hasBootstrap(String businessId) async => bootstrapped;

  @override
  Future<List<Map<String, dynamic>>> appointments(
    String businessId, {
    String filter = 'all',
    String? search,
    int pastLimit = 30,
  }) async {
    calls.add((filter: filter, search: search));
    if (search == 'old' && delayedSearch != null) return delayedSearch!.future;
    return [
      {
        ...appointmentRow(
          '${fresh ? 'Fresh' : 'Saved'} $filter ${search ?? ''}',
        ),
        'can_check_in': canCheckIn,
        'sync_state': syncState,
        'job_id': checkedInJob,
      },
    ];
  }
}

class _Sync extends AppointmentSyncService {
  _Sync(BriskersLocalDatabase db) : super(database: db);
  int flushes = 0;
  int pulls = 0;
  bool fail = false;
  Completer<void>? delayedPull;
  VoidCallback? onPull;
  VoidCallback? onCheckIn;
  int checkIns = 0;

  @override
  Future<void> queueCheckIn(String businessId, String appointmentId) async {
    checkIns++;
    onCheckIn?.call();
  }

  @override
  Future<Map<String, String>> flush(String businessId) async {
    flushes++;
    if (fail) throw StateError('Service unavailable');
    return {};
  }

  @override
  Future<void> pull(String businessId) async {
    pulls++;
    await delayedPull?.future;
    onPull?.call();
  }
}

class _Api extends BriskersApi {
  int dashboards = 0;
  int statusUpdates = 0;

  @override
  Future<void> setAppointmentStatus(
    String businessId,
    String appointmentId,
    String status,
  ) async {
    statusUpdates++;
  }

  @override
  Future<Map<String, dynamic>> dashboard(String businessId, String day) async {
    dashboards++;
    return {'pending_appointment_requests': 2};
  }
}

class _Visibility extends JobSummaryVisibility {
  _Visibility(String businessId, this.onQuarantine, BriskersLocalDatabase db)
    : super(businessId: businessId, onQuarantine: onQuarantine, database: db);

  final ValueChanged<Set<String>> onQuarantine;
  final blocked = <String>{};

  void quarantine(String id) {
    blocked.add(id);
    beginLoad();
    onQuarantine({id});
  }

  @override
  Future<List<Map<String, dynamic>>> filter(
    Iterable<Map<String, dynamic>> rows, {
    String jobIdKey = 'id',
    bool cached = false,
  }) async =>
      JobSummaryVisibility.withoutJobs(rows, blocked, jobIdKey: jobIdKey);
}

void main() {
  var sequence = 0;
  late String businessId;
  late BriskersLocalDatabase db;
  late _Appointments repository;
  late _Sync sync;
  late _Api api;
  late _Visibility visibility;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
    await BriskersLanguageController.instance.setLanguage('en');
    // The entry-refresh guard is deliberately scoped to a business.
    businessId = 'appointments-loading-${sequence++}';
    db = BriskersLocalDatabase(NativeDatabase.memory());
    repository = _Appointments(db);
    sync = _Sync(db);
    api = _Api();
  });

  tearDown(() async {
    await db.close();
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });

  Future<void> show(
    WidgetTester tester, {
    int dockResetToken = 0,
    String roleCode = 'owner',
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentsScreen(
            businessId: businessId,
            roleCode: roleCode,
            dockResetToken: dockResetToken,
            repository: repository,
            appointmentSync: sync,
            api: api,
            visibilityFactory: (business, onQuarantine) =>
                visibility = _Visibility(business, onQuarantine, db),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> filter(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cached appointments paint before sync without an offline warning',
    (tester) async {
      sync.delayedPull = Completer<void>();
      await show(tester);
      expect(find.text('Saved today '), findsOneWidget);
      expect(find.text('Showing saved appointments.'), findsOneWidget);
      expect(find.text(tr('savedAppointmentsOffline')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(sync.pulls, 1);
      expect(api.dashboards, 0);

      sync.delayedPull!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Showing saved appointments.'), findsNothing);
      expect(api.dashboards, 1);
    },
  );

  testWidgets('filter, search, clear and repeated filter taps stay local', (
    tester,
  ) async {
    await show(tester);
    final flushes = sync.flushes;
    final pulls = sync.pulls;
    final dashboards = api.dashboards;
    await filter(tester, tr('all'));
    await search(tester, 'brakes');
    await search(tester, 'brakes@example.com');
    expect(repository.calls.last, (
      filter: 'all',
      search: 'brakes@example.com',
    ));
    expect(find.text('Saved all brakes@example.com'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    await filter(tester, tr('past'));
    await filter(tester, tr('all'));
    expect(repository.calls.last, (filter: 'all', search: null));
    expect(sync.flushes, flushes);
    expect(sync.pulls, pulls);
    expect(api.dashboards, dashboards);
    // Local filtering must not revoke readiness of a successful sync.
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text(tr('savedAppointmentsOffline')), findsNothing);
  });

  testWidgets(
    'background sync publishes the current query after filter changes',
    (tester) async {
      sync.delayedPull = Completer<void>();
      sync.onPull = () => repository.fresh = true;
      await show(tester);
      await filter(tester, tr('all'));
      await search(tester, 'current');
      expect(find.text('Saved all current'), findsOneWidget);

      sync.delayedPull!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Fresh all current'), findsOneWidget);
      expect(find.text('Saved today '), findsNothing);
      expect(sync.flushes, 1);
      expect(sync.pulls, 1);
      expect(api.dashboards, 1);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    },
  );

  testWidgets('a slow earlier search cannot overwrite the newest result', (
    tester,
  ) async {
    await show(tester);
    repository.delayedSearch = Completer<List<Map<String, dynamic>>>();
    await search(tester, 'old');
    await search(tester, 'new');
    expect(find.text('Saved today new'), findsOneWidget);
    repository.delayedSearch!.complete([appointmentRow('Stale result')]);
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('Saved today new'), findsOneWidget);
    expect(sync.pulls, 1);
  });

  testWidgets('manual refresh syncs while a fresh tab entry keeps its query', (
    tester,
  ) async {
    await show(tester);
    await filter(tester, tr('all'));
    await search(tester, 'saved query');
    await show(tester, dockResetToken: 1);
    expect(repository.calls.last, (filter: 'all', search: 'saved query'));
    expect(find.text('Saved all saved query'), findsOneWidget);
    expect(sync.pulls, 1);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(sync.flushes, 2);
    expect(sync.pulls, 2);
    expect(api.dashboards, 2);
  });

  testWidgets('overlapping manual refresh requests share one sync', (
    tester,
  ) async {
    await show(tester);
    sync.delayedPull = Completer<void>();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final first = refresh.onRefresh();
    await tester.pump();
    final second = refresh.onRefresh();
    await tester.pump();
    expect(sync.flushes, 2);
    expect(sync.pulls, 2);
    sync.delayedPull!.complete();
    await Future.wait([first, second]);
    await tester.pumpAndSettle();
    expect(sync.pulls, 2);
  });

  testWidgets('a mutation during refresh gets a follow-up sync', (
    tester,
  ) async {
    await show(tester);
    sync.delayedPull = Completer<void>();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final pendingRefresh = refresh.onRefresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('tentative')));
    await tester.pumpAndSettle();
    expect(api.statusUpdates, 1);
    expect(sync.pulls, 2);

    sync.delayedPull!.complete();
    await pendingRefresh;
    // The mutation handler is a separate async continuation from onRefresh.
    // Give its local read and trailing replay a frame before asserting.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(sync.flushes, 3);
    expect(sync.pulls, 3);
  });

  testWidgets(
    'check-in already applied by an active refresh recovers its Job',
    (tester) async {
      repository.canCheckIn = true;
      sync.onCheckIn = () => repository.syncState = 'pending';
      await show(tester, roleCode: 'kiosk');
      sync.delayedPull = Completer<void>();
      sync.onPull = () {
        if (sync.checkIns > 0) {
          repository.checkedInJob = 'created-job';
          repository.syncState = 'synced';
        }
      };
      final pendingRefresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved today '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check In'));
      await tester.pump();
      expect(sync.checkIns, 1);
      expect(sync.flushes, 2);

      sync.delayedPull!.complete();
      await pendingRefresh;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Check-in completed.'), findsOneWidget);
      expect(find.textContaining('It will sync automatically'), findsNothing);
      expect(sync.flushes, 3);
      expect(sync.pulls, 3);
    },
  );

  testWidgets(
    'switching a stalled Force Online load offline paints cache immediately',
    (tester) async {
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.online,
      );
      sync.delayedPull = Completer<void>();
      await show(tester, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saved today '), findsNothing);

      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved today '), findsOneWidget);
      expect(find.text(tr('savedAppointmentsOffline')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(sync.pulls, 1);
      sync.delayedPull!.complete();
      await tester.pumpAndSettle();
      expect(sync.pulls, 1);
    },
  );

  testWidgets('failed refresh keeps saved cards and reports refresh failure', (
    tester,
  ) async {
    sync.fail = true;
    await show(tester);
    expect(find.text('Saved today '), findsOneWidget);
    expect(
      find.text('Unable to refresh. Showing saved appointments.'),
      findsOneWidget,
    );
    // A failed server request is not proof that the device is offline.
    expect(find.text(tr('savedAppointmentsOffline')), findsNothing);
    await filter(tester, tr('all'));
    expect(sync.flushes, 1);
    expect(find.text('Saved all '), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('retained screen reacts to offline and online mode changes', (
    tester,
  ) async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    await show(tester);
    expect(sync.flushes, 0);
    expect(sync.pulls, 0);
    expect(find.text(tr('savedAppointmentsOffline')), findsOneWidget);
    await search(tester, 'offline query');
    expect(sync.flushes, 0);

    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
    await tester.pumpAndSettle();
    expect(sync.flushes, 1);
    expect(sync.pulls, 1);
    expect(find.text('Saved today offline query'), findsOneWidget);
    expect(find.text(tr('savedAppointmentsOffline')), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.offline,
    );
    await tester.pumpAndSettle();
    expect(sync.flushes, 1);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text(tr('savedAppointmentsOffline')), findsOneWidget);
  });

  testWidgets(
    'quarantine prevents a delayed local query from restoring a card',
    (tester) async {
      await show(tester);
      repository.delayedSearch = Completer<List<Map<String, dynamic>>>();
      await search(tester, 'old');
      visibility.quarantine('blocked-job');
      repository.delayedSearch!.complete([
        {...appointmentRow('Quarantined appointment'), 'job_id': 'blocked-job'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Quarantined appointment'), findsNothing);
    },
  );
}
