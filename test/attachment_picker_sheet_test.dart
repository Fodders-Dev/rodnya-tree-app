import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/attachment_picker_sheet.dart';

/// Defense-in-depth widget tests for the unified attachment picker sheet.
///
/// The sheet is the single entry point for all "add media" flows in the
/// app (chat composer, post composer, story composer). The route-level
/// smoke harness in tool/prod_route_smoke.mjs cannot drive Flutter
/// CanvasKit through Playwright selectors, so the picker behaviour
/// (renders all tiles, returns the tapped id, returns null on dismiss)
/// is asserted here instead.
void main() {
  testWidgets('renders one tile per action with label + icon',
      (tester) async {
    await tester.pumpWidget(
      _PickerHarness(
        actions: const [
          AttachmentPickerAction(
            id: 'gallery',
            icon: Icons.photo_library_rounded,
            label: 'Галерея',
            color: Color(0xFFE05A8B),
          ),
          AttachmentPickerAction(
            id: 'camera',
            icon: Icons.photo_camera_rounded,
            label: 'Камера',
            color: Color(0xFF3D8DFF),
          ),
          AttachmentPickerAction(
            id: 'video',
            icon: Icons.videocam_rounded,
            label: 'Видео',
            color: Color(0xFFE85A40),
          ),
          AttachmentPickerAction(
            id: 'file',
            icon: Icons.insert_drive_file_rounded,
            label: 'Файл',
            color: Color(0xFF3D8DFF),
          ),
        ],
        title: 'ПРИКРЕПИТЬ',
      ),
    );

    await tester.tap(find.text('Открыть пикер'));
    await tester.pumpAndSettle();

    expect(find.text('ПРИКРЕПИТЬ'), findsOneWidget);
    expect(find.text('Галерея'), findsOneWidget);
    expect(find.text('Камера'), findsOneWidget);
    expect(find.text('Видео'), findsOneWidget);
    expect(find.text('Файл'), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_rounded), findsOneWidget);
  });

  testWidgets('returns the tapped action id', (tester) async {
    final harness = _PickerHarness(
      actions: const [
        AttachmentPickerAction(
          id: 'gallery',
          icon: Icons.photo_library_rounded,
          label: 'Галерея',
          color: Color(0xFFE05A8B),
        ),
        AttachmentPickerAction(
          id: 'camera',
          icon: Icons.photo_camera_rounded,
          label: 'Камера',
          color: Color(0xFF3D8DFF),
        ),
      ],
    );
    await tester.pumpWidget(harness);

    await tester.tap(find.text('Открыть пикер'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Камера'));
    await tester.pumpAndSettle();

    expect(_PickerHarnessState.lastResult, 'camera');
  });

  testWidgets('returns null when dismissed via barrier', (tester) async {
    final harness = _PickerHarness(
      actions: const [
        AttachmentPickerAction(
          id: 'gallery',
          icon: Icons.photo_library_rounded,
          label: 'Галерея',
          color: Color(0xFFE05A8B),
        ),
      ],
    );
    await tester.pumpWidget(harness);

    await tester.tap(find.text('Открыть пикер'));
    await tester.pumpAndSettle();
    expect(find.text('Галерея'), findsOneWidget);

    // Tap above the sheet to dismiss via barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Галерея'), findsNothing);
    expect(_PickerHarnessState.lastResult, isNull);
    expect(_PickerHarnessState.invocationCount, greaterThan(0));
  });

  testWidgets('omits the title row when title is empty', (tester) async {
    await tester.pumpWidget(
      _PickerHarness(
        actions: const [
          AttachmentPickerAction(
            id: 'gallery',
            icon: Icons.photo_library_rounded,
            label: 'Галерея',
            color: Color(0xFFE05A8B),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Открыть пикер'));
    await tester.pumpAndSettle();

    // No title means no uppercase header above the grid.
    expect(find.text('ПРИКРЕПИТЬ'), findsNothing);
    expect(find.text('Галерея'), findsOneWidget);
  });
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness({required this.actions, this.title});

  final List<AttachmentPickerAction> actions;
  final String? title;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  static String? lastResult;
  static int invocationCount = 0;

  @override
  void initState() {
    super.initState();
    lastResult = null;
    invocationCount = 0;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                invocationCount += 1;
                lastResult = await showAttachmentPickerSheet(
                  context,
                  actions: widget.actions,
                  title: widget.title,
                );
              },
              child: const Text('Открыть пикер'),
            ),
          ),
        ),
      ),
    );
  }
}
