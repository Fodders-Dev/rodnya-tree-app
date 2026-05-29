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
import 'package:rodnya/widgets/article_photo_block.dart';

class _FakeArticleService implements ProfileArticleServiceInterface {
  _FakeArticleService({List<ArticleBlock>? blocks})
      : _blocks = blocks ?? <ArticleBlock>[];

  final List<ArticleBlock> _blocks;
  final List<String> calls = [];
  Map<String, dynamic>? lastUpdatedContent;
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
        type: content.containsKey('spans') ? 'paragraph' : 'header',
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

ArticleBlock _paragraph(String id, String text) => ArticleBlock(
      id: id,
      type: 'paragraph',
      content: ArticleBlock.paragraphContent(text),
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

  testWidgets('«+ Раздел» appends a header block', (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', 'текст')]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-header')));
    await tester.pumpAndSettle();
    expect(svc.calls.contains('append:header'), true);
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

  testWidgets('voice toolbar button still shows «скоро» (2b-2)',
      (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', 'x')]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-voice')));
    await tester.pump();
    expect(find.textContaining('следующем обновлении'), findsOneWidget);
    expect(svc.calls.any((c) => c.startsWith('append')), false);
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
}

class _FakeStorage implements StorageServiceInterface {
  int uploadCalls = 0;

  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async {
    uploadCalls += 1;
    return 'https://img/uploaded.jpg';
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
