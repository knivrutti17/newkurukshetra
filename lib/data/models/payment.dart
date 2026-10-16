import 'package:cloud_firestore/cloud_firestore.dart';

/// A payment transaction stored in the top-level `payments` Firestore collection.
class Payment {
  const Payment({
    required this.id,
    required this.instituteId,
    required this.feeInstallmentId,
    required this.studentId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    required this.recordedBy,
    required this.createdAt,
    this.referenceNumber,
  });

  static const paymentMethods = <String>[
    'Cash',
    'UPI',
    'Bank Transfer',
    'Cheque',
    'Card',
  ];

  final String id;
  final String instituteId;
  final String feeInstallmentId;
  final String studentId;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String? referenceNumber;
  final String recordedBy;
  final DateTime createdAt;

  int get amountPaise => (amount * 100).round();

  factory Payment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Payment(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      feeInstallmentId: data['feeInstallmentId'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      amount: _asDouble(data['amount']),
      paymentDate: _asDate(data['paymentDate']),
      paymentMethod: data['paymentMethod'] as String? ?? 'Cash',
      referenceNumber: data['referenceNumber'] as String?,
      recordedBy: data['recordedBy'] as String? ?? '',
      createdAt: _asDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'feeInstallmentId': feeInstallmentId,
    'studentId': studentId,
    'amount': amount,
    'paymentDate': Timestamp.fromDate(paymentDate),
    'paymentMethod': paymentMethod,
    if (referenceNumber != null && referenceNumber!.trim().isNotEmpty)
      'referenceNumber': referenceNumber!.trim(),
    'recordedBy': recordedBy,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  Payment copyWith({
    String? id,
    String? instituteId,
    String? feeInstallmentId,
    String? studentId,
    double? amount,
    DateTime? paymentDate,
    String? paymentMethod,
    String? referenceNumber,
    String? recordedBy,
    DateTime? createdAt,
  }) => Payment(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    feeInstallmentId: feeInstallmentId ?? this.feeInstallmentId,
    studentId: studentId ?? this.studentId,
    amount: amount ?? this.amount,
    paymentDate: paymentDate ?? this.paymentDate,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    recordedBy: recordedBy ?? this.recordedBy,
    createdAt: createdAt ?? this.createdAt,
  );

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

