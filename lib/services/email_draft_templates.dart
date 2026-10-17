import 'package:shared_preferences/shared_preferences.dart';

/// Local business-scoped Gmail draft templates. The Gmail compose screen
/// remains editable; this only controls the initial draft content.
class EmailDraftTemplates {
  const EmailDraftTemplates({required this.subject, required this.body});

  static const defaultSubject =
      '{type} #{number} - Briskers Foreign Car Repair';
  static const defaultBody =
      'Please find the attached {typeLower} from Briskers Foreign Car Repair.';

  final String subject;
  final String body;

  static String _key(String businessId, String suffix) =>
      'email_draft_template.$businessId.$suffix';

  static Future<EmailDraftTemplates> load(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return EmailDraftTemplates(
      subject: prefs.getString(_key(businessId, 'subject')) ?? defaultSubject,
      body: prefs.getString(_key(businessId, 'body')) ?? defaultBody,
    );
  }

  Future<void> save(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId, 'subject'), subject);
    await prefs.setString(_key(businessId, 'body'), body);
  }

  String render(String template, {required bool estimate, required String number}) {
    final kind = estimate ? 'Estimate' : 'Invoice';
    return template
        .replaceAll('{type}', kind)
        .replaceAll('{typeLower}', kind.toLowerCase())
        .replaceAll('{number}', number);
  }
}
