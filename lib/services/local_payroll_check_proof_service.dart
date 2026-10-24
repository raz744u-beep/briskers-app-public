import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/payroll_payment_contract.dart';
import 'local_payroll_draft_store.dart';

typedef PayrollProofDirectoryProvider = Future<Directory> Function();

/// Non-networked, app-private Check photo staging for draft payroll entries.
///
/// Proof is NOT a posted payment and is never uploaded here. The caller must
/// authenticate/authorize the Owner before invoking this service. The service
/// separately requires an Owner flag and non-empty authenticated user ID.
///
/// File paths are derived from SHA-256 scope/content, not picker filenames,
/// employee nicknames or raw shop IDs. Files are kept until a future reviewed
/// backend has confirmed a durable private upload. No cleanup while pending.
class LocalPayrollCheckProofService {
  LocalPayrollCheckProofService({
    PayrollProofDirectoryProvider? directoryProvider,
    LocalPayrollDraftStore? drafts,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _drafts = drafts ?? LocalPayrollDraftStore();

  static const int maxPhotoBytes = 20 * 1024 * 1024;
  static const int maxPhotoPixels = 16000000;
  static const String _folderName = 'briskers_private/payroll_check_proofs';

  final PayrollProofDirectoryProvider _directoryProvider;
  final LocalPayrollDraftStore _drafts;
  final Random _random = Random.secure();

  static void _requireOwner(
    bool isOwner,
    String businessId,
    String ownerUserId,
    String operationId,
  ) {
    if (!isOwner) {
      throw StateError('Only the Owner can stage payroll check proof.');
    }
    if (businessId.trim().isEmpty ||
        ownerUserId.trim().isEmpty ||
        operationId.trim().isEmpty) {
      throw ArgumentError('Shop, Owner and operation ID are required.');
    }
  }

  static String _scope(
    String businessId,
    String ownerUserId,
    String operationId,
  ) => sha256
      .convert(utf8.encode('$businessId\u0000$ownerUserId\u0000$operationId'))
      .toString();

  Future<Directory> _privateDirectory(
    String businessId,
    String ownerUserId,
    String operationId,
  ) async {
    final root = await _directoryProvider();
    return Directory(
      '${root.path}/$_folderName/${_scope(businessId, ownerUserId, operationId)}',
    );
  }

  static String? _extension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return '.jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return '.png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return '.webp';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      final brand = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return '.heic';
      }
    }
    return null;
  }

  static bool _decodes(Uint8List bytes) {
    try {
      final extension = _extension(bytes);
      if (extension == '.jpg') {
        if (bytes.length < 4 ||
            bytes[bytes.length - 2] != 0xff ||
            bytes.last != 0xd9) {
          return false;
        }
      } else if (extension == '.png') {
        const end = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
        if (bytes.length < end.length) return false;
        for (var i = 0; i < end.length; i++) {
          if (bytes[bytes.length - end.length + i] != end[i]) return false;
        }
      } else if (extension == '.webp') {
        if (ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 !=
            bytes.length) {
          return false;
        }
      } else {
        return false;
      }
      final decoder = image.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width * info.height > maxPhotoPixels ||
          (info is image.WebPInfo ? info.hasAnimation : info.numFrames != 1)) {
        return false;
      }
      final decoded = decoder!.decodeFrame(0);
      return decoded != null &&
          decoded.width == info.width &&
          decoded.height == info.height;
    } catch (_) {
      return false;
    }
  }

  /// Copy picker bytes into permanent app-support storage. Never rely on the
  /// temporary picker URI surviving app restart or network interruption.
  ///
  /// A new version replaces the old file only after the new bytes are flushed
  /// and renamed on the same filesystem. The unrelated original is untouched.
  Future<PayrollPaymentDraft> stageForDraft({
    required bool isOwner,
    required String ownerUserId,
    required PayrollPaymentDraft draft,
    required PayrollPaymentMethod method,
    required XFile selectedPhoto,
    bool Function()? isContextCurrent,
  }) async {
    _requireOwner(isOwner, draft.businessId, ownerUserId, draft.operationId);
    if (isContextCurrent?.call() == false) {
      throw StateError('Owner session changed.');
    }
    if (!method.enabled ||
        !method.requiresCheckPhoto ||
        method.businessId != draft.businessId ||
        method.id != draft.methodId) {
      throw ArgumentError('A valid shop-owned Check method is required.');
    }

    final length = await selectedPhoto.length();
    if (length <= 0 || length > maxPhotoBytes) {
      throw const FormatException(
        'Check photo must be between 1 byte and 20 MiB.',
      );
    }
    var bytes = await selectedPhoto.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw const FormatException('Check photo exceeds the allowed size.');
    }
    var extension = _extension(bytes);
    if (extension == null || !_decodes(bytes)) {
      throw const FormatException(
        'Choose a readable JPEG, PNG or WebP photo, up to 16 megapixels. Convert HEIC to JPEG first.',
      );
    }

    if (extension == '.webp' || extension == '.png') {
      // Canonical 8-bit PNG removes compressed metadata and bounds server decode.
      bytes = Uint8List.fromList(
        image.encodePng(
          image
              .decodeImage(bytes)!
              .convert(format: image.Format.uint8, numChannels: 4),
        ),
      );
      extension = '.png';
      if (bytes.length > maxPhotoBytes) {
        throw const FormatException(
          'Converted Check photo exceeds 20 MiB. Choose a smaller photo.',
        );
      }
    }

    final digest = sha256.convert(bytes).toString();
    final privateDir = await _privateDirectory(
      draft.businessId,
      ownerUserId,
      draft.operationId,
    );
    await privateDir.create(recursive: true);
    final destination = File('${privateDir.path}/$digest$extension');
    final unique =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 32).toRadixString(16)}';
    final temporary = File('${privateDir.path}/.pending-$unique');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await temporary.length() != bytes.length) {
        throw const FileSystemException(
          'Private Check photo copy was incomplete.',
        );
      }
      await temporary.rename(destination.path);
      final verifiedBytes = await destination.readAsBytes();
      if (verifiedBytes.length != bytes.length ||
          sha256.convert(verifiedBytes).toString() != digest) {
        throw const FileSystemException('Saved Check photo checksum mismatch.');
      }

      final updatedDraft = PayrollPaymentDraft(
        businessId: draft.businessId,
        employeeId: draft.employeeId,
        operationId: draft.operationId,
        methodId: draft.methodId,
        methodLabelSnapshot: draft.methodLabelSnapshot,
        amountCents: draft.amountCents,
        paymentDate: draft.paymentDate,
        payrollWeekKey: draft.payrollWeekKey,
        laborAllocations: draft.laborAllocations,
        sourceAccountId: draft.sourceAccountId,
        reference: draft.reference,
        checkProofAttachmentId: 'local-check-$digest',
        checkProofDurablyStored: true,
        checkProofSizeBytes: verifiedBytes.length,
        checkProofSha256: digest,
      );
      await _drafts.save(
        isOwner: isOwner,
        ownerUserId: ownerUserId,
        draft: updatedDraft,
        isContextCurrent: isContextCurrent,
      );
      return updatedDraft;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List> readFrozenProofBytes({
    required bool isOwner,
    required String ownerUserId,
    required String businessId,
    required String operationId,
    required String digest,
    required int byteSize,
  }) async {
    _requireOwner(isOwner, businessId, ownerUserId, operationId);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        byteSize <= 0 ||
        byteSize > maxPhotoBytes) {
      throw const FormatException('Invalid frozen proof metadata.');
    }
    final directory = await _privateDirectory(
      businessId,
      ownerUserId,
      operationId,
    );
    for (final extension in ['.jpg', '.png', '.webp']) {
      final file = File('${directory.path}/$digest$extension');
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.length != byteSize ||
          _extension(bytes) != extension ||
          !_decodes(bytes) ||
          sha256.convert(bytes).toString() != digest) {
        throw const FormatException('Check photo changed.');
      }
      if (extension == '.png') {
        final canonical = image.encodePng(
          image
              .decodePng(bytes)!
              .convert(format: image.Format.uint8, numChannels: 4),
        );
        if (sha256.convert(canonical).toString() != digest) {
          throw const FormatException(
            'Reselect this photo to normalize its metadata before submission.',
          );
        }
      }
      if (extension == '.webp') {
        throw const FormatException(
          'Reselect this photo to save a server-compatible PNG before submission.',
        );
      }
      return bytes;
    }
    throw const FileSystemException('Private Check photo is unavailable.');
  }

  /// Re-open and checksum the actual file after restart.
  ///
  /// An invented attachment ID, an altered photo, or a private scope mismatch
  /// returns false; metadata alone is insufficient evidence of a valid photo.
  Future<bool> isProofIntact({
    required bool isOwner,
    required String ownerUserId,
    required PayrollPaymentDraft draft,
  }) async {
    _requireOwner(isOwner, draft.businessId, ownerUserId, draft.operationId);
    final digest = draft.checkProofSha256;
    if (!draft.checkProofDurablyStored ||
        digest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        draft.checkProofAttachmentId != 'local-check-$digest' ||
        draft.checkProofSizeBytes == null ||
        draft.checkProofSizeBytes! <= 0 ||
        draft.checkProofSizeBytes! > maxPhotoBytes) {
      return false;
    }
    final privateDir = await _privateDirectory(
      draft.businessId,
      ownerUserId,
      draft.operationId,
    );
    for (final ext in const ['.jpg', '.png', '.webp', '.heic']) {
      final file = File('${privateDir.path}/$digest$ext');
      if (!await file.exists()) continue;
      try {
        if (await file.length() != draft.checkProofSizeBytes) return false;
        final bytes = await file.readAsBytes();
        return _extension(bytes) == ext &&
            _decodes(bytes) &&
            sha256.convert(bytes).toString() == digest;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
