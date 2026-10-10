// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/briskers_colors.dart';
import '../../services/diagnostics_service.dart';
import '../../services/functional_diagnostics_service.dart';
import '../../widgets/briskers_page_header.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
  });

  final String businessId;
  final String roleCode;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final BriskersDiagnosticsService _diagnostics =
      BriskersDiagnosticsService();
  final BriskersFunctionalDiagnosticsService _functionalDiagnostics =
      const BriskersFunctionalDiagnosticsService();

  bool _running = false;
  bool _functionalRunning = false;
  DiagnosticsReport? _report;
  FunctionalDiagnosticsReport? _functionalReport;

  Future<void> _run({required bool full}) async {
    if (_running || _functionalRunning || widget.roleCode != 'owner') return;
    setState(() => _running = true);
    try {
      final report = await _diagnostics.run(
        widget.businessId,
        full: full,
      );
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runFunctional() async {
    if (_running || _functionalRunning || widget.roleCode != 'owner') return;
    setState(() => _functionalRunning = true);
    try {
      final report = await _functionalDiagnostics.run();
      if (!mounted) return;
      setState(() => _functionalReport = report);
    } finally {
      if (mounted) setState(() => _functionalRunning = false);
    }
  }

  Future<void> _copyReport() async {
    final parts = <String>[];
    if (_report != null) parts.add(_report!.toText());
    if (_functionalReport != null) {
      parts.add(_functionalReport!.toText());
    }
    if (parts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: parts.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied.')),
    );
  }

  Color _levelColor(BriskersDiagnosticLevel level) {
    return switch (level) {
      BriskersDiagnosticLevel.pass => const Color(0xFF169B62),
      BriskersDiagnosticLevel.warning => const Color(0xFFE58A00),
      BriskersDiagnosticLevel.fail => const Color(0xFFC62828),
    };
  }

  IconData _levelIcon(BriskersDiagnosticLevel level) {
    return switch (level) {
      BriskersDiagnosticLevel.pass => Icons.check_circle_outline,
      BriskersDiagnosticLevel.warning => Icons.warning_amber_rounded,
      BriskersDiagnosticLevel.fail => Icons.error_outline,
    };
  }

  Widget _checkCard(DiagnosticCheck check) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          _levelIcon(check.level),
          color: _levelColor(check.level),
        ),
        title: Text(
          check.id + ' • ' + check.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(check.summary),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          if (check.details.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No additional details.'),
            )
          else
            for (final detail in check.details)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(detail)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roleCode != 'owner') {
      return Scaffold(
        appBar: AppBar(
          title: const BriskersPageTitle(
            title: 'Diagnostics',
            logoHeight: 40,
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Diagnostics is restricted to the Owner / developer account.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final report = _report;
    final functionalReport = _functionalReport;
    final categories = <String, List<DiagnosticCheck>>{};
    if (report != null) {
      for (final check in report.checks) {
        categories.putIfAbsent(check.category, () => []).add(check);
      }
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: const BriskersPageTitle(
          title: 'Diagnostics',
          logoHeight: 40,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.health_and_safety_outlined,
                        color: BriskersColors.settings,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Briskers Health Check',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Read-only checks against the real local shop data. Diagnostics does not modify shop records.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _running || _functionalRunning
                              ? null
                              : () => _run(full: false),
                          icon: const Icon(Icons.bolt_outlined),
                          label: const Text('Quick Check'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: BriskersColors.settings,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _running || _functionalRunning
                              ? null
                              : () => _run(full: true),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Full Check'),
                        ),
                      ),
                    ],
                  ),
                  if (_running) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text('Running health diagnostics…'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        color: Color(0xFF1976D2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Functional Sandbox',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Runs isolated workflow and payment-layout checks in a disposable in-memory database. It does not touch your customers, jobs, invoices, expenses or the network.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _running || _functionalRunning
                          ? null
                          : _runFunctional,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Run Functional Check'),
                    ),
                  ),
                  if (_functionalRunning) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text('Running isolated workflow tests…'),
                  ],
                ],
              ),
            ),
          ),
          if (functionalReport != null) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCount(
                            label: 'Passed',
                            count: functionalReport.passed,
                            color: const Color(0xFF169B62),
                          ),
                        ),
                        Expanded(
                          child: _SummaryCount(
                            label: 'Warnings',
                            count: functionalReport.warnings,
                            color: const Color(0xFFE58A00),
                          ),
                        ),
                        Expanded(
                          child: _SummaryCount(
                            label: 'Failed',
                            count: functionalReport.failed,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Functional Check • Isolated sandbox',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copyReport,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                'Functional sandbox',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            for (final check in functionalReport.checks) _checkCard(check),
          ],
          if (report != null) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCount(
                            label: 'Passed',
                            count: report.passed,
                            color: const Color(0xFF169B62),
                          ),
                        ),
                        Expanded(
                          child: _SummaryCount(
                            label: 'Warnings',
                            count: report.warnings,
                            color: const Color(0xFFE58A00),
                          ),
                        ),
                        Expanded(
                          child: _SummaryCount(
                            label: 'Failed',
                            count: report.failed,
                            color: const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (report.full ? 'Full Check' : 'Quick Check') +
                                ' • ' +
                                report.connectionMode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copyReport,
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copy Report'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in categories.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              for (final check in entry.value) _checkCard(check),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryCount extends StatelessWidget {
  const _SummaryCount({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
