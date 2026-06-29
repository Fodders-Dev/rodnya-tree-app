import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/chat_send_progress.dart';

ChatSendProgress progress(int completed, int total) => ChatSendProgress(
      stage: ChatSendProgressStage.uploading,
      completed: completed,
      total: total,
    );

void main() {
  group('ChatSendProgress.value', () {
    test('single attachment is indeterminate (null), not a frozen 0%', () {
      // total<=1 has no per-file granularity — must animate, never stick at 0.
      expect(progress(0, 1).value, isNull);
      expect(progress(1, 1).value, isNull);
    });

    test('multi-file with nothing done yet is indeterminate (null)', () {
      expect(progress(0, 3).value, isNull);
    });

    test('multi-file with progress is determinate', () {
      expect(progress(1, 3).value, closeTo(1 / 3, 1e-9));
      expect(progress(2, 4).value, closeTo(0.5, 1e-9));
      expect(progress(3, 3).value, 1.0);
    });

    test('completed clamps to total', () {
      expect(progress(5, 3).value, 1.0);
    });

    test('empty/zero total is indeterminate (null)', () {
      expect(progress(0, 0).value, isNull);
    });
  });
}
