import 'dart:async';

import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../screens/appointments/voice_appointment_pilot_screen.dart';

/// Access is registered only by a signed-in shop shell with scheduling rights.
/// The app-level overlay remains visible above nested customer/job/invoice pages.
class BriskersVoiceAccess extends ChangeNotifier {
  BriskersVoiceAccess._();

  static final BriskersVoiceAccess instance = BriskersVoiceAccess._();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Object? _owner;
  String? _businessId;
  bool _routeOpen = false;

  bool get enabled => _businessId != null && !_routeOpen;

  void register({
    required Object owner,
    required String businessId,
    required bool canManageAppointments,
  }) {
    _owner = owner;
    _businessId = canManageAppointments && businessId.isNotEmpty
        ? businessId
        : null;
    notifyListeners();
  }

  void unregister(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _businessId = null;
    notifyListeners();
  }

  Future<void> open() async {
    final businessId = _businessId;
    final navigator = navigatorKey.currentState;
    if (businessId == null || _routeOpen || navigator == null) return;
    _routeOpen = true;
    notifyListeners();
    try {
      await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => VoiceAppointmentPilotScreen(
            businessId: businessId,
          ),
        ),
      );
    } finally {
      _routeOpen = false;
      notifyListeners();
    }
  }
}

/// Sits above the root Navigator, so opening a customer/job/invoice details
/// route does not remove the one-tap microphone. Do not cover the keyboard.
class BriskersGlobalVoiceOverlay extends StatelessWidget {
  const BriskersGlobalVoiceOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Stack(
      children: [
        child,
        if (!keyboardVisible)
          Positioned(
            bottom: 86,
            left: 12,
            child: AnimatedBuilder(
              animation: BriskersVoiceAccess.instance,
              builder: (context, _) {
                if (!BriskersVoiceAccess.instance.enabled) {
                  return const SizedBox.shrink();
                }
                return FloatingActionButton.small(
                  heroTag: 'briskers-global-voice-appointment-pilot',
                  tooltip: 'Briskers voice assistant — schedule appointment',
                  backgroundColor: BriskersColors.schedule,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    unawaited(BriskersVoiceAccess.instance.open());
                  },
                  child: const Icon(Icons.mic_none_rounded),
                );
              },
            ),
          ),
      ],
    );
  }
}
