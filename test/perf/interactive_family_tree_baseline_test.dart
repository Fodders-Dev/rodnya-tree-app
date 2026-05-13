// Phase 4 chunk 3 prep — perf baseline для legacy InteractiveFamilyTree
// (mine view). Measure'ит first-paint duration на synthetic chain
// fixtures 100/500/1000 persons.
//
// Output: test/perf/baseline.json — пишется после run'а с
// updateBaseline=true. На последующих runs (updateBaseline=false)
// проверяет regression threshold (10% slowdown).
//
// **Не precision benchmark** — widget test environment не real
// device. Цель: early-warning regression detection на CI и
// pre-chunk-3 «sanity what is current cost».
//
// Pin'нутые variables (DECISIONS.md 2026-05-12 Gate 2 caveat):
//   ThemeMode.light, fixed window size, textScaler = noScaling.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

import 'fixtures.dart';

final Uint8List _transparentImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlH0X8AAAAASUVORK5CYII=',
);

// Mock HTTP / network image loader. Borrow'еn у
// test/interactive_family_tree_test.dart (Phase 2 pattern). Без
// него network image attempts при render'е fail'ятся длительно.
class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _TestHttpClient();
  }
}

class _TestHttpClient implements HttpClient {
  bool _autoUncompress = true;
  @override
  bool get autoUncompress => _autoUncompress;
  @override
  set autoUncompress(bool value) {
    _autoUncompress = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _TestHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TestHttpClientRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientRequest implements HttpClientRequest {
  @override
  HttpHeaders headers = _TestHttpHeaders();
  @override
  bool followRedirects = false;
  @override
  int maxRedirects = 5;
  @override
  Future<HttpClientResponse> close() async => _TestHttpClientResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final HttpHeaders headers = _TestHttpHeaders();
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _transparentImageBytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  bool get persistentConnection => false;
  @override
  bool get isRedirect => false;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentImageBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Read existing baseline.json либо null если нет.
Map<String, dynamic>? _readBaseline() {
  final file = File('test/perf/baseline.json');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Write baseline.json. Только manually triggered через
/// `UPDATE_PERF_BASELINE=1 flutter test test/perf/...`.
void _writeBaseline(Map<String, dynamic> data) {
  final file = File('test/perf/baseline.json');
  file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(data));
}

Future<int> _measureFirstPaintMs(
  WidgetTester tester,
  PerfFixture fixture,
) async {
  // Pinned variables (DECISIONS.md 2026-05-12 Gate 2 caveat).
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.reset();
  });

  // Warm-up pump чтобы Flutter не amortize'нул setup overhead в
  // первое измерение.
  await tester.pumpWidget(const SizedBox.shrink());

  final stopwatch = Stopwatch()..start();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1920, 1080),
          textScaler: TextScaler.noScaling,
        ),
        child: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: fixture.peopleData,
            relations: fixture.relations,
            onPersonTap: (_) {},
            isEditMode: false,
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'perf-user',
          ),
        ),
      ),
    ),
  );
  stopwatch.stop();
  return stopwatch.elapsedMilliseconds;
}

void main() {
  final originalHttpOverrides = HttpOverrides.current;
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });
  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  const sizes = <int>[100, 500, 1000];

  testWidgets(
      'Phase 4 chunk 3 prep — InteractiveFamilyTree perf baseline '
      '(legacy mine view, 100/500/1000 chain)', (tester) async {
    final updateBaseline =
        Platform.environment['UPDATE_PERF_BASELINE'] == '1';
    final results = <String, int>{};

    for (final size in sizes) {
      final fixture = generateLinearChain(count: size);
      final ms = await _measureFirstPaintMs(tester, fixture);
      results[size.toString()] = ms;
      debugPrint('[perf-baseline] $size nodes → first paint $ms ms');
    }

    if (updateBaseline) {
      _writeBaseline({
        'description':
            'Phase 4 chunk 3 prep baseline на legacy InteractiveFamilyTree '
            '(mine view). Synthetic linear chain fixtures.',
        'pinnedVariables': {
          'themeMode': 'light',
          'physicalSize': '1920x1080',
          'devicePixelRatio': 1.0,
          'textScaler': 'noScaling',
        },
        'firstPaintMsPerNodeCount': results,
        'capturedAtBranch': 'claude/quiet-meridian-7a91b3',
        'notes':
            'Numbers — widget-test environment first-pumpWidget durations, не '
            'real-device frame timings. Используются как regression early-'
            'warning baseline. Chunk 3 implementation должен оставаться '
            'within 10% от baseline на mine view при feature-flag OFF.',
      });
      return;
    }

    final baseline = _readBaseline();
    if (baseline == null) {
      // Первый run без UPDATE_PERF_BASELINE — просто print результаты,
      // не fail (baseline ещё не зафиксирован).
      debugPrint(
        '[perf-baseline] no baseline.json found — run с '
        'UPDATE_PERF_BASELINE=1 чтобы зафиксировать.',
      );
      return;
    }
    final baselineMs =
        Map<String, dynamic>.from(baseline['firstPaintMsPerNodeCount'] as Map);
    for (final size in sizes) {
      final key = size.toString();
      final baselineValue = (baselineMs[key] as num).toInt();
      final observed = results[key]!;
      final threshold = (baselineValue * 1.10).round();
      expect(
        observed,
        lessThanOrEqualTo(threshold),
        reason: 'Perf regression на $size nodes: baseline=$baselineValue ms, '
            'observed=$observed ms, threshold=${threshold}ms (+10%). '
            'Если это ожидаемая cost (e.g. chunk 3 implementation), '
            'обнови baseline через UPDATE_PERF_BASELINE=1.',
      );
    }
  });
}
