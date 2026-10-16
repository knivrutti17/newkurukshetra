import 'package:cloud_firestore/cloud_firestore.dart';

/// A pending administrative or academic action awaiting authorized review.
class ApprovalAction {
  const ApprovalAction({
    required this.id,
    required this.instituteId,
    required this.type,
    required this.title,
    required this.description,
    required this.payload,
    required this.requestedBy,
    required this.requestedAt,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectionReason,
    required this.updatedAt,
  });

  final String id;
  final String instituteId;
  final String type; // e.g. 'fee_concession', 'batch_transfer', 'attendance_override', 'refund_request', 'schedule_override'
  final String title;
  final String description;
  final Map<String, dynamic> payload;
  final String requestedBy;
  final DateTime requestedAt;
  final String status; // 'pending', 'approved', 'rejected', 'awaiting_execution'
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime updatedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isAwaitingExecution => status == 'awaiting_execution';

  String get typeLabel => switch (type) {
        'fee_concession' => 'Fee Concession',
        'batch_transfer' => 'Batch Transfer',
        'attendance_override' => 'Attendance Override',
        'refund_request' => 'Refund Request',
        'schedule_override' => 'Schedule Override',
        _ => type.replaceAll('_', ' ').toUpperCase(),
      };

  String get statusLabel => switch (status) {
        'pending' => 'Pending Review',
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'awaiting_execution' => 'Awaiting Execution',
        _ => status,
      };

  factory ApprovalAction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ApprovalAction(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      type: data['type'] as String? ?? 'general',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      payload: (data['payload'] as Map<String, dynamic>?) ?? const {},
      requestedBy: data['requestedBy'] as String? ?? 'Staff Member',
      requestedAt: _asDate(data['requestedAt']),
      status: data['status'] as String? ?? 'pending',
      approvedBy: data['approvedBy'] as String?,
      approvedAt: _asNullableDate(data['approvedAt']),
      rejectedBy: data['rejectedBy'] as String?,
      rejectedAt: _asNullableDate(data['rejectedAt']),
      rejectionReason: data['rejectionReason'] as String?,
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
        'instituteId': instituteId,
        'type': type,
        'title': title,
        'description': description,
        'payload': payload,
        'requestedBy': requestedBy,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'status': status,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
        if (rejectedBy != null) 'rejectedBy': rejectedBy,
        if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('requestedAt');
    return data;
  }

  ApprovalAction copyWith({
    String? id,
    String? instituteId,
    String? type,
    String? title,
    String? description,
    Map<String, dynamic>? payload,
    String? requestedBy,
    DateTime? requestedAt,
    String? status,
    String? approvedBy,
    DateTime? approvedAt,
    String? rejectedBy,
    DateTime? rejectedAt,
    String? rejectionReason,
    DateTime? updatedAt,
  }) =>
      ApprovalAction(
        id: id ?? this.id,
        instituteId: instituteId ?? this.instituteId,
        type: type ?? this.type,
        title: title ?? this.title,
        description: description ?? this.description,
        payload: payload ?? this.payload,
        requestedBy: requestedBy ?? this.requestedBy,
        requestedAt: requestedAt ?? this.requestedAt,
        status: status ?? this.status,
        approvedBy: approvedBy ?? this.approvedBy,
        approvedAt: approvedAt ?? this.approvedAt,
        rejectedBy: rejectedBy ?? this.rejectedBy,
        rejectedAt: rejectedAt ?? this.rejectedAt,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        updatedAt: updatedAt ?? this.updatedAt,
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
    if (value == null) return null;
    return _asDate(value);
  }
}

