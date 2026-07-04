/// Общая форма API-исключений для показа пользователю.
///
/// В сервисах живёт девять структурно одинаковых классов
/// (CustomApiException, CustomApiCallException, CustomApiPostException…)
/// без общего супертипа — из-за этого ни один generic-хелпер не мог их
/// распознать и в снекбары утекали сырые toString(). Интерфейс ничего
/// не меняет в поведении — только даёт [humanizeError] точку матчинга.
abstract class UserFacingApiException implements Exception {
  /// Серверный текст ошибки: бывает дружелюбным русским, бывает
  /// техническим — показывать напрямую можно только после проверки
  /// на технические маркеры (см. humanizeError).
  String get message;

  /// HTTP-статус, когда известен (у части доменных исключений — null).
  int? get statusCode;
}
