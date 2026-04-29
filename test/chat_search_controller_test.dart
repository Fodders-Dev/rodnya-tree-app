import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/controllers/chat_search_controller.dart';

void main() {
  test('tracks search mode and normalized query', () {
    final controller = ChatSearchController();
    addTearDown(controller.dispose);

    expect(controller.isSearchMode, isFalse);
    expect(controller.hasQuery, isFalse);
    expect(controller.matches('Любой текст'), isTrue);

    controller.open();
    controller.textController.text = '  Привет  ';

    expect(controller.isSearchMode, isTrue);
    expect(controller.query, 'Привет');
    expect(controller.normalizedQuery, 'привет');
    expect(controller.hasQuery, isTrue);
    expect(controller.matches('Семейный привет'), isTrue);
    expect(controller.matches('Другое сообщение'), isFalse);
  });

  test('close clears query and emits one batched notification', () {
    final controller = ChatSearchController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    controller.open();
    controller.textController.text = 'поиск';
    controller.close();

    expect(controller.isSearchMode, isFalse);
    expect(controller.query, isEmpty);
    expect(notifications, 3);
  });
}
