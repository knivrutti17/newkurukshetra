import 'package:cloud_firestore/cloud_firestore.dart';

enum AttendanceStatus { present, absent, late }

extension AttendanceStatusValue on AttendanceStatus {
  String get value => name;

  String get label => switch (this) {
    AttendanceStatus.present => 'Present',
    AttendanceStatus.absent => 'Absent',
    AttendanceStatus.late => 'Late',
  };

  static AttendanceStatus fromValue(String? value) => switch (value) {
    'absent' => AttendanceStatus.absent,
    'late' => AttendanceStatus.late,
    _ => AttendanceStatus.present,
  };
}

/// One student's attendance for one batch on one class date.
///
/// The deterministic document ID prevents two documents being created for the
/// same student and class session. Assignment fields support the demo's
/// scoped UI; Firebase rules must enforce real access in production.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.instituteId,
    required this.studentId,
    required this.batchId,
    required this.classDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.recordedBy,
    this.counselorId,
    this.trainerId,
  });

  final String id;
  final String instituteId;
  final String studentId;
  final String batchId;
  final DateTime classDate;
  final AttendanceStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String recordedBy;
  final String? counselorId;
  final String? trainerId;

  factory AttendanceRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AttendanceRecord(
      id: document.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      studentId: data['studentId'] as String? ?? '',
      batchId: data['batchId'] as String? ?? '',
      classDate: _asDate(data['classDate']),
      status: AttendanceStatusValue.fromValue(data['status'] as String?),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      recordedBy: data['recordedBy'] as String? ?? '',
      counselorId: data['counselorId'] as String?,
      trainerId: data['trainerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'studentId': studentId,
    'batchId': batchId,
    'classDate': Timestamp.fromDate(normalizeClassDate(classDate)),
    'status': status.value,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'recordedBy': recordedBy,
    if (counselorId != null) 'counselorId': counselorId,
    if (trainerId != null) 'trainerId': trainerId,
  };

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    DateTime? updatedAt,
    String? recordedBy,
  }) => AttendanceRecord(
    id: id,
    instituteId: instituteId,
    studentId: studentId,
    batchId: batchId,
    classDate: classDate,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    recordedBy: recordedBy ?? this.recordedBy,
    counselorId: counselorId,
    trainerId: trainerId,
  );

  static DateTime normalizeClassDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String dateKey(DateTime value) {
    final date = normalizeClassDate(value);
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String documentId({
    required String instituteId,
    required String batchId,
    required DateTime classDate,
    required String studentId,
  }) => '$instituteId--$batchId--${dateKey(classDate)}--$studentId';

  static DateTime _asDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
