import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BriskersLanguageController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('language'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.translate),
                title: Text(
                  tr('languageTest'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(tr('languageTestBody')),
              ),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              value: 'en',
              groupValue: controller.code,
              title: Text(tr('english')),
              subtitle: const Text('English'),
              onChanged: (value) {
                if (value != null) controller.setLanguage(value);
              },
            ),
            RadioListTile<String>(
              value: 'es',
              groupValue: controller.code,
              title: Text(tr('spanish')),
              subtitle: const Text('Español'),
              onChanged: (value) {
                if (value != null) controller.setLanguage(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
