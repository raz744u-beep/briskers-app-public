import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/expenses/expense_detail_screen.dart';

void main() {
  test('SAF permission denial is recoverable and not a missing file', () {
    expect(
      expensePhotoNeedsFolderPermission(
        'SafPermissionException: Permission Denial: requires ACTION_OPEN_DOCUMENT',
      ),
      true,
    );
    expect(
      expensePhotoNeedsFolderPermission(
        'SecurityException: no persisted UriPermission',
      ),
      true,
    );
    expect(
      expensePhotoNeedsFolderPermission('FileNotFoundException: no image'),
      false,
    );
  });
}
