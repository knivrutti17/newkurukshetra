import '../models/app_user.dart';
import '../models/fee_installment.dart';
import '../models/payment.dart';
import '../models/student.dart';
import '../repositories/fee_repository.dart';

class FeeValidationException implements Exception {
  const FeeValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FeeSummary {
  const FeeSummary({
    required this.totalDue,
    required this.totalPaid,
    required this.outstandingBalance,
    required this.overdueCount,
    required this.overdueAmount,
  });

  final double totalDue;
  final double totalPaid;
  final double outstandingBalance;
  final int overdueCount;
  final double overdueAmount;
}

class FeeService {
  FeeService({FeeRepository? repository})
    : _repository = repository ?? FirestoreFeeRepository();

  final FeeRepository _repository;

  bool canManage(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  bool canView(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  Stream<List<FeeInstallment>> watchInstallmentsForUser(AppUser user) {
    if (!canView(user)) {
      return Stream.value(const <FeeInstallment>[]);
    }
    return _repository.watchInstallments(scope: _scopeFor(user));
  }

  Future<List<FeeInstallment>> getInstallmentsForUser(AppUser user) {
    if (!canView(user)) {
      return Future.value(const <FeeInstallment>[]);
    }
    return _repository.getInstallments(scope: _scopeFor(user));
  }

  Future<FeeInstallment?> getInstallmentById(AppUser user, String installmentId) {
    if (!canView(user)) {
      return Future.value(null);
    }
    return _repository.getInstallment(installmentId);
  }

  Stream<List<Payment>> watchPaymentsForInstallment(
    AppUser user,
    String installmentId,
  ) {
    if (!canView(user)) {
      return Stream.value(const <Payment>[]);
    }
    return _repository.watchPaymentsForInstallment(installmentId);
  }

  Future<List<Payment>> getPaymentsForInstallment(
    AppUser user,
    String installmentId,
  ) {
    if (!canView(user)) {
      return Future.value(const <Payment>[]);
    }
    return _repository.getPaymentsForInstallment(installmentId);
  }

  Future<FeeInstallment> createInstallmentForUser(
    AppUser user,
    FeeInstallment installment, {
    Student? student,
  }) async {
    _ensureCanManage(user);
    if (student != null && student.status != 'active') {
      throw const FeeValidationException(
        'Cannot create a fee instalment for an inactive or archived student.',
      );
    }
    _validateInstallment(installment);
    return _repository.createInstallment(installment);
  }

  Future<Payment> recordPaymentForUser(
    AppUser user, {
    required FeeInstallment installment,
    required double amount,
    required String paymentMethod,
    String? referenceNumber,
    DateTime? paymentDate,
  }) async {
    _ensureCanManage(user);

    final paymentPaise = (amount * 100).round();
    if (paymentPaise <= 0) {
      throw const FeeValidationException(
        'Payment amount must be greater than zero.',
      );
    }

    if (paymentPaise > installment.balancePaise) {
      throw FeeValidationException(
        'Payment amount ₹${amount.toStringAsFixed(2)} exceeds remaining balance of ₹${installment.outstandingBalance.toStringAsFixed(2)}.',
      );
    }

    final payment = Payment(
      id: '',
      instituteId: installment.instituteId,
      feeInstallmentId: installment.id,
      studentId: installment.studentId,
      amount: amount,
      paymentDate: paymentDate ?? DateTime.now(),
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      recordedBy: user.id,
      createdAt: DateTime.now(),
    );

    return _repository.recordPayment(
      installment: installment,
      payment: payment,
    );
  }

  FeeSummary calculateSummary(
    List<FeeInstallment> installments, {
    DateTime? asOf,
  }) {
    var duePaise = 0;
    var paidPaise = 0;
    var overduePaise = 0;
    var overdueCount = 0;

    final now = asOf ?? DateTime.now();

    for (final item in installments) {
      final itemDue = item.amountDuePaise;
      final itemPaid = item.paidAmountPaise;
      final itemBalance = (itemDue - itemPaid).clamp(0, itemDue);

      duePaise += itemDue;
      paidPaise += itemPaid;

      final status = FeeInstallment.deriveStatus(
        amountDue: item.amountDue,
        paidAmount: item.paidAmount,
        dueDate: item.dueDate,
        asOf: now,
      );

      if (status == 'overdue') {
        overdueCount++;
        overduePaise += itemBalance;
      }
    }

    final balancePaise = (duePaise - paidPaise).clamp(0, duePaise);

    return FeeSummary(
      totalDue: duePaise / 100.0,
      totalPaid: paidPaise / 100.0,
      outstandingBalance: balancePaise / 100.0,
      overdueCount: overdueCount,
      overdueAmount: overduePaise / 100.0,
    );
  }

  FeeAccessScope _scopeFor(AppUser user) =>
      FeeAccessScope(instituteId: user.instituteId);

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const FeeValidationException(
        'Your demo role does not have permission to manage fees.',
      );
    }
  }

  void _validateInstallment(FeeInstallment installment) {
    if (installment.studentId.trim().isEmpty) {
      throw const FeeValidationException('Please select a student.');
    }
    if (installment.amountDue <= 0) {
      throw const FeeValidationException(
        'Instalment amount must be greater than zero.',
      );
    }
  }
}
