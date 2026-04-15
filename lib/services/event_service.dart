import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/app_event.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';

class EventService {
  EventService({
    FamilyTreeServiceInterface? familyTreeService,
    DateTime Function()? nowProvider,
  })  : _familyTreeService =
            familyTreeService ?? GetIt.I<FamilyTreeServiceInterface>(),
        _nowProvider = nowProvider ?? DateTime.now;

  final FamilyTreeServiceInterface _familyTreeService;
  final DateTime Function() _nowProvider;

  Future<List<AppEvent>> getUpcomingEvents(
    String treeId, {
    int limit = 5,
  }) async {
    debugPrint('[EventService] Запрос событий для дерева $treeId...');
    List<AppEvent> allEvents = [];
    final now = _nowProvider();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final results = await Future.wait<dynamic>([
        _familyTreeService.getRelatives(treeId),
        _familyTreeService.getRelations(treeId),
      ]);
      final relatives = results[0] as List<FamilyPerson>;
      final relations = results[1] as List<FamilyRelation>;
      final relativesById = <String, FamilyPerson>{
        for (final person in relatives) person.id: person,
      };
      debugPrint('[EventService] Найдено ${relatives.length} родственников.');

      for (final person in relatives) {
        if (person.birthDate != null) {
          final nextBirthday = _nextAnnualOccurrence(person.birthDate!, today);
          allEvents.add(
            AppEvent(
              id: '${person.id}_birthday',
              type: AppEventType.birthday,
              date: nextBirthday,
              title: 'День рождения',
              personName: person.name,
              personId: person.id,
              icon: Icons.cake_outlined,
            ),
          );
        }

        if (!person.isAlive && person.deathDate != null) {
          final deathDate = person.deathDate!;
          final memorial9 = deathDate.add(const Duration(days: 8));
          if (_isUpcoming(memorial9, today)) {
            allEvents.add(
              AppEvent(
                id: '${person.id}_memorial9',
                type: AppEventType.memorial9days,
                date: memorial9,
                title: '9 дней',
                personName: person.name,
                personId: person.id,
                icon: Icons.church_outlined,
              ),
            );
          }

          final memorial40 = deathDate.add(const Duration(days: 39));
          if (_isUpcoming(memorial40, today)) {
            allEvents.add(
              AppEvent(
                id: '${person.id}_memorial40',
                type: AppEventType.memorial40days,
                date: memorial40,
                title: '40 дней',
                personName: person.name,
                personId: person.id,
                icon: Icons.church_outlined,
              ),
            );
          }

          final nextDeathAnniversary = _nextAnnualOccurrence(deathDate, today);
          allEvents.add(
            AppEvent(
              id: '${person.id}_death_anniversary',
              type: AppEventType.deathAnniversary,
              date: nextDeathAnniversary,
              title: 'Годовщина памяти',
              personName: person.name,
              personId: person.id,
              icon: Icons.auto_awesome_mosaic_outlined,
            ),
          );
        }

        allEvents.addAll(_buildCustomFamilyEvents(person, today));
      }

      allEvents.addAll(
        _buildWeddingAnniversaryEvents(
          relations: relations,
          relativesById: relativesById,
          today: today,
        ),
      );
      allEvents.addAll(_buildRussianHolidayEvents(today));
      allEvents.addAll(_buildOrthodoxHolidayEvents(today));

      allEvents.sort((a, b) {
        final dateComparison = a.date.compareTo(b.date);
        if (dateComparison != 0) {
          return dateComparison;
        }
        return _typePriority(a.type).compareTo(_typePriority(b.type));
      });

      debugPrint('[EventService] Всего вычислено ${allEvents.length} событий.');

      final upcomingEvents =
          allEvents.where((event) => _isUpcoming(event.date, today)).toList();

      debugPrint(
        '[EventService] Найдено ${upcomingEvents.length} предстоящих событий.',
      );

      return upcomingEvents.take(limit).toList();
    } catch (e, s) {
      debugPrint('[EventService] Ошибка при получении событий: $e\n$s');
      return [];
    }
  }

  List<AppEvent> _buildWeddingAnniversaryEvents({
    required List<FamilyRelation> relations,
    required Map<String, FamilyPerson> relativesById,
    required DateTime today,
  }) {
    return relations
        .where((relation) => _shouldShowWeddingAnniversary(relation, today))
        .map((relation) {
      final partner1 = relativesById[relation.person1Id];
      final partner2 = relativesById[relation.person2Id];
      final marriageDate = relation.marriageDate!;
      final nextAnniversary = _nextAnnualOccurrence(marriageDate, today);
      final partnerNames = [
        partner1?.name,
        partner2?.name,
      ].whereType<String>().where((name) => name.trim().isNotEmpty).toList();

      return AppEvent(
        id: '${relation.id}_wedding_anniversary',
        type: AppEventType.weddingAnniversary,
        date: nextAnniversary,
        title: 'Годовщина свадьбы',
        personName:
            partnerNames.isEmpty ? 'Семейная пара' : partnerNames.join(' и '),
        personId: partner1?.id ?? partner2?.id ?? '',
        icon: Icons.favorite_outline,
      );
    }).toList();
  }

  List<AppEvent> _buildCustomFamilyEvents(
    FamilyPerson person,
    DateTime today,
  ) {
    final details = person.details;
    final events = details?.importantEvents;
    if (events == null || events.isEmpty) {
      return const <AppEvent>[];
    }

    return events
        .where((event) => _isUpcoming(event.date, today))
        .map(
          (event) => AppEvent(
            id: '${person.id}_custom_${event.title}_${event.date.toIso8601String()}',
            type: AppEventType.customFamilyEvent,
            date: DateTime(event.date.year, event.date.month, event.date.day),
            title: event.title,
            personName: person.name,
            personId: person.id,
            icon: Icons.event_outlined,
          ),
        )
        .toList();
  }

  List<AppEvent> _buildRussianHolidayEvents(DateTime today) {
    final years = [today.year, today.year + 1];
    const definitions = <_AnnualHolidayDefinition>[
      _AnnualHolidayDefinition(
        month: 1,
        day: 1,
        title: 'Новый год',
        icon: Icons.celebration_outlined,
      ),
      _AnnualHolidayDefinition(
        month: 2,
        day: 23,
        title: 'День защитника Отечества',
        icon: Icons.shield_outlined,
      ),
      _AnnualHolidayDefinition(
        month: 3,
        day: 8,
        title: 'Международный женский день',
        icon: Icons.local_florist_outlined,
      ),
      _AnnualHolidayDefinition(
        month: 5,
        day: 1,
        title: 'Праздник Весны и Труда',
        icon: Icons.park_outlined,
      ),
      _AnnualHolidayDefinition(
        month: 5,
        day: 9,
        title: 'День Победы',
        icon: Icons.star_outline,
      ),
      _AnnualHolidayDefinition(
        month: 6,
        day: 12,
        title: 'День России',
        icon: Icons.flag_outlined,
      ),
      _AnnualHolidayDefinition(
        month: 11,
        day: 4,
        title: 'День народного единства',
        icon: Icons.groups_2_outlined,
      ),
    ];

    return years
        .expand(
          (year) => definitions.map(
            (holiday) => AppEvent(
              id: 'rf_${holiday.month}_${holiday.day}_$year',
              type: AppEventType.russianHoliday,
              date: DateTime(year, holiday.month, holiday.day),
              title: holiday.title,
              personName: 'Государственный праздник',
              personId: '',
              icon: holiday.icon,
            ),
          ),
        )
        .where((event) => _isUpcoming(event.date, today))
        .toList();
  }

  List<AppEvent> _buildOrthodoxHolidayEvents(DateTime today) {
    final years = [today.year, today.year + 1];

    return years
        .expand((year) {
          final easter = _orthodoxEaster(year);
          final definitions = <_DatedHolidayDefinition>[
            _DatedHolidayDefinition(
              date: DateTime(year, 1, 7),
              title: 'Рождество Христово',
              icon: Icons.auto_awesome_outlined,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 1, 19),
              title: 'Крещение Господне',
              icon: Icons.water_drop_outlined,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 4, 7),
              title: 'Благовещение',
              icon: Icons.wb_twilight_outlined,
            ),
            _DatedHolidayDefinition(
              date: easter.subtract(const Duration(days: 7)),
              title: 'Вербное воскресенье',
              icon: Icons.spa_outlined,
            ),
            _DatedHolidayDefinition(
              date: easter,
              title: 'Пасха',
              icon: Icons.church_outlined,
            ),
            _DatedHolidayDefinition(
              date: easter.add(const Duration(days: 39)),
              title: 'Вознесение',
              icon: Icons.flight_takeoff_outlined,
            ),
            _DatedHolidayDefinition(
              date: easter.add(const Duration(days: 49)),
              title: 'Троица',
              icon: Icons.forest_outlined,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 8, 19),
              title: 'Преображение',
              icon: Icons.wb_sunny_outlined,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 8, 28),
              title: 'Успение Богородицы',
              icon: Icons.nightlight_outlined,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 9, 21),
              title: 'Рождество Богородицы',
              icon: Icons.favorite_outline,
            ),
            _DatedHolidayDefinition(
              date: DateTime(year, 9, 27),
              title: 'Воздвижение Креста',
              icon: Icons.add_road_outlined,
            ),
          ];

          return definitions.map(
            (holiday) => AppEvent(
              id: 'orthodox_${holiday.title}_${holiday.date.toIso8601String()}',
              type: AppEventType.orthodoxHoliday,
              date: holiday.date,
              title: holiday.title,
              personName: 'Православный календарь',
              personId: '',
              icon: holiday.icon,
            ),
          );
        })
        .where((event) => _isUpcoming(event.date, today))
        .toList();
  }

  DateTime _nextAnnualOccurrence(DateTime source, DateTime today) {
    var occurrence = DateTime(today.year, source.month, source.day);
    if (occurrence.isBefore(today)) {
      occurrence = DateTime(today.year + 1, source.month, source.day);
    }
    return occurrence;
  }

  bool _isUpcoming(DateTime date, DateTime today) {
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.isAtSameMomentAs(today) || eventDay.isAfter(today);
  }

  bool _shouldShowWeddingAnniversary(
    FamilyRelation relation,
    DateTime today,
  ) {
    if (relation.relation1to2 != RelationType.spouse &&
        relation.relation2to1 != RelationType.spouse) {
      return false;
    }

    final marriageDate = relation.marriageDate;
    if (marriageDate == null) {
      return false;
    }

    final divorceDate = relation.divorceDate;
    if (divorceDate != null && !_isUpcoming(divorceDate, today)) {
      return false;
    }

    return true;
  }

  int _typePriority(AppEventType type) {
    switch (type) {
      case AppEventType.birthday:
        return 0;
      case AppEventType.weddingAnniversary:
        return 1;
      case AppEventType.deathAnniversary:
        return 2;
      case AppEventType.memorial9days:
      case AppEventType.memorial40days:
        return 3;
      case AppEventType.customFamilyEvent:
        return 4;
      case AppEventType.russianHoliday:
        return 5;
      case AppEventType.orthodoxHoliday:
        return 6;
      case AppEventType.other:
        return 7;
    }
  }

  DateTime _orthodoxEaster(int year) {
    final a = year % 4;
    final b = year % 7;
    final c = year % 19;
    final d = (19 * c + 15) % 30;
    final e = (2 * a + 4 * b - d + 34) % 7;
    final month = (d + e + 114) ~/ 31;
    final day = ((d + e + 114) % 31) + 1;
    final julianDate = DateTime(year, month, day);
    return julianDate.add(const Duration(days: 13));
  }
}

class _AnnualHolidayDefinition {
  const _AnnualHolidayDefinition({
    required this.month,
    required this.day,
    required this.title,
    required this.icon,
  });

  final int month;
  final int day;
  final String title;
  final IconData icon;
}

class _DatedHolidayDefinition {
  const _DatedHolidayDefinition({
    required this.date,
    required this.title,
    required this.icon,
  });

  final DateTime date;
  final String title;
  final IconData icon;
}
