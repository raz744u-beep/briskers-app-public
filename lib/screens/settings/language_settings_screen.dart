import 'package:flutter/material.dart';

import '../../core/briskers_i18n.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BriskersLanguageController.instance;

    Widget languageTile({
      required String code,
      required String title,
      required String subtitle,
    }) {
      final selected = controller.code == code;
      return Card(
        child: ListTile(
          leading: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: () => controller.setLanguage(code),
        ),
      );
    }

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
            languageTile(
              code: 'en',
              title: tr('english'),
              subtitle: 'English',
            ),
            const SizedBox(height: 8),
            languageTile(
              code: 'es',
              title: tr('spanish'),
              subtitle: 'Español',
            ),
          ],
        ),
      ),
    );
  }
}
