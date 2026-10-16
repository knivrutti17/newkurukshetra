import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/repositories/fee_repository.dart';
import 'package:kurukshetra/data/services/fee_seed_service.dart';
import 'package:kurukshetra/data/services/fee_service.dart';

void main() {
  group('FeeInstallment model', () {
    test('derives status correctly across payment states and due dates', () {
      final now = DateTime(2026, 6, 15);
      final futureDate = DateTime(2026, 6, 25);
      final pastDate = DateTime(2026, 6, 5);

      // Pending: 0 paid, future due date
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 0,
          dueDate: futureDate,
          asOf: now,
        ),
        'pending',
      );

      // Partially Paid: partially paid, future due date
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 8000,
          dueDate: futureDate,
          asOf: now,
        ),
        'partiallyPaid',
      );

      // Overdue: 0 paid, past due date
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 0,
          dueDate: pastDate,
          asOf: now,
        ),
        'overdue',
      );

      // Overdue: partial paid, past due date
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 8000,
          dueDate: pastDate,
          asOf: now,
        ),
        'overdue',
      );

      // Paid: full payment even if due date is past (never marked overdue)
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 20000,
          dueDate: pastDate,
          asOf: now,
        ),
        'paid',
      );

      // Paid: full payment with future due date
      expect(
        FeeInstallment.deriveStatus(
          amountDue: 20000,
          paidAmount: 20000,
          dueDate: futureDate,
          asOf: now,
        ),
        'paid',
      );
    });

    test('calculates integer paise and outstanding balances accurately', () {
      final installment = FeeInstallment(
        id: 'inst-1',
        instituteId: 'demo-institute',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        courseId: 'data-analytics',
        batchId: 'batch-1',
        amountDue: 22500.50,
        dueDate: DateTime(2026, 7, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        status: 'partiallyPaid',
        paidAmount: 10000.25,
      );

      expect(installment.amountDuePaise, 2250050);
      expect(installment.paidAmountPaise, 1000025);
      expect(installment.balancePaise, 1250025);
      expect(installment.outstandingBalance, 12500.25);
      expect(installment.isPaid, isFalse);

      final paidInstallment = installment.copyWith(
        paidAmount: 22500.50,
        status: 'paid',
      );
      expect(paidInstallment.balancePaise, 0);
      expect(paidInstallment.outstandingBalance, 0.0);
      expect(paidInstallment.isPaid, isTrue);
    });

    test('serializes to Firestore map and back', () {
      final now = DateTime(2026, 3, 15);
      final installment = FeeInstallment(
        id: 'inst-test',
        instituteId: 'demo-institute',
        studentId: 'stud-123',
        studentName: 'Rohan Sharma',
        courseId: 'flutter-dev',
        batchId: 'batch-flutter-1',
        amountDue: 35000,
        dueDate: DateTime(2026, 5, 1),
        createdAt: now,
        updatedAt: now,
        status: 'pending',
        paidAmount: 0,
      );

      final map = installment.toFirestore();
      expect(map['instituteId'], 'demo-institute');
      expect(map['studentId'], 'stud-123');
      expect(map['studentName'], 'Rohan Sharma');
      expect(map['amountDue'], 35000.0);
      expect(map['paidAmount'], 0.0);
      expect(map['status'], 'pending');
    });
  });

  group('Payment model', () {
    test('calculates integer paise and provides supported payment methods', () {
      final payment = Payment(
        id: 'pay-1',
        instituteId: 'demo-institute',
        feeInstallmentId: 'inst-1',
        studentId: 'student-1',
        amount: 5432.10,
        paymentDate: DateTime(2026, 3, 10),
        paymentMethod: 'UPI',
        referenceNumber: 'UPI/1234567890',
        recordedBy: 'user-1',
        createdAt: DateTime(2026, 3, 10),
      );

      expect(payment.amountPaise, 543210);
      expect(payment.referenceNumber, 'UPI/1234567890');
      expect(Payment.paymentMethods, contains('Cash'));
      expect(Payment.paymentMethods, contains('UPI'));
      expect(Payment.paymentMethods, contains('Bank Transfer'));
      expect(Payment.paymentMethods, contains('Cheque'));
      expect(Payment.paymentMethods, contains('Card'));
    });
  });

  group('FeeService - Role Permissions', () {
    late _InMemoryFeeRepository repository;
    late FeeService service;

    final owner = _user(AppRole.owner, 'owner-1');
    final accounts = _user(AppRole.accounts, 'accounts-1');
    final counselor = _user(AppRole.counselor, 'counselor-1');
    final trainer = _user(AppRole.trainer, 'trainer-1');

    setUp(() {
      repository = _InMemoryFeeRepository();
      service = FeeService(repository: repository);
    });

    test('only Owner and Accounts have manage and view permissions', () {
      expect(service.canManage(owner), isTrue);
      expect(service.canView(owner), isTrue);

      expect(service.canManage(accounts), isTrue);
      expect(service.canView(accounts), isTrue);

      expect(service.canManage(counselor), isFalse);
      expect(service.canView(counselor), isFalse);

      expect(service.canManage(trainer), isFalse);
      expect(service.canView(trainer), isFalse);
    });

    test('counselor and trainer are rejected when creating an instalment', () async {
      final installment = _installment(amount: 15000);

      await expectLater(
        service.createInstallmentForUser(counselor, installment),
        throwsA(isA<FeeValidationException>()),
      );

      await expectLater(
        service.createInstallmentForUser(trainer, installment),
        throwsA(isA<FeeValidationException>()),
      );
    });

    test('counselor and trainer are rejected when recording a payment', () async {
      final installment = _installment(amount: 15000);
      repository.installments.add(installment);

      await expectLater(
        service.recordPaymentForUser(
          counselor,
          installment: installment,
          amount: 5000,
          paymentMethod: 'UPI',
        ),
        throwsA(isA<FeeValidationException>()),
      );

      await expectLater(
        service.recordPaymentForUser(
          trainer,
          installment: installment,
          amount: 5000,
          paymentMethod: 'UPI',
        ),
        throwsA(isA<FeeValidationException>()),
      );
    });

    test('counselor and trainer receive empty stream and list for watch/get', () async {
      repository.installments.add(_installment(amount: 15000));

      final counselorList = await service.getInstallmentsForUser(counselor);
      expect(counselorList, isEmpty);

      final counselorStream = await service.watchInstallmentsForUser(counselor).first;
      expect(counselorStream, isEmpty);

      final trainerList = await service.getInstallmentsForUser(trainer);
      expect(trainerList, isEmpty);
    });
  });

  group('FeeService - Validations and Operations', () {
    late _InMemoryFeeRepository repository;
    late FeeService service;
    final owner = _user(AppRole.owner, 'owner-1');

    setUp(() {
      repository = _InMemoryFeeRepository();
      service = FeeService(repository: repository);
    });

    test('rejects instalment with empty student ID', () async {
      final invalid = _installment(studentId: '  ');
      await expectLater(
        service.createInstallmentForUser(owner, invalid),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('select a student'),
          ),
        ),
      );
    });

    test('rejects instalment with zero or negative amount', () async {
      final zeroAmount = _installment(amount: 0);
      await expectLater(
        service.createInstallmentForUser(owner, zeroAmount),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('greater than zero'),
          ),
        ),
      );

      final negativeAmount = _installment(amount: -500);
      await expectLater(
        service.createInstallmentForUser(owner, negativeAmount),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('greater than zero'),
          ),
        ),
      );
    });

    test('rejects instalment for inactive or archived student', () async {
      final inactiveStudent = _student(id: 'stud-archived', status: 'archived');
      final installment = _installment(studentId: 'stud-archived');

      await expectLater(
        service.createInstallmentForUser(
          owner,
          installment,
          student: inactiveStudent,
        ),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('inactive or archived'),
          ),
        ),
      );
    });

    test('owner creates valid instalment successfully', () async {
      final activeStudent = _student(id: 'stud-1', status: 'active');
      final valid = _installment(
        id: 'inst-100',
        studentId: 'stud-1',
        amount: 25000,
        dueDate: DateTime(2027, 2, 1),
      );

      final created = await service.createInstallmentForUser(
        owner,
        valid,
        student: activeStudent,
      );

      expect(created.id, 'inst-100');
      expect(created.amountDue, 25000);
      expect(created.paidAmount, 0.0);
      expect(created.status, 'pending');
      expect(repository.installments, hasLength(1));
    });

    test('records partial payment and updates instalment status', () async {
      final installment = _installment(
        id: 'inst-part',
        amount: 20000,
        dueDate: DateTime(2027, 2, 1),
      );
      repository.installments.add(installment);

      final payment = await service.recordPaymentForUser(
        owner,
        installment: installment,
        amount: 8000,
        paymentMethod: 'UPI',
        referenceNumber: 'TXN123456',
      );

      expect(payment.id, isNotEmpty);
      expect(payment.amount, 8000);
      expect(payment.paymentMethod, 'UPI');
      expect(payment.referenceNumber, 'TXN123456');

      final updated = repository.installments.single;
      expect(updated.paidAmount, 8000);
      expect(updated.status, 'partiallyPaid');
      expect(updated.outstandingBalance, 12000);
      expect(repository.payments, hasLength(1));
    });

    test('records full payment and marks status as paid', () async {
      final installment = _installment(
        id: 'inst-full',
        amount: 15000,
        dueDate: DateTime(2026, 5, 1), // past date
      );
      repository.installments.add(installment);

      final payment = await service.recordPaymentForUser(
        owner,
        installment: installment,
        amount: 15000,
        paymentMethod: 'Bank Transfer',
        referenceNumber: 'IMPS987654',
      );

      expect(payment.amount, 15000);
      final updated = repository.installments.single;
      expect(updated.paidAmount, 15000);
      expect(updated.status, 'paid');
      expect(updated.outstandingBalance, 0);
      expect(updated.isPaid, isTrue);
    });

    test('rejects payment amount equal to zero or negative', () async {
      final installment = _installment(id: 'inst-test', amount: 10000);
      repository.installments.add(installment);

      await expectLater(
        service.recordPaymentForUser(
          owner,
          installment: installment,
          amount: 0,
          paymentMethod: 'Cash',
        ),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('greater than zero'),
          ),
        ),
      );

      await expectLater(
        service.recordPaymentForUser(
          owner,
          installment: installment,
          amount: -100,
          paymentMethod: 'Cash',
        ),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('greater than zero'),
          ),
        ),
      );
    });

    test('rejects overpayment exceeding remaining balance', () async {
      final installment = _installment(
        id: 'inst-overpay',
        amount: 10000,
        paidAmount: 6000,
        status: 'partiallyPaid',
      );
      repository.installments.add(installment);

      // Remaining balance is 4000; payment of 4001 should fail
      await expectLater(
        service.recordPaymentForUser(
          owner,
          installment: installment,
          amount: 4001,
          paymentMethod: 'Cash',
        ),
        throwsA(
          predicate<FeeValidationException>(
            (e) => e.message.contains('exceeds remaining balance'),
          ),
        ),
      );
    });

    test('calculateSummary computes accurate aggregates using integer paise', () {
      final asOf = DateTime(2026, 6, 15);
      final list = <FeeInstallment>[
        // Paid: 10,000 due, 10,000 paid
        FeeInstallment(
          id: '1',
          instituteId: 'demo-institute',
          studentId: 's1',
          studentName: 'Student 1',
          courseId: 'c1',
          batchId: 'b1',
          amountDue: 10000,
          dueDate: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 5, 1),
          status: 'paid',
          paidAmount: 10000,
        ),
        // Pending: 15,000 due, 0 paid, future date (2026-07-01)
        FeeInstallment(
          id: '2',
          instituteId: 'demo-institute',
          studentId: 's2',
          studentName: 'Student 2',
          courseId: 'c1',
          batchId: 'b1',
          amountDue: 15000,
          dueDate: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          status: 'pending',
          paidAmount: 0,
        ),
        // Overdue: 20,000 due, 5,000 paid, past date (2026-06-01)
        FeeInstallment(
          id: '3',
          instituteId: 'demo-institute',
          studentId: 's3',
          studentName: 'Student 3',
          courseId: 'c1',
          batchId: 'b1',
          amountDue: 20000,
          dueDate: DateTime(2026, 6, 1),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 2, 1),
          status: 'partiallyPaid',
          paidAmount: 5000,
        ),
      ];

      final summary = service.calculateSummary(list, asOf: asOf);

      // Total Due: 10,000 + 15,000 + 20,000 = 45,000
      expect(summary.totalDue, 45000.0);
      // Total Paid: 10,000 + 0 + 5,000 = 15,000
      expect(summary.totalPaid, 15000.0);
      // Outstanding Balance: 45,000 - 15,000 = 30,000
      expect(summary.outstandingBalance, 30000.0);
      // Overdue: Only item 3 is overdue (past due date & unpaid balance of 15,000)
      expect(summary.overdueCount, 1);
      expect(summary.overdueAmount, 15000.0);
    });
  });

  group('FeeSeedService', () {
    late _InMemoryFeeRepository repository;
    late FeeSeedService seedService;

    setUp(() {
      repository = _InMemoryFeeRepository();
      seedService = FeeSeedService(feeRepository: repository);
    });

    test('populates sample fees and payments when collection is empty', () async {
      final result = await seedService.loadSampleFees();

      expect(result.alreadyHadData, isFalse);
      expect(result.installmentsCreated, greaterThan(0));
      expect(result.paymentsCreated, greaterThan(0));
      expect(repository.installments, isNotEmpty);
      expect(repository.payments, isNotEmpty);
    });

    test('is safe to call repeatedly and skips when data already exists', () async {
      final first = await seedService.loadSampleFees();
      expect(first.alreadyHadData, isFalse);
      final countAfterFirst = repository.installments.length;

      final second = await seedService.loadSampleFees();
      expect(second.alreadyHadData, isTrue);
      expect(second.installmentsCreated, 0);
      expect(repository.installments.length, countAfterFirst);
    });
  });
}

class _InMemoryFeeRepository implements FeeRepository, FeeSeedRepository {
  final List<FeeInstallment> installments = [];
  final List<Payment> payments = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  int _nextId = 1;

  @override
  Stream<List<FeeInstallment>> watchInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 200,
  }) async* {
    yield _scopedInstallments(scope);
    yield* _changes.stream.map((_) => _scopedInstallments(scope));
  }

  @override
  Future<List<FeeInstallment>> getInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
  }) async => _scopedInstallments(scope);

  List<FeeInstallment> _scopedInstallments(FeeAccessScope scope) {
    final list = installments
        .where((i) => scope.instituteId == null || i.instituteId == scope.instituteId)
        .toList();
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  @override
  Future<FeeInstallment?> getInstallment(String id) async {
    final index = installments.indexWhere((i) => i.id == id);
    return index == -1 ? null : installments[index];
  }

  @override
  Future<FeeInstallment> createInstallment(FeeInstallment installment) async {
    final id = installment.id.isEmpty ? 'inst-${_nextId++}' : installment.id;
    final now = DateTime.now();
    final saved = installment.copyWith(
      id: id,
      createdAt: now,
      updatedAt: now,
      paidAmount: 0.0,
      status: FeeInstallment.deriveStatus(
        amountDue: installment.amountDue,
        paidAmount: 0.0,
        dueDate: installment.dueDate,
        asOf: now,
      ),
    );
    installments.add(saved);
    _changes.add(null);
    return saved;
  }

  @override
  Stream<List<Payment>> watchPaymentsForInstallment(String installmentId) async* {
    yield _scopedPayments(installmentId);
    yield* _changes.stream.map((_) => _scopedPayments(installmentId));
  }

  @override
  Future<List<Payment>> getPaymentsForInstallment(String installmentId) async =>
      _scopedPayments(installmentId);

  List<Payment> _scopedPayments(String installmentId) {
    final list = payments
        .where((p) => p.feeInstallmentId == installmentId)
        .toList();
    list.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return list;
  }

  @override
  Stream<List<Payment>> watchAllPayments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 500,
  }) async* {
    yield _allScopedPayments(scope);
    yield* _changes.stream.map((_) => _allScopedPayments(scope));
  }

  List<Payment> _allScopedPayments(FeeAccessScope scope) {
    final list = payments
        .where((p) => scope.instituteId == null || p.instituteId == scope.instituteId)
        .toList();
    list.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return list;
  }

  @override
  Future<Payment> recordPayment({
    required FeeInstallment installment,
    required Payment payment,
  }) async {
    final index = installments.indexWhere((i) => i.id == installment.id);
    if (index == -1) {
      throw StateError('Instalment ${installment.id} does not exist.');
    }

    final current = installments[index];
    final currentDuePaise = current.amountDuePaise;
    final currentPaidPaise = current.paidAmountPaise;
    final newPaymentPaise = payment.amountPaise;

    if (newPaymentPaise <= 0) {
      throw StateError('Payment amount must be greater than zero.');
    }

    final updatedPaidPaise = currentPaidPaise + newPaymentPaise;
    if (updatedPaidPaise > currentDuePaise) {
      final remaining = (currentDuePaise - currentPaidPaise) / 100.0;
      throw StateError(
        'Payment of ₹${payment.amount.toStringAsFixed(2)} exceeds remaining balance of ₹${remaining.toStringAsFixed(2)}.',
      );
    }

    final updatedPaidAmount = updatedPaidPaise / 100.0;
    final now = DateTime.now();
    final newStatus = FeeInstallment.deriveStatus(
      amountDue: current.amountDue,
      paidAmount: updatedPaidAmount,
      dueDate: current.dueDate,
      asOf: now,
    );

    final payId = payment.id.isEmpty ? 'pay-${_nextId++}' : payment.id;
    final savedPayment = payment.copyWith(
      id: payId,
      createdAt: now,
    );

    installments[index] = current.copyWith(
      paidAmount: updatedPaidAmount,
      status: newStatus,
      updatedAt: now,
    );
    payments.add(savedPayment);
    _changes.add(null);
    return savedPayment;
  }

  @override
  Future<bool> isFeeInstallmentsEmpty() async => installments.isEmpty;

  @override
  Future<int> countExistingSampleInstallments(
    List<FeeInstallment> samples,
  ) async => samples.where((s) => installments.any((i) => i.id == s.id)).length;

  @override
  Future<void> createMissingSampleInstallmentsAndPayments({
    required List<FeeInstallment> installments,
    required List<Payment> payments,
  }) async {
    for (final inst in installments) {
      if (this.installments.every((i) => i.id != inst.id)) {
        this.installments.add(inst);
      }
    }
    for (final p in payments) {
      if (this.payments.every((item) => item.id != p.id)) {
        this.payments.add(p);
      }
    }
    _changes.add(null);
  }
}

AppUser _user(AppRole role, String id) => AppUser(
  id: id,
  name: 'Demo ${role.label}',
  email: '${role.name}@institute.test',
  role: role,
);

Student _student({
  required String id,
  String name = 'Test Student',
  String status = 'active',
}) => Student(
  id: id,
  instituteId: 'demo-institute',
  fullName: name,
  phone: '9876543210',
  email: 'test@student.test',
  status: status,
  courseId: 'data-analytics',
  courseName: 'Data Analytics',
  batchId: 'da-jan-2026-a',
  batchName: 'DA Jan 2026 A',
  counselorId: 'counselor-1',
  enrollmentDate: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

FeeInstallment _installment({
  String id = 'inst-default',
  String studentId = 'sample-01-aisha-khan',
  String studentName = 'Aisha Khan',
  String courseId = 'data-analytics',
  String batchId = 'da-jan-2026-a',
  double amount = 22500,
  double paidAmount = 0,
  DateTime? dueDate,
  String status = 'pending',
}) => FeeInstallment(
  id: id,
  instituteId: 'demo-institute',
  studentId: studentId,
  studentName: studentName,
  courseId: courseId,
  batchId: batchId,
  amountDue: amount,
  dueDate: dueDate ?? DateTime(2027, 2, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  status: status,
  paidAmount: paidAmount,
);
