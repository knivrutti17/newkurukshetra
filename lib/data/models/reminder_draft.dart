import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'fee_installment.dart';

enum ReminderDraftStatus { draft, approved, cancelled }

extension ReminderDraftStatusValue on ReminderDraftStatus {
  String get value => switch (this) {
    ReminderDraftStatus.draft => 'draft',
    ReminderDraftStatus.approved => 'approved',
    ReminderDraftStatus.cancelled => 'cancelled',
  };

  static ReminderDraftStatus fromValue(String? value) => switch (value) {
    'approved' => ReminderDraftStatus.approved,
    'cancelled' => ReminderDraftStatus.cancelled,
    _ => ReminderDraftStatus.draft,
  };
}

class ReminderDraft {
  const ReminderDraft({
    required this.id,
    required this.instituteId,
    required this.studentId,
    required this.studentName,
    required this.feeInstallmentId,
    required this.outstandingAmountAtDraft,
    required this.dueDateAtDraft,
    required this.message,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.approvedBy,
    this.approvedAt,
    this.cancelledBy,
    this.cancelledAt,
  });

  final String id;
  final String instituteId;
  final String studentId;
  final String studentName;
  final String feeInstallmentId;
  final double outstandingAmountAtDraft;
  final DateTime dueDateAtDraft;
  final String message;
  final ReminderDraftStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? cancelledBy;
  final DateTime? cancelledAt;

  static String documentId({
    required String instituteId,
    required String feeInstallmentId,
  }) => 'reminder-$instituteId-$feeInstallmentId';

  bool get isDraft => status == ReminderDraftStatus.draft;
  bool get isApproved => status == ReminderDraftStatus.approved;
  bool get isCancelled => status == ReminderDraftStatus.cancelled;

  bool isObsoleteForInstallment(FeeInstallment installment) {
    if (installment.id != feeInstallmentId) {
      return false;
    }
    return installment.balancePaise <= 0 || installment.isPaid;
  }

  static ReminderDraft buildFromInstallment({
    required String id,
    required String instituteId,
    required String studentId,
    required String studentName,
    required String feeInstallmentId,
    required String createdBy,
    required FeeInstallment installment,
    String messageTemplate = 'Hello {studentName}, our records show an outstanding instalment of {outstandingAmount} for your course, due on {dueDate}. If you have already paid, please contact the accounts team so we can verify your payment. Please contact us if you need assistance.',
  }) {
    final now = DateTime.now();
    final formattedAmount = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 2,
      locale: 'en_IN',
    ).format(installment.outstandingBalance);
    final formattedDate = DateFormat('dd/MM/yyyy').format(installment.dueDate);
    final resolvedMessage = messageTemplate
        .replaceAll('{studentName}', studentName)
        .replaceAll('{outstandingAmount}', formattedAmount)
        .replaceAll('{dueDate}', formattedDate);

    return ReminderDraft(
      id: id,
      instituteId: instituteId,
      studentId: studentId,
      studentName: studentName,
      feeInstallmentId: feeInstallmentId,
      outstandingAmountAtDraft: installment.outstandingBalance,
      dueDateAtDraft: installment.dueDate,
      message: resolvedMessage,
      status: ReminderDraftStatus.draft,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory ReminderDraft.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ReminderDraft(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      feeInstallmentId: data['feeInstallmentId'] as String? ?? '',
      outstandingAmountAtDraft: _asDouble(data['outstandingAmountAtDraft']),
      dueDateAtDraft: _asDate(data['dueDateAtDraft']),
      message: data['message'] as String? ?? '',
      status: ReminderDraftStatusValue.fromValue(data['status'] as String?),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      approvedBy: data['approvedBy'] as String?,
      approvedAt: _asNullableDate(data['approvedAt']),
      cancelledBy: data['cancelledBy'] as String?,
      cancelledAt: _asNullableDate(data['cancelledAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'id': id,
    'instituteId': instituteId,
    'studentId': studentId,
    'studentName': studentName,
    'feeInstallmentId': feeInstallmentId,
    'outstandingAmountAtDraft': outstandingAmountAtDraft,
    'dueDateAtDraft': Timestamp.fromDate(dueDateAtDraft),
    'message': message,
    'status': status.value,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    if (approvedBy != null) 'approvedBy': approvedBy,
    if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
    if (cancelledBy != null) 'cancelledBy': cancelledBy,
    if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
  };

  ReminderDraft copyWith({
    String? id,
    String? instituteId,
    String? studentId,
    String? studentName,
    String? feeInstallmentId,
    double? outstandingAmountAtDraft,
    DateTime? dueDateAtDraft,
    String? message,
    ReminderDraftStatus? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? approvedBy,
    DateTime? approvedAt,
    String? cancelledBy,
    DateTime? cancelledAt,
  }) => ReminderDraft(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    studentId: studentId ?? this.studentId,
    studentName: studentName ?? this.studentName,
    feeInstallmentId: feeInstallmentId ?? this.feeInstallmentId,
    outstandingAmountAtDraft:
        outstandingAmountAtDraft ?? this.outstandingAmountAtDraft,
    dueDateAtDraft: dueDateAtDraft ?? this.dueDateAtDraft,
    message: message ?? this.message,
    status: status ?? this.status,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    approvedBy: approvedBy ?? this.approvedBy,
    approvedAt: approvedAt ?? this.approvedAt,
    cancelledBy: cancelledBy ?? this.cancelledBy,
    cancelledAt: cancelledAt ?? this.cancelledAt,
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

  static DateTime? _asNullableDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
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
