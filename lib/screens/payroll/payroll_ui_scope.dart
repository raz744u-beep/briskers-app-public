import 'package:flutter/widgets.dart';
import '../../local/briskers_local_database.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/payroll_owner_lan.dart';

/// Injects the existing account/ledger into regular navigation tests and hosts;
/// the grant is still verified by LocalOwnerAuthorization and payment proofs.
class PayrollUiScope extends InheritedWidget {
  const PayrollUiScope({super.key,required super.child,required this.database,required this.unlock,required this.connection,this.debugAllowOwnerView=false});
  final BriskersLocalDatabase database;
  final Future<LocalOwnerGrant> Function(String) unlock;
  final PayrollOwnerLan connection;
  /// Only consumed in debug widget fixtures. Never grants release app access.
  final bool debugAllowOwnerView;
  static PayrollUiScope? of(BuildContext context)=>context.dependOnInheritedWidgetOfExactType<PayrollUiScope>();
  @override bool updateShouldNotify(covariant PayrollUiScope old)=>database!=old.database||connection!=old.connection||debugAllowOwnerView!=old.debugAllowOwnerView;
}
