import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/auth_sessions_service.dart';
import '../services/custom_api_auth_service.dart';

/// Shown on a *fresh* device that wants to sign in by having an existing
/// device scan its QR code. Generates a one-time login token, displays it as
/// a QR, and polls the backend until the other device approves (or the token
/// expires).
class QrLoginDisplayScreen extends StatefulWidget {
  const QrLoginDisplayScreen({super.key});

  @override
  State<QrLoginDisplayScreen> createState() => _QrLoginDisplayScreenState();
}

class _QrLoginDisplayScreenState extends State<QrLoginDisplayScreen> {
  late final AuthSessionsService _sessionsService =
      GetIt.I<AuthSessionsService>();
  late final CustomApiAuthService _authService =
      GetIt.I<CustomApiAuthService>();

  QrLoginStartResult? _qrToken;
  Object? _error;
  bool _isLoading = true;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await _sessionsService.startQrLogin();
      if (_disposed) return;
      setState(() {
        _qrToken = token;
        _isLoading = false;
      });
      _schedulePolling();
      _scheduleExpiry();
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  void _schedulePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final token = _qrToken?.token;
      if (token == null || _disposed) return;
      try {
        final result = await _sessionsService.pollQrLogin(token);
        if (_disposed) return;
        if (result.status == QrLoginPollStatus.approved &&
            result.auth != null) {
          _pollTimer?.cancel();
          _expiryTimer?.cancel();
          await _authService.acceptAuthPayload(result.auth!);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Вы вошли в Родню')),
          );
          context.go('/profile');
        } else if (result.status == QrLoginPollStatus.expired) {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _qrToken = null;
            _error = 'QR-код истёк. Сгенерируйте новый.';
          });
        }
      } catch (_) {
        // Transient errors; keep trying.
      }
    });
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final expiresAt = _qrToken?.expiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return;
    _expiryTimer = Timer(remaining + const Duration(seconds: 1), () {
      if (_disposed) return;
      setState(() {
        _qrToken = null;
        _error = 'QR-код истёк. Сгенерируйте новый.';
      });
    });
  }

  String _qrPayload(String token) => 'rodnya://qr-login/$token';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Вход по QR')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error.toString(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _start,
                          child: const Text('Сгенерировать новый'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: _qrPayload(_qrToken!.token),
                            size: 240,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '1. На устройстве, на котором вы уже вошли — '
                          'откройте «Активные сеансы».\n'
                          '2. Нажмите иконку сканера в правом верхнем углу.\n'
                          '3. Наведите камеру на этот код.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
