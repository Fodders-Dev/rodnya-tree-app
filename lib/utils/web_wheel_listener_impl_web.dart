// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'web_wheel_listener.dart';

CancelWebWheelListener? registerWebWheelListener(WebWheelHandler handler) {
  void onWheel(html.Event event) {
    if (event is html.WheelEvent) {
      handler(
        event.deltaX.toDouble(),
        event.deltaY.toDouble(),
        event.client.x.toDouble(),
        event.client.y.toDouble(),
      );
    }
  }

  html.document.addEventListener('wheel', onWheel, true);
  html.window.addEventListener('wheel', onWheel, true);
  return () {
    html.document.removeEventListener('wheel', onWheel, true);
    html.window.removeEventListener('wheel', onWheel, true);
  };
}
