import 'package:flutter/material.dart';

/// Helps keep Flutter routes usable when an Android device reports an old
/// keyboard inset after the text field has already lost focus.
///
/// A real, focused EditableText still gets the normal viewInsets and
/// Scaffold keyboard-resizing behavior. No platform settings or records
/// are mutated.
class StaleKeyboardInsetGuard extends StatelessWidget {
  const StaleKeyboardInsetGuard({super.key, required this.child});

  final Widget child;

  static bool get editableTextHasFocus {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorStateOfType<EditableTextState>() != null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FocusManager.instance,
      child: child,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final insets = media.viewInsets;
        if (insets.bottom <= 0 || editableTextHasFocus) {
          return child!;
        }
        return MediaQuery(
          data: media.copyWith(
            viewInsets: EdgeInsets.fromLTRB(
              insets.left,
              insets.top,
              insets.right,
              0,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
