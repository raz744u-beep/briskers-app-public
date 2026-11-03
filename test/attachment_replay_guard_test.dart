import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/briskers_api.dart';

void main() {
  test('attachment mutation without a replay guard keeps its result', () async {
    expect(await runAttachmentMutation(() async => 'uploaded-key'), 'uploaded-key');
  });

  test('a checkpoint rejection prevents the network mutation', () async {
    var calls = 0;
    Future<T> guard<T>(Future<T> Function() operation) async {
      throw StateError('Quarantined');
    }
    await expectLater(runAttachmentMutation(() async {
      calls++;
      return 'must-not-upload';
    }, replayGuard: guard), throwsStateError);
    expect(calls, 0);
  });

  test('late substage acknowledgement is retained and cannot reach finalize', () async {
    final started = Completer<void>();
    final response = Completer<String>();
    final receipts = <Object?>[];
    var quarantined = false;
    var finalized = false;
    Future<T> guard<T>(Future<T> Function() operation) async {
      if (quarantined) throw StateError('Quarantined');
      final result = await operation();
      if (quarantined) {
        receipts.add(result);
        throw StateError('Late acknowledgement retained');
      }
      return result;
    }
    final sequence = () async {
      await runAttachmentMutation(() {
        started.complete();
        return response.future;
      }, replayGuard: guard);
      await runAttachmentMutation(() async {
        finalized = true;
      }, replayGuard: guard);
    }();
    final rejected = expectLater(sequence, throwsStateError);
    await started.future;
    quarantined = true;
    response.complete('uploaded-object-key');
    await rejected;
    expect(receipts, ['uploaded-object-key']);
    expect(finalized, isFalse);
  });

  test('each successful registration upload and finalize stage is checked', () async {
    var checks = 0;
    Future<T> guard<T>(Future<T> Function() operation) async {
      checks++;
      return operation();
    }
    final registration = await runAttachmentMutation(
      () async => {'attachment_id': 'attachment-1'}, replayGuard: guard,
    );
    final key = await runAttachmentMutation(() async => 'object-key', replayGuard: guard);
    await runAttachmentMutation(() async {
      expect(registration['attachment_id'], 'attachment-1');
      expect(key, 'object-key');
    }, replayGuard: guard);
    expect(checks, 3);
  });
}
