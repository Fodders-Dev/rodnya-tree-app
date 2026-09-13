// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.7): answer
// screen — audio (via the audioRecordOverride seam, mirroring
// profile_article_editor_test.dart's pattern), text, decline, and a
// density probe (412×915 dp, dpr 3 per the brief).
//
// Short fake copy throughout — the test harness's fallback font is wider
// than Manrope, so long strings can overflow at these widths even though
// the real app (with Manrope loaded) fits comfortably.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/backend/interfaces/story_request_capable_family_tree_service.dart';
import 'package:rodnya/models/story_request.dart';
import 'package:rodnya/screens/story_request_answer_screen.dart';
import 'package:rodnya/widgets/audio_record_sheet.dart';

class _FakeStoryRequestService implements StoryRequestCapableFamilyTreeService {
  _FakeStoryRequestService(this.request);

  StoryRequest request;
  final List<String> calls = [];
  StoryRequestAnswerInput? lastAnswer;

  @override
  Future<StoryRequest?> getStoryRequest({required String requestId}) async {
    calls.add('get:$requestId');
    return request;
  }

  @override
  Future<StoryRequest?> answerStoryRequest({
    required String requestId,
    required StoryRequestAnswerInput answer,
  }) async {
    calls.add('answer:${answer.kind.serverValue}');
    lastAnswer = answer;
    request = StoryRequest(
      id: request.id,
      treeId: request.treeId,
      personId: request.personId,
      requesterUserId: request.requesterUserId,
      targetUserId: request.targetUserId,
      question: request.question,
      status: StoryRequestStatus.answered,
      answer: StoryRequestAnswer(
        articleBlockId: 'block-1',
        kind: answer.kind,
        answeredByUserId: request.targetUserId,
        answeredAt: '2026-09-13T10:00:00Z',
      ),
      createdAt: request.createdAt,
      expiresAt: request.expiresAt,
      person: request.person,
      requester: request.requester,
      target: request.target,
    );
    return request;
  }

  @override
  Future<StoryRequest?> declineStoryRequest({required String requestId}) async {
    calls.add('decline');
    request = StoryRequest(
      id: request.id,
      treeId: request.treeId,
      personId: request.personId,
      requesterUserId: request.requesterUserId,
      targetUserId: request.targetUserId,
      question: request.question,
      status: StoryRequestStatus.declined,
      createdAt: request.createdAt,
      expiresAt: request.expiresAt,
      person: request.person,
      requester: request.requester,
      target: request.target,
    );
    return request;
  }

  @override
  Future<StoryRequest?> revokeStoryRequest({required String requestId}) async {
    calls.add('revoke');
    return request;
  }

  @override
  Future<StoryRequest?> createStoryRequest({
    required String treeId,
    required String personId,
    required String targetUserId,
    required StoryRequestQuestion question,
  }) async {
    throw UnimplementedError('not used by the answer screen');
  }

  @override
  Future<List<StoryRequest>> listStoryRequests({
    required String role,
    StoryRequestStatus? status,
  }) async {
    return const <StoryRequest>[];
  }
}

class _FakeStorage implements StorageServiceInterface {
  int uploadBytesCalls = 0;
  int uploadImageCalls = 0;
  String? lastBucket;

  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async {
    uploadImageCalls += 1;
    return 'https://img/story-photo.jpg';
  }

  @override
  Future<bool> deleteImage(String imageUrl) async => true;

  @override
  Future<String?> uploadProfileImage(XFile imageFile) async => null;

  @override
  Future<String?> uploadCoverImage(XFile imageFile) async => null;

  @override
  Future<String?> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List fileBytes,
    FileOptions? fileOptions,
  }) async {
    uploadBytesCalls += 1;
    lastBucket = bucket;
    return 'https://audio/story-answer.m4a';
  }
}

StoryRequest _pendingRequest({String question = 'Кто на фото?'}) {
  return StoryRequest(
    id: 'sreq-1',
    treeId: 'tree-1',
    personId: 'person-1',
    requesterUserId: 'u-initiator',
    targetUserId: 'u-target',
    question: StoryRequestQuestion(text: question),
    status: StoryRequestStatus.pending,
    createdAt: '2026-09-13T10:00:00Z',
    expiresAt: '2026-10-13T10:00:00Z',
    person: const StoryRequestPersonSummary(id: 'person-1', displayName: 'Лида'),
    requester: const StoryRequestPersonSummary(id: 'u-initiator', displayName: 'Артём'),
    target: const StoryRequestPersonSummary(id: 'u-target', displayName: 'Лида'),
  );
}

/// Pushes the screen via a real Navigator (host screen), so Navigator.pop
/// inside the screen (skip / terminal «Готово») works without a GoRouter
/// in the tree — only the thank-you screen's «К странице …» button needs
/// GoRouter, and no test here taps it.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeStoryRequestService service,
  _FakeStorage? storage,
  Future<AudioRecordResult?> Function(BuildContext)? audioRecordOverride,
  Future<XFile?> Function(ImageSource)? pickImageOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StoryRequestAnswerScreen(
                requestId: service.request.id,
                serviceOverride: service,
                storageOverride: storage,
                audioRecordOverride: audioRecordOverride,
                pickImageOverride: pickImageOverride,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the pending request and shows question + context',
      (tester) async {
    final service = _FakeStoryRequestService(_pendingRequest());
    await _pumpScreen(tester, service: service);

    expect(find.text('«Кто на фото?»'), findsOneWidget);
    expect(find.textContaining('Артём'), findsWidgets);
    expect(find.textContaining('Лида'), findsWidgets);
    expect(find.byKey(const Key('story-answer-mic')), findsOneWidget);
  });

  testWidgets('mic → record → upload → answerStoryRequest(audio) → thank you',
      (tester) async {
    final service = _FakeStoryRequestService(_pendingRequest());
    final storage = _FakeStorage();
    await _pumpScreen(
      tester,
      service: service,
      storage: storage,
      audioRecordOverride: (_) async => AudioRecordResult(
        file: XFile.fromData(
          Uint8List.fromList(const [1, 2, 3]),
          name: 'rec.m4a',
          mimeType: 'audio/m4a',
        ),
        mimeType: 'audio/m4a',
        durationSec: 12,
      ),
    );

    await tester.tap(find.byKey(const Key('story-answer-mic')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(storage.uploadBytesCalls, 1);
    expect(storage.lastBucket, 'story-request-audio');
    expect(service.calls.contains('answer:audio'), true);
    expect(service.lastAnswer?.mediaUrl, 'https://audio/story-answer.m4a');
    expect(service.lastAnswer?.durationSec, 12);
    expect(find.byKey(const Key('story-answer-thankyou-message')), findsOneWidget);
    expect(find.textContaining('Артём'), findsWidgets);
  });

  testWidgets('«Написать текстом» → type → «Сохранить» → answerStoryRequest(text)',
      (tester) async {
    final service = _FakeStoryRequestService(_pendingRequest());
    await _pumpScreen(tester, service: service);

    await tester.tap(find.byKey(const Key('story-answer-text-mode')));
    await tester.pumpAndSettle();

    final submitFinder = find.byKey(const Key('story-answer-text-submit'));
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('story-answer-text-field')),
      'Это моя история.',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);

    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(service.calls.contains('answer:text'), true);
    expect(service.lastAnswer?.text, 'Это моя история.');
    expect(find.byKey(const Key('story-answer-thankyou-message')), findsOneWidget);
  });

  testWidgets('«Не хочу отвечать» → confirm → declineStoryRequest → terminal',
      (tester) async {
    final service = _FakeStoryRequestService(_pendingRequest());
    await _pumpScreen(tester, service: service);

    await tester.tap(find.byKey(const Key('story-answer-decline')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('story-answer-decline-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('story-answer-decline-confirm')));
    await tester.pumpAndSettle();

    expect(service.calls.contains('decline'), true);
    expect(find.byKey(const Key('story-answer-terminal-message')), findsOneWidget);
  });

  testWidgets(
    'density probe 412×915 @dpr3: mic ≥72dp, texts ≥16sp, question ≥20sp, fits above the fold',
    (tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final service = _FakeStoryRequestService(_pendingRequest(question: 'Кто на фото?'));
      await _pumpScreen(tester, service: service);

      final micSize = tester.getSize(find.byKey(const Key('story-answer-mic')));
      expect(micSize.width, greaterThanOrEqualTo(72));
      expect(micSize.height, greaterThanOrEqualTo(72));

      final questionText =
          tester.widget<Text>(find.byKey(const Key('story-answer-question')));
      expect(questionText.style?.fontSize, greaterThanOrEqualTo(20));

      final textModeLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('story-answer-text-mode')),
          matching: find.byType(Text),
        ),
      );
      expect(textModeLabel.style?.fontSize, greaterThanOrEqualTo(16));

      final skipRect = tester.getRect(find.byKey(const Key('story-answer-skip')));
      final declineRect =
          tester.getRect(find.byKey(const Key('story-answer-decline')));
      expect(
        declineRect.bottom,
        lessThanOrEqualTo(915),
        reason: 'Экран ответа должен помещаться на 412×915 без скролла.',
      );
      expect(skipRect.bottom, lessThanOrEqualTo(915));
    },
  );
}
