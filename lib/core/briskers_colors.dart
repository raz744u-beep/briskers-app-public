import 'package:flutter/material.dart';

class BriskersColors {
  const BriskersColors._();

  static const blueHeader = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF31A9D9), Color(0xFF2075BC), Color(0xFF174B92)],
  );
  static const confirm = Color(0xFF008F83);
  static const destructive = Color(0xFFB91C1C);

  // Main navigation.
  static const today = Color(0xFF3949AB);
  static const actionBlue = Color(0xFF3B82F6);
  static const customers = actionBlue;
  // Approved darker blue for Customer and Vehicle save actions; do not use
  // Material's generic primary color for these forms.
  static const customerSave = Color(0xFF18529A);
  static const schedule = appointments;
  static const jobs = Color(0xFF00897B);
  static const more = Color(0xFF607D8B);

  // Permanent workflow colors used throughout Briskers.
  static const appointments = Color(0xFF1976D2);
  static const estimates = Color(0xFF7E57C2);
  static const invoices = Color(0xFF2E7D32);
  static const vehicles = Color(0xFFEF6C00);
  static const notes = Color(0xFFD99A00);

  static const expenses = Color(0xFFEF4444);
  static const reports = Color(0xFF3949AB);
  static const chat = Color(0xFF00838F);
  static const settings = Color(0xFF5E35B1);
}
