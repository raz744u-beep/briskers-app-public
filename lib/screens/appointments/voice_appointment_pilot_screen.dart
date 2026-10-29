import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/briskers_colors.dart';
import '../../services/appointment_sync_service.dart';
import '../../services/local_appointment_repository.dart';
import '../../services/local_customer_repository.dart';
import '../../services/voice_appointment_command.dart';

/// Android/iOS proof of concept: one tap from Appointments opens this screen,
/// starts recognition, reads the draft aloud, and accepts "confirm" or "cancel".
/// Never changes shop data without unambiguous customer/date/time and confirmation.
class VoiceAppointmentPilotScreen extends StatefulWidget {
  const VoiceAppointmentPilotScreen({super.key, required this.businessId});

  final String businessId;

  @override
  State<VoiceAppointmentPilotScreen> createState() =>
      _VoiceAppointmentPilotScreenState();
}

class _VoiceAppointmentPilotScreenState
    extends State<VoiceAppointmentPilotScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final LocalCustomerRepository _customers = LocalCustomerRepository();
  final LocalAppointmentRepository _appointments = LocalAppointmentRepository();
  final AppointmentSyncService _sync = AppointmentSyncService();

  String _heard = '';
  String _message = 'Preparing microphone...';
  bool _initialized = false;
  bool _listening = false;
  bool _handled = false;
  bool _confirming = false;
  bool _saving = false;
  VoiceAppointmentCommand? _draft;
  Map<String, dynamic>? _customer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.awaitSpeakCompletion(true);
      final available = await _speech.initialize(
        onStatus: _speechStatus,
        onError: (error) {
          if (!mounted || _handled) return;
          setState(() {
            _listening = false;
            _message = 'Microphone error. Try again when safe.';
          });
        },
      );
      if (!mounted) return;
      if (!available) {
        setState(() {
          _message = 'Speech recognition is unavailable on this phone.';
        });
        return;
      }
      _initialized = true;
      await _listen();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not initialize voice. Check microphone permissions.';
      });
    }
  }

  Future<void> _listen() async {
    if (!mounted || !_initialized || _saving) return;
    _handled = false;
    _heard = '';
    setState(() {
      _listening = true;
      _message = _confirming
          ? 'Listening for CONFIRM or CANCEL...'
          : 'Listening. Say the customer, date, time and service.';
    });
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || _handled) return;
          _heard = result.recognizedWords;
          setState(() {});
          if (result.finalResult) {
            unawaited(_processWords());
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 25),
          listenMode: ListenMode.confirmation,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _message = 'Listening failed. Please try again.';
      });
    }
  }

  void _speechStatus(String status) {
    if (!mounted || !_listening || _handled) return;
    if (status == 'done' || status == 'notListening') {
      setState(() => _listening = false);
      // Some recognizers finish without a finalResult callback.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted || _handled) return;
        if (_heard.trim().isEmpty) {
          setState(() => _message = 'Nothing heard. Try again.');
        } else {
          unawaited(_processWords());
        }
      });
    }
  }

  Future<void> _say(String words, {bool listenAgain = false}) async {
    if (!mounted) return;
    setState(() {
      _message = words;
      _listening = false;
    });
    try {
      await _tts.speak(words);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message =
          'Voice playback unavailable. Use the on-screen controls when parked.');
      return;
    }
    if (listenAgain && mounted) await _listen();
  }

  Future<void> _processWords() async {
    if (_handled || !mounted) return;
    _handled = true;
    _listening = false;
    await _speech.stop();
    if (!mounted) return;
    final words = _heard.trim();

    if (_confirming) {
      final reply = VoiceAppointmentCommand.normalized(words);
      if (<String>{'yes', 'confirm', 'confirmed', 'save', 'save it',
        'book it', 'confirm appointment'}.contains(reply)) {
        await _save();
      } else if (<String>{'no', 'cancel', 'cancel it', 'stop'}.contains(reply)) {
        _confirming = false;
        _draft = null;
        _customer = null;
        await _say('Cancelled. No appointment was created.');
        if (mounted) Navigator.of(context).pop(false);
      } else {
        await _say('Please say confirm to save, or cancel.', listenAgain: true);
      }
      return;
    }

    final draft = VoiceAppointmentCommand.parse(words);
    if (draft == null) {
      await _say(
        'I could not understand the date and time. Please try again, '
        'and say something like Wednesday at 10 A M.',
        listenAgain: true,
      );
      return;
    }

    try {
      // Do not guess a customer or fall back to just the first matching name.
      // Matching local records keeps this usable without an internet connection.
      final all = await _customers.customers(widget.businessId);
      final transcript = ' ${VoiceAppointmentCommand.normalized(words)} ';
      final matches = all.where((customer) {
        final name = VoiceAppointmentCommand.normalized(
          customer['display_name']?.toString() ?? '',
        );
        if (name.isEmpty) return false;
        if (transcript.contains(' $name ')) return true;
        final parts = name.split(' ');
        if (parts.length < 2) return false;
        final firstLast = '${parts.first} ${parts.last}';
        return transcript.contains(' $firstLast ');
      }).toList();

      if (!mounted) return;
      if (matches.length != 1) {
        await _say(
          matches.isEmpty
              ? 'I could not find that customer in the saved customer list. '
                  'Please repeat the command with the full customer name.'
              : 'More than one customer matches. '
                  'Please repeat the command with the full customer name.',
          listenAgain: true,
        );
        return;
      }

      final customer = matches.single;
      final customerId = customer['id']?.toString() ?? '';
      if (customerId.isEmpty) throw StateError('Customer has no ID.');
      final existing = await _appointments.appointments(
        widget.businessId, filter: 'all',
      );
      for (final item in existing) {
        if (item['customer_id']?.toString() != customerId) continue;
        if (item['status']?.toString() == 'cancelled') continue;
        final existingStart = DateTime.tryParse(
          item['starts_at']?.toString() ?? '',
        )?.toLocal();
        if (existingStart != null &&
            existingStart.difference(draft.startsAt).inMinutes.abs() < 1) {
          await _say(
            'This customer already has an appointment at that time. '
            'Nothing new was saved.',
          );
          return;
        }
      }

      _draft = draft;
      _customer = customer;
      _confirming = true;
      final name = customer['display_name']?.toString() ?? 'Customer';
      var service = draft.service;
      if (VoiceAppointmentCommand.normalized(service).contains(
          VoiceAppointmentCommand.normalized(name))) {
        service = 'Service appointment';
      }
      final when = DateFormat('EEEE, MMMM d, at h:mm a')
          .format(draft.startsAt);
      await _say(
        'Schedule $name on $when. '
        'Reason: $service. '
        'No vehicle or mechanic is selected. '
        'Say confirm to save this appointment, or cancel.',
        listenAgain: true,
      );
    } catch (_) {
      if (!mounted) return;
      await _say(
        'Could not access saved customers or appointments. '
        'Nothing was saved. Please retry when safe.',
      );
    }
  }

  Future<void> _save() async {
    if (_saving || !_confirming || _draft == null || _customer == null) return;
    final draft = _draft!;
    final customerId = _customer!['id']?.toString() ?? '';
    if (customerId.isEmpty) return;
    setState(() {
      _saving = true;
      _message = 'Saving to Briskers...';
    });
    try {
      var reason = draft.service;
      final name = VoiceAppointmentCommand.normalized(
        _customer!['display_name']?.toString() ?? '',
      );
      if (VoiceAppointmentCommand.normalized(reason).contains(name)) {
        reason = 'Service appointment';
      }
      await _sync.queueCreate(
        widget.businessId,
        customerId: customerId,
        title: reason,
        description: reason == 'Service appointment' ? null : reason,
        startsAt: draft.startsAt,
        endsAt: draft.startsAt.add(const Duration(hours: 1)),
      );
      if (!mounted) return;
      await _say('Appointment saved on this device. '
          'It will synchronize when Briskers is online.');
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      _confirming = false;
      await _say('Could not save the appointment. Nothing new was confirmed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Briskers Voice · Appointments'),
        backgroundColor: BriskersColors.appointments.withValues(alpha: .10),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _listening ? Icons.mic : Icons.mic_none,
                size: 88,
                color: BriskersColors.appointments,
              ),
              const SizedBox(height: 18),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_heard.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Heard: $_heard', textAlign: TextAlign.center),
              ],
              if (draft != null && _customer != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(_customer!['display_name']?.toString() ?? ''),
                    subtitle: Text(
                      '${DateFormat('EEE, MMM d · h:mm a').format(draft.startsAt)}\n${draft.service}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_confirming)
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Confirm appointment'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _saving ? null : () async {
                    _confirming = false;
                    _draft = null;
                    _customer = null;
                    if (!_initialized) {
                      await _begin();
                    } else {
                      await _listen();
                    }
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Try again'),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
