import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/briskers_i18n.dart';
import 'core/connection_mode.dart';
import 'core/supabase_config.dart';
import 'local/local_database_provider.dart';
import 'services/expenseiq_background_scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw a frame before any local database migration or plugin initialization.
  runApp(const _BriskersBootstrap());
}

class _BriskersBootstrap extends StatefulWidget {
  const _BriskersBootstrap();

  @override
  State<_BriskersBootstrap> createState() => _BriskersBootstrapState();
}

class _BriskersBootstrapState extends State<_BriskersBootstrap> {
  static const String _buildNumber = String.fromEnvironment(
    'BRISKERS_BUILD_NUMBER', defaultValue: 'unidentified');
  static const String _sourceRef = String.fromEnvironment(
    'BRISKERS_SOURCE', defaultValue: 'unidentified');
  String _step = 'Preparing startup';
  String? _failedStep;
  String? _failureKind;
  String? _failureCode;
  String? _failureChannel;
  String? _languagePrefsError;
  String? _connectionPrefsError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _runStep(String name, Future<void> Function() action) async {
    if (!mounted) return;
    setState(() => _step = name);
    // A stuck plugin should leave a visible, actionable error rather
    // than showing the native Flutter splash indefinitely.
    await action().timeout(const Duration(seconds: 45));
  }

  Future<void> _initialize() async {
    try {
      await _runStep('Opening local database', initializeLocalDatabase);
      // Preferences are non-financial UI settings. A stalled or unavailable
      // Android preferences plugin must not prevent access to the local
      // database. Never clear the underlying stored preferences on error.
      await _runStep('Loading language', () async {
        try {
          await BriskersLanguageController.instance.initialize()
              .timeout(const Duration(seconds: 8));
        } catch (error) {
          _languagePrefsError = error is PlatformException
              ? error.code
              : error.runtimeType.toString();
          debugPrint('Language preferences unavailable; using English '
              'until preferences recover: $error');
        }
      });
      await _runStep('Loading connection settings', () async {
        try {
          await BriskersConnectionModeController.instance.initialize()
              .timeout(const Duration(seconds: 8));
        } catch (error) {
          _connectionPrefsError = error is PlatformException
              ? error.code
              : error.runtimeType.toString();
          // Unknown saved mode must never trigger unexpected network work.
          BriskersConnectionModeController.instance.useSafeOfflineFallback();
          debugPrint('Connection preferences unavailable; safely '
              'forcing offline until user selects a connection mode: $error');
        }
      });
      await _runStep('Initializing secure session', () => Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      ));
      await _runStep('Starting photo background service',
          ExpenseIqBackgroundScheduler.initialize);
      if (mounted) setState(() => _ready = true);
    } catch (error, stack) {
      debugPrint('Briskers startup failed at $_step: $error\n$stack');
      if (mounted) {
        setState(() {
          _failedStep = _step;
          _failureKind = error.runtimeType.toString();
          if (error is PlatformException) {
            _failureCode = error.code;
            // Surface only the non-sensitive plugin channel diagnostic.
            // Never show session payloads, credentials, or arbitrary exception text.
            final String message = error.message ?? '';
            if (message.contains('shared_preferences_android')) {
              _failureChannel = 'shared_preferences_android';
            } else if (message.contains('app_links')) {
              _failureChannel = 'app_links';
            } else if (message.contains('flutter_secure_storage')) {
              _failureChannel = 'flutter_secure_storage';
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const BriskersApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Briskers',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Build $_buildNumber  •  $_sourceRef',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 24),
                  if (_failedStep == null) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(_step, textAlign: TextAlign.center),
                  ] else ...[
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 14),
                    const Text('Briskers could not finish starting.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Stage: $_failedStep', textAlign: TextAlign.center),
                    if (_failureKind != null) ...[
                      const SizedBox(height: 6),
                      Text('Error type: $_failureKind',
                          textAlign: TextAlign.center),
                    ],
                    if (_failureCode != null) ...[
                      const SizedBox(height: 6),
                      Text('Error code: $_failureCode',
                          textAlign: TextAlign.center),
                    ],
                    if (_failureChannel != null) ...[
                      const SizedBox(height: 6),
                      Text('Plugin: $_failureChannel',
                          textAlign: TextAlign.center),
                    ],
                    if (_languagePrefsError != null) ...[
                      const SizedBox(height: 6),
                      Text('Language preferences: $_languagePrefsError',
                          textAlign: TextAlign.center),
                    ],
                    if (_connectionPrefsError != null) ...[
                      const SizedBox(height: 6),
                      Text('Connection preferences: $_connectionPrefsError',
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 12),
                    const Text('Your local data has not been cleared. '
                        'Do not uninstall or clear app storage.',
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
