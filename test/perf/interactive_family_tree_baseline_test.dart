// Perf baseline для InteractiveFamilyTree extended-network render
// path. Measure'ит first-paint duration на synthetic chain fixtures
// 100/500/1000 persons.
//
// Measure-and-log only (DECISIONS.md 2026-05-18 cleanup): regression
// catching через observability — debugPrint output читается manually
// в CI logs либо при local run.
//
// **Не precision benchmark** — widget test environment не real
// device. Цель: early-warning regression detection через log diff.
//
// Pin'нутые variables (DECISIONS.md 2026-05-12 Gate 2 caveat):
//   ThemeMode.light, fixed window size, textScaler = noScaling.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/providers/extended_network_controller.dart';
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

/// Number of measurement runs per fixture size. Mean из 3 runs даёт
/// σ/√3 ≈ 8.7% (если single-run σ ≈ 15%) — это устойчиво держит
/// 10% threshold ниже variance ceiling'а (DECISIONS.md 2026-05-12
/// methodology refinement).
const int _measurementRuns = 3;

/// Constructs an ExtendedNetworkSlice с graphPersons matching the
/// fixture's people. Все nodes treated as own (no ownerMap entries),
/// чтобы measure cost feature-flag branching alone — render result
/// identical к flag=false (defensive default-to-own).
ExtendedNetworkSlice _allOwnSlice(PerfFixture fixture) {
  final persons = fixture.peopleData
      .map((entry) {
        final person = entry['person'];
        return ExtendedNetworkPerson(
          id: (person as dynamic).id as String,
          name: null,
          gender: null,
          birthDate: null,
          deathDate: null,
          photoUrl: null,
          isAlive: true,
          hopDistance: 0,
        );
      })
      .toList(growable: false);
  return ExtendedNetworkSlice(
    graphPersons: persons,
    graphRelations: const <ExtendedNetworkRelation>[],
    branchMembership: const <String, List<String>>{},
    ownerMap: const <String, ExtendedNetworkOwnerInfo>{}, // all own
    stats: ExtendedNetworkStats(
      totalCount: persons.length,
      myCount: persons.length,
      extendedCount: 0,
      anonymousCount: 0,
      maxHopsReached: false,
      capReached: false,
    ),
  );
}

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

  final slice = _allOwnSlice(fixture);
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
            viewMode: ExtendedNetworkMode.extended,
            networkSlice: slice,
          ),
        ),
      ),
    ),
  );
  stopwatch.stop();
  return stopwatch.elapsedMilliseconds;
}

/// Returns mean of `_measurementRuns` independent measurements.
/// Single-run variance σ ≈ 15% noisy, mean of 3 даёт σ/√3 ≈ 8.7%
/// — устойчиво держит читаемые ms numbers ниже noise ceiling'а.
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
      'InteractiveFamilyTree perf baseline (extended-network render, '
      '100/500/1000 linear chain)',
      tags: 'perf', (tester) async {
    for (final size in sizes) {
      final fixture = generateLinearChain(count: size);
      await _measureFirstPaintMs(tester, fixture);
      // Mean logged from inside _measureFirstPaintMs along с raw
      // samples. No expect — regression detection через debugPrint
      // observability (DECISIONS.md 2026-05-18).
    }
  });
}
