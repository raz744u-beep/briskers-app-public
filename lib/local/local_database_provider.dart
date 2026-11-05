import 'package:flutter/foundation.dart';
import 'briskers_local_database.dart';

final BriskersLocalDatabase _applicationDatabase = BriskersLocalDatabase.defaults();
BriskersLocalDatabase? _debugDatabase;
BriskersLocalDatabase get localDatabase => _debugDatabase ?? _applicationDatabase;

@visibleForTesting
void debugUseLocalDatabase(BriskersLocalDatabase? database) {
  assert(() { _debugDatabase=database; return true; }());
}

Future<void> initializeLocalDatabase() async {
  await localDatabase.customSelect('SELECT 1').get();
}
