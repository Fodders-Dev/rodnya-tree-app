import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineage/services/rustore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('requestReview returns false when review request throws', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final service = RustoreService(
      reviewInitialize: () async {},
      reviewRequest: () async {
        throw Exception('RuStore not installed');
      },
      reviewShow: () async {},
    );

    final result = await service.requestReview();
    expect(result, isFalse);
  });

  test('requestReview returns true when review dialog flow completes',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final service = RustoreService(
      reviewInitialize: () async {},
      reviewRequest: () async {},
      reviewShow: () async {},
    );

    final result = await service.requestReview();
    expect(result, isTrue);
  });
}
