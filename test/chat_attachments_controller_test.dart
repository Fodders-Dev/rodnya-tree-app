import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/controllers/chat_attachments_controller.dart';

void main() {
  test('adds files up to the configured limit', () {
    final controller = ChatAttachmentsController(maxAttachments: 2);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    final added = controller.addAll([
      _file('one.jpg'),
      _file('two.jpg'),
      _file('three.jpg'),
    ]);

    expect(added, 2);
    expect(controller.length, 2);
    expect(controller.remainingSlots, 0);
    expect(
      controller.attachments.map((file) => file.path).toList(),
      ['/tmp/one.jpg', '/tmp/two.jpg'],
    );
    expect(notifications, 1);
  });

  test('replaces, removes and clears attachments', () {
    final controller = ChatAttachmentsController(maxAttachments: 3);
    addTearDown(controller.dispose);

    final first = _file('first.jpg');
    final second = _file('second.mp4');
    final third = _file('third.pdf');

    controller.replaceAll([first, second, third]);
    expect(controller.attachments, [first, second, third]);

    expect(controller.remove(second), isTrue);
    expect(controller.attachments, [first, third]);

    expect(controller.removeAt(0), first);
    expect(controller.attachments, [third]);

    controller.clear();
    expect(controller.isEmpty, isTrue);
  });

  test('removeWhere notifies only when the list changes', () {
    final controller = ChatAttachmentsController(maxAttachments: 3);
    addTearDown(controller.dispose);
    controller.replaceAll([
      _file('voice_note_1.m4a'),
      _file('photo.jpg'),
    ]);

    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    controller.removeWhere((file) => file.path.endsWith('.zip'));
    expect(notifications, 0);

    controller.removeWhere((file) => file.path.contains('voice_note_'));
    expect(notifications, 1);
    expect(controller.attachments.single.path, '/tmp/photo.jpg');
  });
}

XFile _file(String name) {
  return XFile('/tmp/$name', name: name);
}
