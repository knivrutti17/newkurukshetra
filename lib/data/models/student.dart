import 'package:cloud_firestore/cloud_firestore.dart';

/// A student stored in the top-level `students` Firestore collection.
///
/// [counselorId] and [trainerId] are optional assignment fields used by the
/// demo UI to narrow the records shown to those roles. They are not a security
/// boundary; production must enforce equivalent rules with trusted identities.
class Student {
  const Student({
    required this.id,
    required this.instituteId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.courseId,
    required this.courseName,
    required this.batchId,
    required this.batchName,
    required this.enrollmentDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.counselorId,
    this.trainerId,
  });

  static const statuses = <String>['active', 'inactive', 'archived'];

  final String id;
  final String instituteId;
  final String fullName;
  final String email;
  final String phone;
  final String courseId;
  final String courseName;
  final String batchId;
  final String batchName;
  final DateTime enrollmentDate;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? counselorId;
  final String? trainerId;

  bool get isArchived => status == 'archived';

  factory Student.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Student(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      fullName: data['fullName'] as String? ?? 'Unnamed student',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      batchId: data['batchId'] as String? ?? '',
      batchName: data['batchName'] as String? ?? '',
      enrollmentDate: _asDate(data['enrollmentDate']),
      status: data['status'] as String? ?? 'active',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      counselorId: data['counselorId'] as String?,
      trainerId: data['trainerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'courseId': courseId,
    'courseName': courseName,
    'batchId': batchId,
    'batchName': batchName,
    'enrollmentDate': Timestamp.fromDate(enrollmentDate),
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    if (counselorId != null) 'counselorId': counselorId,
    if (trainerId != null) 'trainerId': trainerId,
  };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  Student copyWith({
    String? id,
    String? instituteId,
    String? fullName,
    String? email,
    String? phone,
    String? courseId,
    String? courseName,
    String? batchId,
    String? batchName,
    DateTime? enrollmentDate,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? counselorId,
    String? trainerId,
  }) => Student(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    courseId: courseId ?? this.courseId,
    courseName: courseName ?? this.courseName,
    batchId: batchId ?? this.batchId,
    batchName: batchName ?? this.batchName,
    enrollmentDate: enrollmentDate ?? this.enrollmentDate,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    counselorId: counselorId ?? this.counselorId,
    trainerId: trainerId ?? this.trainerId,
  );

  /// Creates a stable identifier suitable for client-created course/batch IDs.
  static String identifierFromName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
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
}
