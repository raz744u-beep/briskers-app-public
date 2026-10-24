import 'dart:io';

import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:briskers_app/services/local_payroll_method_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalPayrollMethodStore store;
  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    store = LocalPayrollMethodStore(database: db);
  });
  tearDown(() => db.close());
  Future<List<PayrollPaymentMethod>> load({
    String shop = 'shop',
    String owner = 'owner',
  }) => store.load(isOwner: true, businessId: shop, ownerUserId: owner);

  test('seed once with distinct UUIDs, isolate shops and Owners', () async {
    final first = await load();
    expect(first.map((m) => m.kind), [
      PayrollPaymentMethodKind.cash,
      PayrollPaymentMethodKind.check,
      PayrollPaymentMethodKind.zelle,
      PayrollPaymentMethodKind.ach,
    ]);
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(first.every((m) => uuid.hasMatch(m.id)), true);
    expect((await load()).map((m) => m.id), first.map((m) => m.id));
    expect(
      (await load(shop: 'other')).any((m) => first.any((x) => m.id == x.id)),
      false,
    );
    expect(
      (await load(owner: 'other')).any((m) => first.any((x) => m.id == x.id)),
      false,
    );
  });

  test(
    'rename and disable preserve Check kind, default and draft label',
    () async {
      final check = (await load())[1];
      await store.setDefault(
        isOwner: true,
        businessId: 'shop',
        ownerUserId: 'owner',
        employeeId: 'employee-id',
        methodId: check.id,
      );
      final drafts = LocalPayrollDraftStore(database: db);
      await drafts.save(
        isOwner: true,
        ownerUserId: 'owner',
        draft: PayrollPaymentDraft(
          businessId: 'shop',
          employeeId: 'employee-id',
          operationId: 'op',
          methodId: check.id,
          methodLabelSnapshot: check.label,
          amountCents: 1250,
          paymentDate: DateTime(2026, 10, 23),
          payrollWeekKey: '2026-10-19',
        ),
      );
      await store.update(
        isOwner: true,
        ownerUserId: 'owner',
        method: check,
        label: 'Paper payment',
        enabled: false,
      );
      final methods = await load();
      expect(methods[1].requiresCheckPhoto, true);
      final defaults = await store.defaults(
        isOwner: true,
        businessId: 'shop',
        ownerUserId: 'owner',
      );
      expect(defaults['employee-id'], check.id);
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: 'shop',
          methods: methods,
          employeeDefaultId: defaults['employee-id'],
        ),
        isNull,
      );
      expect(
        PayrollPaymentMethodChoice.resolve(
          businessId: 'shop',
          methods: methods,
          employeeDefaultId: defaults['employee-id'],
          paymentOverrideId: methods[0].id,
        )?.id,
        methods[0].id,
      );
      expect(
        (await drafts.load(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner',
        )).single.methodLabelSnapshot,
        'Check',
      );
      expect(
        await db
            .customSelect(
              "SELECT * FROM sync_outbox WHERE entity_type LIKE '%payroll%'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'reject stale edits, foreign defaults and invalid reorder atomically',
    () async {
      final first = await load();
      await store.update(
        isOwner: true,
        ownerUserId: 'owner',
        method: first[0],
        label: 'Notes',
        enabled: true,
      );
      await expectLater(
        store.update(
          isOwner: true,
          ownerUserId: 'owner',
          method: first[0],
          label: 'Stale',
          enabled: true,
        ),
        throwsStateError,
      );
      await expectLater(
        store.setDefault(
          isOwner: true,
          businessId: 'other',
          ownerUserId: 'owner',
          employeeId: 'employee-id',
          methodId: first[0].id,
        ),
        throwsStateError,
      );
      await expectLater(
        store.reorder(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner',
          ids: [first[0].id, first[0].id],
        ),
        throwsArgumentError,
      );
      expect((await load()).map((m) => m.id), first.map((m) => m.id));
      await store.reorder(
        isOwner: true,
        businessId: 'shop',
        ownerUserId: 'owner',
        ids: first.reversed.map((m) => m.id).toList(),
      );
      expect((await load()).map((m) => m.id), first.reversed.map((m) => m.id));
    },
  );

  test('add, clear default and reject unauthorized access', () async {
    await load();
    await store.add(
      isOwner: true,
      businessId: 'shop',
      ownerUserId: 'owner',
      label: 'Custom payout',
      kind: PayrollPaymentMethodKind.custom,
    );
    final methods = await load();
    expect(methods, hasLength(5));
    await store.setDefault(
      isOwner: true,
      businessId: 'shop',
      ownerUserId: 'owner',
      employeeId: 'employee-id',
      methodId: methods.last.id,
    );
    await store.setDefault(
      isOwner: true,
      businessId: 'shop',
      ownerUserId: 'owner',
      employeeId: 'employee-id',
      methodId: null,
    );
    expect(
      await store.defaults(
        isOwner: true,
        businessId: 'shop',
        ownerUserId: 'owner',
      ),
      isEmpty,
    );
    await expectLater(
      store.load(isOwner: false, businessId: 'shop', ownerUserId: 'owner'),
      throwsStateError,
    );
    await expectLater(
      store.load(isOwner: true, businessId: 'shop', ownerUserId: ''),
      throwsArgumentError,
    );
  });

  test(
    'identities and employee preference survive actual database close/reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'payroll-method-test-',
      );
      final file = File('${directory.path}/local.sqlite');
      var disk = BriskersLocalDatabase(NativeDatabase(file));
      try {
        var persisted = LocalPayrollMethodStore(database: disk);
        final methods = await persisted.load(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner',
        );
        await persisted.setDefault(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner',
          employeeId: 'employee-id',
          methodId: methods[2].id,
        );
        await disk.close();
        disk = BriskersLocalDatabase(NativeDatabase(file));
        persisted = LocalPayrollMethodStore(database: disk);
        expect(
          (await persisted.load(
            isOwner: true,
            businessId: 'shop',
            ownerUserId: 'owner',
          )).map((m) => m.id),
          methods.map((m) => m.id),
        );
        expect(
          (await persisted.defaults(
            isOwner: true,
            businessId: 'shop',
            ownerUserId: 'owner',
          ))['employee-id'],
          methods[2].id,
        );
      } finally {
        await disk.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
