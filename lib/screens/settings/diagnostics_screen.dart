import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/briskers_colors.dart';
import '../../services/diagnostics_service.dart';
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

  bool _running = false;
  DiagnosticsReport? _report;

  Future<void> _run({required bool full}) async {
    if (_running || widget.roleCode != 'owner') return;
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

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied.')),
    );
  }

  Color _levelColor(DiagnosticLevel level) {
    return switch (level) {
      DiagnosticLevel.pass => const Color(0xFF169B62),
      DiagnosticLevel.warning => const Color(0xFFE58A00),
      DiagnosticLevel.fail => const Color(0xFFC62828),
    };
  }

  IconData _levelIcon(DiagnosticLevel level) {
    return switch (level) {
      DiagnosticLevel.pass => Icons.check_circle_outline,
      DiagnosticLevel.warning => Icons.warning_amber_rounded,
      DiagnosticLevel.fail => Icons.error_outline,
    };
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
                    'Read-only checks. Diagnostics does not modify shop records.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _running
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
                          onPressed:
                              _running ? null : () => _run(full: true),
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
                    const Text('Running diagnostics…'),
                  ],
                ],
              ),
            ),
          ),
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
              for (final check in entry.value)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    leading: Icon(
                      _levelIcon(check.level),
                      color: _levelColor(check.level),
                    ),
                    title: Text(
                      check.id + ' • ' + check.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(check.summary),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
                ),
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
