// UX-аудит 2026-07-04: humanizeError — общий гуманизатор ошибок без
// AuthServiceInterface. Гварды: сырой toString() НИКОГДА не утекает.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_call_service.dart';
import 'package:rodnya/utils/user_facing_error.dart';

void main() {
  const fallback = 'Не удалось выполнить действие.';

  group('humanizeError', () {
    test('не-API исключение → всегда fallback, не toString()', () {
      final result =
          humanizeError(StateError('internal detail'), fallback: fallback);
      expect(result, fallback);
      expect(result.contains('internal detail'), isFalse);
    });

    test('сетевые ошибки → «проверьте интернет»', () {
      for (final error in <Object>[
        TimeoutException('12s'),
        Exception('SocketException: Failed host lookup: api.rodnya-tree.ru'),
        Exception('ClientException: Connection reset by peer'),
      ]) {
        expect(
          humanizeError(error, fallback: fallback),
          'Не удалось подключиться к серверу. Проверьте интернет и попробуйте ещё раз.',
          reason: '$error',
        );
      }
    });

    test('429 → «слишком много попыток», 5xx → «временно недоступен»', () {
      expect(
        humanizeError(
          const CustomApiException('rate limited', statusCode: 429),
          fallback: fallback,
        ),
        'Слишком много попыток. Подождите немного и попробуйте ещё раз.',
      );
      expect(
        humanizeError(
          const CustomApiException('boom', statusCode: 503),
          fallback: fallback,
        ),
        'Сервис временно недоступен. Попробуйте позже.',
      );
    });

    test('дружелюбный серверный message проходит как есть', () {
      expect(
        humanizeError(
          const CustomApiException(
              'Пользователь уже участвует в другом звонке'),
          fallback: fallback,
        ),
        'Пользователь уже участвует в другом звонке',
      );
    });

    test('технический серверный message → fallback', () {
      expect(
        humanizeError(
          const CustomApiException('HttpException: backend (500) at /v1/x'),
          fallback: fallback,
        ),
        fallback,
      );
    });

    test('доменные клоны матчатся через общий интерфейс (call, без статуса)',
        () {
      expect(
        humanizeError(
          const CustomApiCallException('Звонок уже завершён'),
          fallback: fallback,
        ),
        'Звонок уже завершён',
      );
    });
  });
}
