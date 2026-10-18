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
    final node = FocusManager.instance.primaryFocus;
    // A route's FocusScope is itself a focus node. Scanning all of its
    // descendants reports any TextField as "editing", even when none is
    // focused, and incorrectly removes the dock and shrinks the viewport.
    if (node == null || node is FocusScopeNode) return false;

    final focused = node.context;
    if (focused == null || !focused.mounted) return false;
    if (focused.widget is EditableText ||
        focused.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }

    // TextField can attach its FocusNode to a Focus widget above its
    // EditableText. Only inspect the actual *primary* focused subtree,
    // never the enclosing route-wide FocusScope.
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
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusManagerChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusManagerChanged);
    super.dispose();
  }

  void _recheckAfterFrame() {
    // During focus handoff the new focused EditableText's Element may not
    // be attached until the next frame. Recheck after the handoff rather
    // than locking in the old (zeroed) MediaQuery for the rest of the route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onFocusManagerChanged() {
    if (!mounted) return;
    setState(() {});
    _recheckAfterFrame();
  }

  void _onDescendantFocusChange(bool _) => _recheckAfterFrame();

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onDescendantFocusChange,
      child: Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          final insets = media.viewInsets;
          final shouldRecoverInset = insets.bottom > 0 &&
              !StaleKeyboardInsetGuard.editableTextHasFocus;
          assert(() {
            if (insets.bottom > 0) {
              debugPrint('IME-GUARD-BUILD raw=${insets.bottom} focused=${StaleKeyboardInsetGuard.editableTextHasFocus} recover=$shouldRecoverInset');
            }
            return true;
          }());
          // Retain a stable inherited MediaQuery element in both states.
          return MediaQuery(
            data: shouldRecoverInset
                ? media.copyWith(
                    viewInsets: EdgeInsets.fromLTRB(
                      insets.left, insets.top, insets.right, 0,
                    ),
                  )
                : media,
            child: widget.child,
          );
        },
      ),
    );
  }
}
