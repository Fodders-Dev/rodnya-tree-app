// SPEED-4 (web-ветка): в браузере соединениями управляет сам браузер
// (HTTP/2, connection pooling) — idleTimeout недоступен и не нужен.
import 'package:http/http.dart' as http;

http.Client createWarmHttpClient() => http.Client();
