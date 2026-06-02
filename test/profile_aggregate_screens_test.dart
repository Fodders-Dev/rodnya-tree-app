// Viewer §3.2.5 / §3.2.6 (sub-chunk 2b): the «Голосовые записи» and «Все
// фото» aggregate screens collect every audio block / every photo (photo
// blocks + gallery items) from the biography article and render them
// read-only (audio player / lightbox grid).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/screens/profile_all_photos_screen.dart';
import 'package:rodnya/screens/profile_basic_info_screen.dart';
import 'package:rodnya/screens/profile_visibility_screen.dart';
import 'package:rodnya/screens/profile_voice_recordings_screen.dart';
import 'package:rodnya/widgets/article_audio_block.dart';
import 'package:rodnya/widgets/visibility_toggle_section.dart';

ArticleBlock _b(String id, String type, Map<String, dynamic> content,
        {String? author}) =>
    ArticleBlock(
      id: id,
      type: type,
      content: content,
      authorUserId: author,
      createdAt: 't',
      updatedAt: 't',
    );

class _StubArticleService implements ProfileArticleServiceInterface {
  _StubArticleService(this._blocks);
  final List<ArticleBlock> _blocks;

  @override
  Future<ProfileArticle> getArticle(String personId) async =>
      ProfileArticle(personId: personId, blocks: _blocks);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

// Plain service (not GraphPersonAccessCapable) → VisibilityToggleSection
// self-hides without calling any method.
class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Голосовые: collects audio blocks with section + author',
      (tester) async {
    final svc = _StubArticleService([
      _b('h1', 'header', ArticleBlock.headerContent('Детство')),
      _b('au1', 'audio', ArticleBlock.audioContent(url: 'https://a/1.m4a', durationSec: 42), author: 'u-artem'),
      _b('p1', 'paragraph', ArticleBlock.paragraphContent('текст')),
      _b('h2', 'header', ArticleBlock.headerContent('Свадьба')),
      _b('au2', 'audio', ArticleBlock.audioContent(url: 'https://a/2.m4a', durationSec: 75)),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVoiceRecordingsScreen(
          personId: 'p1',
          personName: 'Лидия',
          authorNames: const {'u-artem': 'Артём'},
          serviceOverride: svc,
        ),
      ),
    );
    // Audio block render is plugin-free (lazy player) — pump, don't settle.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Both audio blocks surfaced, each under its section, with the author.
    expect(find.byType(ArticleAudioBlock), findsNWidgets(2));
    expect(find.textContaining('Раздел «Детство»'), findsOneWidget);
    expect(find.textContaining('Раздел «Свадьба»'), findsOneWidget);
    expect(find.text('Записал(а) Артём'), findsOneWidget);
  });

  testWidgets('Голосовые: empty article → empty state', (tester) async {
    final svc = _StubArticleService([
      _b('p1', 'paragraph', ArticleBlock.paragraphContent('нет аудио')),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVoiceRecordingsScreen(
          personId: 'p1',
          personName: 'Лидия',
          serviceOverride: svc,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(ArticleAudioBlock), findsNothing);
    expect(find.text('Здесь появятся голосовые записи'), findsOneWidget);
  });

  testWidgets('Все фото: collects photo blocks + gallery items',
      (tester) async {
    final svc = _StubArticleService([
      _b('ph1', 'photo', {'url': 'https://img/p.jpg'}),
      _b(
          'g1',
          'gallery',
          ArticleBlock.galleryContent(items: [
            <String, dynamic>{'url': 'https://img/g0.jpg'},
            <String, dynamic>{'url': 'https://img/g1.jpg'},
          ])),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAllPhotosScreen(
          personId: 'p1',
          personName: 'Лидия',
          serviceOverride: svc,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // 1 photo block + 2 gallery items = 3 thumbnails; title counts them.
    expect(find.text('Все фото (3)'), findsOneWidget);
    expect(find.byKey(const Key('all-photos-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('all-photos-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('all-photos-thumb-2')), findsOneWidget);
  });

  testWidgets('Основная информация: renders fields + ✓ Память + edit',
      (tester) async {
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileBasicInfoScreen(
          fields: const [
            BasicInfoField('Имя', 'Лидия Александровна'),
            BasicInfoField('Дата смерти', '14 декабря 2022', memorial: true),
            BasicInfoField('Пол', 'Женский'),
          ],
          canEdit: true,
          onEdit: () => edited = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Лидия Александровна'), findsOneWidget);
    expect(find.text('14 декабря 2022'), findsOneWidget);
    expect(find.text('✓ Память'), findsOneWidget);
    expect(find.text('Женский'), findsOneWidget);

    expect(find.byKey(const Key('basic-info-edit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('basic-info-edit')));
    await tester.pump();
    expect(edited, true);
  });

  testWidgets('Основная информация: viewer (no edit) → no edit button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileBasicInfoScreen(
          fields: [BasicInfoField('Имя', 'Иван')],
          canEdit: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Иван'), findsOneWidget);
    expect(find.byKey(const Key('basic-info-edit')), findsNothing);
  });

  testWidgets('Кто видит карточку: screen wraps the visibility section',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVisibilityScreen(
          graphPersonId: 'gp1',
          viewerUserId: 'u1',
          familyTreeService: _FakeFamilyTreeService(),
        ),
      ),
    );
    await tester.pump(); // snapshot load (no graph capability → self-hides)

    expect(find.text('Кто видит карточку'), findsOneWidget); // AppBar
    expect(find.byType(VisibilityToggleSection), findsOneWidget);
  });

  testWidgets('Все фото: no photos → empty state', (tester) async {
    final svc = _StubArticleService([
      _b('p1', 'paragraph', ArticleBlock.paragraphContent('нет фото')),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAllPhotosScreen(
          personId: 'p1',
          personName: 'Лидия',
          serviceOverride: svc,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Пока нет фотографий'), findsOneWidget);
  });
}
