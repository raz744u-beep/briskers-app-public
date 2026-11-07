import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_owner_authorization.dart';
import 'local_owner_authorization.dart';

/// Only Owner accounts can configure or use the independent Worker secret.
/// Never store it in app settings, a source file, or an APK dart-define.
abstract interface class ReceiptAiTokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _DeviceReceiptAiTokenStorage implements ReceiptAiTokenStorage {
  const _DeviceReceiptAiTokenStorage();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

typedef ReceiptAiOwnerVerifier = Future<bool> Function(String businessId);

/// Secure, per-business and per-Owner account credential, with no background
/// sync dependency. A stable credential can be read repeatedly without the
/// Owner's two-minute financial-payment authorization.
class ReceiptAiGatewayAccess {
  ReceiptAiGatewayAccess({
    ReceiptAiTokenStorage? storage,
    ReceiptAiOwnerVerifier? verifyOwner,
    OwnerSessionIdentity? Function()? identity,
  }) : _storage = storage ?? const _DeviceReceiptAiTokenStorage(),
       _verifyOwner = verifyOwner ??
           DeviceOwnerAuthorization.instance.canViewSavedOwnerPayroll,
       _identity = identity ?? DeviceOwnerAuthorization.instance.currentIdentity;

  final ReceiptAiTokenStorage _storage;
  final ReceiptAiOwnerVerifier _verifyOwner;
  final OwnerSessionIdentity? Function() _identity;

  static String _key(String business, String actor) =>
      'briskers_receipt_ai_gateway_v2:${Uri.encodeComponent(business)}:${Uri.encodeComponent(actor)}';

  static String _oldKey(String business) =>
      'receipt_ai_gateway_token:$business';

  Future<OwnerSessionIdentity> _requireOwner(String business) async {
    if (business.trim().isEmpty) {
      throw StateError('Select the Briskers business before scanning.');
    }
    final before = _identity();
    if (before == null || !await _verifyOwner(business) ||
        !before.matches(_identity())) {
      throw StateError('Open the saved Owner account to connect receipt AI.');
    }
    return before;
  }

  /// Returns only the active Owner's matching business credential.
  /// Legacy storage is migrated after the same Owner check, once, without
  /// exposing the secret or requiring another credential entry.
  Future<String?> read(String business) async {
    final owner = await _requireOwner(business);
    final scopedKey = _key(business, owner.actorId);
    var token = await _storage.read(scopedKey);
    if (token == null || token.isEmpty) {
      token = await _storage.read(_oldKey(business));
      if (token != null && token.isNotEmpty) {
        if (!owner.matches(_identity())) {
          throw StateError('Owner account changed during receipt AI setup.');
        }
        await _storage.write(scopedKey, token);
        await _storage.delete(_oldKey(business));
      }
    }
    if (!owner.matches(_identity())) {
      throw StateError('Owner account changed during receipt AI setup.');
    }
    return token?.trim().isNotEmpty == true ? token!.trim() : null;
  }

  /// Called only after a real authenticated receipt extraction succeeds.
  /// Invalid credentials cannot silently replace a working saved credential.
  Future<void> saveVerified(String business, String candidate) async {
    final token = candidate.trim();
    if (token.length < 16 || token.length > 4096 ||
        token.contains(RegExp(r'\\s'))) {
      throw const FormatException('Receipt gateway token has an invalid format.');
    }
    final owner = await _requireOwner(business);
    if (!owner.matches(_identity())) {
      throw StateError('Owner account changed during receipt AI setup.');
    }
    await _storage.write(_key(business, owner.actorId), token);
    if (!owner.matches(_identity())) {
      await _storage.delete(_key(business, owner.actorId));
      throw StateError('Owner account changed during receipt AI setup.');
    }
  }

  Future<void> disconnect(String business) async {
    final owner = await _requireOwner(business);
    await _storage.delete(_key(business, owner.actorId));
    await _storage.delete(_oldKey(business));
  }
}
