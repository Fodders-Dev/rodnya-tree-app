part of '../relatives_screen.dart';

class _ContactStatus {
  const _ContactStatus({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;
}

String _countLabel(
  int count, {
  required String one,
  required String few,
  required String many,
}) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) {
    return '$count $one';
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count $few';
  }
  return '$count $many';
}

class _RelativesSectionHeader {
  const _RelativesSectionHeader({
    required this.title,
    this.count,
    this.collapsible = false,
    this.expanded = true,
    this.onToggle,
  });

  final String title;
  final int? count;

  /// F3: секция «Нужно пригласить» сворачивается — заголовок-строка с
  /// количеством и шевроном, чтобы живые пользователи были сверху.
  final bool collapsible;
  final bool expanded;
  final VoidCallback? onToggle;
}

class _RelationPathStep {
  const _RelationPathStep({
    required this.personId,
    required this.code,
  });

  final String personId;
  final String code;
}
