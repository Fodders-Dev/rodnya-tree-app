import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/app_event.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../utils/holiday_date_rules.dart';

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
              treeId: person.treeId,
              personBirthYear: person.birthDate!.year,
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
                treeId: person.treeId,
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
                treeId: person.treeId,
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
              treeId: person.treeId,
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
      allEvents.addAll(_buildFolkHolidayEvents(today));

      debugPrint('[EventService] Всего вычислено ${allEvents.length} событий.');

      final upcomingEvents =
          allEvents.where((event) => _isUpcoming(event.date, today)).toList();

      upcomingEvents.sort((a, b) {
        final dateComparison = a.date.compareTo(b.date);
        if (dateComparison != 0) {
          return dateComparison;
        }
        return _typePriority(a.type).compareTo(_typePriority(b.type));
      });

      debugPrint(
        '[EventService] Найдено ${upcomingEvents.length} предстоящих событий.',
      );

      final familyUpcoming = upcomingEvents
          .where((event) => _isFamilyEventType(event.type))
          .toList();
      final calendarUpcoming = upcomingEvents
          .where((event) => !_isFamilyEventType(event.type))
          .toList();

      final prioritizedEvents = <AppEvent>[
        ...familyUpcoming.take(limit),
      ];

      if (prioritizedEvents.length < limit) {
        prioritizedEvents.addAll(
          calendarUpcoming.take(limit - prioritizedEvents.length),
        );
      }

      return prioritizedEvents;
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
        treeId: partner1?.treeId ?? partner2?.treeId,
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
        .map((event) {
          final eventDate = event.repeatsAnnually
              ? _nextAnnualOccurrence(event.date, today)
              : DateTime(event.date.year, event.date.month, event.date.day);
          if (!_isUpcoming(eventDate, today)) {
            return null;
          }

          return AppEvent(
            id: '${person.id}_custom_${event.title}_${event.date.toIso8601String()}',
            type: AppEventType.customFamilyEvent,
            date: eventDate,
            title: event.title,
            personName: person.name,
            personId: person.id,
            treeId: person.treeId,
            icon: Icons.event_outlined,
          );
        })
        .whereType<AppEvent>()
        .toList();
  }

  // Fixed-date Russian state/observance holidays. Shared by the
  // upcoming-feed builder and the calendar grid (per-year builder).
  static const List<_AnnualHolidayDefinition> _russianHolidayDefs =
      <_AnnualHolidayDefinition>[
    _AnnualHolidayDefinition(
      month: 1,
      day: 1,
      title: 'Новый год',
      icon: Icons.celebration_outlined,
      description: 'Главный семейный праздник — встреча нового года в ночь '
          'с 31 декабря на 1 января.',
    ),
    _AnnualHolidayDefinition(
      month: 2,
      day: 23,
      title: 'День защитника Отечества',
      icon: Icons.shield_outlined,
      description: 'День чествования защитников Родины и военнослужащих.',
    ),
    _AnnualHolidayDefinition(
      month: 3,
      day: 8,
      title: 'Международный женский день',
      icon: Icons.local_florist_outlined,
      description: 'Весенний праздник, день поздравления женщин.',
    ),
    _AnnualHolidayDefinition(
      month: 5,
      day: 1,
      title: 'Праздник Весны и Труда',
      icon: Icons.park_outlined,
      description: 'Первомай — праздник весны и труда.',
    ),
    _AnnualHolidayDefinition(
      month: 5,
      day: 9,
      title: 'День Победы',
      icon: Icons.star_outline,
      description: 'День Победы в Великой Отечественной войне 1941–1945 годов.',
    ),
    _AnnualHolidayDefinition(
      month: 6,
      day: 12,
      title: 'День России',
      icon: Icons.flag_outlined,
      description: 'Государственный праздник, посвящённый суверенитету России.',
    ),
    _AnnualHolidayDefinition(
      month: 11,
      day: 4,
      title: 'День народного единства',
      icon: Icons.groups_2_outlined,
      description: 'Праздник в память о событиях 1612 года и единстве народа.',
    ),
    _AnnualHolidayDefinition(
      month: 1,
      day: 14,
      title: 'Старый Новый год',
      icon: Icons.celebration_outlined,
      description: 'Новый год по старому, юлианскому календарю.',
    ),
    _AnnualHolidayDefinition(
      month: 7,
      day: 8,
      title: 'День семьи, любви и верности',
      icon: Icons.favorite_outline,
      description: 'Праздник семьи, связанный с памятью святых Петра '
          'и Февронии Муромских.',
    ),
    _AnnualHolidayDefinition(
      month: 9,
      day: 1,
      title: 'День знаний',
      icon: Icons.school_outlined,
      description: 'Начало учебного года в школах, училищах и вузах.',
    ),
    _AnnualHolidayDefinition(
      month: 12,
      day: 12,
      title: 'День Конституции',
      icon: Icons.account_balance_outlined,
      description:
          'День принятия Конституции Российской Федерации в 1993 году.',
    ),
  ];

  /// All Russian holidays placed in a concrete [year] (no upcoming
  /// filter) — the calendar grid wants every date, past included.
  List<AppEvent> _russianHolidaysForYear(int year) {
    return _russianHolidayDefs
        .map(
          (holiday) => AppEvent(
            id: 'rf_${holiday.month}_${holiday.day}_$year',
            type: AppEventType.russianHoliday,
            date: DateTime(year, holiday.month, holiday.day),
            title: holiday.title,
            personName: 'Государственный праздник',
            personId: '',
            icon: holiday.icon,
            description: holiday.description,
          ),
        )
        .toList();
  }

  List<AppEvent> _buildRussianHolidayEvents(DateTime today) {
    return [today.year, today.year + 1]
        .expand(_russianHolidaysForYear)
        .where((event) => _isUpcoming(event.date, today))
        .toList();
  }

  /// All Orthodox holidays placed in a concrete [year] (no upcoming
  /// filter). Movable feasts derive from [_orthodoxEaster].
  List<AppEvent> _orthodoxHolidaysForYear(int year) {
    final easter = orthodoxEaster(year);
    final definitions = <_DatedHolidayDefinition>[
      _DatedHolidayDefinition(
        date: DateTime(year, 1, 7),
        title: 'Рождество Христово',
        icon: Icons.auto_awesome_outlined,
        description: 'Праздник Рождества Господа Иисуса Христа — один из '
            'главных праздников Церкви.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 1, 19),
        title: 'Крещение Господне',
        icon: Icons.water_drop_outlined,
        description: 'Богоявление — Крещение Иисуса Христа в реке Иордан. '
            'Совершается освящение воды.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 4, 7),
        title: 'Благовещение',
        icon: Icons.wb_twilight_outlined,
        description: 'Благовещение Пресвятой Богородице о рождении Спасителя.',
      ),
      _DatedHolidayDefinition(
        date: easter.subtract(const Duration(days: 7)),
        title: 'Вербное воскресенье',
        icon: Icons.spa_outlined,
        description: 'Вход Господень в Иерусалим. Празднуется за неделю '
            'до Пасхи.',
      ),
      _DatedHolidayDefinition(
        date: easter,
        title: 'Пасха',
        icon: Icons.church_outlined,
        description: 'Светлое Христово Воскресение — главный праздник '
            'православной Церкви.',
      ),
      _DatedHolidayDefinition(
        date: easter.add(const Duration(days: 39)),
        title: 'Вознесение',
        icon: Icons.flight_takeoff_outlined,
        description: 'Вознесение Господне — на сороковой день после Пасхи.',
      ),
      _DatedHolidayDefinition(
        date: easter.add(const Duration(days: 49)),
        title: 'Троица',
        icon: Icons.forest_outlined,
        description: 'День Святой Троицы (Пятидесятница) — сошествие Святого '
            'Духа на апостолов.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 8, 19),
        title: 'Преображение',
        icon: Icons.wb_sunny_outlined,
        description: 'Преображение Господне. В народе — Яблочный Спас.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 8, 28),
        title: 'Успение Богородицы',
        icon: Icons.nightlight_outlined,
        description: 'Успение Пресвятой Богородицы.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 9, 21),
        title: 'Рождество Богородицы',
        icon: Icons.favorite_outline,
        description: 'Рождество Пресвятой Богородицы.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 9, 27),
        title: 'Воздвижение Креста',
        icon: Icons.add_road_outlined,
        description: 'Воздвижение Честного и Животворящего Креста Господня.',
      ),
      // Movable (derive from Easter): Масленица — Прощёное воскресенье
      // (easter−49); Радоница — поминальный вторник (easter+9).
      _DatedHolidayDefinition(
        date: easter.subtract(const Duration(days: 49)),
        title: 'Масленица',
        icon: Icons.local_fire_department_outlined,
        description: 'Сырная седмица перед Великим постом; завершается '
            'Прощёным воскресеньем.',
      ),
      _DatedHolidayDefinition(
        date: easter.add(const Duration(days: 9)),
        title: 'Радоница',
        icon: Icons.local_florist_outlined,
        description: 'День поминовения усопших на второй неделе после Пасхи.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 7, 12),
        title: 'День Петра и Павла',
        icon: Icons.account_balance_outlined,
        description: 'День памяти первоверховных апостолов Петра и Павла, '
            'завершение Петрова поста.',
      ),
      _DatedHolidayDefinition(
        date: DateTime(year, 10, 14),
        title: 'Покров Пресвятой Богородицы',
        icon: Icons.shield_moon_outlined,
        description: 'Покров Пресвятой Богородицы — праздник в честь '
            'заступничества Богородицы.',
      ),
    ];

    return definitions
        .map(
          (holiday) => AppEvent(
            id: 'orthodox_${holiday.title}_${holiday.date.toIso8601String()}',
            type: AppEventType.orthodoxHoliday,
            date: holiday.date,
            title: holiday.title,
            personName: 'Православный календарь',
            personId: '',
            icon: holiday.icon,
            description: holiday.description,
          ),
        )
        .toList();
  }

  List<AppEvent> _buildOrthodoxHolidayEvents(DateTime today) {
    return [today.year, today.year + 1]
        .expand(_orthodoxHolidaysForYear)
        .where((event) => _isUpcoming(event.date, today))
        .toList();
  }

  /// K3: народные и профессиональные праздники — «близкое к народу».
  /// Даты считаются движком правил (utils/holiday_date_rules.dart):
  /// фиксированные, «N-е воскресенье месяца», «последнее воскресенье»;
  /// владелец явно просил уметь «последний четверг месяца», а не только
  /// числа. У каждого — короткое тёплое описание для инфо-шита.
  static final List<_FolkHolidayDefinition> _folkHolidayDefs =
      <_FolkHolidayDefinition>[
    _FolkHolidayDefinition(
      id: 'tatyana',
      title: 'Татьянин день',
      resolveDate: (year) => fixedDate(year, 1, 25),
      icon: Icons.school_outlined,
      description: 'День российского студенчества и именины всех Татьян — '
          'повод позвонить и поздравить.',
    ),
    _FolkHolidayDefinition(
      id: 'fools_day',
      title: 'День смеха',
      resolveDate: (year) => fixedDate(year, 4, 1),
      icon: Icons.sentiment_very_satisfied_outlined,
      description: 'Первое апреля — день добрых шуток и розыгрышей.',
    ),
    _FolkHolidayDefinition(
      id: 'cosmonautics',
      title: 'День космонавтики',
      resolveDate: (year) => fixedDate(year, 4, 12),
      icon: Icons.rocket_launch_outlined,
      description: 'День первого полёта человека в космос — 12 апреля 1961 '
          'года Юрий Гагарин облетел Землю.',
    ),
    _FolkHolidayDefinition(
      id: 'medic',
      title: 'День медицинского работника',
      resolveDate: (year) => nthWeekdayOfMonth(year, 6, DateTime.sunday, 3),
      icon: Icons.medical_services_outlined,
      description: 'Третье воскресенье июня — день врачей, медсестёр и всех, '
          'кто заботится о нашем здоровье.',
    ),
    _FolkHolidayDefinition(
      id: 'fisherman',
      title: 'День рыбака',
      resolveDate: (year) => nthWeekdayOfMonth(year, 7, DateTime.sunday, 2),
      icon: Icons.phishing_outlined,
      description: 'Второе воскресенье июля — праздник всех, кто любит '
          'рыбалку и живёт ею.',
    ),
    _FolkHolidayDefinition(
      id: 'navy',
      title: 'День Военно-морского флота',
      resolveDate: (year) => lastWeekdayOfMonth(year, 7, DateTime.sunday),
      icon: Icons.anchor_outlined,
      description: 'Последнее воскресенье июля — день моряков и всех, кто '
          'служил на флоте.',
    ),
    _FolkHolidayDefinition(
      id: 'railway',
      title: 'День железнодорожника',
      resolveDate: (year) => nthWeekdayOfMonth(year, 8, DateTime.sunday, 1),
      icon: Icons.train_outlined,
      description: 'Первое воскресенье августа — праздник железнодорожников '
          'и их семей.',
    ),
    _FolkHolidayDefinition(
      id: 'builder',
      title: 'День строителя',
      resolveDate: (year) => nthWeekdayOfMonth(year, 8, DateTime.sunday, 2),
      icon: Icons.construction_outlined,
      description: 'Второе воскресенье августа — день тех, кто строит дома '
          'и города.',
    ),
    _FolkHolidayDefinition(
      id: 'miner',
      title: 'День шахтёра',
      resolveDate: (year) => lastWeekdayOfMonth(year, 8, DateTime.sunday),
      icon: Icons.terrain_outlined,
      description: 'Последнее воскресенье августа — праздник горняков и '
          'шахтёрских семей.',
    ),
    _FolkHolidayDefinition(
      id: 'kindergarten',
      title: 'День воспитателя',
      resolveDate: (year) => fixedDate(year, 9, 27),
      icon: Icons.child_care_outlined,
      description: 'День воспитателей и работников детских садов — тех, кто '
          'растит самых маленьких.',
    ),
    _FolkHolidayDefinition(
      id: 'elderly',
      title: 'День пожилого человека',
      resolveDate: (year) => fixedDate(year, 10, 1),
      icon: Icons.volunteer_activism_outlined,
      description: 'Международный день заботы о старших — позвоните бабушке '
          'и дедушке.',
    ),
    _FolkHolidayDefinition(
      id: 'teacher',
      title: 'День учителя',
      resolveDate: (year) => fixedDate(year, 10, 5),
      icon: Icons.menu_book_outlined,
      description: 'День учителя — поздравьте тех, кто вас учил.',
    ),
    _FolkHolidayDefinition(
      id: 'father',
      title: 'День отца',
      resolveDate: (year) => nthWeekdayOfMonth(year, 10, DateTime.sunday, 3),
      icon: Icons.face_outlined,
      description: 'Третье воскресенье октября — день пап. Тёплый повод '
          'сказать спасибо отцу.',
    ),
    _FolkHolidayDefinition(
      id: 'grandparents',
      title: 'День бабушек и дедушек',
      resolveDate: (year) => fixedDate(year, 10, 28),
      icon: Icons.elderly_outlined,
      description: 'День бабушек и дедушек в России — навестите или '
          'позвоните старшим.',
    ),
    _FolkHolidayDefinition(
      id: 'mother',
      title: 'День матери',
      resolveDate: (year) => lastWeekdayOfMonth(year, 11, DateTime.sunday),
      icon: Icons.favorite_outline,
      description: 'Последнее воскресенье ноября — день мам. Самый тёплый '
          'семейный повод.',
    ),
  ];

  /// Народные праздники конкретного года (для месячной сетки и agenda).
  List<AppEvent> _folkHolidaysForYear(int year) {
    return _folkHolidayDefs
        .map(
          (holiday) => AppEvent(
            id: 'folk_${holiday.id}_$year',
            type: AppEventType.folkHoliday,
            date: holiday.resolveDate(year),
            title: holiday.title,
            personName: 'Народный календарь',
            personId: '',
            icon: holiday.icon,
            description: holiday.description,
          ),
        )
        .toList();
  }

  List<AppEvent> _buildFolkHolidayEvents(DateTime today) {
    return [today.year, today.year + 1]
        .expand(_folkHolidaysForYear)
        .where((event) => _isUpcoming(event.date, today))
        .toList();
  }

  /// Calendar-grid scope: every family + holiday event that falls in
  /// [year], month [month] — past dates included, no upcoming filter, no
  /// cap (the grid shows the whole month). Recurring family dates
  /// (birthday / death anniversary / annual custom / wedding) are placed
  /// at their occurrence in [year]; one-time events (memorials, non-
  /// repeating custom) appear only in their actual year.
  // NB: errors propagate (no swallow-to-[]). The only caller is the
  // calendar screen, which needs to tell «no events» apart from «load
  // failed» to show a retry affordance (CP-2) — returning [] on a network
  // error made a failed fetch look like an empty month.
  Future<List<AppEvent>> getEventsForMonth(
    String treeId,
    int year,
    int month,
  ) async {
    final results = await Future.wait<dynamic>([
      _familyTreeService.getRelatives(treeId),
      _familyTreeService.getRelations(treeId),
    ]);
    final relatives = results[0] as List<FamilyPerson>;
    final relations = results[1] as List<FamilyRelation>;
    final all = _buildEventsForYear(
      relatives: relatives,
      relations: relations,
      year: year,
    );
    return all
        .where((e) => e.date.year == year && e.date.month == month)
        .toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0
            ? byDate
            : _typePriority(a.type).compareTo(_typePriority(b.type));
      });
  }

  /// All events whose occurrence lands in [year]. Mirrors the
  /// getUpcomingEvents derivation but year-anchored (no upcoming filter)
  /// — kept separate from getUpcomingEvents so that feed behaviour is
  /// untouched.
  List<AppEvent> _buildEventsForYear({
    required List<FamilyPerson> relatives,
    required List<FamilyRelation> relations,
    required int year,
  }) {
    final out = <AppEvent>[];
    final relativesById = <String, FamilyPerson>{
      for (final person in relatives) person.id: person,
    };

    for (final person in relatives) {
      final birth = person.birthDate;
      if (birth != null) {
        out.add(AppEvent(
          id: '${person.id}_birthday_$year',
          type: AppEventType.birthday,
          date: DateTime(year, birth.month, birth.day),
          title: 'День рождения',
          personName: person.name,
          personId: person.id,
          treeId: person.treeId,
          personBirthYear: birth.year,
          icon: Icons.cake_outlined,
        ));
      }

      if (!person.isAlive && person.deathDate != null) {
        final death = person.deathDate!;
        out.add(AppEvent(
          id: '${person.id}_death_anniversary_$year',
          type: AppEventType.deathAnniversary,
          date: DateTime(year, death.month, death.day),
          title: 'Годовщина памяти',
          personName: person.name,
          personId: person.id,
          treeId: person.treeId,
          icon: Icons.auto_awesome_mosaic_outlined,
        ));
        final memorial9 = death.add(const Duration(days: 8));
        if (memorial9.year == year) {
          out.add(AppEvent(
            id: '${person.id}_memorial9',
            type: AppEventType.memorial9days,
            date: memorial9,
            title: '9 дней',
            personName: person.name,
            personId: person.id,
            treeId: person.treeId,
            icon: Icons.church_outlined,
          ));
        }
        final memorial40 = death.add(const Duration(days: 39));
        if (memorial40.year == year) {
          out.add(AppEvent(
            id: '${person.id}_memorial40',
            type: AppEventType.memorial40days,
            date: memorial40,
            title: '40 дней',
            personName: person.name,
            personId: person.id,
            treeId: person.treeId,
            icon: Icons.church_outlined,
          ));
        }
      }

      final customEvents = person.details?.importantEvents;
      if (customEvents != null) {
        for (final ev in customEvents) {
          final date = ev.repeatsAnnually
              ? DateTime(year, ev.date.month, ev.date.day)
              : DateTime(ev.date.year, ev.date.month, ev.date.day);
          if (!ev.repeatsAnnually && date.year != year) continue;
          out.add(AppEvent(
            id: '${person.id}_custom_${ev.title}_${ev.date.toIso8601String()}_$year',
            type: AppEventType.customFamilyEvent,
            date: date,
            title: ev.title,
            personName: person.name,
            personId: person.id,
            treeId: person.treeId,
            icon: Icons.event_outlined,
          ));
        }
      }
    }

    for (final relation in relations) {
      if (relation.relation1to2 != RelationType.spouse &&
          relation.relation2to1 != RelationType.spouse) {
        continue;
      }
      final marriage = relation.marriageDate;
      if (marriage == null || marriage.year > year) continue;
      final divorce = relation.divorceDate;
      if (divorce != null && year > divorce.year) continue;
      final p1 = relativesById[relation.person1Id];
      final p2 = relativesById[relation.person2Id];
      final names = [p1?.name, p2?.name]
          .whereType<String>()
          .where((n) => n.trim().isNotEmpty)
          .toList();
      out.add(AppEvent(
        id: '${relation.id}_wedding_anniversary_$year',
        type: AppEventType.weddingAnniversary,
        date: DateTime(year, marriage.month, marriage.day),
        title: 'Годовщина свадьбы',
        personName: names.isEmpty ? 'Семейная пара' : names.join(' и '),
        personId: p1?.id ?? p2?.id ?? '',
        treeId: p1?.treeId ?? p2?.treeId,
        icon: Icons.favorite_outline,
      ));
    }

    out.addAll(_russianHolidaysForYear(year));
    out.addAll(_orthodoxHolidaysForYear(year));
    out.addAll(_folkHolidaysForYear(year));
    return out;
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
      case AppEventType.folkHoliday:
        return 7;
      case AppEventType.other:
        return 8;
    }
  }

  bool _isFamilyEventType(AppEventType type) {
    switch (type) {
      case AppEventType.birthday:
      case AppEventType.weddingAnniversary:
      case AppEventType.deathAnniversary:
      case AppEventType.memorial9days:
      case AppEventType.memorial40days:
      case AppEventType.customFamilyEvent:
        return true;
      case AppEventType.russianHoliday:
      case AppEventType.orthodoxHoliday:
      case AppEventType.folkHoliday:
      case AppEventType.other:
        return false;
    }
  }

  // K3: пасхалия переехала в utils/holiday_date_rules.dart (orthodoxEaster)
  // — там же живёт весь движок плавающих дат; вторую копию не держим.
}

/// K3: декларация народного праздника — дата считается правилом движка
/// (fixed / nthWeekdayOfMonth / lastWeekdayOfMonth / easterOffset).
class _FolkHolidayDefinition {
  const _FolkHolidayDefinition({
    required this.id,
    required this.title,
    required this.resolveDate,
    required this.icon,
    required this.description,
  });

  final String id;
  final String title;
  final DateTime Function(int year) resolveDate;
  final IconData icon;
  final String description;
}

class _AnnualHolidayDefinition {
  const _AnnualHolidayDefinition({
    required this.month,
    required this.day,
    required this.title,
    required this.icon,
    this.description,
  });

  final int month;
  final int day;
  final String title;
  final IconData icon;
  final String? description;
}

class _DatedHolidayDefinition {
  const _DatedHolidayDefinition({
    required this.date,
    required this.title,
    required this.icon,
    this.description,
  });

  final DateTime date;
  final String title;
  final IconData icon;
  final String? description;
}
