import '../models/batch.dart';
import '../models/course.dart';
import '../repositories/batch_repository.dart';
import '../repositories/course_repository.dart';

class CourseBatchSeedResult {
  const CourseBatchSeedResult({
    required this.coursesCreated,
    required this.coursesSkipped,
    required this.batchesCreated,
    required this.batchesSkipped,
    required this.alreadyHadData,
  });

  final int coursesCreated;
  final int coursesSkipped;
  final int batchesCreated;
  final int batchesSkipped;
  final bool alreadyHadData;
}

/// Populates sample courses and batches with deterministic IDs when triggered by an Owner.
///
/// Safe to run repeatedly: never overwrites existing records and reports what was skipped.
class CourseBatchSeedService {
  CourseBatchSeedService({
    CourseSeedRepository? courseRepository,
    BatchSeedRepository? batchRepository,
  }) : _courseRepository =
           courseRepository ?? FirestoreCourseRepository(),
       _batchRepository =
           batchRepository ?? FirestoreBatchRepository();

  final CourseSeedRepository _courseRepository;
  final BatchSeedRepository _batchRepository;

  Future<CourseBatchSeedResult> loadSampleData() async {
    final sampleCourses = _sampleCourses;
    final sampleBatches = _sampleBatches;

    final coursesEmpty = await _courseRepository.isCoursesCollectionEmpty();
    final batchesEmpty = await _batchRepository.isBatchesCollectionEmpty();

    if (!coursesEmpty && !batchesEmpty) {
      return CourseBatchSeedResult(
        coursesCreated: 0,
        coursesSkipped: sampleCourses.length,
        batchesCreated: 0,
        batchesSkipped: sampleBatches.length,
        alreadyHadData: true,
      );
    }

    final existingCoursesCount =
        await _courseRepository.countExistingSampleCourses(sampleCourses);
    final existingBatchesCount =
        await _batchRepository.countExistingSampleBatches(sampleBatches);

    await _courseRepository.createMissingSampleCourses(sampleCourses);
    await _batchRepository.createMissingSampleBatches(sampleBatches);

    return CourseBatchSeedResult(
      coursesCreated: sampleCourses.length - existingCoursesCount,
      coursesSkipped: existingCoursesCount,
      batchesCreated: sampleBatches.length - existingBatchesCount,
      batchesSkipped: existingBatchesCount,
      alreadyHadData: false,
    );
  }

  List<Course> get _sampleCourses => <Course>[
    _course(
      id: 'data-analytics',
      name: 'Data Analytics',
      description:
          'Data wrangling, SQL, Python, BI dashboards and statistical modeling.',
      duration: '6 Months',
      feeAmount: 45000,
      createdAt: DateTime(2026, 1, 1),
    ),
    _course(
      id: 'full-stack-development',
      name: 'Full Stack Development',
      description:
          'Modern web engineering with Flutter, Node.js, TypeScript and cloud systems.',
      duration: '8 Months',
      feeAmount: 60000,
      createdAt: DateTime(2026, 1, 1),
    ),
    _course(
      id: 'digital-marketing',
      name: 'Digital Marketing',
      description:
          'SEO, SEM, social media growth, marketing analytics and campaign execution.',
      duration: '4 Months',
      feeAmount: 35000,
      createdAt: DateTime(2026, 1, 1),
    ),
    _course(
      id: 'ui-ux-design',
      name: 'UI UX Design',
      description:
          'User research, wireframing, design systems, Figma and interactive prototyping.',
      duration: '5 Months',
      feeAmount: 40000,
      createdAt: DateTime(2026, 1, 1),
    ),
    _course(
      id: 'cyber-security',
      name: 'Cyber Security',
      description:
          'Network defense, threat intelligence, ethical hacking and incident response.',
      duration: '6 Months',
      feeAmount: 55000,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  List<Batch> get _sampleBatches => <Batch>[
    _batch(
      id: 'da-jan-2026-a',
      name: 'DA Jan 2026 A',
      courseId: 'data-analytics',
      courseName: 'Data Analytics',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 1, 8),
      endDate: DateTime(2026, 7, 8),
      capacity: 25,
      scheduleDescription: 'Mon-Wed-Fri, 09:00 AM - 11:00 AM',
      createdAt: DateTime(2026, 1, 1),
    ),
    _batch(
      id: 'da-may-2026-b',
      name: 'DA May 2026 B',
      courseId: 'data-analytics',
      courseName: 'Data Analytics',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 11, 1),
      capacity: 25,
      scheduleDescription: 'Tue-Thu-Sat, 02:00 PM - 04:00 PM',
      createdAt: DateTime(2026, 1, 1),
    ),
    _batch(
      id: 'fsd-feb-2026-b',
      name: 'FSD Feb 2026 B',
      courseId: 'full-stack-development',
      courseName: 'Full Stack Development',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 10, 1),
      capacity: 30,
      scheduleDescription: 'Mon-Fri, 11:30 AM - 01:30 PM',
      createdAt: DateTime(2026, 1, 1),
    ),
    _batch(
      id: 'fsd-may-2026-a',
      name: 'FSD May 2026 A',
      courseId: 'full-stack-development',
      courseName: 'Full Stack Development',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 5, 15),
      endDate: DateTime(2027, 1, 15),
      capacity: 25,
      scheduleDescription: 'Mon-Fri, 03:00 PM - 05:00 PM',
      createdAt: DateTime(2026, 1, 1),
    ),
    _batch(
      id: 'dm-mar-2026-a',
      name: 'DM Mar 2026 A',
      courseId: 'digital-marketing',
      courseName: 'Digital Marketing',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 7, 1),
      capacity: 20,
      scheduleDescription: 'Sat-Sun, 10:00 AM - 01:00 PM',
      createdAt: DateTime(2026, 1, 1),
    ),
    _batch(
      id: 'ux-apr-2026-c',
      name: 'UX Apr 2026 C',
      courseId: 'ui-ux-design',
      courseName: 'UI UX Design',
      trainerId: 'demo-trainer',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 4, 1),
      endDate: DateTime(2026, 9, 1),
      capacity: 20,
      scheduleDescription: 'Tue-Thu, 06:00 PM - 08:30 PM',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  Course _course({
    required String id,
    required String name,
    required String description,
    required String duration,
    required double feeAmount,
    required DateTime createdAt,
    String status = 'active',
  }) => Course(
    id: id,
    instituteId: 'demo-institute',
    name: name,
    description: description,
    duration: duration,
    feeAmount: feeAmount,
    status: status,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  Batch _batch({
    required String id,
    required String name,
    required String courseId,
    required String courseName,
    required String trainerId,
    required String trainerName,
    required DateTime startDate,
    required DateTime endDate,
    required int capacity,
    required String scheduleDescription,
    required DateTime createdAt,
    String status = 'active',
  }) => Batch(
    id: id,
    instituteId: 'demo-institute',
    name: name,
    courseId: courseId,
    courseName: courseName,
    trainerId: trainerId,
    trainerName: trainerName,
    startDate: startDate,
    endDate: endDate,
    capacity: capacity,
    scheduleDescription: scheduleDescription,
    status: status,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

