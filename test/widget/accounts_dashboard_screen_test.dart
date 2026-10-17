import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/features/dashboard/screens/accounts_dashboard_screen.dart';

void main() {
  const accountsUser = AppUser(
    id: 'accounts-1',
    name: 'Suresh Kumar',
    email: 'accounts@institute.test',
    role: AppRole.accounts,
    instituteId: 'demo-institute',
  );

  final today = DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));
  final futureDate = today.add(const Duration(days: 15));

  final sampleInstallmentOverdue = FeeInstallment(
    id: 'inst-overdue',
    instituteId: 'demo-institute',
    studentId: 'student-1',
    studentName: 'Aarav Patel',
    courseId: 'course-1',
    batchId: 'batch-1',
    amountDue: 10000,
    dueDate: yesterday,
    createdAt: yesterday.subtract(const Duration(days: 30)),
    updatedAt: yesterday,
    status: 'overdue',
    paidAmount: 2000,
  );

  final sampleInstallmentPending = FeeInstallment(
    id: 'inst-pending',
    instituteId: 'demo-institute',
    studentId: 'student-2',
    studentName: 'Diya Sharma',
    courseId: 'course-1',
    batchId: 'batch-1',
    amountDue: 7000,
    dueDate: futureDate,
    createdAt: yesterday.subtract(const Duration(days: 10)),
    updatedAt: yesterday,
    status: 'partial',
    paidAmount: 0,
  );

  final samplePayment1 = Payment(
    id: 'pay-1',
    instituteId: 'demo-institute',
    studentId: 'student-1',
    feeInstallmentId: 'inst-overdue',
    amount: 2000,
    paymentDate: today,
    paymentMethod: 'UPI',
    referenceNumber: 'UPI-987654321',
    recordedBy: 'accounts-1',
    createdAt: today,
  );

  final samplePayment2 = Payment(
    id: 'pay-2',
    instituteId: 'demo-institute',
    studentId: 'student-3',
    feeInstallmentId: 'inst-3',
    amount: 8000,
    paymentDate: today,
    paymentMethod: 'Bank Transfer',
    referenceNumber: 'NEFT-123456789',
    recordedBy: 'accounts-1',
    createdAt: today,
  );

  AccountsDashboardData createSampleData() {
    return AccountsDashboardData(
      installments: [sampleInstallmentOverdue, sampleInstallmentPending],
      payments: [samplePayment1, samplePayment2],
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<AccountsDashboardData> Function()? dataLoader,
    ValueChanged<String>? onSectionSelected,
    Size surfaceSize = const Size(1400, 1000),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AccountsDashboardScreen(
          user: accountsUser,
          dataLoader: dataLoader ?? () async => createSampleData(),
          onSectionSelected: onSectionSelected,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AccountsDashboardScreen Widget Tests', () {
    testWidgets('renders greeting and 4 accurate KPI cards', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Good to see you, Suresh.'), findsOneWidget);
      expect(find.text('ACCOUNTS'), findsOneWidget);

      // KPI card labels
      expect(find.text('Pending Instalments'), findsOneWidget);
      expect(find.text('Overdue Instalments'), findsNWidgets(2)); // KPI + Section Title
      expect(find.text('Total Outstanding Balance'), findsOneWidget);
      expect(find.text('Payments Received This Month'), findsOneWidget);

      // KPI card values
      // Pending: 2 instalments with outstanding balance
      expect(find.text('2'), findsOneWidget);
      // Overdue: 1 instalment
      expect(find.text('1'), findsOneWidget);
      // Outstanding: 8000 + 7000 = 15000.00
      expect(find.text('₹15000.00'), findsOneWidget);
      // Payments received this month: 2000 + 8000 = 10000.00
      expect(find.text('₹10000.00'), findsOneWidget);
    });

    testWidgets('renders recent payments list and opens payment details dialog', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Recent Payments'), findsOneWidget);
      expect(find.textContaining('UPI-987654321'), findsOneWidget);
      expect(find.textContaining('NEFT-123456789'), findsOneWidget);

      // Tap on payment to open details dialog
      await tester.tap(find.textContaining('UPI-987654321'));
      await tester.pumpAndSettle();

      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('UPI-987654321'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Details'), findsNothing);
    });

    testWidgets('renders overdue instalments list and opens instalment details', (
      tester,
    ) async {
      await pumpScreen(tester);

      // Aarav Patel is in the overdue section
      expect(find.text('Aarav Patel (student-1)'), findsOneWidget);

      // Tap Details
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

      expect(find.text('Instalment Details'), findsOneWidget);
      expect(find.text('inst-overdue'), findsOneWidget);
      expect(find.text('Create Reminder Draft'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('all 5 quick action buttons invoke onSectionSelected', (
      tester,
    ) async {
      final selectedSections = <String>[];
      await pumpScreen(
        tester,
        onSectionSelected: (section) => selectedSections.add(section),
      );

      expect(find.text('Quick Actions'), findsOneWidget);

      await tester.tap(find.text('Fee Management'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Risk Alerts'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reminder Drafts'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fee Reports'));
      await tester.pumpAndSettle();

      expect(selectedSections, [
        'fee-management',
        'payments',
        'risk-alerts',
        'reminder-drafts',
        'fee-reports',
      ]);
    });

    testWidgets('displays error state with retry on failure', (tester) async {
      var shouldFail = true;
      await pumpScreen(
        tester,
        dataLoader: () async {
          if (shouldFail) {
            throw Exception('Connection timed out');
          }
          return createSampleData();
        },
      );

      expect(find.text('Unable to load financial dashboard'), findsOneWidget);
      expect(find.text('Retry connection'), findsOneWidget);

      shouldFail = false;
      await tester.tap(find.text('Retry connection'));
      await tester.pumpAndSettle();

      expect(find.text('Good to see you, Suresh.'), findsOneWidget);
      expect(find.text('Pending Instalments'), findsOneWidget);
    });
  });
}
