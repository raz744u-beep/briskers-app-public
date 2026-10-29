import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/voice_appointment_command.dart';

void main() {
  final now = DateTime(2026, 10, 29, 16, 0); // Thursday

  test('Upcoming Wednesday at ten means Nov 4 at 10 AM', () {
    final command = VoiceAppointmentCommand.parse(
      "schedule Larry Carter for an oil change next Wednesday at 10 o'clock",
      now: now,
    );
    expect(command, isNotNull);
    expect(command!.startsAt, DateTime(2026, 11, 4, 10));
    expect(command.service, 'Oil change');
  });

  test('Spoken ten am is recognized', () {
    final command = VoiceAppointmentCommand.parse(
      'schedule Larry Carter next Wednesday at ten am for oil change',
      now: now,
    );
    expect(command?.startsAt, DateTime(2026, 11, 4, 10));
    expect(command?.service, 'Oil change');
  });

  test('Tomorrow and half-hour time are recognized', () {
    final command = VoiceAppointmentCommand.parse(
      'schedule Larry Carter tomorrow at 9:30 am',
      now: now,
    );
    expect(command?.startsAt, DateTime(2026, 10, 30, 9, 30));
    expect(
      VoiceAppointmentCommand.parse(
        'schedule Larry Carter tomorrow at nine thirty am', now: now,
      )?.startsAt,
      DateTime(2026, 10, 30, 9, 30),
    );
  });

  test('Afternoon time is recognized', () {
    final command = VoiceAppointmentCommand.parse(
      'book next Wednesday at 2 pm',
      now: now,
    );
    expect(command?.startsAt, DateTime(2026, 11, 4, 14));
  });

  test('Month and day are recognized', () {
    final command = VoiceAppointmentCommand.parse(
      'November 4th at 10 am',
      now: now,
    );
    expect(command?.startsAt, DateTime(2026, 11, 4, 10));
  });

  test('No guessed time or date', () {
    expect(
      VoiceAppointmentCommand.parse('schedule next Wednesday', now: now),
      isNull,
    );
    expect(
      VoiceAppointmentCommand.parse('schedule Larry at 10', now: now),
      isNull,
    );
  });

  test('Past appointments must not be created', () {
    expect(
      VoiceAppointmentCommand.parse('schedule today at 10 am', now: now),
      isNull,
    );
  });
}
