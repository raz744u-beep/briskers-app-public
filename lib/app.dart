import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/briskers_i18n.dart';

import 'screens/auth_gate.dart';
import 'core/supabase_config.dart';
import 'widgets/auth_visibility_shield.dart';

class BriskersApp extends StatefulWidget {
  const BriskersApp({super.key});
  @override
  State<BriskersApp> createState() => _BriskersAppState();
}

class _BriskersAppState extends State<BriskersApp> {
  var _authNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.light,
    );

    return AnimatedBuilder(
      animation: BriskersLanguageController.instance,
      builder: (context, _) => MaterialApp(
      navigatorKey: _authNavigatorKey,
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
          child: AuthVisibilityShield(
            actorId: () => supabase.auth.currentUser?.id,
            actorChanges: supabase.auth.onAuthStateChange.map((event) => event.session?.user.id),
            closePreviousScreens: () => setState(() { _authNavigatorKey = GlobalKey<NavigatorState>(); }),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      theme: ThemeData(
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
      ),
      home: const AuthGate(),
      ),
    );
  }
}

