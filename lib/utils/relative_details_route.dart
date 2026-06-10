/// P0 (мамин баг): единый builder ссылки на карточку родственника.
///
/// Карточка резолвит дерево сама (кэш → выбранное → обход), но явный
/// `treeId` из контекста — самый надёжный и быстрый путь, поэтому каждая
/// точка входа, которая знает дерево, обязана его прокинуть. Билдер
/// держит query-сборку (и encode) в одном месте, чтобы 14 call-site'ов
/// не расходились в форматах.
String relativeDetailsRoute(
  String personId, {
  String? treeId,
  String? action,
}) {
  final params = <String, String>{
    if (treeId != null && treeId.trim().isNotEmpty) 'treeId': treeId.trim(),
    if (action != null && action.trim().isNotEmpty) 'action': action.trim(),
  };
  final base = '/relative/details/$personId';
  if (params.isEmpty) {
    return base;
  }
  final query = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '$base?$query';
}
