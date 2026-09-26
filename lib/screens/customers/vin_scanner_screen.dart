import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/formatters.dart';

class VinScannerScreen extends StatefulWidget {
  const VinScannerScreen({super.key});

  @override
  State<VinScannerScreen> createState() => _VinScannerScreenState();
}

class _VinScannerScreenState extends State<VinScannerScreen> {
  bool _handled = false;

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;

      final cleaned = normalizeVin(raw);
      if (cleaned.isEmpty) continue;

      _handled = true;
      Navigator.pop(context, cleaned.length > 17 ? cleaned.substring(0, 17) : cleaned);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan VIN barcode')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _handleCapture),
          IgnorePointer(
            child: Center(
              child: Container(
                width: MediaQuery.sizeOf(context).width * 0.88,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Point the camera at the VIN barcode. The scanned VIN will be placed in the VIN field and can still be edited manually.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
