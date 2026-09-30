import 'briskers_local_database.dart';

final BriskersLocalDatabase localDatabase = BriskersLocalDatabase.defaults();

Future<void> initializeLocalDatabase() async {
  await localDatabase.customSelect('SELECT 1').get();
}
