// Profile Phase 2a (2026-05-29): article editor widget tests.
//
// Covers: render loaded blocks, debounced paragraph auto-save (PATCH),
// «+ Раздел» append, темы-промпт sheet insert (header + paragraph),
// debounce timing, and the empty state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/screens/profile_article_editor_screen.dart';

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

  testWidgets('media toolbar buttons show «скоро» snackbar', (tester) async {
    final svc = _FakeArticleService(blocks: [_paragraph('b1', 'x')]);
    await tester.pumpWidget(_wrap(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('article-add-photo')));
    await tester.pump();
    expect(find.textContaining('следующем обновлении'), findsOneWidget);
    // No block append for media in 2a.
    expect(svc.calls.any((c) => c.startsWith('append')), false);
  });
}
