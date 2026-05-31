// Profile Phase 2b-2 audio (2026-05-31 polish): the audio block must
// resume from where it paused (not restart at 0), and must not touch the
// audioplayers plugin merely by rendering. These drive the widget through
// a fake AudioPlayer injected via [ArticleAudioBlock.playerFactory] — the
// fake records the control calls and pushes player-state events, so we
// assert play→pause→resume (not play→pause→play) without a real plugin.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/widgets/article_audio_block.dart';

ArticleBlock _audioBlock() => ArticleBlock(
      id: 'au1',
      type: 'audio',
      content: {'url': 'https://a/v.m4a', 'durationSec': 42},
      createdAt: 't',
      updatedAt: 't',
    );

Widget _wrap(ArticleAudioBlock block) => MaterialApp(
      home: Scaffold(body: Center(child: block)),
    );

void main() {
  testWidgets('rendering does not build a player (lazy)', (tester) async {
    var built = 0;
    await tester.pumpWidget(
      _wrap(ArticleAudioBlock(
        block: _audioBlock(),
        busy: false,
        onReplace: () {},
        onDelete: () {},
        playerFactory: () {
          built += 1;
          return _FakePlayer();
        },
      )),
    );
    await tester.pump();

    // Merely rendering the block must not construct the player.
    expect(built, 0);
    expect(find.byKey(const Key('article-audio-play-au1')), findsOneWidget);
    expect(find.byKey(const Key('article-audio-seek-au1')), findsOneWidget);
  });

  testWidgets('paused → tap resumes (does not restart from 0)',
      (tester) async {
    final fake = _FakePlayer();
    await tester.pumpWidget(
      _wrap(ArticleAudioBlock(
        block: _audioBlock(),
        busy: false,
        onReplace: () {},
        onDelete: () {},
        playerFactory: () => fake,
      )),
    );
    await tester.pump();

    final playBtn = find.byKey(const Key('article-audio-play-au1'));

    // 1st tap: stopped → play (first playback).
    await tester.tap(playBtn);
    await tester.pump();
    await tester.pump();

    // 2nd tap: playing → pause (keeps position).
    await tester.tap(playBtn);
    await tester.pump();
    await tester.pump();

    // 3rd tap: paused → resume (NOT a fresh play from 0).
    await tester.tap(playBtn);
    await tester.pump();
    await tester.pump();

    expect(fake.calls, ['play', 'pause', 'resume']);
  });

  testWidgets('seek commits the chosen position immediately (no snap to 0)',
      (tester) async {
    final fake = _FakePlayer();
    await tester.pumpWidget(
      _wrap(ArticleAudioBlock(
        block: _audioBlock(), // durationSec 42 → slider enabled, total 0:42
        busy: false,
        onReplace: () {},
        onDelete: () {},
        playerFactory: () => fake,
      )),
    );
    await tester.pump();

    // Before any interaction the timer reads 0:00 / 0:42.
    expect(find.text('0:00 / 0:42'), findsOneWidget);

    // Drag-release at 6s via the Slider's onChangeEnd. The fake's position
    // stream never ticks (paused/stopped), reproducing the bug condition —
    // the widget must reflect the target itself.
    final slider = tester.widget<Slider>(
      find.byKey(const Key('article-audio-seek-au1')),
    );
    slider.onChangeEnd!(6000.0);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // Functionally seeked, and the timer/thumb now show 0:06 — not the
    // stale 0:00 it used to snap back to.
    expect(fake.calls.contains('seek'), true);
    expect(find.text('0:06 / 0:42'), findsOneWidget);
    expect(find.text('0:00 / 0:42'), findsNothing);
    final after = tester.widget<Slider>(
      find.byKey(const Key('article-audio-seek-au1')),
    );
    expect(after.value, 6000.0);
  });
}

/// A plugin-free [AudioPlayer] stand-in. Records the control calls and
/// pushes a matching [PlayerState] so the widget's state machine advances
/// (stopped → playing → paused → …). Everything else routes through
/// [noSuchMethod]; the four event streams are provided explicitly because
/// the widget subscribes to them in `_ensurePlayer`.
class _FakePlayer implements AudioPlayer {
  final StreamController<PlayerState> _stateCtl =
      StreamController<PlayerState>.broadcast();
  final List<String> calls = <String>[];

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateCtl.stream;
  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();
  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> dispose() async {
    await _stateCtl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #play) {
      calls.add('play');
      _stateCtl.add(PlayerState.playing);
      return Future<void>.value();
    }
    if (name == #pause) {
      calls.add('pause');
      _stateCtl.add(PlayerState.paused);
      return Future<void>.value();
    }
    if (name == #resume) {
      calls.add('resume');
      _stateCtl.add(PlayerState.playing);
      return Future<void>.value();
    }
    if (name == #seek) {
      calls.add('seek');
      return Future<void>.value();
    }
    if (name == #setSourceUrl) {
      calls.add('setSourceUrl');
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}
