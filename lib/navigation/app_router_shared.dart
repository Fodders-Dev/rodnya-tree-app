import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Widget buildDesktopConstrainedScreen(Widget child) {
  return Builder(
    builder: (context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ClipRect(child: child),
        ),
      ),
    ),
  );
}

class RodnyaCustomTransitionPage<T> extends CustomTransitionPage<T> {
  RodnyaCustomTransitionPage({
    required Widget child,
    required super.transitionsBuilder,
    bool constrainWidth = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    super.transitionDuration = const Duration(milliseconds: 300),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
  }) : super(
          child: constrainWidth ? buildDesktopConstrainedScreen(child) : child,
          maintainState: true,
        );
}

class RodnyaNoTransitionPage<T> extends RodnyaCustomTransitionPage<T> {
  RodnyaNoTransitionPage({required super.child, super.key})
      : super(
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
}

class AppRouteTransitions {
  const AppRouteTransitions._();

  static Widget fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget slide(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;

    final tween = Tween(begin: begin, end: end).chain(
      CurveTween(curve: curve),
    );
    return SlideTransition(
      position: animation.drive(tween),
      child: child,
    );
  }

  static Widget slideUp(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;

    final tween = Tween(begin: begin, end: end).chain(
      CurveTween(curve: curve),
    );
    return SlideTransition(
      position: animation.drive(tween),
      child: child,
    );
  }
}

class E2EIdleScreen extends StatelessWidget {
  const E2EIdleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.expand(),
    );
  }
}

class StoryViewerRouteFallback extends StatelessWidget {
  const StoryViewerRouteFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'История недоступна',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
