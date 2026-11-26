import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_wheel_listener.dart';

CancelWebWheelListener? registerWebWheelListener(WebWheelHandler handler) {
  void onWheel(web.Event event) {
    if (event.isA<web.WheelEvent>()) {
      final wheel = event as web.WheelEvent;
      handler(
        wheel.deltaX,
        wheel.deltaY,
        wheel.clientX.toDouble(),
        wheel.clientY.toDouble(),
      );
    }
  }

  final listener = onWheel.toJS;
  final capture = true.toJS;
  web.document.addEventListener('wheel', listener, capture);
  web.window.addEventListener('wheel', listener, capture);
  return () {
    web.document.removeEventListener('wheel', listener, capture);
    web.window.removeEventListener('wheel', listener, capture);
  };
}
