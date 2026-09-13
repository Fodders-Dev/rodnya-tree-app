import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/story_request_capable_family_tree_service.dart';
import 'package:rodnya/models/story_request.dart';
import 'package:rodnya/widgets/family_story_questions_sheet.dart';

class _FakeStoryRequestService implements StoryRequestCapableFamilyTreeService {
  String? lastTargetUserId;
  String? lastPersonId;
  StoryRequestQuestion? lastQuestion;
  Object? throwOnCreate;

  @override
  Future<StoryRequest?> createStoryRequest({
    required String treeId,
    required String personId,
    required String targetUserId,
    required StoryRequestQuestion question,
  }) async {
    if (throwOnCreate != null) throw throwOnCreate!;
    lastPersonId = personId;
    lastTargetUserId = targetUserId;
    lastQuestion = question;
    return StoryRequest(
      id: 'sreq-new',
      treeId: treeId,
      personId: personId,
      requesterUserId: 'u-me',
      targetUserId: targetUserId,
      question: question,
      status: StoryRequestStatus.pending,
      createdAt: '2026-09-13T10:00:00Z',
      expiresAt: '2026-10-13T10:00:00Z',
    );
  }

  @override
  Future<StoryRequest?> getStoryRequest({required String requestId}) async => null;

  @override
  Future<StoryRequest?> answerStoryRequest({
    required String requestId,
    required StoryRequestAnswerInput answer,
  }) async =>
      null;

  @override
  Future<StoryRequest?> declineStoryRequest({required String requestId}) async => null;

  @override
  Future<StoryRequest?> revokeStoryRequest({required String requestId}) async => null;

  @override
  Future<List<StoryRequest>> listStoryRequests({
    required String role,
    StoryRequestStatus? status,
  }) async =>
      const <StoryRequest>[];
}

void main() {
  testWidgets('family story sheet selects a question and returns save action',
      (tester) async {
    FamilyStoryQuestionAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецова Валентина',
                  relation: 'Бабушка',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Спросить историю'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('family-story-question-old_photos')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('family-story-question-old_photos')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-story-save-answer')));
    await tester.pumpAndSettle();

    expect(result?.type, FamilyStoryQuestionActionType.saveAnswer);
    expect(result?.question.id, 'old_photos');
  });

  testWidgets('family story sheet can return share action', (tester) async {
    FamilyStoryQuestionAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецов Андрей',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-story-share-question')));
    await tester.pumpAndSettle();

    expect(result?.type, FamilyStoryQuestionActionType.share);
    expect(result?.question.id, 'parents_birthplace');
  });

  // MVP-1 «Спросить историю» (STORY-REQUEST-MVP1-BRIEF.md §3.3): «Кого
  // спросить» step, gated on BOTH a StoryRequestCapableFamilyTreeService
  // AND at least one askTarget.

  testWidgets(
    'no capability service → sheet behaves exactly as before (no ask-in-app button)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецова Валентина',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-story-ask-in-app')), findsNothing);
      expect(find.text('Отправить вопрос'), findsOneWidget);
    },
  );

  testWidgets(
    'capability present but no askTargets → still no ask-in-app button (nobody to ask yet)',
    (tester) async {
      final service = _FakeStoryRequestService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецова Валентина',
                  storyRequestService: service,
                  treeId: 'tree-1',
                  personId: 'person-1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-story-ask-in-app')), findsNothing);
    },
  );

  testWidgets(
    'capability + targets → «Кого спросить» step sends createStoryRequest and returns requestSent',
    (tester) async {
      final service = _FakeStoryRequestService();
      FamilyStoryQuestionAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showFamilyStoryQuestionsSheet(
                    context,
                    personName: 'Лида',
                    storyRequestService: service,
                    treeId: 'tree-1',
                    personId: 'person-1',
                    askTargets: const [
                      FamilyStoryAskTarget(
                        userId: 'user-hero',
                        displayName: 'Лида',
                        isHero: true,
                      ),
                      FamilyStoryAskTarget(userId: 'user-other', displayName: 'Артём'),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-story-ask-in-app')), findsOneWidget);
      await tester.tap(find.byKey(const Key('family-story-ask-in-app')));
      await tester.pumpAndSettle();

      expect(find.text('Кого спросить?'), findsOneWidget);
      expect(find.byKey(const Key('family-story-target-user-hero')), findsOneWidget);
      expect(find.byKey(const Key('family-story-target-user-other')), findsOneWidget);

      await tester.tap(find.byKey(const Key('family-story-target-user-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-story-send-request')));
      await tester.pumpAndSettle();

      expect(service.lastTargetUserId, 'user-other');
      expect(service.lastPersonId, 'person-1');
      expect(service.lastQuestion?.text, isNotEmpty);
      expect(result?.type, FamilyStoryQuestionActionType.requestSent);
      expect(result?.request?.id, 'sreq-new');
      expect(find.text('Артём получит ваш вопрос'), findsOneWidget);
    },
  );

  testWidgets(
    '«Кого спросить» surfaces StoryRequestError.message inline и не закрывает лист',
    (tester) async {
      final service = _FakeStoryRequestService()
        ..throwOnCreate = const StoryRequestError(
          code: 'DUPLICATE_PENDING',
          message: 'Такой вопрос уже ждёт ответа',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Лида',
                  storyRequestService: service,
                  treeId: 'tree-1',
                  personId: 'person-1',
                  askTargets: const [
                    FamilyStoryAskTarget(userId: 'user-other', displayName: 'Артём'),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-story-ask-in-app')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-story-target-user-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-story-send-request')));
      await tester.pumpAndSettle();

      expect(find.text('Такой вопрос уже ждёт ответа'), findsOneWidget);
      expect(find.text('Кого спросить?'), findsOneWidget, reason: 'лист не закрылся');
    },
  );
}
