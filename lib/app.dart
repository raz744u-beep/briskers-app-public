import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/briskers_i18n.dart';

import 'screens/auth_gate.dart';

class BriskersApp extends StatelessWidget {
  const BriskersApp({super.key});

  static ThemeData get applicationTheme {
    final scheme=ColorScheme.fromSeed(seedColor:const Color(0xFF3B82F6),brightness:Brightness.light);
    return ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        fontFamily: 'Roboto',
        typography: Typography.material2021(
          platform: TargetPlatform.android,
          colorScheme: scheme,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BriskersLanguageController.instance,
      builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Briskers',
      locale: BriskersLanguageController.instance.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.noScaling),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: applicationTheme,
      home: const AuthGate(),
      ),
    );
  }
}
