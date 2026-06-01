// Profile Phase 2a/2b (2026-05-29): article editor widget tests.
//
// 2a: render loaded blocks, debounced paragraph auto-save (PATCH),
// «+ Раздел» append, темы-промпт sheet insert, debounce timing, empty
// state. 2b-1: photo add (mock pick+upload), caption auto-save, set
// date, delete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/screens/profile_article_editor_screen.dart';
import 'package:rodnya/widgets/article_audio_block.dart';
import 'package:rodnya/widgets/article_gallery_block.dart';
import 'package:rodnya/widgets/article_photo_block.dart';
import 'package:rodnya/widgets/audio_record_sheet.dart';

class _FakeArticleService implements ProfileArticleServiceInterface {
  _FakeArticleService({List<ArticleBlock>? blocks})
      : _blocks = blocks ?? <ArticleBlock>[];

  final List<ArticleBlock> _blocks;
  final List<String> calls = [];
  Map<String, dynamic>? lastUpdatedContent;
  Map<String, dynamic>? lastAppendContent;
  int _seq = 0;

  @override
  Future<ProfileArticle> getArticle(String personId) async {
    calls.add('get');
    return ProfileArticle(personId: personId, blocks: List.of(_blocks));
  }

  @override
  Future<ArticleBlock> appendBlock(
    String personId, {
    required String type,
    required Map<String, dynamic> content,
  }) async {
    calls.add('append:$type');
    lastAppendContent = content;
    return ArticleBlock(
      id: 'new-${_seq++}',
      type: type,
      content: content,
      authorUserId: 'u1',
      createdAt: 't',
      updatedAt: 't',
    );
  }

  @override
  Future<ArticleBlockUpdateResult> updateBlock(
    String personId,
    String blockId, {
    required Map<String, dynamic> content,
    String? baseUpdatedAt,
  }) async {
    calls.add('update:$blockId');
    lastUpdatedContent = content;
    return ArticleBlockUpdateResult(
      block: ArticleBlock(
        id: blockId,
        type: _inferBlockType(content),
        content: content,
        authorUserId: 'u1',
        createdAt: 't',
        updatedAt: 't2',
      ),
      conflict: false,
    );
  }

  @override
  Future<void> removeBlock(String personId, String blockId) async {
    calls.add('remove:$blockId');
  }

  @override
  Future<ProfileArticle> reorderBlocks(
    String personId,
    List<String> orderedBlockIds,
  ) async {
    calls.add('reorder');
    return ProfileArticle(personId: personId, blocks: List.of(_blocks));
  }
}

// Mirror the backend's type-preserving update: a block keeps its type
// across a content patch. The fake infers it from the content shape so a
// quote re-renders as a quote (not as a header) after auto-save.
String _inferBlockType(Map<String, dynamic> content) {
  if (content.containsKey('spans')) return 'paragraph';
  if (content.containsKey('level')) return 'header';
  if (content.containsKey('attribution')) return 'quote';
  if (content.containsKey('items')) return 'gallery';
  if (content.containsKey('url')) {
    return content.containsKey('durationSec') ? 'audio' : 'photo';
  }
  if (content.isEmpty) return 'divider';
  return 'paragraph';
}

ArticleBlock _paragraph(String id, String text) => ArticleBlock(
      id: id,
      type: 'paragraph',
      content: ArticleBlock.paragraphContent(text),
      createdAt: 't',
      updatedAt: 't',
    );

ArticleBlock _quote(String id, {required String text, String? attribution}) =>
    ArticleBlock(
      id: id,
      type: 'quote',
      content: ArticleBlock.quoteContent(text: text, attribution: attribution),
      createdAt: 't',
      updatedAt: 't',
    );

ArticleBlock _divider(String id) => ArticleBlock(
      id: id,
      type: 'divider',
      content: ArticleBlock.dividerContent(),
      createdAt: 't',
      updatedAt: 't',
    );

Widget _wrap(_FakeArticleService svc, {Duration? debounce}) => MaterialApp(
      home: ProfileArticleEditorScreen(
        personId: 'p1',
        personName: 'Лидия',
        serviceOverride: svc,
        saveDebounce: debounce ?? const Duration(milliseconds: 200),
      ),
    );

void main() {
  testWidgets('renders loaded blocks', (tester) async {
    final svc = _FakeArticleService(
      blocks: [_paragraph('b1', 'Лидия родилась в 1949 году.')],
    );
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();
    expect(find.text('Лидия родилась в 1949 году.'), findsOneWidget);
    expect(find.byKey(const Key('article-block-b1')), findsOneWidget);
    expect(svc.calls.contains('get'), true);
  });

  testWidgets('empty article shows prompt + start button', (tester) async {
    final svc = _FakeArticleService();
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();
    expect(find.text('Биография ещё не написана.'), findsOneWidget);
    expect(find.byKey(const Key('article-empty-start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('article-empty-start')));
    await tester.pumpAndSettle();
    expect(svc.calls.contains('append:paragraph'), true);
  });

  testWidgets('paragraph edit auto-saves after debounce', (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', 'старт')]);
    await tester.pumpWidget(_wrap(svc, debounce: const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('article-block-b1')),
      'Новый текст',
    );
    // Before debounce elapses — no save yet.
    await tester.pump(const Duration(milliseconds: 80));
    expect(svc.calls.contains('update:b1'), false);

    // After debounce — save fires.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(svc.calls.contains('update:b1'), true);
    expect(
      (svc.lastUpdatedContent?['spans'] as List).first['text'],
      'Новый текст',
    );
  });

  testWidgets('«Блок» → «Раздел» appends a header block', (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', 'текст')]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-block')));
    await tester.pumpAndSettle(); // block picker
    await tester.tap(find.byKey(const Key('block-menu-header')));
    await tester.pumpAndSettle();
    expect(svc.calls.contains('append:header'), true);
  });

  // ===== Phase 2c: quote + divider blocks =====

  testWidgets('«Блок» → «Цитата» appends a quote block with both fields',
      (tester) async {
    final svc = _FakeArticleService();
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-menu-quote')));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('append:quote'), true);
    expect(svc.lastAppendContent, {'text': '', 'attribution': null});
    // The appended block (new-0) renders the quote text + attribution.
    expect(find.byKey(const Key('article-block-new-0')), findsOneWidget);
    expect(
      find.byKey(const Key('article-quote-attribution-new-0')),
      findsOneWidget,
    );
  });

  testWidgets('quote edit auto-saves text + attribution', (tester) async {
    final svc = _FakeArticleService(
      blocks: [_quote('q1', text: 'старая', attribution: 'Дед')],
    );
    await tester.pumpWidget(
      _wrap(svc, debounce: const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('article-block-q1')),
      'Жизнь прожить — не поле перейти',
    );
    await tester.enterText(
      find.byKey(const Key('article-quote-attribution-q1')),
      'Бабушка Лидия',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('update:q1'), true);
    expect(svc.lastUpdatedContent?['text'], 'Жизнь прожить — не поле перейти');
    expect(svc.lastUpdatedContent?['attribution'], 'Бабушка Лидия');
  });

  testWidgets('«Блок» → «Разделитель» appends a divider + renders a line',
      (tester) async {
    final svc = _FakeArticleService();
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-menu-divider')));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('append:divider'), true);
    expect(svc.lastAppendContent, isEmpty); // {}
    expect(find.byKey(const Key('article-divider-new-0')), findsOneWidget);
  });

  testWidgets('divider deletes from the ⋮ menu without a confirm dialog',
      (tester) async {
    final svc = _FakeArticleService(
      blocks: [_paragraph('b1', 'keep'), _divider('d1')],
    );
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-block-menu-d1')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить разделитель'), findsOneWidget);
    await tester.tap(find.text('Удалить разделитель'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить разделитель?'), findsNothing); // no confirm
    expect(svc.calls.contains('remove:d1'), true);
    expect(find.byKey(const Key('article-divider-d1')), findsNothing);
  });

  // ===== Phase 2c: gallery (multi-photo) =====

  testWidgets('«Блок» → «Галерея» multi-picks → uploads → gallery block',
      (tester) async {
    final svc = _FakeArticleService();
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapGallery(svc, storage, pickCount: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-menu-gallery')));
    // Avoid pumpAndSettle — the gallery's network images never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(storage.uploadCalls, 2); // both picks uploaded
    expect(svc.calls.contains('append:gallery'), true);
    expect((svc.lastAppendContent?['items'] as List).length, 2);
    expect(find.byType(ArticleGalleryBlock), findsOneWidget);
  });

  testWidgets('gallery: remove one photo patches items (keeps the rest)',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_gallery('g1', 3)]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapGallery(svc, storage));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    await tester.tap(find.byKey(const Key('article-gallery-remove-g1-0')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(svc.calls.contains('update:g1'), true);
    expect((svc.lastUpdatedContent?['items'] as List).length, 2);
    expect(find.byType(ArticleGalleryBlock), findsOneWidget); // still a gallery
  });

  testWidgets('gallery: removing the last photo deletes the block',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_gallery('g1', 1)]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapGallery(svc, storage));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    await tester.tap(find.byKey(const Key('article-gallery-remove-g1-0')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(svc.calls.contains('remove:g1'), true); // ≥1 rule — block removed
    expect(find.byType(ArticleGalleryBlock), findsNothing);
  });

  testWidgets('gallery v2: reorder moves the photo (items order updated)',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_gallery('g1', 3)]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapGallery(svc, storage));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Invoke the reorder callback directly — drag gestures are awkward to
    // drive in a widget test. Move photo 0 so it lands at the end.
    final gallery =
        tester.widget<ArticleGalleryBlock>(find.byType(ArticleGalleryBlock));
    gallery.onReorder!(0, 2);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(svc.calls.contains('update:g1'), true);
    final items = (svc.lastUpdatedContent?['items'] as List).cast<Map>();
    expect(
      items.map((m) => m['url']).toList(),
      ['https://img/g1.jpg', 'https://img/g2.jpg', 'https://img/g0.jpg'],
    );
  });

  testWidgets('gallery v2: caption saves onto the item', (tester) async {
    final svc = _FakeArticleService(blocks: [_gallery('g1', 2)]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapGallery(svc, storage));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final gallery =
        tester.widget<ArticleGalleryBlock>(find.byType(ArticleGalleryBlock));
    gallery.onCaptionChanged!(0, 'Лето 1970');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(svc.calls.contains('update:g1'), true);
    final items = (svc.lastUpdatedContent?['items'] as List).cast<Map>();
    expect(items[0]['caption'], 'Лето 1970');
    expect(items[1].containsKey('caption'), false); // untouched item
  });

  testWidgets('идеи sheet inserts a section + paragraph', (tester) async {
    final svc = _FakeArticleService();
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-empty-ideas')));
    await tester.pumpAndSettle();
    // Sheet open — pick «Детство».
    expect(find.text('С чего начать?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('article-idea-детство')));
    await tester.pumpAndSettle();

    // Header (theme) + paragraph (prompt) appended.
    expect(svc.calls.where((c) => c == 'append:header').length, 1);
    expect(svc.calls.where((c) => c == 'append:paragraph').length, 1);
    expect(find.text('Детство'), findsOneWidget);
  });

  // ===== Phase 2b-1: photo blocks =====

  testWidgets('add photo: source → pick → upload → photo block appended',
      (tester) async {
    final svc = _FakeArticleService();
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapPhoto(svc, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-photo')));
    await tester.pumpAndSettle(); // source chooser
    await tester.tap(find.byKey(const Key('photo-source-gallery')));
    // Let pick + upload + append resolve (avoid pumpAndSettle — the
    // photo block's network image would never settle).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(storage.uploadCalls, 1);
    expect(svc.calls.contains('append:photo'), true);
    expect(find.byType(ArticlePhotoBlock), findsOneWidget);
  });

  testWidgets('photo caption auto-saves through updateBlock', (tester) async {
    final svc = _FakeArticleService(blocks: [_photo('ph1')]);
    final storage = _FakeStorage();
    await tester.pumpWidget(
      _wrapPhoto(svc, storage, debounce: const Duration(milliseconds: 150)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    await tester.enterText(
      find.byKey(const Key('article-photo-caption-ph1')),
      'Бабушка в саду',
    );
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(svc.calls.contains('update:ph1'), true);
    expect(svc.lastUpdatedContent?['caption'], 'Бабушка в саду');
    // url preserved through the caption patch.
    expect(svc.lastUpdatedContent?['url'], 'https://img/ph1.jpg');
  });

  testWidgets('set photo date (год) patches dateTaken + accuracy',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_photo('ph1')]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapPhoto(svc, storage));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // A recent year sits at the top of the (descending) lazy list, so
    // it's rendered without scrolling.
    final year = DateTime.now().year - 1;
    final dateBtn = find.byKey(const Key('article-photo-date-ph1'));
    await tester.ensureVisible(dateBtn); // below the tall image
    await tester.pumpAndSettle();
    await tester.tap(dateBtn);
    await tester.pumpAndSettle(); // date sheet
    await tester.tap(find.byKey(const Key('photo-date-year')));
    await tester.pumpAndSettle(); // year list
    await tester.tap(find.byKey(Key('photo-year-$year')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(svc.calls.contains('update:ph1'), true);
    expect(svc.lastUpdatedContent?['dateTakenAccuracy'], 'year');
    expect(
      (svc.lastUpdatedContent?['dateTaken'] as String).startsWith('$year'),
      true,
    );
  });

  testWidgets('delete photo block calls removeBlock + drops it',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_photo('ph1')]);
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrapPhoto(svc, storage));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    await tester.tap(find.byKey(const Key('article-photo-menu-ph1')));
    await tester.pumpAndSettle(); // popup menu
    await tester.tap(find.text('Удалить'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(svc.calls.contains('remove:ph1'), true);
    expect(find.byType(ArticlePhotoBlock), findsNothing);
  });

  // ===== Phase 2b-1b: text block delete =====

  testWidgets('delete non-empty paragraph → confirm → removeBlock',
      (tester) async {
    final svc = _FakeArticleService(
      blocks: [_paragraph('b1', 'Удаляемый'), _paragraph('b2', 'Остаётся')],
    );
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-block-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить абзац'));
    await tester.pumpAndSettle(); // confirm dialog (non-empty)
    expect(find.text('Удалить абзац?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('article-delete-confirm')));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('remove:b1'), true);
    expect(find.byKey(const Key('article-block-b1')), findsNothing);
    expect(find.byKey(const Key('article-block-b2')), findsOneWidget);
  });

  testWidgets('delete empty paragraph → no confirm dialog', (tester) async {
    final svc = _FakeArticleService(
      blocks: [_paragraph('b1', ''), _paragraph('b2', 'keep')],
    );
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-block-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить абзац'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить абзац?'), findsNothing); // no dialog for empty
    expect(svc.calls.contains('remove:b1'), true);
    expect(find.byKey(const Key('article-block-b1')), findsNothing);
  });

  testWidgets('deleting the last block returns to empty state',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', '')]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-block-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить абзац'));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('remove:b1'), true);
    expect(find.text('Биография ещё не написана.'), findsOneWidget);
    expect(find.byKey(const Key('article-empty-start')), findsOneWidget);
  });

  testWidgets('header menu label says «Удалить раздел»', (tester) async {
    final svc = _FakeArticleService(blocks: [
      ArticleBlock(
        id: 'h1',
        type: 'header',
        content: ArticleBlock.headerContent('Детство'),
        createdAt: 't',
        updatedAt: 't',
      ),
      _paragraph('b2', 'x'),
    ]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('article-block-menu-h1')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить раздел'), findsOneWidget);
  });

  testWidgets('backspace on empty block removes it + focuses previous',
      (tester) async {
    final svc = _FakeArticleService(
      blocks: [_paragraph('b1', 'Первый'), _paragraph('b2', '')],
    );
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-block-b2')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(svc.calls.contains('remove:b2'), true);
    expect(find.byKey(const Key('article-block-b2')), findsNothing);
    expect(find.byKey(const Key('article-block-b1')), findsOneWidget);
  });

  // ===== UI cluster: warm surface (bug 2) + toolbar labels (bug 3) =====

  testWidgets('editor surface is warm cream in light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: ProfileArticleEditorScreen(
          personId: 'p1',
          serviceOverride: _FakeArticleService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFFFAF7F2));
  });

  testWidgets('editor surface is warm sepia (not black) in dark theme',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: ProfileArticleEditorScreen(
          personId: 'p1',
          serviceOverride: _FakeArticleService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // Theme B — darker-but-clearly-warm сепия (device-verified; #1C1814
    // read as near-black to the eye).
    expect(scaffold.backgroundColor, const Color(0xFF2A211A));
    expect(scaffold.backgroundColor, isNot(Colors.black));
  });

  testWidgets('toolbar labels stay on one line (no wrap)', (tester) async {
    await tester.pumpWidget(_wrap(_FakeArticleService(blocks: [
      _paragraph('b1', 'x'),
    ])));
    await tester.pumpAndSettle();
    for (final label in ['Идеи', 'Блок', 'Фото', 'Голос']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1, reason: label);
      expect(text.softWrap, false, reason: label);
    }
  });

  // ===== Phase 2b-2: voice transcript accelerator =====

  testWidgets('«Голос» → «Надиктовать текст» → transcript as paragraph',
      (tester) async {
    final svc = _FakeArticleService();
    const transcript = 'Лидия родилась в селе Иваново в 1949 году';
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileArticleEditorScreen(
          personId: 'p1',
          serviceOverride: svc,
          voiceInputOverride: (_) async => transcript,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-voice')));
    await tester.pumpAndSettle(); // chooser
    await tester.tap(find.byKey(const Key('voice-menu-dictate')));
    await tester.pumpAndSettle();

    expect(svc.calls.contains('append:paragraph'), true);
    expect(
      (svc.lastAppendContent?['spans'] as List).first['text'],
      transcript,
    );
    expect(find.text(transcript), findsOneWidget);
  });

  testWidgets('dictate cancelled / denied → no block (can still type)',
      (tester) async {
    final svc = _FakeArticleService();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileArticleEditorScreen(
          personId: 'p1',
          serviceOverride: svc,
          voiceInputOverride: (_) async => null, // cancel / permission denied
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-menu-dictate')));
    await tester.pumpAndSettle();

    expect(svc.calls.any((c) => c.startsWith('append')), false);
    expect(find.byKey(const Key('article-empty-start')), findsOneWidget);
  });

  testWidgets('«Голос» → «Записать голос» → audio block (record + upload)',
      (tester) async {
    final svc = _FakeArticleService();
    final storage = _FakeStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileArticleEditorScreen(
          personId: 'p1',
          serviceOverride: svc,
          storageOverride: storage,
          audioRecordOverride: (_) async => AudioRecordResult(
            file: XFile.fromData(
              Uint8List.fromList(const [1, 2, 3]),
              name: 'rec.m4a',
              mimeType: 'audio/m4a',
            ),
            mimeType: 'audio/m4a',
            durationSec: 42,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-voice')));
    await tester.pumpAndSettle(); // chooser
    await tester.tap(find.byKey(const Key('voice-menu-record')));
    // Let record-override + uploadBytes + append resolve (avoid
    // pumpAndSettle — the audio block could keep a stream open).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(storage.uploadBytesCalls, 1);
    expect(storage.lastBucket, 'article-audio');
    expect(storage.lastContentType, 'audio/m4a');
    expect(svc.calls.contains('append:audio'), true);
    expect(svc.lastAppendContent?['url'], 'https://audio/rec.m4a');
    expect(svc.lastAppendContent?['durationSec'], 42);
    expect(svc.lastAppendContent?['transcript'], isNull);
    expect(find.byType(ArticleAudioBlock), findsOneWidget);
  });
}

class _FakeStorage implements StorageServiceInterface {
  int uploadCalls = 0;
  int uploadBytesCalls = 0;
  String? lastBucket;
  String? lastContentType;

  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async {
    uploadCalls += 1;
    return 'https://img/uploaded.jpg';
  }

  @override
  Future<String?> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List fileBytes,
    FileOptions? fileOptions,
  }) async {
    uploadBytesCalls += 1;
    lastBucket = bucket;
    lastContentType = fileOptions?.contentType;
    return 'https://audio/rec.m4a';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ArticleBlock _photo(String id, {String url = 'https://img/ph1.jpg'}) =>
    ArticleBlock(
      id: id,
      type: 'photo',
      content: {'url': url},
      createdAt: 't',
      updatedAt: 't',
    );

ArticleBlock _gallery(String id, int count) => ArticleBlock(
      id: id,
      type: 'gallery',
      content: ArticleBlock.galleryContent(
        items: [
          for (var i = 0; i < count; i++)
            <String, dynamic>{'url': 'https://img/g$i.jpg'},
        ],
      ),
      createdAt: 't',
      updatedAt: 't',
    );

Widget _wrapGallery(
  _FakeArticleService svc,
  _FakeStorage storage, {
  int pickCount = 2,
}) =>
    MaterialApp(
      home: ProfileArticleEditorScreen(
        personId: 'p1',
        personName: 'Лидия',
        serviceOverride: svc,
        storageOverride: storage,
        pickMultiImageOverride: () async => [
          for (var i = 0; i < pickCount; i++)
            XFile.fromData(
              Uint8List.fromList(const [1, 2, 3]),
              name: 'g$i.jpg',
              mimeType: 'image/jpeg',
            ),
        ],
        saveDebounce: const Duration(milliseconds: 200),
      ),
    );

Widget _wrapPhoto(
  _FakeArticleService svc,
  _FakeStorage storage, {
  Duration? debounce,
}) =>
    MaterialApp(
      home: ProfileArticleEditorScreen(
        personId: 'p1',
        personName: 'Лидия',
        serviceOverride: svc,
        storageOverride: storage,
        pickImageOverride: (_) async => XFile.fromData(
          Uint8List.fromList(const [1, 2, 3]),
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
        ),
        saveDebounce: debounce ?? const Duration(milliseconds: 200),
      ),
    );
