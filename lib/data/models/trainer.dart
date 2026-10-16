import 'package:cloud_firestore/cloud_firestore.dart';

/// Structured availability details for a trainer.
///
/// Designed to be consumed by the future Timetable module without requiring
/// a timetable generation engine in the current task.
class TrainerAvailability {
  const TrainerAvailability({
    this.weekdays = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    this.preferredTimeRange = 'Morning (09:00 AM - 01:00 PM)',
    this.unavailableNotes = '',
    this.generalNotes = '',
  });

  static const allWeekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final List<String> weekdays;
  final String preferredTimeRange;
  final String unavailableNotes;
  final String generalNotes;

  String get summary {
    if (weekdays.isEmpty) {
      return 'No weekdays configured';
    }
    final daysStr = weekdays.length == 7
        ? 'All 7 days'
        : weekdays.length == 5 &&
                weekdays.contains('Monday') &&
                weekdays.contains('Friday')
            ? 'Mon - Fri'
            : weekdays.map((d) => d.substring(0, 3)).join(', ');
    return '$daysStr • $preferredTimeRange';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'weekdays': weekdays,
    'preferredTimeRange': preferredTimeRange,
    'unavailableNotes': unavailableNotes,
    'generalNotes': generalNotes,
  };

  factory TrainerAvailability.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const TrainerAvailability();
    return TrainerAvailability(
      weekdays: (data['weekdays'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      preferredTimeRange: data['preferredTimeRange'] as String? ??
          'Morning (09:00 AM - 01:00 PM)',
      unavailableNotes: data['unavailableNotes'] as String? ?? '',
      generalNotes: data['generalNotes'] as String? ?? '',
    );
  }

  TrainerAvailability copyWith({
    List<String>? weekdays,
    String? preferredTimeRange,
    String? unavailableNotes,
    String? generalNotes,
  }) => TrainerAvailability(
    weekdays: weekdays ?? this.weekdays,
    preferredTimeRange: preferredTimeRange ?? this.preferredTimeRange,
    unavailableNotes: unavailableNotes ?? this.unavailableNotes,
    generalNotes: generalNotes ?? this.generalNotes,
  );
}

/// A trainer stored in the top-level `trainers` Cloud Firestore collection.
class Trainer {
  const Trainer({
    required this.id,
    required this.instituteId,
    required this.fullName,
    required this.email,
    required this.emailNormalized,
    required this.phone,
    required this.expertise,
    required this.qualifications,
    required this.experienceYears,
    required this.availability,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const statuses = <String>['active', 'inactive'];

  final String id;
  final String instituteId;
  final String fullName;
  final String email;
  final String emailNormalized;
  final String phone;
  final List<String> expertise;
  final String qualifications;
  final int experienceYears;
  final TrainerAvailability availability;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'active';
  bool get isInactive => status == 'inactive';

  factory Trainer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawEmail = data['email'] as String? ?? '';
    return Trainer(
      id: doc.id,
      instituteId: data['instituteId'] as String? ?? 'demo-institute',
      fullName: data['fullName'] as String? ?? '',
      email: rawEmail,
      emailNormalized: data['emailNormalized'] as String? ??
          rawEmail.trim().toLowerCase(),
      phone: data['phone'] as String? ?? '',
      expertise: (data['expertise'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[],
      qualifications: data['qualifications'] as String? ?? '',
      experienceYears: _asInt(data['experienceYears'], fallback: 0),
      availability: TrainerAvailability.fromMap(
        data['availability'] as Map<String, dynamic>?,
      ),
      status: data['status'] as String? ?? 'active',
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'instituteId': instituteId,
    'fullName': fullName,
    'email': email,
    'emailNormalized': emailNormalized,
    'phone': phone,
    'expertise': expertise,
    'qualifications': qualifications,
    'experienceYears': experienceYears,
    'availability': availability.toMap(),
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toUpdateMap() {
    final data = toFirestore();
    data.remove('createdAt');
    return data;
  }

  Trainer copyWith({
    String? id,
    String? instituteId,
    String? fullName,
    String? email,
    String? emailNormalized,
    String? phone,
    List<String>? expertise,
    String? qualifications,
    int? experienceYears,
    TrainerAvailability? availability,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Trainer(
    id: id ?? this.id,
    instituteId: instituteId ?? this.instituteId,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    emailNormalized: emailNormalized ?? this.emailNormalized,
    phone: phone ?? this.phone,
    expertise: expertise ?? this.expertise,
    qualifications: qualifications ?? this.qualifications,
    experienceYears: experienceYears ?? this.experienceYears,
    availability: availability ?? this.availability,
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

