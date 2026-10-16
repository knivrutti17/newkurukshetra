import 'package:cloud_firestore/cloud_firestore.dart';

enum StudentAlertType {
  lowAttendance,
  repeatedAbsence,
  overdueFees,
  combinedRisk,
}

extension StudentAlertTypeValue on StudentAlertType {
  String get value => name;

  String get label => switch (this) {
    StudentAlertType.lowAttendance => 'Low attendance',
    StudentAlertType.repeatedAbsence => 'Repeated absences',
    StudentAlertType.overdueFees => 'Overdue instalments',
    StudentAlertType.combinedRisk => 'Attendance and fees',
  };

  bool get isAcademic =>
      this == StudentAlertType.lowAttendance ||
      this == StudentAlertType.repeatedAbsence;

  static StudentAlertType fromValue(String? value) => switch (value) {
    'repeatedAbsence' => StudentAlertType.repeatedAbsence,
    'overdueFees' => StudentAlertType.overdueFees,
    'combinedRisk' => StudentAlertType.combinedRisk,
    _ => StudentAlertType.lowAttendance,
  };
}

enum StudentAlertSeverity { low, medium, high }

extension StudentAlertSeverityValue on StudentAlertSeverity {
  String get value => name;

  String get label => switch (this) {
    StudentAlertSeverity.low => 'Low',
    StudentAlertSeverity.medium => 'Medium',
    StudentAlertSeverity.high => 'High',
  };

  static StudentAlertSeverity fromValue(String? value) => switch (value) {
    'medium' => StudentAlertSeverity.medium,
    'high' => StudentAlertSeverity.high,
    _ => StudentAlertSeverity.low,
  };
}

enum StudentAlertStatus { newAlert, inReview, followUp, resolved, dismissed }

extension StudentAlertStatusValue on StudentAlertStatus {
  String get value => switch (this) {
    StudentAlertStatus.newAlert => 'new',
    _ => name,
  };

  String get label => switch (this) {
    StudentAlertStatus.newAlert => 'New',
    StudentAlertStatus.inReview => 'In review',
    StudentAlertStatus.followUp => 'Follow-up pending',
    StudentAlertStatus.resolved => 'Resolved',
    StudentAlertStatus.dismissed => 'Dismissed',
  };

  bool get isClosed =>
      this == StudentAlertStatus.resolved ||
      this == StudentAlertStatus.dismissed;

  static StudentAlertStatus fromValue(String? value) => switch (value) {
    'inReview' => StudentAlertStatus.inReview,
    'followUp' => StudentAlertStatus.followUp,
    'resolved' => StudentAlertStatus.resolved,
    'dismissed' => StudentAlertStatus.dismissed,
    _ => StudentAlertStatus.newAlert,
  };
}

/// An append-only, lightweight history entry embedded in its alert document.
/// Keeping it with the alert avoids a second collection for ordinary follow-up.
class AlertFollowUpEntry {
  const AlertFollowUpEntry({
    required this.at,
    required this.actorId,
    required this.actorName,
    required this.note,
    this.status,
  });

  final DateTime at;
  final String actorId;
  final String actorName;
  final String note;
  final StudentAlertStatus? status;

  factory AlertFollowUpEntry.fromMap(Map<String, dynamic> data) =>
      AlertFollowUpEntry(
        at: _asDate(data['at']),
        actorId: data['actorId'] as String? ?? '',
        actorName: data['actorName'] as String? ?? '',
        note: data['note'] as String? ?? '',
        status: data['status'] == null
            ? null
            : StudentAlertStatusValue.fromValue(data['status'] as String?),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'at': Timestamp.fromDate(at),
    'actorId': actorId,
    'actorName': actorName,
    'note': note,
    if (status != null) 'status': status!.value,
  };
}

/// A persisted, explainable indicator for human review. It is not a prediction.
class StudentAlert {
  const StudentAlert({
    required this.id,
    required this.instituteId,
    required this.studentId,
    required this.studentName,
    required this.batchId,
    required this.batchName,
    required this.alertType,
    required this.severity,
    required this.title,
    required this.reason,
    required this.evidence,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.counselorId,
    this.trainerId,
    this.assignedTo,
    this.followUpNote,
    this.followUpHistory = const <AlertFollowUpEntry>[],
    this.resolvedAt,
    this.resolvedBy,
    this.closureReason,
  });

  final String id;
  final String instituteId;
  final String studentId;
  final String studentName;
  final String batchId;
  final String batchName;
  final StudentAlertType alertType;
  final StudentAlertSeverity severity;
  final String title;
  final String reason;
  final Map<String, dynamic> evidence;
  final StudentAlertStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? counselorId;
  final String? trainerId;
  final String? assignedTo;
  final String? followUpNote;
  final List<AlertFollowUpEntry> followUpHistory;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? closureReason;

  bool get isActive => !status.isClosed;

  static String deterministicId({
    required String instituteId,
    required String studentId,
    required StudentAlertType type,
  }) => '$instituteId--$studentId--${type.value}';

  factory StudentAlert.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawHistory = data['followUpHistory'];
    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map(
                (item) =>
                    AlertFollowUpEntry.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <AlertFollowUpEntry>[];
    return StudentAlert(
      id: document.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? 'Unnamed student',
      batchId: data['batchId'] as String? ?? '',
      batchName: data['batchName'] as String? ?? '',
      alertType: StudentAlertTypeValue.fromValue(data['alertType'] as String?),
      severity: StudentAlertSeverityValue.fromValue(
        data['severity'] as String?,
      ),
      title: data['title'] as String? ?? 'Student risk alert',
      reason: data['reason'] as String? ?? '',
      evidence: _map(data['evidence']),
      status: StudentAlertStatusValue.fromValue(data['status'] as String?),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      counselorId: data['counselorId'] as String?,
      trainerId: data['trainerId'] as String?,
      assignedTo: data['assignedTo'] as String?,
      followUpNote: data['followUpNote'] as String?,
      followUpHistory: history,
      resolvedAt: data['resolvedAt'] == null
          ? null
          : _asDate(data['resolvedAt']),
      resolvedBy: data['resolvedBy'] as String?,
      closureReason: data['closureReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'studentId': studentId,
    'studentName': studentName,
    'batchId': batchId,
    'batchName': batchName,
    'alertType': alertType.value,
    'severity': severity.value,
    'title': title,
    'reason': reason,
    'evidence': evidence,
    'status': status.value,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    if (counselorId != null) 'counselorId': counselorId,
    if (trainerId != null) 'trainerId': trainerId,
    if (assignedTo != null) 'assignedTo': assignedTo,
    if (followUpNote != null) 'followUpNote': followUpNote,
    'followUpHistory': followUpHistory.map((entry) => entry.toMap()).toList(),
    if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
    if (resolvedBy != null) 'resolvedBy': resolvedBy,
    if (closureReason != null) 'closureReason': closureReason,
  };

  StudentAlert copyWith({
    String? studentName,
    String? batchId,
    String? batchName,
    StudentAlertSeverity? severity,
    String? title,
    String? reason,
    Map<String, dynamic>? evidence,
    StudentAlertStatus? status,
    DateTime? updatedAt,
    String? assignedTo,
    String? followUpNote,
    List<AlertFollowUpEntry>? followUpHistory,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? closureReason,
  }) => StudentAlert(
    id: id,
    instituteId: instituteId,
    studentId: studentId,
    studentName: studentName ?? this.studentName,
    batchId: batchId ?? this.batchId,
    batchName: batchName ?? this.batchName,
    alertType: alertType,
    severity: severity ?? this.severity,
    title: title ?? this.title,
    reason: reason ?? this.reason,
    evidence: evidence ?? this.evidence,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    counselorId: counselorId,
    trainerId: trainerId,
    assignedTo: assignedTo ?? this.assignedTo,
    followUpNote: followUpNote ?? this.followUpNote,
    followUpHistory: followUpHistory ?? this.followUpHistory,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    closureReason: closureReason ?? this.closureReason,
  );
}

DateTime _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}
