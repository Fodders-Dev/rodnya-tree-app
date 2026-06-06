// Phase E5b: PollCard renders option bars and votes optimistically.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/poll_service_interface.dart';
import 'package:rodnya/models/poll.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/poll_card.dart';

class _FakePollService implements PollServiceInterface {
  int voteCalls = 0;
  List<String>? lastOptionIds;
  Completer<Poll>? deferred;

  @override
  Future<Poll> vote(String pollId, List<String> optionIds) {
    voteCalls++;
    lastOptionIds = optionIds;
    if (deferred != null) {
      return deferred!.future;
    }
    return Future.value(
      Poll(
        id: pollId,
        treeId: 't',
        authorId: 'org',
        authorName: 'Орг',
        question: 'Когда?',
        options: const [
          PollOption(id: 'o1', text: 'Суббота'),
          PollOption(id: 'o2', text: 'Воскресенье'),
        ],
        createdAt: DateTime(2026, 6, 1),
        responses: [
          {'userId': 'me', 'optionIds': optionIds},
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Poll _poll({
  List<Map<String, dynamic>> responses = const [],
  bool allowMultiple = false,
}) {
  return Poll(
    id: 'p1',
    treeId: 't',
    authorId: 'org',
    authorName: 'Орг',
    question: 'Когда собираемся?',
    options: const [
      PollOption(id: 'o1', text: 'Суббота'),
      PollOption(id: 'o2', text: 'Воскресенье'),
    ],
    allowMultiple: allowMultiple,
    createdAt: DateTime(2026, 6, 1),
    responses: responses,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('tapping an option votes optimistically and calls vote',
      (tester) async {
    final svc = _FakePollService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: PollCard(
            poll: _poll(),
            serviceOverride: svc,
            currentUserId: 'me',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 голосов'), findsOneWidget);

    await tester.tap(find.byKey(const Key('poll-option-o1')));
    await tester.pump(); // optimistic — vote already invoked

    expect(svc.voteCalls, 1);
    expect(svc.lastOptionIds, ['o1']);

    await tester.pumpAndSettle(); // server reconcile
    expect(find.text('1 голос'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('reverts the vote when the service fails', (tester) async {
    final svc = _FakePollService()..deferred = Completer<Poll>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: PollCard(
            poll: _poll(),
            serviceOverride: svc,
            currentUserId: 'me',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('poll-option-o1')));
    await tester.pump(); // optimistic
    expect(find.text('1 голос'), findsOneWidget);

    svc.deferred!.completeError(Exception('boom'));
    await tester.pump(); // revert + snackbar
    expect(find.text('0 голосов'), findsOneWidget);
    expect(find.text('Не удалось сохранить голос'), findsOneWidget);
  });

  testWidgets('option bars compute percent from responses', (tester) async {
    final poll = _poll(
      responses: [
        {
          'userId': 'u1',
          'optionIds': ['o1'],
        },
        {
          'userId': 'u2',
          'optionIds': ['o1'],
        },
        {
          'userId': 'u3',
          'optionIds': ['o2'],
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: PollCard(poll: poll)),
      ),
    );
    await tester.pumpAndSettle();

    // total 3 → o1 = 2 (67%), o2 = 1 (33%).
    expect(find.text('3 голоса'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
  });
}
