import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/auth_sessions_service.dart';
import '../services/custom_api_auth_service.dart';

/// Used by an *already-signed-in* device to confirm a QR-login request from
/// another device.  Camera reads the token, the auth API mints a new session
/// for the same user with the new device's metadata, and the unauthenticated
/// device picks up the auth payload via polling.
class QrLoginScanScreen extends StatefulWidget {
  const QrLoginScanScreen({super.key});

  @override
  State<QrLoginScanScreen> createState() => _QrLoginScanScreenState();
}

class _QrLoginScanScreenState extends State<QrLoginScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    final token = _extractToken(raw);
    if (token == null) {
      _showSnack('QR-код не относится к Родне');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final service = GetIt.I<AuthSessionsService>();
      await service.approveQrLogin(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вход подтверждён на другом устройстве')),
      );
      context.pop();
    } on CustomApiException catch (error) {
      _showSnack(error.message);
    } catch (error) {
      _showSnack('Не удалось подтвердить вход: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String? _extractToken(String raw) {
    // Accept either the bare token or a rodnya:// URI form so this is
    // resilient to future QR payload shapes.
    if (raw.startsWith('rodnya://qr-login/')) {
      return raw.substring('rodnya://qr-login/'.length);
    }
    if (RegExp(r'^[a-fA-F0-9]{32,}$').hasMatch(raw)) {
      return raw;
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканировать QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            tooltip: 'Вспышка',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            tooltip: 'Камера',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            const ColoredBox(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Откройте на новом устройстве экран входа по QR и наведите '
                  'камеру на код.',
                  style: TextStyle(color: Colors.white),
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
