import '../../features/auth/services/auth_service.dart';
import '../models/app_user.dart';
import '../models/student.dart';
import '../repositories/student_repository.dart';

/// Application-facing student operations and demo role checks.
///
/// These checks are for the local demo interface only. Firestore must enforce
/// the equivalent access policy with Firebase Authentication in production.
class StudentService {
  StudentService({StudentRepository? repository})
    : _repository = repository ?? FirestoreStudentRepository();

  final StudentRepository _repository;

  bool canManage(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.counselor;

  bool isAccountsView(AppUser user) => user.role == AppRole.accounts;

  Stream<List<Student>> watchForUser(AppUser user) =>
      _repository.watchStudents(scope: _scopeFor(user));

  Future<Student> createForUser(AppUser user, Student student) async {
    _ensureCanManage(user);
    final scopedStudent = user.role == AppRole.counselor
        ? student.copyWith(counselorId: user.id)
        : student;
    return _repository.createStudent(scopedStudent);
  }

  Future<Student> updateForUser(AppUser user, Student student) async {
    _ensureCanManage(user);
    _ensureCounselorCanManage(user, student);
    return _repository.updateStudent(student);
  }

  Future<Student> archiveForUser(AppUser user, Student student) async {
    _ensureCanManage(user);
    _ensureCounselorCanManage(user, student);
    return _repository.archiveStudent(student);
  }

  StudentAccessScope _scopeFor(AppUser user) => switch (user.role) {
    AppRole.owner ||
    AppRole.accounts => StudentAccessScope(instituteId: user.instituteId),
    AppRole.counselor => StudentAccessScope(
      instituteId: user.instituteId,
      counselorId: user.id,
    ),
    AppRole.trainer => StudentAccessScope(
      instituteId: user.instituteId,
      trainerId: user.id,
    ),
  };

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const AuthException('Your demo role has view-only student access.');
    }
  }

  void _ensureCounselorCanManage(AppUser user, Student student) {
    if (user.role == AppRole.counselor && student.counselorId != user.id) {
      throw const AuthException(
        'You can only manage students assigned to your demo counselor account.',
      );
    }
  }
}
