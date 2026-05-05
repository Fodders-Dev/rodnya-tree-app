import 'package:flutter/material.dart';

/// Wraps a form-shaped subtree so tapping outside any TextField
/// dismisses the on-screen keyboard.
///
/// On Android the standard dismiss path is the system back button,
/// which works but is awkward inside a long form — users tap on
/// blank canvas expecting the keyboard to retract (the iOS / TG
/// pattern). This widget provides that gesture without affecting
/// any focusable tappable inside the form: child taps that hit
/// real handlers (buttons, fields, etc.) still fire normally
/// because we use `behavior: HitTestBehavior.translucent` and
/// only fire `unfocus` when the tap actually misses every focused
/// field's hit area.
///
/// Drop it as the outermost widget of a Scaffold body, or wrap
/// just the form region. Cheap — just a GestureDetector + a
/// FocusScope.unfocus call.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Translucent so the tap also reaches buttons / fields below
      // — only "empty" canvas taps trigger the unfocus. The Flutter
      // gesture system fires onTap last (after the inner widgets
      // have had a chance to claim the gesture), so this never
      // steals from real interactive widgets.
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final scope = FocusScope.of(context);
        if (scope.hasPrimaryFocus || scope.focusedChild != null) {
          scope.unfocus();
        }
      },
      child: child,
    );
  }
}
