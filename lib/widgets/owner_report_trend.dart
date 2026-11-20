import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import '../core/owner_report_models.dart';

const reportSeriesColors = <OwnerReportMetric, Color>{
  OwnerReportMetric.income: Color(0xFF079B18),
  OwnerReportMetric.expenses: Color(0xFFF28908),
  OwnerReportMetric.net: Color(0xFF1674E9),
  OwnerReportMetric.sales: Color(0xFF8435C8),
};

/// The comparison chart has its own scrollable history, anchored at the end of
/// the selected report period. It does not silently change the summary period.
class OwnerReportTrend extends StatefulWidget {
  const OwnerReportTrend({super.key, required this.data, required this.period});
  final OwnerReportData data;
  final ReportPeriod period;
  @override
  State<OwnerReportTrend> createState() => _OwnerReportTrendState();
}

class _OwnerReportTrendState extends State<OwnerReportTrend> {
  ReportGrouping _grouping = ReportGrouping.monthly;
  final Set<OwnerReportMetric> _selected = {
    OwnerReportMetric.income, OwnerReportMetric.expenses, OwnerReportMetric.net,
  };
  final ScrollController _scroll = ScrollController();
  String? _detail;
  bool _scrollToEnd = true;
  @override
  void didUpdateWidget(covariant OwnerReportTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.end != widget.period.end) _scrollToEnd = true;
  }
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  List<ReportPeriod> _periods() {
    final end = widget.period.end;
    final count = _grouping == ReportGrouping.monthly ? 12 : _grouping == ReportGrouping.quarterly ? 8 : 6;
    final step = _grouping == ReportGrouping.monthly ? 1 : _grouping == ReportGrouping.quarterly ? 3 : 12;
    final last = switch (_grouping) {
      ReportGrouping.monthly => DateTime(end.year, end.month),
      ReportGrouping.quarterly => DateTime(end.year, ((end.month - 1) ~/ 3) * 3 + 1),
      ReportGrouping.yearly => DateTime(end.year),
    };
    return [for (var i = count - 1; i >= 0; i--)
      ReportPeriod(DateTime(last.year, last.month - step * i),
        i == 0 ? end : DateTime(last.year, last.month - step * i + step, 0))];
  }
  String _label(ReportPeriod p) => switch (_grouping) {
    ReportGrouping.monthly => DateFormat('MMM yy').format(p.start),
    ReportGrouping.quarterly => 'Q${(p.start.month - 1) ~/ 3 + 1} ${p.start.year}',
    ReportGrouping.yearly => '${p.start.year}',
  };
  @override
  Widget build(BuildContext context) {
    final periods = _periods();
    final summaries = periods.map((p) => widget.data.summary(p)).toList();
    final selected = reportSeriesColors.keys.where(_selected.contains).toList();
    if (_scrollToEnd) {
      _scrollToEnd = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8, runSpacing: 8, children: [
          const Text('Financial Trend', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Wrap(spacing: 2, children: [for (final group in ReportGrouping.values)
            TextButton(style: TextButton.styleFrom(
              backgroundColor: _grouping == group ? const Color(0xFF2479C6) : const Color(0xFFE7EFFC),
              foregroundColor: _grouping == group ? Colors.white : const Color(0xFF17202A)),
              onPressed: () => setState(() { _grouping = group; _scrollToEnd = true; _detail = null; }),
              child: Text(switch (group) { ReportGrouping.monthly => 'Monthly', ReportGrouping.quarterly => 'Quarterly', ReportGrouping.yearly => 'Yearly' })),
          ]),
        ]),
      Wrap(spacing: 4, children: [for (final key in reportSeriesColors.keys)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: _selected.contains(key), activeColor: reportSeriesColors[key],
            onChanged: (value) => setState(() { if (value == true) { _selected.add(key); } else { _selected.remove(key); } })),
          Text(key == OwnerReportMetric.income ? 'Income' : key.label),
        ]),
      ]),
      Text('Comparison history through ${DateFormat.yMMMd().format(widget.period.end)}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
      const SizedBox(height: 10),
      if (selected.isEmpty) const SizedBox(height: 220, child: Center(child: Text('Select a series to view the chart.')))
      else SizedBox(height: 270, child: Row(children: [
        SizedBox(width: 58, child: _ChartScale(summaries: summaries, selected: selected)),
        Expanded(child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal,
          child: GestureDetector(onTapUp: (event) {
            final index = (event.localPosition.dx / 90).floor().clamp(0, periods.length - 1);
            final within = event.localPosition.dx % 90 - 12;
            if (within < 0 || within >= 64) return;
            final series = (within / (64 / selected.length)).floor().clamp(0, selected.length - 1);
            final key = selected[series];
            final value = summaries[index].values[key];
            setState(() => _detail = '${_label(periods[index])} · ${key.label}: ${value == null ? 'Not recorded' : NumberFormat.simpleCurrency(locale: 'en_US').format(value / 100)}');
          }, child: Semantics(label: 'Financial comparison chart. Swipe horizontally; tap a bar for its value.',
            child: CustomPaint(key: const ValueKey('owner-report-chart'), size: Size(periods.length * 90, 270), painter: _TrendPainter(
              summaries, selected, periods.map(_label).toList())))))),
      ])),
      const SizedBox(height: 8),
      Text(_detail ?? 'Swipe the chart to explore history. Tap a bar for its exact value.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
    ]);
  }
}

({double top, double bottom}) _bounds(List<OwnerReportSummary> rows, List<OwnerReportMetric> series) {
  var top = 1.0, bottom = 0.0;
  for (final row in rows) {
    for (final key in series) {
      final value = row.values[key];
      if (value != null) { top = math.max(top, value.toDouble()); bottom = math.min(bottom, value.toDouble()); }
    }
  }
  return (top: top, bottom: bottom);
}

class _ChartScale extends StatelessWidget {
  const _ChartScale({required this.summaries, required this.selected});
  final List<OwnerReportSummary> summaries;
  final List<OwnerReportMetric> selected;
  @override
  Widget build(BuildContext context) {
    final range = _bounds(summaries, selected);
    return Padding(padding: const EdgeInsets.only(bottom: 34), child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (var i = 0; i <= 4; i++) Text(
        NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0).format(
          (range.top - (range.top - range.bottom) * i / 4) / 100),
        style: const TextStyle(fontSize: 10))]));
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.rows, this.series, this.labels);
  final List<OwnerReportSummary> rows;
  final List<OwnerReportMetric> series;
  final List<String> labels;
  @override
  void paint(Canvas canvas, Size size) {
    final range = _bounds(rows, series);
    const height = 230.0;
    double y(num value) => height * (range.top - value) / (range.top - range.bottom);
    final grid = Paint()..color = const Color(0xFFDCE3EF)..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(Offset(0, height * i / 4), Offset(size.width, height * i / 4), grid);
    }
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), Paint()..color = const Color(0xFF667085));
    for (var i = 0; i < rows.length; i++) {
      final width = 64 / series.length;
      for (var j = 0; j < series.length; j++) {
        final value = rows[i].values[series[j]];
        if (value == null || value == 0) continue;
        final left = i * 90 + 12 + j * width;
        final top = math.min(y(value), y(0)), bottom = math.max(y(value), y(0));
        canvas.drawRect(Rect.fromLTRB(left, top, left + width - 3, bottom), Paint()..color = reportSeriesColors[series[j]]!);
      }
      final text = TextPainter(text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 11, color: Color(0xFF17202A))), textDirection: TextDirection.ltr)..layout(maxWidth: 88);
      text.paint(canvas, Offset(i * 90 + (90 - text.width) / 2, height + 10));
    }
  }
  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
