import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/owner_report_models.dart';

class OwnerReportPreferences {
  const OwnerReportPreferences(this.business);
  final String business;
  String get _key => 'owner_reports_overview_v1:$business';
  static final Map<String, Future<void>> _writes = {};
  Future<Map<String, dynamic>> _read({bool awaitWrites = true}) async {
    if (awaitWrites) await _writes[_key];
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    try { return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map); }
    catch (_) { return {}; }
  }
  Future<List<OwnerReportMetric>> tiles() async {
    final saved = (await _read())['tiles'];
    if (saved is! List || saved.length != 4) return [...OwnerReportMetric.defaults];
    return [for (var i = 0; i < 4; i++)
      OwnerReportMetric.values.where((v) => v.name == saved[i]).firstOrNull ?? OwnerReportMetric.defaults[i]];
  }
  Future<void> saveTiles(List<OwnerReportMetric> tiles) async {
    if (tiles.length != 4) throw ArgumentError('Choose four tiles.');
    await _patch({'tiles': tiles.map((v) => v.name).toList()});
  }
  Future<ReportPeriod> period(DateTime now) async {
    final data = await _read();
    final preset = data['preset']?.toString() ?? 'thisMonth';
    if (preset != 'custom') return ReportPeriod.preset(preset, now);
    final start = DateTime.tryParse(data['start']?.toString() ?? '');
    final end = DateTime.tryParse(data['end']?.toString() ?? '');
    return start == null || end == null || start.isAfter(end)
        ? ReportPeriod.preset('thisMonth', now) : ReportPeriod(start, end);
  }
  Future<void> savePeriod(ReportPeriod period) async => _patch({
    'preset': period.preset, 'start': period.start.toIso8601String(), 'end': period.end.toIso8601String()});
  Future<void> _patch(Map<String, dynamic> patch) {
    final previous = _writes[_key] ?? Future<void>.value();
    final next = previous.then((_) async {
      final value = {...await _read(awaitWrites: false), ...patch};
      await _save(value);
    });
    // A failed write is reported to its caller, but must not poison later saves.
    _writes[_key] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
  Future<void> _save(Map<String, dynamic> value) async {
    final ok = await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(value));
    if (!ok) throw StateError('Report preferences could not be saved.');
  }
}
