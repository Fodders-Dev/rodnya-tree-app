// Verifies the Profile Redesign hero card / completion meter / sections
// don't overflow on Samsung S20 FE-class viewports (360 × 800 dp).
//
// Flutter test default viewport is 800 × 600 — wide enough that overflow
// only ever shows up on real devices. By pinning the viewport to S20 FE
// dimensions before pumping the widget kit and asserting `tester.takeException()
// == null`, we catch any RenderFlex overflow before it reaches users.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/profile_redesign.dart';

void main() {
  // Samsung S20 FE: 1080 × 2400 px @ 480 dpi → 360 × 800 dp logical.
  // Pin the binding to those numbers so RenderFlex overflows trip
  // `tester.takeException()` here instead of in production.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[RodnyaDesignTokens.light],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  testWidgets('ProfileHeroCard fits a 360 dp viewport without overflow',
      (tester) async {
    await tester.pumpWidget(wrap(
      ProfileHeroCard(
        fullName: 'Кузнецов Андрей Анатольевич',
        firstName: 'Андрей',
        patronymic: 'Анатольевич',
        lastName: 'Кузнецов',
        location: 'Москва · Россия',
        bio: 'Хранитель семейного архива и любитель путешествовать.',
        stats: const [
          ProfileHeroStat(value: '12', label: 'постов'),
          ProfileHeroStat(value: '34', label: 'родственники'),
          ProfileHeroStat(value: '3', label: 'деревья'),
        ],
        actions: [
          PillButton(
            label: 'В дерево',
            icon: Icons.account_tree_outlined,
            onPressed: () {},
          ),
          PillButton(
            label: 'Поделиться',
            icon: Icons.share_outlined,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
        ],
        onEditPressed: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileHeroCard memorial variant fits 360 dp without overflow',
      (tester) async {
    await tester.pumpWidget(wrap(
      ProfileHeroCard(
        fullName: 'Кузнецов Иван Степанович',
        firstName: 'Иван',
        patronymic: 'Степанович',
        lastName: 'Кузнецов',
        location: 'Тула · Россия',
        bio: 'Семейный историк, собирал архивы трёх поколений.',
        relBadge: 'Для вас: Прадед',
        useWarmAvatar: true,
        deceased: true,
        deceasedYears: '1942 — 2018',
        actions: [
          PillButton(
            label: 'Пригласить в Родню',
            icon: Icons.person_add_alt_1_outlined,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileSection + InfoRow renders cleanly at 360 dp',
      (tester) async {
    await tester.pumpWidget(wrap(
      const ProfileSection(
        title: 'Образование и работа',
        children: [
          InfoRow(
            icon: Icons.school_outlined,
            label: 'Образование',
            value: 'Факультет журналистики МГУ имени М.В. Ломоносова',
            isFirst: true,
          ),
          InfoRow(
            icon: Icons.work_outline_rounded,
            label: 'Работа',
            value:
                'Старший редактор отдела долгих историй — Издательский дом Родня',
            isLast: true,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileCompletionMeterCard with chips fits 360 dp',
      (tester) async {
    await tester.pumpWidget(wrap(
      ProfileCompletionMeterCard(
        percent: 62,
        suggestions: [
          ProfileCompletionChipData(label: 'обо мне', onTap: () {}),
          ProfileCompletionChipData(label: 'город', onTap: () {}),
          ProfileCompletionChipData(label: 'работа', onTap: () {}),
          ProfileCompletionChipData(label: 'учёба', onTap: () {}),
          ProfileCompletionChipData(label: 'языки', onTap: () {}),
          ProfileCompletionChipData(label: 'обложка', onTap: () {}),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('PrivacyScopeRow fits 360 dp', (tester) async {
    await tester.pumpWidget(wrap(
      Padding(
        padding: const EdgeInsets.all(12),
        child: PrivacyScopeRow(
          value: 'family',
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hero with many overlapping action pills wraps cleanly',
      (tester) async {
    // Worst-case: relative card hero with 5 action pills (Написать /
    // Пригласить в Родню / Предложить правку / Это моя карточка /
    // Приватность). ProfileHeroCard wraps `actions` with Wrap so all
    // five fit even at 360 dp.
    await tester.pumpWidget(wrap(
      ProfileHeroCard(
        fullName: 'Кузнецов Андрей',
        firstName: 'Андрей',
        lastName: 'Кузнецов',
        useWarmAvatar: true,
        relBadge: 'Для вас: Отец',
        bio: 'Большая семья в Москве',
        actions: [
          PillButton(
            label: 'Написать',
            icon: Icons.message_outlined,
            onPressed: () {},
          ),
          PillButton(
            label: 'Пригласить в Родню',
            icon: Icons.person_add_alt_1_outlined,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
          PillButton(
            label: 'Предложить правку',
            icon: Icons.edit_note_outlined,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
          PillButton(
            label: 'Это моя карточка',
            icon: Icons.verified_user_outlined,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
          PillButton(
            label: 'Приватность',
            icon: Icons.lock_outline_rounded,
            variant: PillButtonVariant.outlined,
            onPressed: () {},
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Section with very long InfoRow value wraps', (tester) async {
    await tester.pumpWidget(wrap(
      const ProfileSection(
        title: 'Семья',
        children: [
          InfoRow(
            icon: Icons.family_restroom_outlined,
            label: 'Заметка',
            value:
                'Очень длинная заметка для семьи которая обязательно должна перенестись на следующую строку без обрезания текста на узком экране Samsung S20 FE — мы хотим чтобы все слова были видны полностью',
            warm: true,
            isFirst: true,
            isLast: true,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
