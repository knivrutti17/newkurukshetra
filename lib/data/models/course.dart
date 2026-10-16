import 'package:cloud_firestore/cloud_firestore.dart';

/// A course stored in the top-level `courses` Firestore collection.
class Course {
  const Course({
    required this.id,
    required this.instituteId,
    required this.name,
    required this.description,
    required this.duration,
    required this.feeAmount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const statuses = <String>['active', 'archived'];

  final String id;
  final String instituteId;
  final String name;
  final String description;
  final String duration;
  final double feeAmount;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => status == 'archived';

  factory Course.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Course(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      duration: data['duration'] as String? ?? '',
      feeAmount: _asDouble(data['feeAmount']),
      status: data['status'] as String? ?? 'active',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'name': name,
    'description': description,
    'duration': duration,
    'feeAmount': feeAmount,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  Course copyWith({
    String? id,
    String? instituteId,
    String? name,
    String? description,
    String? duration,
    double? feeAmount,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Course(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    name: name ?? this.name,
    description: description ?? this.description,
    duration: duration ?? this.duration,
    feeAmount: feeAmount ?? this.feeAmount,
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

