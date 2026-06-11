import 'package:flutter/material.dart';

enum AppEventType {
  birthday,
  weddingAnniversary,
  deathAnniversary,
  memorial9days,
  memorial40days,
  customFamilyEvent,
  russianHoliday,
  orthodoxHoliday,

  /// K3: народные и профессиональные праздники (Татьянин день, День
  /// медработника, День шахтёра…) — «близкое к народу», отдельная
  /// категория, чтобы не смешивать с государственными.
  folkHoliday,
  other,
}

class AppEvent {
  final String id; // Может быть полезен, например, personId + eventType
  final AppEventType type;
  final DateTime date;
  final String title; // Например, "День рождения" или "9 дней"
  final String personName;
  final String personId;

  /// P0: дерево, из которого собрано событие. Карточка человека по тапу
  /// открывается сразу в правильном дереве (а не в выбранном). Опционально:
  /// у праздников дерева нет, старые конструкторы продолжают работать.
  final String? treeId;

  /// K2: год рождения человека (для дней рождения) — agenda-список
  /// показывает «исполнится N лет». Опционально, только у birthday.
  final int? personBirthYear;
  final IconData icon; // Иконка для отображения
  final String? description; // Краткое описание (для праздников)

  AppEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.title,
    required this.personName,
    required this.personId,
    this.treeId,
    this.personBirthYear,
    required this.icon,
    this.description,
  });

  /// K2: возраст, который исполняется в дату события (для birthday).
  int? get ageAtEvent =>
      personBirthYear == null ? null : date.year - personBirthYear!;

  // Метод для получения оставшегося времени или статуса
  String get status {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final difference = eventDay.difference(today).inDays;

    if (difference == 0) {
      return 'Сегодня';
    } else if (difference == 1) {
      return 'Завтра';
    } else if (difference > 1 && difference <= 7) {
      return 'Через $difference ${_dayWord(difference)}';
    } else if (difference < 0) {
      return 'Прошло'; // На всякий случай
    } else {
      return _formatShortDate(date);
    }
  }

  bool get isLinkedToPerson => personId.trim().isNotEmpty;

  String get categoryLabel {
    switch (type) {
      case AppEventType.birthday:
        return 'Родня';
      case AppEventType.weddingAnniversary:
        return 'Семья';
      case AppEventType.deathAnniversary:
      case AppEventType.memorial9days:
      case AppEventType.memorial40days:
        return 'Память';
      case AppEventType.customFamilyEvent:
        return 'Повод';
      case AppEventType.russianHoliday:
        return 'Россия';
      case AppEventType.orthodoxHoliday:
        return 'Православие';
      case AppEventType.folkHoliday:
        return 'Народный';
      case AppEventType.other:
        return 'Календарь';
    }
  }

  String _dayWord(int value) {
    final mod10 = value % 10;
    final mod100 = value % 100;
    if (mod10 == 1 && mod100 != 11) {
      return 'день';
    }
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'дня';
    }
    return 'дней';
  }

  String _formatShortDate(DateTime value) {
    const months = <int, String>{
      1: 'янв',
      2: 'фев',
      3: 'мар',
      4: 'апр',
      5: 'мая',
      6: 'июн',
      7: 'июл',
      8: 'авг',
      9: 'сен',
      10: 'окт',
      11: 'ноя',
      12: 'дек',
    };

    return '${value.day} ${months[value.month] ?? ''}'.trim();
  }
}
