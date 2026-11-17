import 'package:shared_preferences/shared_preferences.dart';

class CustomerWorkflowPreferences {
  const CustomerWorkflowPreferences(this.businessId);

  final String businessId;

  String get _key => 'briskers_customer_next_action_v1_$businessId';

  Future<bool> offerNextAction() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  Future<bool> setOfferNextAction(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_key, value);
}
