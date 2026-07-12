// SPEED-4: платформо-зависимая фабрика «тёплого» http.Client.
// IO (Android/iOS/desktop): idleTimeout 15с → 5мин, чтобы отправка после
// паузы на набор текста не платила свежий TCP+TLS (+100–300мс).
// Web: браузерный клиент как есть.
export 'warm_http_client_web.dart'
    if (dart.library.io) 'warm_http_client_io.dart';
