import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/controllers/chat_selection_controller.dart';

void main() {
  test('tracks remote and outgoing selections', () {
    final controller = ChatSelectionController();
    addTearDown(controller.dispose);

    expect(controller.isSelectionMode, isFalse);
    expect(controller.selectedMessageCount, 0);

    controller.selectRemote('remote-1');
    controller.selectOutgoing('local-1');

    expect(controller.isSelectionMode, isTrue);
    expect(controller.selectedMessageCount, 2);
    expect(controller.isRemoteSelected('remote-1'), isTrue);
    expect(controller.isOutgoingSelected('local-1'), isTrue);

    controller.toggleRemote('remote-1');
    controller.toggleOutgoing('local-2');

    expect(controller.selectedMessageCount, 2);
    expect(controller.isRemoteSelected('remote-1'), isFalse);
    expect(controller.isOutgoingSelected('local-1'), isTrue);
    expect(controller.isOutgoingSelected('local-2'), isTrue);

    controller.clear();

    expect(controller.isSelectionMode, isFalse);
    expect(controller.selectedMessageCount, 0);
  });

  test('notifies only when selection state changes', () {
    final controller = ChatSelectionController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    controller.clear();
    controller.selectRemote('remote-1');
    controller.selectRemote('remote-1');
    controller.toggleRemote('remote-1');
    controller.clear();

    expect(notifications, 2);
  });
}
