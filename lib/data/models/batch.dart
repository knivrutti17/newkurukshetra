import 'package:cloud_firestore/cloud_firestore.dart';

/// A batch stored in the top-level `batches` Firestore collection.
class Batch {
  const Batch({
    required this.id,
    required this.instituteId,
    required this.name,
    required this.courseId,
    required this.courseName,
    required this.trainerId,
    required this.trainerName,
    required this.startDate,
    required this.endDate,
    required this.capacity,
    required this.scheduleDescription,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const statuses = <String>['active', 'archived'];

  final String id;
  final String instituteId;
  final String name;
  final String courseId;
  final String courseName;
  final String trainerId;
  final String trainerName;
  final DateTime startDate;
  final DateTime endDate;
  final int capacity;
  final String scheduleDescription;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => status == 'archived';

  factory Batch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Batch(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      name: data['name'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      trainerId: data['trainerId'] as String? ?? '',
      trainerName: data['trainerName'] as String? ?? '',
      startDate: _asDate(data['startDate']),
      endDate: _asDate(data['endDate']),
      capacity: _asInt(data['capacity'], fallback: 20),
      scheduleDescription: data['scheduleDescription'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'name': name,
    'courseId': courseId,
    'courseName': courseName,
    'trainerId': trainerId,
    'trainerName': trainerName,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': Timestamp.fromDate(endDate),
    'capacity': capacity,
    'scheduleDescription': scheduleDescription,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  Batch copyWith({
    String? id,
    String? instituteId,
    String? name,
    String? courseId,
    String? courseName,
    String? trainerId,
    String? trainerName,
    DateTime? startDate,
    DateTime? endDate,
    int? capacity,
    String? scheduleDescription,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Batch(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    name: name ?? this.name,
    courseId: courseId ?? this.courseId,
    courseName: courseName ?? this.courseName,
    trainerId: trainerId ?? this.trainerId,
    trainerName: trainerName ?? this.trainerName,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    capacity: capacity ?? this.capacity,
    scheduleDescription: scheduleDescription ?? this.scheduleDescription,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
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

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}

