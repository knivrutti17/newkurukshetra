import '../models/student.dart';
import '../repositories/student_repository.dart';

class StudentSeedResult {
  const StudentSeedResult({
    required this.createdCount,
    required this.skippedCount,
    required this.collectionAlreadyHadData,
  });

  final int createdCount;
  final int skippedCount;
  final bool collectionAlreadyHadData;
}

/// Writes fictional data only when `students` has no documents.
///
/// The documents have stable IDs. Re-running is intentionally safe: it never
/// overwrites an existing student record and reports the records it skipped.
class StudentSeedService {
  StudentSeedService({StudentSeedRepository? repository})
    : _repository = repository ?? FirestoreStudentRepository();

  final StudentSeedRepository _repository;

  Future<StudentSeedResult> loadSampleStudents() async {
    final samples = _sampleStudents;
    final isEmpty = await _repository.isStudentsCollectionEmpty();
    if (!isEmpty) {
      return StudentSeedResult(
        createdCount: 0,
        skippedCount: samples.length,
        collectionAlreadyHadData: true,
      );
    }

    final existingSamples = await _repository.countExistingSampleStudents(
      samples,
    );
    await _repository.createMissingSampleStudents(samples);
    return StudentSeedResult(
      createdCount: samples.length - existingSamples,
      skippedCount: existingSamples,
      collectionAlreadyHadData: false,
    );
  }

  List<Student> get _sampleStudents => <Student>[
    _sample(
      id: 'sample-01-aisha-khan',
      name: 'Aisha Khan',
      email: 'aisha.khan@example.test',
      phone: '+91 90000 10001',
      courseId: 'data-analytics',
      courseName: 'Data Analytics',
      batchId: 'da-jan-2026-a',
      batchName: 'DA Jan 2026 A',
      enrollmentDate: DateTime(2026, 1, 8),
      counselorId: 'demo-counselor',
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-02-vikram-rao',
      name: 'Vikram Rao',
      email: 'vikram.rao@example.test',
      phone: '+91 90000 10002',
      courseId: 'data-analytics',
      courseName: 'Data Analytics',
      batchId: 'da-jan-2026-a',
      batchName: 'DA Jan 2026 A',
      enrollmentDate: DateTime(2026, 1, 10),
      counselorId: 'demo-counselor',
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-03-meera-nair',
      name: 'Meera Nair',
      email: 'meera.nair@example.test',
      phone: '+91 90000 10003',
      courseId: 'full-stack-development',
      courseName: 'Full Stack Development',
      batchId: 'fsd-feb-2026-b',
      batchName: 'FSD Feb 2026 B',
      enrollmentDate: DateTime(2026, 2, 2),
      counselorId: 'demo-counselor',
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-04-arjun-patel',
      name: 'Arjun Patel',
      email: 'arjun.patel@example.test',
      phone: '+91 90000 10004',
      courseId: 'full-stack-development',
      courseName: 'Full Stack Development',
      batchId: 'fsd-feb-2026-b',
      batchName: 'FSD Feb 2026 B',
      enrollmentDate: DateTime(2026, 2, 5),
      counselorId: 'demo-counselor',
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-05-kavya-iyer',
      name: 'Kavya Iyer',
      email: 'kavya.iyer@example.test',
      phone: '+91 90000 10005',
      courseId: 'digital-marketing',
      courseName: 'Digital Marketing',
      batchId: 'dm-mar-2026-a',
      batchName: 'DM Mar 2026 A',
      enrollmentDate: DateTime(2026, 3, 3),
      counselorId: 'demo-counselor',
    ),
    _sample(
      id: 'sample-06-rahul-verma',
      name: 'Rahul Verma',
      email: 'rahul.verma@example.test',
      phone: '+91 90000 10006',
      courseId: 'digital-marketing',
      courseName: 'Digital Marketing',
      batchId: 'dm-mar-2026-a',
      batchName: 'DM Mar 2026 A',
      enrollmentDate: DateTime(2026, 3, 6),
      counselorId: 'demo-counselor',
    ),
    _sample(
      id: 'sample-07-sana-shaikh',
      name: 'Sana Shaikh',
      email: 'sana.shaikh@example.test',
      phone: '+91 90000 10007',
      courseId: 'ui-ux-design',
      courseName: 'UI UX Design',
      batchId: 'ux-apr-2026-c',
      batchName: 'UX Apr 2026 C',
      enrollmentDate: DateTime(2026, 4, 1),
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-08-aman-joshi',
      name: 'Aman Joshi',
      email: 'aman.joshi@example.test',
      phone: '+91 90000 10008',
      courseId: 'ui-ux-design',
      courseName: 'UI UX Design',
      batchId: 'ux-apr-2026-c',
      batchName: 'UX Apr 2026 C',
      enrollmentDate: DateTime(2026, 4, 4),
      status: 'inactive',
      trainerId: 'demo-trainer',
    ),
    _sample(
      id: 'sample-09-nisha-deshmukh',
      name: 'Nisha Deshmukh',
      email: 'nisha.deshmukh@example.test',
      phone: '+91 90000 10009',
      courseId: 'data-analytics',
      courseName: 'Data Analytics',
      batchId: 'da-may-2026-b',
      batchName: 'DA May 2026 B',
      enrollmentDate: DateTime(2026, 5, 7),
    ),
    _sample(
      id: 'sample-10-dev-malhotra',
      name: 'Dev Malhotra',
      email: 'dev.malhotra@example.test',
      phone: '+91 90000 10010',
      courseId: 'full-stack-development',
      courseName: 'Full Stack Development',
      batchId: 'fsd-may-2026-a',
      batchName: 'FSD May 2026 A',
      enrollmentDate: DateTime(2026, 5, 10),
      status: 'inactive',
    ),
  ];

  Student _sample({
    required String id,
    required String name,
    required String email,
    required String phone,
    required String courseId,
    required String courseName,
    required String batchId,
    required String batchName,
    required DateTime enrollmentDate,
    String status = 'active',
    String? counselorId,
    String? trainerId,
  }) => Student(
    id: id,
    instituteId: 'demo-institute',
    fullName: name,
    email: email,
    phone: phone,
    courseId: courseId,
    courseName: courseName,
    batchId: batchId,
    batchName: batchName,
    enrollmentDate: enrollmentDate,
    status: status,
    createdAt: enrollmentDate,
    updatedAt: enrollmentDate,
    counselorId: counselorId,
    trainerId: trainerId,
  );
}
