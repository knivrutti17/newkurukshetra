import '../models/app_user.dart';
import '../models/course.dart';
import '../repositories/course_repository.dart';

class CourseValidationException implements Exception {
  const CourseValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CourseService {
  CourseService({CourseRepository? repository})
    : _repository = repository ?? FirestoreCourseRepository();

  final CourseRepository _repository;

  bool canManage(AppUser user) => user.role == AppRole.owner;

  Stream<List<Course>> watchForUser(AppUser user) =>
      _repository.watchCourses(scope: _scopeFor(user));

  Future<List<Course>> getForUser(AppUser user) =>
      _repository.getCourses(scope: _scopeFor(user));

  Future<Course> createForUser(AppUser user, Course course) async {
    _ensureCanManage(user);
    _validate(course);
    return _repository.createCourse(course);
  }

  Future<Course> updateForUser(AppUser user, Course course) async {
    _ensureCanManage(user);
    _validate(course);
    return _repository.updateCourse(course);
  }

  Future<Course> archiveForUser(AppUser user, Course course) async {
    _ensureCanManage(user);
    return _repository.archiveCourse(course);
  }

  CourseAccessScope _scopeFor(AppUser user) =>
      CourseAccessScope(instituteId: user.instituteId);

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const CourseValidationException(
        'Your demo role has view-only course access.',
      );
    }
  }

  void _validate(Course course) {
    if (course.name.trim().isEmpty) {
      throw const CourseValidationException('Course name is required.');
    }
    if (course.duration.trim().isEmpty) {
      throw const CourseValidationException('Course duration is required.');
    }
    if (course.feeAmount < 0) {
      throw const CourseValidationException('Fee amount cannot be negative.');
    }
  }
}
