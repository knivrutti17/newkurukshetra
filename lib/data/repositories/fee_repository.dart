import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fee_installment.dart';
import '../models/payment.dart';

class FeeAccessScope {
  const FeeAccessScope({this.instituteId = 'demo-institute'});

  final String? instituteId;
}

abstract interface class FeeRepository {
  Stream<List<FeeInstallment>> watchInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 200,
  });

  Future<List<FeeInstallment>> getInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
  });

  Future<FeeInstallment?> getInstallment(String id);

  Future<FeeInstallment> createInstallment(FeeInstallment installment);

  Stream<List<Payment>> watchPaymentsForInstallment(String installmentId);

  Future<List<Payment>> getPaymentsForInstallment(String installmentId);

  Stream<List<Payment>> watchAllPayments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 500,
  });

  Future<Payment> recordPayment({
    required FeeInstallment installment,
    required Payment payment,
  });

  Future<bool> isFeeInstallmentsEmpty();
}

abstract interface class FeeSeedRepository {
  Future<bool> isFeeInstallmentsEmpty();
  Future<int> countExistingSampleInstallments(List<FeeInstallment> samples);
  Future<void> createMissingSampleInstallmentsAndPayments({
    required List<FeeInstallment> installments,
    required List<Payment> payments,
  });
}

class FirestoreFeeRepository implements FeeRepository, FeeSeedRepository {
  FirestoreFeeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _installments =>
      _firestore.collection('feeInstallments');

  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  @override
  Stream<List<FeeInstallment>> watchInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query = _installments.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    return query.snapshots().map((snapshot) {
      final list = snapshot.docs.map(FeeInstallment.fromFirestore).toList();
      list.sort((left, right) => left.dueDate.compareTo(right.dueDate));
      return list;
    });
  }

  @override
  Future<List<FeeInstallment>> getInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _installments;
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    final snapshot = await query.get();
    final list = snapshot.docs.map(FeeInstallment.fromFirestore).toList();
    list.sort((left, right) => left.dueDate.compareTo(right.dueDate));
    return list;
  }

  @override
  Future<FeeInstallment?> getInstallment(String id) async {
    final doc = await _installments.doc(id).get();
    if (!doc.exists) return null;
    return FeeInstallment.fromFirestore(doc);
  }

  @override
  Future<FeeInstallment> createInstallment(FeeInstallment installment) async {
    final now = DateTime.now();
    final document = installment.id.isEmpty
        ? _installments.doc()
        : _installments.doc(installment.id);
    final saved = installment.copyWith(
      id: document.id,
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
    await document.set(saved.toFirestore());
    return saved;
  }

  @override
  Stream<List<Payment>> watchPaymentsForInstallment(String installmentId) =>
      _payments
          .where('feeInstallmentId', isEqualTo: installmentId)
          .snapshots()
          .map((snapshot) {
            final list = snapshot.docs.map(Payment.fromFirestore).toList();
            list.sort(
              (left, right) => right.paymentDate.compareTo(left.paymentDate),
            );
            return list;
          });

  @override
  Future<List<Payment>> getPaymentsForInstallment(String installmentId) async {
    final snapshot = await _payments
        .where('feeInstallmentId', isEqualTo: installmentId)
        .get();
    final list = snapshot.docs.map(Payment.fromFirestore).toList();
    list.sort((left, right) => right.paymentDate.compareTo(left.paymentDate));
    return list;
  }

  @override
  Stream<List<Payment>> watchAllPayments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 500,
  }) {
    Query<Map<String, dynamic>> query = _payments.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    return query.snapshots().map((snapshot) {
      final list = snapshot.docs.map(Payment.fromFirestore).toList();
      list.sort((left, right) => right.paymentDate.compareTo(left.paymentDate));
      return list;
    });
  }

  @override
  Future<Payment> recordPayment({
    required FeeInstallment installment,
    required Payment payment,
  }) async {
    return _firestore.runTransaction((transaction) async {
      final instRef = _installments.doc(installment.id);
      final instSnapshot = await transaction.get(instRef);

      if (!instSnapshot.exists) {
        throw StateError('Instalment ${installment.id} does not exist.');
      }

      final current = FeeInstallment.fromFirestore(instSnapshot);
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

      final payRef = payment.id.isEmpty ? _payments.doc() : _payments.doc(payment.id);
      final savedPayment = payment.copyWith(
        id: payRef.id,
        createdAt: now,
      );

      transaction.set(payRef, savedPayment.toFirestore());
      transaction.update(instRef, {
        'paidAmount': updatedPaidAmount,
        'status': newStatus,
        'updatedAt': Timestamp.fromDate(now),
      });

      return savedPayment;
    });
  }

  @override
  Future<bool> isFeeInstallmentsEmpty() async {
    final snapshot = await _installments.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleInstallments(
    List<FeeInstallment> samples,
  ) async {
    final ids = samples.map((item) => item.id).toList();
    final snapshots =
        await Future.wait(ids.map((id) => _installments.doc(id).get()));
    return snapshots.where((item) => item.exists).length;
  }

  @override
  Future<void> createMissingSampleInstallmentsAndPayments({
    required List<FeeInstallment> installments,
    required List<Payment> payments,
  }) async {
    final batch = _firestore.batch();
    for (final inst in installments) {
      final ref = _installments.doc(inst.id);
      batch.set(ref, inst.toFirestore(), SetOptions(merge: false));
    }
    for (final p in payments) {
      final ref = _payments.doc(p.id);
      batch.set(ref, p.toFirestore(), SetOptions(merge: false));
    }
    await batch.commit();
  }
}

