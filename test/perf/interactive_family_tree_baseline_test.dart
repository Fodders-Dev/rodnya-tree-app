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

/// Number of measurement runs per fixture size. Mean из 3 runs даёт
/// σ/√3 ≈ 8.7% (если single-run σ ≈ 15%) — это устойчиво держит
/// 10% threshold ниже variance ceiling'а (DECISIONS.md 2026-05-12
/// methodology refinement).
const int _measurementRuns = 3;

Future<int> _singleMeasurement(
  WidgetTester tester,
  PerfFixture fixture,
) async {
  // Pinned variables (DECISIONS.md 2026-05-12 Gate 2 caveat).
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;

  // Multi-stage warm-up: empty pump → small InteractiveFamilyTree
  // pump → empty pump → real measurement. Two-pump warmup даёт
  // framework time на JIT compile InteractiveFamilyTree code paths
  // и avatar/edge rendering. Без этого первое measurement каждого
  // run'а в 2-3x slow чем стабильное steady-state — что dominates
  // mean of 3.
  await tester.pumpWidget(const SizedBox.shrink());
  final warmupFixture = generateLinearChain(count: 10);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractiveFamilyTree(
          peopleData: warmupFixture.peopleData,
          relations: warmupFixture.relations,
          onPersonTap: (_) {},
          isEditMode: false,
          onAddRelativeTapWithType: (_, __) {},
          currentUserIsInTree: true,
          onAddSelfTapWithType: (_, __) async {},
          currentUserId: 'perf-user',
        ),
      ),
    ),
  );
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

/// Returns mean of `_measurementRuns` independent measurements.
/// Single-run variance σ ≈ 15% noisy, mean of 3 даёт σ/√3 ≈ 8.7%,
/// allowing 10% threshold to be stable.
Future<int> _measureFirstPaintMs(
  WidgetTester tester,
  PerfFixture fixture,
) async {
  addTearDown(() {
    tester.view.reset();
  });
  final samples = <int>[];
  for (var i = 0; i < _measurementRuns; i++) {
    final ms = await _singleMeasurement(tester, fixture);
    samples.add(ms);
  }
  final sum = samples.fold<int>(0, (a, b) => a + b);
  final mean = (sum / samples.length).round();
  debugPrint(
    '[perf-baseline] ${fixture.nodeCount} nodes → samples '
    '${samples.join(", ")} ms; mean $mean ms',
  );
  return mean;
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
      final meanMs = await _measureFirstPaintMs(tester, fixture);
      results[size.toString()] = meanMs;
      // Mean logged from inside _measureFirstPaintMs along с raw
      // samples — repeated debugPrint избыточен.
    }

    if (updateBaseline) {
      _writeBaseline({
        'description':
            'Phase 4 chunk 3 prep baseline на legacy InteractiveFamilyTree '
            '(mine view). Synthetic linear chain fixtures.',
        'methodology':
            'Mean of $_measurementRuns measurement runs per fixture size. '
            'Single-run variance σ ≈ 15% (widget-test environment noise); '
            'mean of $_measurementRuns даёт σ/√$_measurementRuns ≈ 8.7%, '
            'устойчиво держа 10% regression threshold ниже noise ceiling. '
            'Per Артёмов methodology refinement 2026-05-12.',
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
            'within 10% от baseline на mine view при feature-flag OFF. '
            'Shape sensitivity (wide-balanced vs linear-chain) — defer'
            "'нут на chunk 3.5 follow-up.",
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
