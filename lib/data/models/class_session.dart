import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of scheduling conflict detected by the clash detection engine.
enum ScheduleConflictType {
  trainerConflict,
  roomConflict,
  batchConflict,
  availabilityConflict,
  statusConflict,
}

/// An explainable scheduling conflict preventing a class session from being saved.
class ScheduleConflict {
  const ScheduleConflict({
    required this.type,
    required this.message,
    this.conflictingSession,
  });

  final ScheduleConflictType type;
  final String message;
  final ClassSession? conflictingSession;

  String get typeLabel => switch (type) {
        ScheduleConflictType.trainerConflict => 'Trainer Double-Booking',
        ScheduleConflictType.roomConflict => 'Classroom Conflict',
        ScheduleConflictType.batchConflict => 'Batch Overlap',
        ScheduleConflictType.availabilityConflict => 'Outside Available Hours',
        ScheduleConflictType.statusConflict => 'Inactive Entity',
      };
}

/// A scheduled class session stored in the `classSessions` Firestore collection.
class ClassSession {
  const ClassSession({
    required this.id,
    required this.instituteId,
    required this.batchId,
    required this.batchName,
    required this.courseId,
    required this.courseName,
    required this.trainerId,
    required this.trainerName,
    required this.startAt,
    required this.endAt,
    required this.deliveryMode,
    required this.roomId,
    required this.roomName,
    required this.meetingLink,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const deliveryModes = <String>['in_person', 'online', 'hybrid'];
  static const statuses = <String>['scheduled', 'completed', 'cancelled'];

  final String id;
  final String instituteId;
  final String batchId;
  final String batchName;
  final String courseId;
  final String courseName;
  final String trainerId;
  final String trainerName;
  final DateTime startAt;
  final DateTime endAt;
  final String deliveryMode; // 'in_person', 'online', 'hybrid'
  final String roomId;
  final String roomName;
  final String meetingLink;
  final String status; // 'scheduled', 'completed', 'cancelled'
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isScheduled => status == 'scheduled';

  bool get isInPerson => deliveryMode == 'in_person';
  bool get isOnline => deliveryMode == 'online';
  bool get isHybrid => deliveryMode == 'hybrid';

  Duration get duration => endAt.difference(startAt);

  String get deliveryModeLabel => switch (deliveryMode) {
        'in_person' => 'In-Person',
        'online' => 'Online Live',
        'hybrid' => 'Hybrid',
        _ => deliveryMode,
      };

  String get statusLabel => switch (status) {
        'scheduled' => 'Scheduled',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  factory ClassSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ClassSession(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      batchId: data['batchId'] as String? ?? '',
      batchName: data['batchName'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      trainerId: data['trainerId'] as String? ?? '',
      trainerName: data['trainerName'] as String? ?? '',
      startAt: _asDate(data['startAt']),
      endAt: _asDate(data['endAt']),
      deliveryMode: data['deliveryMode'] as String? ?? 'in_person',
      roomId: data['roomId'] as String? ?? '',
      roomName: data['roomName'] as String? ?? '',
      meetingLink: data['meetingLink'] as String? ?? '',
      status: data['status'] as String? ?? 'scheduled',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
        'instituteId': instituteId,
        'batchId': batchId,
        'batchName': batchName,
        'courseId': courseId,
        'courseName': courseName,
        'trainerId': trainerId,
        'trainerName': trainerName,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'deliveryMode': deliveryMode,
        'roomId': roomId,
        'roomName': roomName,
        'meetingLink': meetingLink,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  ClassSession copyWith({
    String? id,
    String? instituteId,
    String? batchId,
    String? batchName,
    String? courseId,
    String? courseName,
    String? trainerId,
    String? trainerName,
    DateTime? startAt,
    DateTime? endAt,
    String? deliveryMode,
    String? roomId,
    String? roomName,
    String? meetingLink,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ClassSession(
        id: id ?? this.id,
        instituteId: instituteId ?? this.instituteId,
        batchId: batchId ?? this.batchId,
        batchName: batchName ?? this.batchName,
        courseId: courseId ?? this.courseId,
        courseName: courseName ?? this.courseName,
        trainerId: trainerId ?? this.trainerId,
        trainerName: trainerName ?? this.trainerName,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        deliveryMode: deliveryMode ?? this.deliveryMode,
        roomId: roomId ?? this.roomId,
        roomName: roomName ?? this.roomName,
        meetingLink: meetingLink ?? this.meetingLink,
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
}

