import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;

/// Shared semantic styling for every confirmation and action sheet in a module.
/// This affects presentation only; callers retain their guards and callbacks.
ThemeData moduleModalTheme(ThemeData base, Color accent) {
  final surface = base.brightness == Brightness.dark
      ? const Color(0xFF202124)
      : Colors.white;
  final foreground = base.brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF202124);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: foreground,
      surfaceTint: Colors.transparent,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: foreground),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: accent),
    ),
  );
}

mixin ModuleModalState<W extends StatefulWidget> on State<W> {
  Color get modalAccent;

  Future<R?> showDialog<R>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    bool useSafeArea = true,
    bool useRootNavigator = true,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
    TraversalEdgeBehavior? traversalEdgeBehavior,
    bool fullscreenDialog = false,
    bool? requestFocus,
    AnimationStyle? animationStyle,
  }) {
    final theme = moduleModalTheme(Theme.of(context), modalAccent);
    return material.showDialog<R>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: Builder(builder: builder),
      ),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: traversalEdgeBehavior,
      fullscreenDialog: fullscreenDialog,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
    );
  }

  Future<R?> showModalBottomSheet<R>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    String? barrierLabel,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    Color? barrierColor,
    bool isScrollControlled = false,
    double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
    bool useRootNavigator = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool? showDragHandle,
    bool useSafeArea = false,
    RouteSettings? routeSettings,
    AnimationController? transitionAnimationController,
    Offset? anchorPoint,
    AnimationStyle? sheetAnimationStyle,
    bool? requestFocus,
  }) {
    final theme = moduleModalTheme(Theme.of(context), modalAccent);
    return material.showModalBottomSheet<R>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: Builder(builder: builder),
      ),
      // Transparent surfaces are intentional for custom shaped sheets.
      backgroundColor: backgroundColor == Colors.transparent
          ? Colors.transparent
          : theme.colorScheme.surface,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      sheetAnimationStyle: sheetAnimationStyle,
      requestFocus: requestFocus,
    );
  }
}

/// For shared dialog functions that are not owned by a screen State.
Future<R?> showModuleDialog<R>({
  required BuildContext context,
  required Color accent,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => material.showDialog<R>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (_) => Theme(
    data: moduleModalTheme(Theme.of(context), accent),
    child: Builder(builder: builder),
  ),
);
