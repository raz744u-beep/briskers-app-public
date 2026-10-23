import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_check_proof_service.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image;

void main() {
  late Directory workingDirectory;
  late File pickerPhoto;
  late BriskersLocalDatabase db;
  late LocalPayrollDraftStore drafts;
  late LocalPayrollCheckProofService photos;

  const check = PayrollPaymentMethod(
    id: 'check-stable-id',
    businessId: 'shop-1',
    label: 'Check',
    kind: PayrollPaymentMethodKind.check,
    enabled: true,
    sortOrder: 10,
    version: 1,
  );
  const cash = PayrollPaymentMethod(
    id: 'cash-stable-id',
    businessId: 'shop-1',
    label: 'Cash',
    kind: PayrollPaymentMethodKind.cash,
    enabled: true,
    sortOrder: 20,
    version: 1,
  );
  // Synthetic local-only image with PNG signature, no real account data.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
  );

  PayrollPaymentDraft newDraft({
    String shop = 'shop-1',
    String operation = 'stable-op-uuid',
    String method = 'check-stable-id',
  }) => PayrollPaymentDraft(
    businessId: shop,
    employeeId: 'employee-identity-not-nickname',
    operationId: operation,
    methodId: method,
    methodLabelSnapshot: 'Check',
    amountCents: 86500,
    paymentDate: DateTime(2026, 10, 22),
    payrollWeekKey: '2026-W43',
  );

  setUp(() async {
    workingDirectory = await Directory.systemTemp.createTemp(
      'payroll-proof-synthetic-',
    );
    pickerPhoto = File('${workingDirectory.path}/temporary-camera-photo.png');
    await pickerPhoto.writeAsBytes(png);
    db = BriskersLocalDatabase(NativeDatabase.memory());
    drafts = LocalPayrollDraftStore(database: db);
    photos = LocalPayrollCheckProofService(
      directoryProvider: () async => workingDirectory,
      drafts: drafts,
    );
  });

  tearDown(() async {
    await db.close();
    if (await workingDirectory.exists()) {
      await workingDirectory.delete(recursive: true);
    }
  });

  test('WebP is normalized to validated PNG for durable server proof', () async {
    await pickerPhoto.writeAsBytes(
      base64Decode(
        'UklGRjYAAABXRUJQVlA4ICoAAADwAQCdASoCAAIAAUAmJaACdLoB+AAETAAA/ttR//G7IVD7ef++9AbwMAA=',
      ),
    );
    final saved = await photos.stageForDraft(
      isOwner: true,
      ownerUserId: 'owner-1',
      draft: newDraft(),
      method: check,
      selectedPhoto: XFile(pickerPhoto.path),
    );
    final bytes = await photos.readFrozenProofBytes(
      isOwner: true,
      ownerUserId: 'owner-1',
      businessId: 'shop-1',
      operationId: saved.operationId,
      digest: saved.checkProofSha256!,
      byteSize: saved.checkProofSizeBytes!,
    );
    expect(image.decodePng(bytes), isNotNull);
    await expectLater(
      photos.readFrozenProofBytes(
        isOwner: true,
        ownerUserId: 'owner-2',
        businessId: 'shop-1',
        operationId: saved.operationId,
        digest: saved.checkProofSha256!,
        byteSize: saved.checkProofSizeBytes!,
      ),
      throwsA(anything),
    );
  });

  test(
    'Check photo copied privately and survives picker temp file removal',
    () async {
      final submitted = await photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: newDraft(),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      );
      expect(submitted.checkProofDurablyStored, true);
      expect(submitted.checkProofSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(submitted.checkProofSizeBytes, png.length);
      expect(
        submitted.checkProofAttachmentId,
        'local-check-${submitted.checkProofSha256}',
      );

      await pickerPhoto.delete(); // Camera/cache input must not be required.
      final restartStore = LocalPayrollDraftStore(database: db);
      final persisted = (await restartStore.load(
        isOwner: true,
        businessId: 'shop-1',
        ownerUserId: 'owner-1',
      )).single;
      final reopenedService = LocalPayrollCheckProofService(
        directoryProvider: () async => workingDirectory,
        drafts: restartStore,
      );
      expect(
        await reopenedService.isProofIntact(
          isOwner: true,
          ownerUserId: 'owner-1',
          draft: persisted,
        ),
        true,
      );
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type LIKE '%payroll%'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test('wrong owner and shop cannot access another proof', () async {
    final record = await photos.stageForDraft(
      isOwner: true,
      ownerUserId: 'owner-1',
      draft: newDraft(),
      method: check,
      selectedPhoto: XFile(pickerPhoto.path),
    );
    expect(
      await photos.isProofIntact(
        isOwner: true,
        ownerUserId: 'owner-2',
        draft: record,
      ),
      false,
    );
    final anotherShop = PayrollPaymentDraft(
      businessId: 'shop-2',
      employeeId: record.employeeId,
      operationId: record.operationId,
      methodId: record.methodId,
      methodLabelSnapshot: record.methodLabelSnapshot,
      amountCents: record.amountCents,
      paymentDate: record.paymentDate,
      payrollWeekKey: record.payrollWeekKey,
      checkProofAttachmentId: record.checkProofAttachmentId,
      checkProofDurablyStored: true,
      checkProofSizeBytes: record.checkProofSizeBytes,
      checkProofSha256: record.checkProofSha256,
    );
    expect(
      await photos.isProofIntact(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: anotherShop,
      ),
      false,
    );
    await expectLater(
      photos.isProofIntact(
        isOwner: false,
        ownerUserId: 'mechanic',
        draft: record,
      ),
      throwsStateError,
    );
  });

  test('tampered proof never verifies after restart', () async {
    final record = await photos.stageForDraft(
      isOwner: true,
      ownerUserId: 'owner-1',
      draft: newDraft(),
      method: check,
      selectedPhoto: XFile(pickerPhoto.path),
    );
    final files = workingDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('/payroll_check_proofs/'))
        .toList();
    expect(files, hasLength(1));
    await files.single.writeAsBytes([...png, 1], flush: true);
    expect(
      await photos.isProofIntact(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: record,
      ),
      false,
    );
    // The saved row must remain a draft, not turn into a posted payment.
    expect(
      (await drafts.load(
        isOwner: true,
        businessId: 'shop-1',
        ownerUserId: 'owner-1',
      )).single.operationId,
      record.operationId,
    );
  });

  test('non-image and empty photo rejected with no submitted draft', () async {
    await pickerPhoto.writeAsString('not a photo');
    await expectLater(
      photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: newDraft(),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      ),
      throwsFormatException,
    );
    await pickerPhoto.writeAsBytes([]);
    await expectLater(
      photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: newDraft(),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      ),
      throwsFormatException,
    );
    expect(
      await drafts.load(
        isOwner: true,
        businessId: 'shop-1',
        ownerUserId: 'owner-1',
      ),
      isEmpty,
    );
  });

  test(
    'rejects header-only and truncated images before saving a draft',
    () async {
      for (final bytes in [
        [0xff, 0xd8, 0xff],
        [0xff, 0xd8, 0xff, 0xd9],
        png.sublist(0, 8),
        png.sublist(0, png.length - 1),
      ]) {
        await pickerPhoto.writeAsBytes(bytes);
        await expectLater(
          photos.stageForDraft(
            isOwner: true,
            ownerUserId: 'owner-1',
            draft: newDraft(),
            method: check,
            selectedPhoto: XFile(pickerPhoto.path),
          ),
          throwsFormatException,
        );
      }
      expect(
        await drafts.load(
          isOwner: true,
          businessId: 'shop-1',
          ownerUserId: 'owner-1',
        ),
        isEmpty,
      );
    },
  );

  test('does not stage check photo for Cash or another shop method', () async {
    for (final method in [cash]) {
      await expectLater(
        photos.stageForDraft(
          isOwner: true,
          ownerUserId: 'owner-1',
          draft: newDraft(method: method.id),
          method: method,
          selectedPhoto: XFile(pickerPhoto.path),
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: newDraft(shop: 'shop-2'),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      ),
      throwsArgumentError,
    );
  });

  test(
    'replacement staged photo updates the same draft, never the ledger',
    () async {
      final first = await photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: newDraft(),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      );
      final secondFile = File('${workingDirectory.path}/replacement.png');
      await secondFile.writeAsBytes(
        image.encodePng(image.Image(width: 3, height: 3)),
        flush: true,
      );
      final second = await photos.stageForDraft(
        isOwner: true,
        ownerUserId: 'owner-1',
        draft: first,
        method: check,
        selectedPhoto: XFile(secondFile.path),
      );
      expect(second.checkProofSha256, isNot(first.checkProofSha256));
      expect(
        (await drafts.load(
          isOwner: true,
          businessId: 'shop-1',
          ownerUserId: 'owner-1',
        )).length,
        1,
      );
      expect(
        await photos.isProofIntact(
          isOwner: true,
          ownerUserId: 'owner-1',
          draft: second,
        ),
        true,
      );
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type LIKE '%payroll%'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test('photo cannot be staged without Owner permission', () async {
    await expectLater(
      photos.stageForDraft(
        isOwner: false,
        ownerUserId: 'mechanic',
        draft: newDraft(),
        method: check,
        selectedPhoto: XFile(pickerPhoto.path),
      ),
      throwsStateError,
    );
    expect(
      await drafts.load(
        isOwner: true,
        businessId: 'shop-1',
        ownerUserId: 'mechanic',
      ),
      isEmpty,
    );
  });
}
