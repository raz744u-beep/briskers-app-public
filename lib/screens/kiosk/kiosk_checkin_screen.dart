import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../services/appointment_sync_service.dart';
import '../../services/kiosk_registration_service.dart';
import '../../services/local_appointment_repository.dart';
import '../../widgets/briskers_page_header.dart';

class KioskCheckInScreen extends StatefulWidget {
  const KioskCheckInScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  final String businessId;
  final String businessName;

  @override
  State<KioskCheckInScreen> createState() =>
      _KioskCheckInScreenState();
}

class _KioskCheckInScreenState
    extends State<KioskCheckInScreen> {
  final AppointmentSyncService _sync = AppointmentSyncService();
  final LocalAppointmentRepository _appointments =
      LocalAppointmentRepository();
  final KioskRegistrationService _registrations =
      KioskRegistrationService();

  final TextEditingController _phone = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _newPhone = TextEditingController();
  final TextEditingController _newEmail = TextEditingController();
  final TextEditingController _vehicleYear = TextEditingController();
  final TextEditingController _vehicleMake = TextEditingController();
  final TextEditingController _vehicleModel = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  Timer? _privacyResetTimer;
  List<Map<String, dynamic>> _matches = const [];
  Map<String, dynamic>? _selected;
  bool _busy = false;
  bool _online = false;
  bool _completed = false;
  bool _completedOnline = false;
  bool _completedWalkIn = false;
  bool _newCustomerMode = false;
  bool _createOnlineAccount = false;
  bool _acceptedDisclaimer = false;
  Map<String, dynamic>? _disclaimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCache());
  }

  @override
  void dispose() {
    _privacyResetTimer?.cancel();
    _phone.dispose();
    _newName.dispose();
    _newPhone.dispose();
    _newEmail.dispose();
    _vehicleYear.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _refreshCache() async {
    try {
      await _registrations.flush(widget.businessId);
    } catch (_) {
      // Pending walk-ins remain queued for the next reconnect.
    }

    try {
      await _sync.flush(widget.businessId);
      await _sync.pull(widget.businessId);
      final disclaimer =
          await _registrations.refreshSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _online = true;
        _disclaimer = disclaimer;
      });
    } catch (_) {
      final disclaimer =
          await _registrations.loadDisclaimer(widget.businessId);
      if (!mounted) return;
      setState(() {
        _online = false;
        _disclaimer = disclaimer;
      });
    }
  }

  bool _sameLocalDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year &&
        x.month == y.month &&
        x.day == y.day;
  }

  Future<void> _findAppointment() async {
    final digits = digitsOnly(_phone.text);
    if (digits.length != 10) {
      setState(() {
        _error = 'Please enter the 10-digit phone number on your appointment.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _matches = const [];
      _selected = null;
    });

    try {
      var matches = await _appointments.appointmentsForPhone(
        widget.businessId,
        digits,
      );

      if (matches.isEmpty) {
        try {
          await _sync.flush(widget.businessId);
          await _sync.pull(widget.businessId);
          _online = true;
          matches = await _appointments.appointmentsForPhone(
            widget.businessId,
            digits,
          );
        } catch (_) {
          _online = false;
        }
      }

      final today = DateTime.now();
      matches = matches.where((appointment) {
        final start = DateTime.tryParse(
          appointment['starts_at']?.toString() ?? '',
        );
        return start != null && _sameLocalDay(start, today);
      }).toList();

      if (!mounted) return;

      if (matches.isEmpty) {
        setState(() {
          _matches = const [];
          _error =
              'We could not find a check-in appointment for that phone number today. Please see the front desk for help.';
        });
        return;
      }

      setState(() {
        _matches = matches;
        _selected = matches.length == 1 ? matches.first : null;
        _error = null;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _checkIn() async {
    final appointment = _selected;
    if (appointment == null || _busy) return;

    final syncState =
        appointment['sync_state']?.toString() ?? 'synced';

    if (syncState == 'conflict') {
      setState(() {
        _error =
            'This appointment changed and needs staff assistance. Please see the front desk.';
      });
      return;
    }

    if (syncState == 'pending') {
      _showCompletion(online: false);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    var completedOnline = false;

    try {
      await _sync.queueCheckIn(
        widget.businessId,
        appointment['id'].toString(),
      );

      try {
        final applied = await _sync.flush(widget.businessId);
        completedOnline =
            (applied[appointment['id'].toString()] ?? '').isNotEmpty;
        await _sync.pull(widget.businessId);
        _online = true;
      } catch (_) {
        _online = false;
      }

      if (!mounted) return;
      _showCompletion(online: completedOnline);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showCompletion({
    required bool online,
    bool walkIn = false,
  }) {
    _privacyResetTimer?.cancel();
    setState(() {
      _completed = true;
      _completedOnline = online;
      _completedWalkIn = walkIn;
      _error = null;
    });

    _privacyResetTimer = Timer(
      const Duration(seconds: 15),
      _reset,
    );
  }

  void _reset() {
    _privacyResetTimer?.cancel();
    _phone.clear();
    _newName.clear();
    _newPhone.clear();
    _newEmail.clear();
    _vehicleYear.clear();
    _vehicleMake.clear();
    _vehicleModel.clear();
    _reason.clear();

    if (!mounted) return;
    setState(() {
      _matches = const [];
      _selected = null;
      _completed = false;
      _completedOnline = false;
      _completedWalkIn = false;
      _newCustomerMode = false;
      _createOnlineAccount = false;
      _acceptedDisclaimer = false;
      _error = null;
    });
  }

  String _appointmentTime(Map<String, dynamic> appointment) {
    final date = DateTime.tryParse(
      appointment['starts_at']?.toString() ?? '',
    );
    if (date == null) return '';
    return DateFormat('h:mm a').format(date.toLocal());
  }

  String _vehicleLabel(Map<String, dynamic> appointment) {
    final direct = appointment['vehicle']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    return <String>[
      if (appointment['vehicle_year'] != null)
        appointment['vehicle_year'].toString(),
      appointment['vehicle_make']?.toString().trim() ?? '',
      appointment['vehicle_model']?.toString().trim() ?? '',
    ].where((value) => value.isNotEmpty).join(' ');
  }

  Widget _statusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: (_online ? Colors.green : Colors.orange)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _online
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            size: 17,
            color: _online ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            _online ? 'Connected' : 'Offline ready',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color:
                  _online ? Colors.green.shade700 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
          child: child,
        ),
      ),
    );
  }

  Widget _welcome() {
    return _frame(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const BriskersLogo(
            height: 82,
            maxWidth: 300,
          ),
          const SizedBox(height: 32),
          Text(
            'Customer Check-In',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter the phone number used for your appointment.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: const [
              UsPhoneTextInputFormatter(),
            ],
            onSubmitted: (_) => _findAppointment(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '504-555-1234',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton.icon(
              onPressed: _busy ? null : _findAppointment,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                      ),
                    )
                  : const Icon(Icons.arrow_forward),
              label: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            _errorCard(),
          ],
          const SizedBox(height: 24),
          Text(
            'Need help? Please see the front desk.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _matchesPage() {
    final selected = _selected;
    if (selected != null) {
      return _confirmationPage(selected);
    }

    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BriskersLogo(
            height: 60,
            maxWidth: 220,
          ),
          const SizedBox(height: 24),
          Text(
            'Choose your appointment',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'More than one appointment matches this phone number today.',
            style: TextStyle(fontSize: 17),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: _matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final appointment = _matches[index];
                final vehicle = _vehicleLabel(appointment);
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(18),
                    leading: const CircleAvatar(
                      radius: 27,
                      child: Icon(Icons.directions_car_outlined),
                    ),
                    title: Text(
                      vehicle.isEmpty ? 'Vehicle appointment' : vehicle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${_appointmentTime(appointment)}  •  '
                        '${appointment['title'] ?? 'Service appointment'}',
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 30,
                    ),
                    onTap: () {
                      setState(() => _selected = appointment);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Use a different phone number'),
          ),
        ],
      ),
    );
  }

  Widget _confirmationPage(Map<String, dynamic> appointment) {
    final vehicle = _vehicleLabel(appointment);
    final syncState =
        appointment['sync_state']?.toString() ?? 'synced';

    return _frame(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BriskersLogo(
            height: 64,
            maxWidth: 230,
          ),
          const SizedBox(height: 28),
          Text(
            'Confirm your appointment',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment['customer']?.toString() ?? 'Customer',
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 14),
                  _detailLine(
                    Icons.schedule,
                    'Appointment',
                    _appointmentTime(appointment),
                  ),
                  _detailLine(
                    Icons.directions_car_outlined,
                    'Vehicle',
                    vehicle.isEmpty ? 'Vehicle on appointment' : vehicle,
                  ),
                  _detailLine(
                    Icons.build_outlined,
                    'Service',
                    appointment['title']?.toString() ??
                        'Service appointment',
                  ),
                  if ((appointment['description']
                              ?.toString()
                              .trim() ??
                          '')
                      .isNotEmpty)
                    _detailLine(
                      Icons.notes_outlined,
                      'Notes',
                      appointment['description'].toString(),
                    ),
                ],
              ),
            ),
          ),
          if (syncState == 'pending') ...[
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This check-in is already saved on this device and is waiting to sync.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorCard(),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              onPressed: _busy ? null : _checkIn,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                      ),
                    )
                  : const Icon(Icons.login),
              label: Text(
                syncState == 'pending'
                    ? 'Done'
                    : 'Check In',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _selected = null);
                  },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _completionPage() {
    return _frame(
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 92,
          ),
          const SizedBox(height: 24),
          Text(
            'You’re checked in!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            _completedOnline
                ? 'The shop has received your check-in.'
                : 'Your check-in is safely saved on this device and will be sent to the shop automatically when the connection returns.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          const Text(
            'Please leave your keys with the front desk.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 34),
          SizedBox(
            width: 320,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Start another check-in'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This screen will reset automatically.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .errorContainer
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_completed) {
      body = _completionPage();
    } else if (_matches.isNotEmpty || _selected != null) {
      body = _matchesPage();
    } else {
      body = _welcome();
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    _statusChip(),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
