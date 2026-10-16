import '../models/class_session.dart';
import '../repositories/timetable_repository.dart';

class TimetableSeedResult {
  const TimetableSeedResult({
    required this.sessionsCreated,
    required this.sessionsSkipped,
    required this.alreadyHadData,
  });

  final int sessionsCreated;
  final int sessionsSkipped;
  final bool alreadyHadData;
}

/// Seeds deterministic sample class sessions for InstituteOS timetable demonstration.
///
/// Safe to execute repeatedly without duplicating data or corrupting existing records.
class TimetableSeedService {
  TimetableSeedService({
    TimetableSeedRepository? timetableRepository,
  }) : _timetableRepository =
            timetableRepository ?? FirestoreTimetableRepository();

  final TimetableSeedRepository _timetableRepository;

  Future<TimetableSeedResult> loadSampleData({DateTime? referenceDate}) async {
    final sampleSessions = getSampleSessions(referenceDate: referenceDate);

    final isEmpty = await _timetableRepository.isSessionsCollectionEmpty();
    if (!isEmpty) {
      final existingCount = await _timetableRepository
          .countExistingSampleSessions(sampleSessions);
      if (existingCount == sampleSessions.length) {
        return TimetableSeedResult(
          sessionsCreated: 0,
          sessionsSkipped: sampleSessions.length,
          alreadyHadData: true,
        );
      }
    }

    final existingCount = await _timetableRepository
        .countExistingSampleSessions(sampleSessions);
    await _timetableRepository.createMissingSampleSessions(sampleSessions);

    return TimetableSeedResult(
      sessionsCreated: sampleSessions.length - existingCount,
      sessionsSkipped: existingCount,
      alreadyHadData: false,
    );
  }

  List<ClassSession> getSampleSessions({DateTime? referenceDate}) {
    final base = referenceDate ?? DateTime.now();
    // Monday of the reference week
    final monday = DateTime(base.year, base.month, base.day)
        .subtract(Duration(days: base.weekday - DateTime.monday));

    final createdAt = DateTime(2026, 1, 1);

    return <ClassSession>[
      // Monday 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni
      ClassSession(
        id: 'sample-session-da-mon',
        instituteId: 'demo-institute',
        batchId: 'da-jan-2026-a',
        batchName: 'DA Jan 2026 A',
        courseId: 'data-analytics',
        courseName: 'Data Analytics',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: monday.add(const Duration(hours: 9)),
        endAt: monday.add(const Duration(hours: 11)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 1 - Ground Floor',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Monday 11:30 - 13:30 | FSD Feb 2026 B | Rohan Kulkarni
      ClassSession(
        id: 'sample-session-fsd-mon',
        instituteId: 'demo-institute',
        batchId: 'fsd-feb-2026-b',
        batchName: 'FSD Feb 2026 B',
        courseId: 'full-stack-development',
        courseName: 'Full Stack Development',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: monday.add(const Duration(hours: 11, minutes: 30)),
        endAt: monday.add(const Duration(hours: 13, minutes: 30)),
        deliveryMode: 'hybrid',
        roomId: 'room-204',
        roomName: 'Tech Studio 204',
        meetingLink: 'https://meet.google.com/institute-fsd-live',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Tuesday 10:00 - 12:00 | DA May 2026 B | Aditya Sen
      ClassSession(
        id: 'sample-session-da-tue',
        instituteId: 'demo-institute',
        batchId: 'da-may-2026-b',
        batchName: 'DA May 2026 B',
        courseId: 'data-analytics',
        courseName: 'Data Analytics',
        trainerId: 'trainer-aditya-sen',
        trainerName: 'Aditya Sen',
        startAt: monday.add(const Duration(days: 1, hours: 10)),
        endAt: monday.add(const Duration(days: 1, hours: 12)),
        deliveryMode: 'online',
        roomId: '',
        roomName: '',
        meetingLink: 'https://zoom.us/j/demo-da-may-cohort',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Tuesday 14:00 - 16:00 | UX Apr 2026 C | Pooja Verma
      ClassSession(
        id: 'sample-session-ux-tue',
        instituteId: 'demo-institute',
        batchId: 'ux-apr-2026-c',
        batchName: 'UX Apr 2026 C',
        courseId: 'ui-ux-design',
        courseName: 'UI UX Design',
        trainerId: 'trainer-pooja-verma',
        trainerName: 'Pooja Verma',
        startAt: monday.add(const Duration(days: 1, hours: 14)),
        endAt: monday.add(const Duration(days: 1, hours: 16)),
        deliveryMode: 'in_person',
        roomId: 'room-studio-a',
        roomName: 'Design Studio A',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Wednesday 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni
      ClassSession(
        id: 'sample-session-da-wed',
        instituteId: 'demo-institute',
        batchId: 'da-jan-2026-a',
        batchName: 'DA Jan 2026 A',
        courseId: 'data-analytics',
        courseName: 'Data Analytics',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: monday.add(const Duration(days: 2, hours: 9)),
        endAt: monday.add(const Duration(days: 2, hours: 11)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 1 - Ground Floor',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Wednesday 11:30 - 13:30 | FSD Feb 2026 B | Rohan Kulkarni
      ClassSession(
        id: 'sample-session-fsd-wed',
        instituteId: 'demo-institute',
        batchId: 'fsd-feb-2026-b',
        batchName: 'FSD Feb 2026 B',
        courseId: 'full-stack-development',
        courseName: 'Full Stack Development',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: monday.add(const Duration(days: 2, hours: 11, minutes: 30)),
        endAt: monday.add(const Duration(days: 2, hours: 13, minutes: 30)),
        deliveryMode: 'hybrid',
        roomId: 'room-204',
        roomName: 'Tech Studio 204',
        meetingLink: 'https://meet.google.com/institute-fsd-live',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Thursday 10:00 - 12:00 | DA May 2026 B | Aditya Sen
      ClassSession(
        id: 'sample-session-da-thu',
        instituteId: 'demo-institute',
        batchId: 'da-may-2026-b',
        batchName: 'DA May 2026 B',
        courseId: 'data-analytics',
        courseName: 'Data Analytics',
        trainerId: 'trainer-aditya-sen',
        trainerName: 'Aditya Sen',
        startAt: monday.add(const Duration(days: 3, hours: 10)),
        endAt: monday.add(const Duration(days: 3, hours: 12)),
        deliveryMode: 'online',
        roomId: '',
        roomName: '',
        meetingLink: 'https://zoom.us/j/demo-da-may-cohort',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Thursday 14:00 - 16:00 | UX Apr 2026 C | Pooja Verma
      ClassSession(
        id: 'sample-session-ux-thu',
        instituteId: 'demo-institute',
        batchId: 'ux-apr-2026-c',
        batchName: 'UX Apr 2026 C',
        courseId: 'ui-ux-design',
        courseName: 'UI UX Design',
        trainerId: 'trainer-pooja-verma',
        trainerName: 'Pooja Verma',
        startAt: monday.add(const Duration(days: 3, hours: 14)),
        endAt: monday.add(const Duration(days: 3, hours: 16)),
        deliveryMode: 'in_person',
        roomId: 'room-studio-a',
        roomName: 'Design Studio A',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Friday 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni
      ClassSession(
        id: 'sample-session-da-fri',
        instituteId: 'demo-institute',
        batchId: 'da-jan-2026-a',
        batchName: 'DA Jan 2026 A',
        courseId: 'data-analytics',
        courseName: 'Data Analytics',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: monday.add(const Duration(days: 4, hours: 9)),
        endAt: monday.add(const Duration(days: 4, hours: 11)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 1 - Ground Floor',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),

      // Friday 14:00 - 17:00 | DM Mar 2026 A | Ananya Joshi
      ClassSession(
        id: 'sample-session-dm-fri',
        instituteId: 'demo-institute',
        batchId: 'dm-mar-2026-a',
        batchName: 'DM Mar 2026 A',
        courseId: 'digital-marketing',
        courseName: 'Digital Marketing',
        trainerId: 'trainer-ananya-joshi',
        trainerName: 'Ananya Joshi',
        startAt: monday.add(const Duration(days: 4, hours: 14)),
        endAt: monday.add(const Duration(days: 4, hours: 17)),
        deliveryMode: 'in_person',
        roomId: 'room-seminar',
        roomName: 'Seminar Hall B',
        meetingLink: '',
        status: 'scheduled',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ];
  }
}

