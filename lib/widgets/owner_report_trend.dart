import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import '../core/briskers_colors.dart';
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
  String? _detail;
  @override
  void didUpdateWidget(covariant OwnerReportTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.end != widget.period.end) _detail = null;
  }

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
    final monthly = _grouping == ReportGrouping.monthly;
    final labels = periods.map(_label).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'Financial Trend',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.center, spacing: 2, children: [
        for (final group in ReportGrouping.values)
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: _grouping == group
                  ? BriskersColors.tabBlue
                  : const Color(0xFFE7EFFC),
              foregroundColor: _grouping == group ? Colors.white : BriskersColors.text,
            ),
            onPressed: () => setState(() {
              _grouping = group;
              _detail = null;
            }),
            child: Text(switch (group) {
              ReportGrouping.monthly => 'Monthly',
              ReportGrouping.quarterly => 'Quarterly',
              ReportGrouping.yearly => 'Yearly',
            }),
          ),
      ]),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [for (final key in reportSeriesColors.keys)
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0) return const SizedBox.shrink();
              final periodWidth = monthly ? constraints.maxWidth / 6 : 90.0;
              final barGroupWidth = periodWidth * _barsFraction;
              final barSlotWidth = barGroupWidth / selected.length;
              return SingleChildScrollView(
                key: ValueKey((_grouping, widget.period.end)),
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: GestureDetector(
                  onTapUp: (event) {
                    final x = event.localPosition.dx;
                    final index = (x / periodWidth).floor().clamp(0, periods.length - 1);
                    final within = x - index * periodWidth - (periodWidth - barGroupWidth) / 2;
                    if (within < 0 || within >= barGroupWidth) return;
                    final seriesIndex = (within / barSlotWidth).floor().clamp(0, selected.length - 1);
                    final key = selected[seriesIndex];
                    final value = summaries[index].values[key];
                    final amount = value == null
                        ? 'Not recorded'
                        : NumberFormat.simpleCurrency(locale: 'en_US').format(value / 100);
                    setState(() => _detail = '${labels[index]} · ${key.label}: $amount');
                  },
                  child: Semantics(
                    label: 'Financial comparison chart. Swipe horizontally to see older periods. Tap a bar for its value.',
                    child: CustomPaint(
                      key: const ValueKey('owner-report-chart'),
                      size: Size(periods.length * periodWidth, 270),
                      painter: _TrendPainter(summaries, selected, labels, periodWidth),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ])),
      const SizedBox(height: 8),
      Text(_detail ?? 'Swipe the chart to explore history. Tap a bar for its exact value.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
    ]);
  }
}

const _barsFraction = 0.78;

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
  _TrendPainter(this.rows, this.series, this.labels, this.periodWidth);
  final List<OwnerReportSummary> rows;
  final List<OwnerReportMetric> series;
  final List<String> labels;
  final double periodWidth;
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
    final groupWidth = periodWidth * _barsFraction;
    final slotWidth = groupWidth / series.length;
    final gap = math.min(3.0, slotWidth * 0.25);
    for (var i = 0; i < rows.length; i++) {
      final groupStart = i * periodWidth;
      for (var j = 0; j < series.length; j++) {
        final value = rows[i].values[series[j]];
        if (value == null || value == 0) continue;
        final left = groupStart + (periodWidth - groupWidth) / 2 + j * slotWidth + gap / 2;
        final top = math.min(y(value), y(0)), bottom = math.max(y(value), y(0));
        canvas.drawRect(Rect.fromLTRB(left, top, left + slotWidth - gap, bottom), Paint()..color = reportSeriesColors[series[j]]!);
      }
      final text = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(fontFamily: 'Roboto', fontSize: 11, color: BriskersColors.text)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: math.max(0.0, periodWidth - 2));
      text.paint(canvas, Offset(groupStart + (periodWidth - text.width) / 2, height + 8));
      text.dispose();
    }
  }
  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
