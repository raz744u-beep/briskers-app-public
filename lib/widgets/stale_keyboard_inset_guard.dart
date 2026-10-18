import 'package:flutter/material.dart';

/// Helps keep Flutter routes usable when an Android device reports an old
/// keyboard inset after the text field has already lost focus.
///
/// A real, focused EditableText still gets the normal viewInsets and
/// Scaffold keyboard-resizing behavior. No platform settings or records
/// are mutated.
class StaleKeyboardInsetGuard extends StatefulWidget {
  const StaleKeyboardInsetGuard({super.key, required this.child});

  final Widget child;

  static bool get editableTextHasFocus {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused.widget is EditableText ||
        focused.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }

    // Some Flutter TextFields attach their FocusNode to a Focus widget
    // ABOVE EditableText, so ancestor checks alone miss real keyboard focus.
    // Inspect only that focused subtree, not the whole application.
    var containsEditable = false;
    void scan(Element element) {
      if (containsEditable) return;
      if (element.widget is EditableText) {
        containsEditable = true;
        return;
      }
      element.visitChildren(scan);
    }
    scan(focused as Element);
    return containsEditable;
  }

  @override
  State<StaleKeyboardInsetGuard> createState() =>
      _StaleKeyboardInsetGuardState();
}

class _StaleKeyboardInsetGuardState extends State<StaleKeyboardInsetGuard> {
  void _onDescendantFocusChange(bool _) {
    // FocusManager may notify before its focused EditableText context is
    // ready. A Focus widget receives descendant transitions and schedules
    // a second, stable viewport computation after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onDescendantFocusChange,
      child: AnimatedBuilder(
        animation: FocusManager.instance,
        child: widget.child,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final insets = media.viewInsets;
          final shouldRecoverInset = insets.bottom > 0 &&
              !StaleKeyboardInsetGuard.editableTextHasFocus;
          // Retain a stable inherited MediaQuery element in both states.
          return MediaQuery(
            data: shouldRecoverInset
                ? media.copyWith(
                    viewInsets: EdgeInsets.fromLTRB(
                      insets.left, insets.top, insets.right, 0,
                    ),
                  )
                : media,
            child: child!,
          );
        },
      ),
    );
  }
}
