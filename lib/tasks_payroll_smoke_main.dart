import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'core/shop_payroll_preview.dart';
import 'local/briskers_local_database.dart';
import 'services/test_payroll_credit_repository.dart';
import 'services/test_payroll_staging_repository.dart';
import 'services/test_payroll_atomic_commit.dart';
import 'widgets/test_local_payroll_task_list.dart';
import 'widgets/test_employee_payroll_staging_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TasksPayrollTestApp());
}

class TasksPayrollTestApp extends StatelessWidget {
  const TasksPayrollTestApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Briskers Tasks Payroll TEST',
    debugShowCheckedModeBanner: false,
    home: TestPayrollHome(),
  );
}

class TestPayrollHome extends StatefulWidget {
  const TestPayrollHome({super.key});

  @override
  State<TestPayrollHome> createState() => _TestPayrollHomeState();
}

class _TestPayrollHomeState extends State<TestPayrollHome> {
  final _db = BriskersLocalDatabase(NativeDatabase.memory());
  static const business = 'briskers-test-only';
  static const employee = 'test-chris';
  late final _credits = TestPayrollCreditRepository(database: _db);
  late final _staging = TestPayrollStagingRepository(database: _db);
  late final _settlement = TestPayrollAtomicCommit(database: _db);
  String _message = 'Synthetic TEST only — no real payments';
  int _refresh = 0;

  Future<void> _seedAndStage() async {
    try {
      const credit = ShopPayrollAllocation(
        id: 'test-work-1', employeeId: employee,
        hoursHundredths: 250, rateCentsPerHour: 4000,
        completed: true, alreadyPaid: false,
      );
      await _credits.seedSyntheticCredit(businessId: business, credit: credit);
      await _staging.stage(
        businessId: business, owner: true,
        proposal: ShopPayrollPaymentProposal(
          operationId: 'test-operation-1', employeeId: employee,
          allocationIds: ['test-work-1'], grossCents: 10000,
          repaymentCents: 0, method: 'Cash TEST',
        ),
        credits: [credit], outstandingAdvanceCents: 0,
      );
      if (mounted) {
        setState(() {
        _message = 'Synthetic work staged — NOT PAID';
        _refresh++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'TEST setup: $error');
    }
  }

  Future<void> _settle() async {
    try {
      final committed = await _settlement.finalizeSynthetic(
        businessId: business, operationId: 'test-operation-1',
        owner: true, syntheticTestMode: true,
      );
      if (mounted) {
        setState(() {
        _message = committed
            ? 'Synthetic transaction recorded locally — NOT real payroll'
            : 'Same synthetic transaction already recorded';
        _refresh++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'TEST settlement rejected: $error');
    }
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Briskers Tasks / Payroll TEST')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Isolated in-memory sample. Nothing is sent to the shop. '
          'Closing the app resets this test.', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(_message),
        const SizedBox(height: 12),
        FilledButton(onPressed: _seedAndStage,
          child: const Text('Create synthetic completed task + stage')),
        OutlinedButton(onPressed: _settle,
          child: const Text('Verify synthetic payment only')),
        const Divider(),
        const Text('Employee: $employee'),
        TestLocalPayrollTaskList(
          key: ValueKey('credits-$_refresh'),
          businessId: business, employeeId: employee,
          isOwner: true, repository: _credits,
        ),
        const Divider(),
        TestEmployeePayrollStagingPanel(
          key: ValueKey('staging-$_refresh'),
          businessId: business, employeeId: employee, repository: _staging,
        ),
      ],
    ),
  );
}
