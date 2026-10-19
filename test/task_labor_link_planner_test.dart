import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/task_labor_link_planner.dart';

void main() {
  test('labor line prepares one task tied to the job', () {
    const line = LaborLineCandidate(lineId: 'line-1', jobId: 'J-12',
      name: 'Labor', description: 'Replace oil pan',
      lineKind: 'item', quantity: 2);
    final a = TaskLaborLinkPlanner.propose(line)!;
    final b = TaskLaborLinkPlanner.propose(line)!;
    expect(a.key, b.key);
    expect(a.description, 'Replace oil pan');
    expect(a.payrollHours, 2);
  });

  test('part lines cannot create labor tasks by accident', () {
    const line = LaborLineCandidate(lineId: 'part-1', jobId: 'J-12',
      name: 'Oil pan', lineKind: 'item', quantity: 1);
    expect(TaskLaborLinkPlanner.propose(line), isNull);
  });

  test('service with labor uses catalog default independent of quantity', () {
    const line = LaborLineCandidate(lineId: 'service-1', jobId: 'J-12',
      name: 'Service B', lineKind: 'item', quantity: 1,
      containsLabor: true, defaultPayrollHours: 3);
    expect(TaskLaborLinkPlanner.propose(line)!.payrollHours, 3);
  });

  test('internal or discounts do not create invoice labor tasks', () {
    const line = LaborLineCandidate(lineId: 'fee', jobId: 'J-12',
      name: 'Shop supplies', lineKind: 'supply', quantity: 1);
    expect(TaskLaborLinkPlanner.propose(line), isNull);
  });
}
