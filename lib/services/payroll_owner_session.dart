import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_job_access_history.dart';

/// A route's local access context. Revocation is permanent for this instance;
/// switching A -> B -> A cannot revive an in-flight read or confirmation.
/// This is a client privacy guard, not authority to post server payments.
class PayrollOwnerSession extends ChangeNotifier {
  PayrollOwnerSession({
    required this.businessId,
    required bool isOwner,
    String? Function()? currentUserId,
    Stream<String?>? userChanges,
  }) : _currentUserId =
           currentUserId ?? (() => LocalJobAccessHistory.currentUserId),
       _initialOwnerRole = isOwner {
    ownerUserId = _currentUserId();
    _subscription = (userChanges ?? _authChanges()).listen((id) {
      if (id != ownerUserId) invalidate();
    });
  }

  final String businessId;
  final bool _initialOwnerRole;
  final String? Function() _currentUserId;
  late final String? ownerUserId;
  StreamSubscription<String?>? _subscription;
  bool _revoked = false;

  static Stream<String?> _authChanges() {
    try {
      return Supabase.instance.client.auth.onAuthStateChange.map(
        (event) => event.session?.user.id,
      );
    } catch (_) {
      return const Stream<String?>.empty();
    }
  }

  bool allows({required String businessId, required bool isOwner}) =>
      !_revoked &&
      _initialOwnerRole &&
      isOwner &&
      ownerUserId != null &&
      this.businessId == businessId &&
      businessId.isNotEmpty &&
      _currentUserId() == ownerUserId;

  void invalidate() {
    if (_revoked) return;
    _revoked = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
