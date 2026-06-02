// Viewer phase — SUB-CHUNK 1 (2026-06-01): read-only article rendering.
//
// ArticleReadView renders all 7 block types WITHOUT edit affordances (no
// TextFields, no ⋮ menus, no gallery ✕ / add-tile, no photo-date button).
// ProfileBiographySection is read-first: visible to viewers; the edit ✏️ /
// «Добавить историю» CTA appear only for editors (canEdit).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/widgets/article_audio_block.dart';
import 'package:rodnya/widgets/article_gallery_block.dart';
import 'package:rodnya/widgets/article_photo_block.dart';
import 'package:rodnya/widgets/article_read_view.dart';
import 'package:rodnya/widgets/profile_biography_section.dart';

ArticleBlock _block(String id, String type, Map<String, dynamic> content,
        {String? author}) =>
    ArticleBlock(
      id: id,
      type: type,
      content: content,
      authorUserId: author,
      createdAt: 't',
      updatedAt: 't',
    );

List<ArticleBlock> _allSevenTypes() => [
      _block('p1', 'paragraph', ArticleBlock.paragraphContent('Это абзац.')),
      _block('h1', 'header', ArticleBlock.headerContent('Детство')),
      _block('q1', 'quote',
          ArticleBlock.quoteContent(text: 'Будь собой.', attribution: 'Бабушка')),
      _block('d1', 'divider', ArticleBlock.dividerContent()),
      _block('ph1', 'photo',
          {'url': 'https://img/ph.jpg', 'caption': 'Подпись фото'}),
      _block(
          'g1',
          'gallery',
          ArticleBlock.galleryContent(items: [
            <String, dynamic>{'url': 'https://img/g0.jpg', 'caption': 'Свадьба'},
            <String, dynamic>{'url': 'https://img/g1.jpg'},
          ])),
      _block('au1', 'audio',
          ArticleBlock.audioContent(url: 'https://a/v.m4a', durationSec: 30)),
    ];

void main() {
  testWidgets('ArticleReadView renders all 7 types without edit affordances',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArticleReadView(blocks: _allSevenTypes()),
          ),
        ),
      ),
    );
    // CachedNetworkImage never settles in tests — pump, don't settle.
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));

    // Every type renders its content.
    expect(find.text('Это абзац.'), findsOneWidget); // paragraph
    expect(find.text('Детство'), findsOneWidget); // header
    expect(find.text('Будь собой.'), findsOneWidget); // quote text
    expect(find.text('— Бабушка'), findsOneWidget); // quote attribution
    expect(find.byKey(const Key('read-block-d1')), findsOneWidget); // divider
    expect(find.text('Подпись фото'), findsOneWidget); // photo caption (static)
    expect(find.byType(ArticlePhotoBlock), findsOneWidget);
    expect(find.byType(ArticleGalleryBlock), findsOneWidget);
    expect(find.text('Свадьба'), findsOneWidget); // gallery caption (read)
    expect(find.byType(ArticleAudioBlock), findsOneWidget);

    // NO edit affordances anywhere.
    expect(find.byType(TextField), findsNothing); // no controllers
    expect(find.byType(PopupMenuButton<String>), findsNothing); // no ⋮ menus
    expect(find.byKey(const Key('article-photo-menu-ph1')), findsNothing);
    expect(find.byKey(const Key('article-photo-date-ph1')), findsNothing);
    expect(find.byKey(const Key('article-audio-menu-au1')), findsNothing);
    expect(find.byKey(const Key('article-gallery-menu-g1')), findsNothing);
    expect(find.byKey(const Key('article-gallery-add-g1')), findsNothing);
    expect(find.byKey(const Key('article-gallery-remove-g1-0')), findsNothing);
  });

  testWidgets('coauthors line shows for a multi-author section',
      (tester) async {
    final blocks = [
      _block('h1', 'header', ArticleBlock.headerContent('Детство')),
      _block('p1', 'paragraph', ArticleBlock.paragraphContent('абзац 1'),
          author: 'u-artem'),
      _block('p2', 'paragraph', ArticleBlock.paragraphContent('абзац 2'),
          author: 'u-natasha'),
      _block('h2', 'header', ArticleBlock.headerContent('Один автор')),
      _block('p3', 'paragraph', ArticleBlock.paragraphContent('абзац 3'),
          author: 'u-artem'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArticleReadView(
              blocks: blocks,
              authorNames: const {'u-artem': 'Артём', 'u-natasha': 'Наталья'},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The 2-author section gets a coauthors line (insertion order); the
    // single-author section does not → exactly one line total.
    expect(find.text('Соавторы: Артём, Наталья'), findsOneWidget);
    expect(find.textContaining('Соавторы:'), findsOneWidget);
  });

  testWidgets('coauthors line hidden when authors are unresolved',
      (tester) async {
    final blocks = [
      _block('h1', 'header', ArticleBlock.headerContent('Детство')),
      _block('p1', 'paragraph', ArticleBlock.paragraphContent('a'),
          author: 'unknown-1'),
      _block('p2', 'paragraph', ArticleBlock.paragraphContent('b'),
          author: 'unknown-2'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleReadView(blocks: blocks, authorNames: const {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Соавторы:'), findsNothing);
  });

  testWidgets('biography section: viewer reads, no edit button', (tester) async {
    final svc = _StubArticleService([
      _block('p1', 'paragraph', ArticleBlock.paragraphContent('История жизни.')),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileBiographySection(
              personId: 'p1',
              fullName: 'Лидия',
              canEdit: false,
              serviceOverride: svc,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('История жизни.'), findsOneWidget);
    expect(find.byType(ArticleReadView), findsOneWidget);
    expect(find.byKey(const Key('biography-edit')), findsNothing);
  });

  testWidgets('biography section: editor gets the ✏️ edit button',
      (tester) async {
    final svc = _StubArticleService([
      _block('p1', 'paragraph', ArticleBlock.paragraphContent('История.')),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileBiographySection(
              personId: 'p1',
              fullName: 'Лидия',
              canEdit: true,
              serviceOverride: svc,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('biography-edit')), findsOneWidget);
  });

  testWidgets('biography section: empty + viewer renders nothing',
      (tester) async {
    final svc = _StubArticleService(const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileBiographySection(
            personId: 'p1',
            fullName: 'Лидия',
            canEdit: false,
            serviceOverride: svc,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('biography-section')), findsNothing);
  });

  testWidgets('biography section: empty + editor shows «Добавить историю»',
      (tester) async {
    final svc = _StubArticleService(const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileBiographySection(
            personId: 'p1',
            fullName: 'Лидия',
            canEdit: true,
            serviceOverride: svc,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('biography-add')), findsOneWidget);
    expect(find.byKey(const Key('biography-edit')), findsNothing); // no ✏️ yet
  });
}

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
