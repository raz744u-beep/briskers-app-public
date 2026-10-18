import 'dart:async';
import 'package:flutter/material.dart';

final authVisibilityEpoch = ValueNotifier<int>(0);

/// Covers the root Navigator, including editors pushed above the auth gate.
/// Hiding does not dispose a draft. Closing previous screens is explicit.
class AuthVisibilityShield extends StatefulWidget {
  const AuthVisibilityShield({super.key, required this.actorId,
    required this.actorChanges, required this.closePreviousScreens, required this.child});
  final String? Function() actorId;
  final Stream<String?> actorChanges;
  final VoidCallback closePreviousScreens;
  final Widget child;
  @override
  State<AuthVisibilityShield> createState() => _AuthVisibilityShieldState();
}

class _AuthVisibilityShieldState extends State<AuthVisibilityShield> {
  StreamSubscription<String?>? _subscription;
  String? _visibleActor;
  bool _locked = false;
  bool _accessChanged = false;
  @override
  void initState() {
    super.initState();
    _visibleActor = widget.actorId();
    authVisibilityEpoch.addListener(_knownAccessChanged);
    _subscription = widget.actorChanges.listen((actor) {
      if (!mounted) return;
      setState(() {
        if (_visibleActor == null && !_locked) {
          _visibleActor = actor;
        } else if (actor != _visibleActor) {
          // A changed identity remains locked even if a later auth event
          // switches back to the original account. Never restore a stale
          // editor route without an explicit Navigator replacement.
          _locked = true;
        }
      });
    });
  }
  void _knownAccessChanged() {
    if (mounted) { setState(() { _accessChanged = true; _locked = true; }); }
  }
  @override
  void dispose() {
    authVisibilityEpoch.removeListener(_knownAccessChanged);
    _subscription?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final locked = _locked || _accessChanged ||
        (_visibleActor != null && widget.actorId() != _visibleActor);
    return Stack(children: [
      Offstage(offstage: locked, child: TickerMode(enabled: !locked, child: widget.child)),
      if (locked) Positioned.fill(child: Material(color: Colors.white,
        child: Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Your account changed. Previous shop screens are hidden.'),
            const SizedBox(height: 12),
            const Text('Close previous screens to continue. Unsaved screen edits will be discarded; saved offline work is kept.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () {
              widget.closePreviousScreens();
              setState(() { _visibleActor = widget.actorId(); _locked = false; _accessChanged = false; });
            }, child: const Text('Close previous screens')),
          ]))))),
    ]);
  }
}
