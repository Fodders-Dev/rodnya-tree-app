import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// M2 (release-APK для средних телефонов): размер декода под фактический
/// слот. CachedNetworkImage без memCacheWidth декодирует оригинал (фото с
/// телефонов — 3-4К), что на 4ГБ-устройствах (Samsung A50) даёт jank и
/// OOM-риск. Считаем ширину декода = логическая ширина слота × DPR,
/// округлённая ВВЕРХ до сотен (стабильные ключи кэша, без недодекода).
/// На Flutter Web (`kIsWeb`) браузер сам управляет декодированием `HtmlImage`,
/// а искусственный `ResizeImage` дробит `ImageCache` между экранами и брейкпоинтами.
int? decodeCacheWidth(BuildContext context, double logicalWidth) {
  if (kIsWeb) {
    return null;
  }
  final dpr = MediaQuery.of(context).devicePixelRatio;
  final px = (logicalWidth * dpr).ceil();
  return ((px + 99) ~/ 100) * 100;
}

/// Ширина декода для слота «во всю ширину экрана» (фид-карусель,
/// полноэкранные просмотры с ограничением по брифингу M2).
int? decodeCacheWidthForScreen(BuildContext context) =>
    decodeCacheWidth(context, MediaQuery.of(context).size.width);
