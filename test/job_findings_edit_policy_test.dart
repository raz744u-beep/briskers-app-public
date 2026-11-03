import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/job_findings_edit_policy.dart';

void main() {
  test('Owner can add findings to a verified full local Job offline', () {
    expect(
      canEditJobFindings(
        firstFrameOnly: false,
        contentBlocked: false,
        serverAllows: false,
        onlineReady: false,
        isOwner: true,
        verifiedLocal: true,
      ),
      isTrue,
    );
  });

  test('First-frame previews and quarantined Jobs never permit edits', () {
    for (final blocked in [false, true]) {
      expect(
        canEditJobFindings(
          firstFrameOnly: !blocked,
          contentBlocked: blocked,
          serverAllows: true,
          onlineReady: false,
          isOwner: true,
          verifiedLocal: true,
        ),
        isFalse,
      );
    }
  });

  test('Unverified local Jobs and non-owners do not inherit Owner override', () {
    for (final isOwner in [false, true]) {
      for (final verifiedLocal in [false, true]) {
        if (isOwner && verifiedLocal) continue;
        expect(
          canEditJobFindings(
            firstFrameOnly: false,
            contentBlocked: false,
            serverAllows: false,
            onlineReady: false,
            isOwner: isOwner,
            verifiedLocal: verifiedLocal,
          ),
          isFalse,
        );
      }
    }
  });

  test('Online actions still use server-granted capability', () {
    for (final serverAllows in [false, true]) {
      expect(
        canEditJobFindings(
          firstFrameOnly: false,
          contentBlocked: false,
          serverAllows: serverAllows,
          onlineReady: true,
          isOwner: true,
          verifiedLocal: true,
        ),
        serverAllows,
      );
    }
  });
}
