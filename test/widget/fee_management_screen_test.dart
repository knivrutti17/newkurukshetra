import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/fee_repository.dart';
import 'package:kurukshetra/data/repositories/student_repository.dart';
import 'package:kurukshetra/data/services/batch_service.dart';
import 'package:kurukshetra/data/services/fee_seed_service.dart';
import 'package:kurukshetra/data/services/fee_service.dart';
import 'package:kurukshetra/data/services/student_service.dart';
import 'package:kurukshetra/features/fees/screens/fee_management_screen.dart';

void main() {
  group('FeeManagementScreen Widget', () {
    testWidgets('Owner sees summary cards, action buttons, and installment rows', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final feeRepo = _WidgetTestFeeRepository();
      final feeService = FeeService(repository: feeRepo);
      final seedService = FeeSeedService(feeRepository: feeRepo);

      final studentRepo = _WidgetTestStudentRepository();
      final studentService = StudentService(repository: studentRepo);

      final batchRepo = _WidgetTestBatchRepository();
      final batchService = BatchService(repository: batchRepo);

      final sampleInst = FeeInstallment(
        id: 'inst-1',
        instituteId: 'demo-institute',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        courseId: 'data-analytics',
        batchId: 'da-jan-2026-a',
        amountDue: 22500,
        dueDate: DateTime(2027, 3, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        status: 'pending',
        paidAmount: 0,
      );
      feeRepo.installments.add(sampleInst);

      final owner = const AppUser(
        id: 'owner-1',
        name: 'Aarav Patel',
        email: 'owner@institute.test',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeeManagementScreen(
              user: owner,
              feeService: feeService,
              feeSeedService: seedService,
              studentService: studentService,
              batchService: batchService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Fee & Instalment Management'), findsOneWidget);
      expect(find.text('Total Fees Due'), findsOneWidget);
      expect(find.text('Payments Received'), findsOneWidget);
      expect(find.text('Outstanding Balance'), findsOneWidget);
      expect(find.text('Overdue Instalments'), findsOneWidget);

      expect(find.text('Add Instalment'), findsOneWidget);
      expect(find.text('Load Sample Fees'), findsOneWidget);
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    });

    testWidgets('Accounts staff sees Record Payment and Add Instalment but no seed button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final feeRepo = _WidgetTestFeeRepository();
      final feeService = FeeService(repository: feeRepo);
      final seedService = FeeSeedService(feeRepository: feeRepo);
      final studentService = StudentService(repository: _WidgetTestStudentRepository());
      final batchService = BatchService(repository: _WidgetTestBatchRepository());

      final sampleInst = FeeInstallment(
        id: 'inst-1',
        instituteId: 'demo-institute',
        studentId: 'student-1',
        studentName: 'Vikram Rao',
        courseId: 'flutter-dev',
        batchId: 'flutter-batch-1',
        amountDue: 18000,
        dueDate: DateTime(2027, 3, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        status: 'pending',
        paidAmount: 0,
      );
      feeRepo.installments.add(sampleInst);

      final accounts = const AppUser(
        id: 'accounts-1',
        name: 'Neha Gupta',
        email: 'accounts@institute.test',
        role: AppRole.accounts,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeeManagementScreen(
              user: accounts,
              feeService: feeService,
              feeSeedService: seedService,
              studentService: studentService,
              batchService: batchService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Fee & Instalment Management'), findsOneWidget);
      expect(find.text('Add Instalment'), findsOneWidget);
      expect(find.text('Load Sample Fees'), findsNothing); // Owner only
      expect(find.text('Vikram Rao'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    });

    testWidgets('Counselor sees restricted access message', (tester) async {
      final counselor = const AppUser(
        id: 'counselor-1',
        name: 'Priya Sharma',
        email: 'counselor@institute.test',
        role: AppRole.counselor,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeeManagementScreen(
              user: counselor,
              feeService: FeeService(repository: _WidgetTestFeeRepository()),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Financial details restricted'), findsOneWidget);
      expect(
        find.textContaining('Counselors are not authorized to view'),
        findsOneWidget,
      );
    });

    testWidgets('Trainer sees restricted access message', (tester) async {
      final trainer = const AppUser(
        id: 'trainer-1',
        name: 'Rohan Kulkarni',
        email: 'trainer@institute.test',
        role: AppRole.trainer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeeManagementScreen(
              user: trainer,
              feeService: FeeService(repository: _WidgetTestFeeRepository()),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Fee access not permitted for Trainers'), findsOneWidget);
      expect(
        find.textContaining('Trainers do not have access to fee amounts'),
        findsOneWidget,
      );
    });
  });
}

class _WidgetTestFeeRepository implements FeeRepository, FeeSeedRepository {
  final List<FeeInstallment> installments = [];
  final List<Payment> payments = [];

  @override
  Stream<List<FeeInstallment>> watchInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 200,
  }) => Stream.value(installments);

  @override
  Future<List<FeeInstallment>> getInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
  }) async => installments;

  @override
  Future<FeeInstallment?> getInstallment(String id) async {
    final index = installments.indexWhere((i) => i.id == id);
    return index == -1 ? null : installments[index];
  }

  @override
  Future<FeeInstallment> createInstallment(FeeInstallment installment) async {
    installments.add(installment);
    return installment;
  }

  @override
  Stream<List<Payment>> watchPaymentsForInstallment(String installmentId) =>
      Stream.value(
        payments.where((p) => p.feeInstallmentId == installmentId).toList(),
      );

  @override
  Future<List<Payment>> getPaymentsForInstallment(String installmentId) async =>
      payments.where((p) => p.feeInstallmentId == installmentId).toList();

  @override
  Stream<List<Payment>> watchAllPayments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 500,
  }) => Stream.value(payments);

  @override
  Future<Payment> recordPayment({
    required FeeInstallment installment,
    required Payment payment,
  }) async {
    payments.add(payment);
    return payment;
  }

  @override
  Future<bool> isFeeInstallmentsEmpty() async => installments.isEmpty;

  @override
  Future<int> countExistingSampleInstallments(List<FeeInstallment> samples) async =>
      samples.where((s) => installments.any((i) => i.id == s.id)).length;

  @override
  Future<void> createMissingSampleInstallmentsAndPayments({
    required List<FeeInstallment> installments,
    required List<Payment> payments,
  }) async {
    this.installments.addAll(installments);
    this.payments.addAll(payments);
  }
}

class _WidgetTestStudentRepository
    implements StudentRepository, StudentSeedRepository {
  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) => Stream.value(const []);

  @override
  Future<Student> createStudent(Student student) async => student;

  @override
  Future<Student> updateStudent(Student student) async => student;

  @override
  Future<Student> archiveStudent(Student student) async => student;

  @override
  Future<bool> isStudentsCollectionEmpty() async => true;

  @override
  Future<int> countExistingSampleStudents(List<Student> sampleStudents) async => 0;

  @override
  Future<void> createMissingSampleStudents(List<Student> sampleStudents) async {}
}

class _WidgetTestBatchRepository
    implements BatchRepository, BatchSeedRepository {
  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) => Stream.value(const []);

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async => const [];

  @override
  Future<Batch> createBatch(Batch batch) async => batch;

  @override
  Future<Batch> updateBatch(Batch batch) async => batch;

  @override
  Future<Batch> archiveBatch(Batch batch) async => batch;

  @override
  Future<bool> isBatchesCollectionEmpty() async => true;

  @override
  Future<int> countExistingSampleBatches(List<Batch> samples) async => 0;

  @override
  Future<void> createMissingSampleBatches(List<Batch> samples) async {}
}
