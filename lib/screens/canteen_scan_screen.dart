import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/upi.dart';

/// Scans the canteen's UPI QR code and pops with the [UpiPayee] found.
/// Everything happens on the device: no image or text leaves the phone.
class CanteenScanScreen extends StatefulWidget {
  const CanteenScanScreen({super.key});

  @override
  State<CanteenScanScreen> createState() => _CanteenScanScreenState();
}

enum _CameraState { checking, granted, denied, permanentlyDenied }

class _CanteenScanScreenState extends State<CanteenScanScreen> {
  MobileScannerController? _controller;
  _CameraState _camera = _CameraState.checking;
  bool _handled = false;
  bool _torchOn = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (!mounted) return;
      if (status.isGranted) {
        setState(() {
          _controller = MobileScannerController(
            formats: const [BarcodeFormat.qrCode],
            detectionSpeed: DetectionSpeed.noDuplicates,
          );
          _camera = _CameraState.granted;
        });
      } else if (status.isPermanentlyDenied) {
        setState(() => _camera = _CameraState.permanentlyDenied);
      } else {
        setState(() => _camera = _CameraState.denied);
      }
    } catch (e) {
      debugPrint('Camera permission error: $e');
      if (mounted) setState(() => _camera = _CameraState.denied);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text == null || text.trim().isEmpty) continue;
      final payee = parseUpiPayload(text);
      if (payee != null) {
        _handled = true;
        Navigator.pop(context, payee);
        return;
      }
    }
    if (_hint == null && mounted) {
      setState(() => _hint = 'This does not look like a UPI payment QR');
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller?.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (e) {
      debugPrint('Torch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_camera == _CameraState.granted && _controller != null)
              MobileScanner(controller: _controller!, onDetect: _onDetect)
            else
              _buildStatus(),
            if (_camera == _CameraState.granted) ...[
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: canteenTeal, width: 3),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hint ?? 'Point the camera at the canteen\'s UPI QR code',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _hint == null ? Colors.white : Colors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Scanned on your phone only. Nothing is uploaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (_camera == _CameraState.granted)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(
                    _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleTorch,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    if (_camera == _CameraState.checking) {
      return const Center(child: CircularProgressIndicator(color: canteenTeal));
    }
    final permanent = _camera == _CameraState.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Camera permission is needed to scan the QR code',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can also go back and type the UPI ID yourself.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: permanent
                  ? () => openAppSettings()
                  : () {
                      setState(() => _camera = _CameraState.checking);
                      _prepare();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: canteenTeal,
                foregroundColor: Colors.white,
              ),
              child: Text(permanent ? 'Open app settings' : 'Allow camera'),
            ),
          ],
        ),
      ),
    );
  }
}
