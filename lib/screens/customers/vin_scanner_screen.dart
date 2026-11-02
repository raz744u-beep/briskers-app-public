import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/vin_capture_parser.dart';

enum _CaptureStage { choose, barcode, processing, review }

/// Camera and photograph inputs do not write to the vehicle database.
/// A full VIN must be explicitly confirmed in this screen before returning.
class VinScannerScreen extends StatefulWidget {
  const VinScannerScreen({super.key});

  @override
  State<VinScannerScreen> createState() => _VinScannerScreenState();
}

class _VinScannerScreenState extends State<VinScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _vin = TextEditingController();
  MobileScannerController? _barcodeCamera;
  _CaptureStage _stage = _CaptureStage.choose;
  List<String> _candidates = const [];
  String? _error;
  String? _cameraPhotoPath;
  bool _torchOn = false;
  bool _barcodeHandled = false;
  bool _allowUnverified = false;

  @override
  void dispose() {
    final camera = _barcodeCamera;
    if (camera != null) unawaited(camera.dispose());
    _removeTemporaryPhoto();
    _vin.dispose();
    super.dispose();
  }

  void _removeTemporaryPhoto() {
    final path = _cameraPhotoPath;
    _cameraPhotoPath = null;
    if (path == null) return;
    // Only camera images created by this capture flow are deleted. A photo
    // chosen from the gallery is never removed or modified.
    unawaited(_deleteCameraPhoto(path));
  }

  Future<void> _deleteCameraPhoto(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Camera temporary files are best-effort cleanup. No gallery file
      // or server-stored customer artifact is ever deleted here.
    }
  }

  Future<void> _choose() async {
    final camera = _barcodeCamera;
    if (camera != null) {
      try { await camera.stop(); } catch (_) {}
    }
    _removeTemporaryPhoto();
    if (!mounted) return;
    setState(() {
      _stage = _CaptureStage.choose;
      _candidates = const [];
      _vin.clear();
      _error = null;
      _barcodeHandled = false;
      _torchOn = false;
      _allowUnverified = false;
    });
  }

  void _manual() {
    _removeTemporaryPhoto();
    setState(() {
      _stage = _CaptureStage.review;
      _candidates = const [];
      _vin.clear();
      _error = null;
      _allowUnverified = false;
    });
  }

  Future<void> _barcode() async {
    _removeTemporaryPhoto();
    final previous = _barcodeCamera;
    if (previous != null) {
      try { await previous.stop(); } catch (_) {}
      await previous.dispose();
    }
    if (!mounted) return;
    setState(() {
      _barcodeHandled = false;
      _torchOn = false;
      _error = null;
      _candidates = const [];
      _stage = _CaptureStage.barcode;
      _barcodeCamera = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        autoZoom: true,
        formats: const [
          BarcodeFormat.code39,
          BarcodeFormat.code128,
          BarcodeFormat.pdf417,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.qrCode,
        ],
      );
    });
  }

  Future<void> _onBarcode(BarcodeCapture capture) async {
    if (_barcodeHandled || !mounted) return;
    final values = VinCaptureParser.fromBarcodeValues(
      capture.barcodes.map((barcode) => barcode.rawValue),
    );
    if (values.isEmpty) {
      // Keep looking instead of accepting a random barcode and silently
      // cutting its text to seventeen characters.
      if (_error == null) {
        setState(() => _error =
            'Barcode detected, but not a complete VIN. Try a photo instead.');
      }
      return;
    }
    _barcodeHandled = true;
    try { await _barcodeCamera?.stop(); } catch (_) {}
    if (!mounted) return;
    _review(values);
  }

  void _review(List<String> values) {
    if (!mounted) return;
    // A checksum mismatch must not be silently presented as a verified scan.
    // Keep the image-based candidate visible for the owner's correction.
    final ranked = VinCaptureParser.preferVerified(values);
    setState(() {
      _stage = _CaptureStage.review;
      _candidates = ranked;
      _allowUnverified = false;
      _vin.text = ranked.isEmpty ? '' : ranked.first;
      _vin.selection = TextSelection.collapsed(offset: _vin.text.length);
      _error = ranked.isEmpty
          ? 'No complete VIN recognized. Retake the picture or type it.'
          : VinCaptureParser.hasValidCheckDigit(ranked.first)
              ? null
              : 'VIN check digit does not match. The camera may have '
                  'misread characters. Compare against the vehicle label.';
    });
  }

  Future<void> _photo(ImageSource source) async {
    // Release live barcode camera before opening the system photo camera.
    try { await _barcodeCamera?.stop(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _stage = _CaptureStage.processing;
      _error = null;
    });
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2800,
      );
      if (!mounted) return;
      if (image == null) {
        await _choose();
        return;
      }
      _removeTemporaryPhoto();
      if (source == ImageSource.camera) _cameraPhotoPath = image.path;
      // Latin ML Kit OCR runs on the device. Do not upload/store the image.
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        final lines = [
          for (final block in result.blocks)
            for (final line in block.lines) line.text,
        ];
        _review(VinCaptureParser.fromTextLines(lines));
      } finally {
        await recognizer.close();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _CaptureStage.choose;
        _error = 'Could not read the photo. Retake it or enter the VIN.';
      });
    }
  }

  void _confirm() {
    final candidate = VinCaptureParser.normalize(_vin.text);
    if (!VinCaptureParser.isValid(candidate)) {
      setState(() {
        _error = candidate.length != 17
            ? 'A modern VIN has exactly 17 characters. Found ${candidate.length}.'
            : 'VIN cannot contain I, O, or Q. Check letters against the label.';
      });
      return;
    }
    // A modern US-market VIN includes a calculated check digit. Explicit
    // second confirmation is required for unverified imported VINs, never
    // automatic acceptance of an OCR guess.
    if (!VinCaptureParser.hasValidCheckDigit(candidate) &&
        !_allowUnverified) {
      setState(() {
        _allowUnverified = true;
        _error = 'VIN check digit does not match. Double-check all '
            'characters against the vehicle, especially the first three. '
            'Tap Use unverified VIN only if you have checked it manually.';
      });
      return;
    }
    // Capture never saves the vehicle or calls the network; parent form
    // receives the user-confirmed value and remains editable.
    Navigator.of(context).pop(candidate);
  }

  Widget _choice({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onPressed,
  }) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: Icon(icon, size: 30),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onPressed,
    ),
  );

  Widget _chooseView() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Capture a VIN',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'Windshield VINs are usually printed. Door-jamb labels may also '
        'have barcodes. You can confirm and edit any reading before saving.',
      ),
      const SizedBox(height: 18),
      _choice(
        icon: Icons.photo_camera_outlined,
        title: 'Take a VIN photo',
        description: 'Best for windshield numbers or printed door stickers.',
        onPressed: () => _photo(ImageSource.camera),
      ),
      _choice(
        icon: Icons.qr_code_scanner,
        title: 'Scan a VIN barcode',
        description: 'For door-jamb barcode labels. Auto-zoom and flashlight.',
        onPressed: _barcode,
      ),
      _choice(
        icon: Icons.photo_library_outlined,
        title: 'Choose an existing photo',
        description: 'Read a VIN from a photo already on this device.',
        onPressed: () => _photo(ImageSource.gallery),
      ),
      _choice(
        icon: Icons.keyboard_outlined,
        title: 'Enter manually',
        description: 'Type all 17 characters and confirm.',
        onPressed: _manual,
      ),
      const SizedBox(height: 18),
      const Text(
        'Photo recognition happens on this phone. It does not send the '
        'picture to the Briskers server or an AI cloud service.',
        style: TextStyle(fontSize: 12),
      ),
      if (_error != null) _errorNotice(),
    ],
  );

  Widget _errorNotice() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      _error!,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
      textAlign: TextAlign.center,
    ),
  );

  Widget _barcodeView() => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _barcodeCamera!,
        onDetect: _onBarcode,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Camera unavailable. Use Take a VIN photo or manual entry. '
              '${error.toString()}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      IgnorePointer(
        child: Center(
          child: Container(
            width: MediaQuery.sizeOf(context).width * .90,
            height: 130,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.lightGreenAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 12,
        left: 12,
        right: 12,
        child: Card(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Center the door-label barcode in the green frame. '
                  'Only complete VINs will be accepted.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) _errorNotice(),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _barcodeCamera?.toggleTorch();
                          if (mounted) setState(() => _torchOn = !_torchOn);
                        } catch (_) {}
                      },
                      icon: Icon(_torchOn ? Icons.flash_off : Icons.flash_on),
                      label: Text(_torchOn ? 'Flash off' : 'Flashlight'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _photo(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo instead'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _reviewView() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Confirm VIN',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text(
        'Compare every character with the windshield or door sticker. '
        'Recognition can mistake 0 for O or 1 for I.',
      ),
      if (_cameraPhotoPath != null) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(_cameraPhotoPath!),
            fit: BoxFit.contain,
            height: 160,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ],
      if (_candidates.length > 1) ...[
        const SizedBox(height: 14),
        const Text('Possible VINs (select the correct one):'),
        const SizedBox(height: 6),
        for (final candidate in _candidates.take(5))
          ListTile(
            title: SelectableText(candidate),
            trailing: _vin.text == candidate
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.circle_outlined),
            onTap: () => setState(() {
              _vin.text = candidate;
              _allowUnverified = false;
              _error = VinCaptureParser.hasValidCheckDigit(candidate)
                  ? null
                  : 'VIN check digit does not match. Check the label.';
            }),
          ),
      ],
      const SizedBox(height: 18),
      TextField(
        controller: _vin,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 17,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'VIN — check all 17 characters',
          hintText: 'Example: WBA...',
          helperText: 'Letters I, O, and Q are not used in modern VINs',
        ),
        onChanged: (_) {
          setState(() {
            _allowUnverified = false;
            _error = null;
          });
        },
      ),
      if (_error != null) _errorNotice(),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _confirm,
        icon: const Icon(Icons.check_circle_outline),
        label: Text(_allowUnverified ? 'Use unverified VIN' : 'Use this VIN'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _choose,
        icon: const Icon(Icons.refresh),
        label: const Text('Retake or scan again'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('VIN Capture'),
      actions: [
        if (_stage == _CaptureStage.barcode)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Other VIN options',
            onPressed: _choose,
          ),
      ],
    ),
    body: switch (_stage) {
      _CaptureStage.choose => _chooseView(),
      _CaptureStage.barcode => _barcodeView(),
      _CaptureStage.processing => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Reading VIN on this device...'),
          ],
        ),
      ),
      _CaptureStage.review => _reviewView(),
    },
  );
}
