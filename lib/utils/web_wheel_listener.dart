import 'web_wheel_listener_impl_stub.dart'
    if (dart.library.html) 'web_wheel_listener_impl_web.dart' as impl;

typedef WebWheelHandler = bool Function(
  double deltaX,
  double deltaY,
  double clientX,
  double clientY,
);
typedef CancelWebWheelListener = void Function();

CancelWebWheelListener? registerWebWheelListener(WebWheelHandler handler) {
  return impl.registerWebWheelListener(handler);
}
