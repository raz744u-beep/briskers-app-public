/// Pure weekly payroll planning for the isolated Briskers Tasks TEST app.
/// No bank entries, financial transactions, or production payroll writes.
class TestPayrollWork {
  const TestPayrollWork({
    required this.taskKey,
    required this.employeeId,
    required this.creditedMinutes,
    required this.previouslyPaidMinutes,
  });
  final String taskKey;
  final String employeeId;
  final int creditedMinutes;
  final int previouslyPaidMinutes;

  int get unpaidMinutes => creditedMinutes - previouslyPaidMinutes;
}

class TestPayrollSelection {
  const TestPayrollSelection._();

  /// Allows paying incomplete jobs and carrying other work forward.
  /// A task allocation cannot be paid twice, even across payroll weeks.
  static Map<String, int> selectMinutes({
    required List<TestPayrollWork> available,
    required Map<String, int> requestedMinutesByTask,
  }) {
    final unique = <String>{};
    final result = <String, int>{};
    for (final work in available) {
      final key = '${work.employeeId}|${work.taskKey}';
      if (!unique.add(key)) {
        throw StateError('Duplicate employee/task allocation');
      }
      if (work.creditedMinutes < 0 ||
          work.previouslyPaidMinutes < 0 ||
          work.previouslyPaidMinutes > work.creditedMinutes) {
        throw StateError('Invalid credited or previously paid time');
      }
      final requested = requestedMinutesByTask[key] ?? 0;
      if (requested < 0 || requested > work.unpaidMinutes) {
        throw StateError('Cannot pay more than remaining task allocation');
      }
      if (requested != 0) result[key] = requested;
    }
    if (requestedMinutesByTask.keys.any((key) => !unique.contains(key))) {
      throw StateError('Unknown employee/task payroll selection');
    }
    return result;
  }
}
