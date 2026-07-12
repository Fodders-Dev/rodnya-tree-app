// SPEED-4: тёплый HTTP-клиент для горячих путей (отправка сообщений).
// Дефолтный dart:io HttpClient рвёт idle keep-alive соединение через 15с —
// пауза на набор текста длиннее 15с означает свежий TCP+TLS handshake на
// следующей отправке (+100–300мс на мобильной сети). Держим соединение
// тёплым 5 минут: сокет уже прогрет открытием чата (первый GET сообщений),
// и остаётся тёплым на всю сессию переписки.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createWarmHttpClient() {
  final inner = HttpClient()..idleTimeout = const Duration(minutes: 5);
  return IOClient(inner);
}
