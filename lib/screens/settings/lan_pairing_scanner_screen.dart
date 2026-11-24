import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/lan_inventory_session.dart';

class LanPairingScannerScreen extends StatefulWidget {
  const LanPairingScannerScreen({super.key});

  @override
  State<LanPairingScannerScreen> createState() => _LanPairingScannerScreenState();
}

class _LanPairingScannerScreenState extends State<LanPairingScannerScreen> {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _finished = false;
  bool _invalidCode = false;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finished || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || !LanInventorySession.isComparisonCode(code)) continue;
      _finished = true;
      Navigator.pop(context, code);
      return;
    }
    if (!_invalidCode && capture.barcodes.isNotEmpty) {
      setState(() => _invalidCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _camera,
                onDetect: _onDetect,
                errorBuilder: (context, error) => const Center(
                  child: Text('Camera unavailable. Enter the code manually.'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(_invalidCode
                  ? 'Use the QR code on the source phone’s LAN record preview.'
                  : 'Point this camera at the QR code on the source phone.'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Enter code manually'),
            ),
          ],
        ),
      ),
    );
  }
}
