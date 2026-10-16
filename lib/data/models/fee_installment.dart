import 'package:cloud_firestore/cloud_firestore.dart';

/// A fee instalment stored in the top-level `feeInstallments` Firestore collection.
class FeeInstallment {
  const FeeInstallment({
    required this.id,
    required this.instituteId,
    required this.studentId,
    required this.studentName,
    required this.courseId,
    required this.batchId,
    required this.amountDue,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.paidAmount = 0.0,
  });

  static const statuses = <String>['pending', 'partiallyPaid', 'paid', 'overdue'];

  final String id;
  final String instituteId;
  final String studentId;
  final String studentName;
  final String courseId;
  final String batchId;
  final double amountDue;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final double paidAmount;

  int get amountDuePaise => (amountDue * 100).round();
  int get paidAmountPaise => (paidAmount * 100).round();
  int get balancePaise =>
      (amountDuePaise - paidAmountPaise).clamp(0, amountDuePaise);
  double get outstandingBalance => balancePaise / 100.0;

  bool get isPaid => paidAmountPaise >= amountDuePaise && amountDuePaise > 0;

  /// Calculates payment status from due date, amount due, and recorded payments.
  ///
  /// A paid instalment must NEVER become overdue.
  static String deriveStatus({
    required double amountDue,
    required double paidAmount,
    required DateTime dueDate,
    DateTime? asOf,
  }) {
    final duePaise = (amountDue * 100).round();
    final paidPaise = (paidAmount * 100).round();

    if (paidPaise >= duePaise && duePaise > 0) {
      return 'paid';
    }

    final now = asOf ?? DateTime.now();
    // End of due date (23:59:59)
    final endOfDueDate = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      23,
      59,
      59,
    );
    final isPastDue = now.isAfter(endOfDueDate);

    if (isPastDue && paidPaise < duePaise) {
      return 'overdue';
    }
    if (paidPaise > 0) {
      return 'partiallyPaid';
    }
    return 'pending';
  }

  factory FeeInstallment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final amountDue = _asDouble(data['amountDue']);
    final paidAmount = _asDouble(data['paidAmount']);
    final dueDate = _asDate(data['dueDate']);
    final rawStatus = data['status'] as String?;

    // Derive status to ensure accurate overdue/paid evaluation
    final derived = deriveStatus(
      amountDue: amountDue,
      paidAmount: paidAmount,
      dueDate: dueDate,
    );

    return FeeInstallment(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      batchId: data['batchId'] as String? ?? '',
      amountDue: amountDue,
      dueDate: dueDate,
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      status: rawStatus ?? derived,
      paidAmount: paidAmount,
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'studentId': studentId,
    'studentName': studentName,
    'courseId': courseId,
    'batchId': batchId,
    'amountDue': amountDue,
    'dueDate': Timestamp.fromDate(dueDate),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'status': status.isNotEmpty
        ? status
        : deriveStatus(
            amountDue: amountDue,
            paidAmount: paidAmount,
            dueDate: dueDate,
          ),
    'paidAmount': paidAmount,
  };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  FeeInstallment copyWith({
    String? id,
    String? instituteId,
    String? studentId,
    String? studentName,
    String? courseId,
    String? batchId,
    double? amountDue,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
    double? paidAmount,
  }) {
    final newAmountDue = amountDue ?? this.amountDue;
    final newPaidAmount = paidAmount ?? this.paidAmount;
    final newDueDate = dueDate ?? this.dueDate;

    return FeeInstallment(
      id: id ?? this.id,
      instituteId: instituteId ?? this.instituteId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      courseId: courseId ?? this.courseId,
      batchId: batchId ?? this.batchId,
      amountDue: newAmountDue,
      dueDate: newDueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ??
          deriveStatus(
            amountDue: newAmountDue,
            paidAmount: newPaidAmount,
            dueDate: newDueDate,
          ),
      paidAmount: newPaidAmount,
    );
  }

  static DateTime _asDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
}
