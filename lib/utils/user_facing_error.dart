import 'dart:async';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/models/user_facing_exception.dart';

const List<String> _technicalMarkers = <String>[
  'exception',
  'typeerror',
  'stateerror',
  'socketexception',
  'httpexception',
  'failed to',
  'backend (',
  'no such method',
];

const List<String> _networkMarkers = <String>[
  'socketexception',
  'failed host lookup',
  'connection refused',
  'connection reset',
  'connection closed',
  'network is unreachable',
  'clientexception',
  'timed out',
  'timeoutexception',
];

bool _looksTechnical(String text) {
  final normalized = text.toLowerCase();
  return _technicalMarkers.any(normalized.contains);
}

bool _looksLikeNetworkError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  // SocketException/ClientException матчим по тексту: dart:io на web
  // недоступен, а http.ClientException тянуть сюда не хочется.
  final normalized = error.toString().toLowerCase();
  return _networkMarkers.any(normalized.contains);
}

/// Человеческое сообщение об ошибке без AuthServiceInterface — для
/// виджетов (post_card, comment_sheet) и экранов, у которых нет
/// auth-сервиса под рукой. UX-аудит 2026-07-04: ~45 мест показывали
/// сырой toString() («SocketException: Failed host lookup…»).
///
/// Порядок: сеть → статус-бакеты → серверный message (если не выглядит
/// технически) → [fallback]. Не-API исключения ВСЕГДА дают [fallback] —
/// toString() пользователю не утекает никогда.
String humanizeError(Object error, {required String fallback}) {
  if (_looksLikeNetworkError(error)) {
    return 'Не удалось подключиться к серверу. Проверьте интернет и попробуйте ещё раз.';
  }
  if (error is UserFacingApiException) {
    final status = error.statusCode;
    if (status == 429) {
      return 'Слишком много попыток. Подождите немного и попробуйте ещё раз.';
    }
    if (status != null && status >= 500) {
      return 'Сервис временно недоступен. Попробуйте позже.';
    }
    final message = error.message.trim();
    if (message.isNotEmpty && !_looksTechnical(message)) {
      return message;
    }
  }
  return fallback;
}

String describeUserFacingError({
  required AuthServiceInterface authService,
  required Object error,
  required String fallbackMessage,
}) {
  final description = authService.describeError(error).trim();
  if (description.isEmpty) {
    return fallbackMessage;
  }

  final raw = error.toString().trim();
  final looksTechnical = description == raw || _looksTechnical(description);
  return looksTechnical ? fallbackMessage : description;
}
