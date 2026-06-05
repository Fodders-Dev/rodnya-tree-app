// Shared feed media gallery (A): single tile vs multi-photo carousel
// with page-dots, plus the video-URL sniffer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/feed_media_gallery.dart';

void main() {
  test('isFeedVideoUrl sniffs video extensions, ignoring query strings', () {
    expect(isFeedVideoUrl('https://x/clip.mp4'), isTrue);
    expect(isFeedVideoUrl('https://x/clip.MOV?token=abc'), isTrue);
    expect(isFeedVideoUrl('https://x/photo.jpg'), isFalse);
    expect(isFeedVideoUrl('https://x/photo.jpeg?w=200'), isFalse);
  });

  testWidgets('single photo renders a tile (no carousel dots)', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedMediaGallery(
            imageUrls: const ['https://example.com/1.jpg'],
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FeedMediaGallery), findsOneWidget);
    // A single image is a plain tile — no carousel / dots.
    expect(find.byKey(const Key('post-carousel-dots')), findsNothing);

    await tester.tap(find.byType(FeedMediaGallery));
    expect(tapped, 0);
  });

  testWidgets('multiple photos render a carousel with one dot each',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedMediaGallery(
            imageUrls: const [
              'https://example.com/1.jpg',
              'https://example.com/2.jpg',
              'https://example.com/3.jpg',
            ],
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final dots = find.descendant(
      of: find.byKey(const Key('post-carousel-dots')),
      matching: find.byType(AnimatedContainer),
    );
    expect(dots, findsNWidgets(3));
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedMediaGallery(imageUrls: const [], onTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('post-carousel-dots')), findsNothing);
  });
}
