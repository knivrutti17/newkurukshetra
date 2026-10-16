import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';

class CourseAccessScope {
  const CourseAccessScope({this.instituteId = 'demo-institute'});

  final String? instituteId;
}

abstract interface class CourseRepository {
  Stream<List<Course>> watchCourses({
    CourseAccessScope scope = const CourseAccessScope(),
    int limit = 200,
  });

  Future<List<Course>> getCourses({
    CourseAccessScope scope = const CourseAccessScope(),
  });

  Future<Course> createCourse(Course course);
  Future<Course> updateCourse(Course course);
  Future<Course> archiveCourse(Course course);
  Future<bool> isCoursesCollectionEmpty();
}

abstract interface class CourseSeedRepository {
  Future<bool> isCoursesCollectionEmpty();
  Future<void> createMissingSampleCourses(List<Course> courses);
  Future<int> countExistingSampleCourses(List<Course> courses);
}

class FirestoreCourseRepository
    implements CourseRepository, CourseSeedRepository {
  FirestoreCourseRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  @override
  Stream<List<Course>> watchCourses({
    CourseAccessScope scope = const CourseAccessScope(),
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query = _courses.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    return query.snapshots().map((snapshot) {
      final courses = snapshot.docs.map(Course.fromFirestore).toList();
      courses.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      return courses;
    });
  }

  @override
  Future<List<Course>> getCourses({
    CourseAccessScope scope = const CourseAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _courses;
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    final snapshot = await query.get();
    final courses = snapshot.docs.map(Course.fromFirestore).toList();
    courses.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return courses;
  }

  @override
  Future<Course> createCourse(Course course) async {
    final now = DateTime.now();
    final document = course.id.isEmpty ? _courses.doc() : _courses.doc(course.id);
    final saved = course.copyWith(
      id: document.id,
      createdAt: now,
      updatedAt: now,
    );
    await document.set(saved.toFirestore());
    return saved;
  }

  @override
  Future<Course> updateCourse(Course course) async {
    if (course.id.isEmpty) {
      throw ArgumentError.value(course.id, 'course.id', 'Cannot be empty');
    }
    final saved = course.copyWith(updatedAt: DateTime.now());
    await _courses.doc(saved.id).update(saved.toUpdateMap());
    return saved;
  }

  @override
  Future<Course> archiveCourse(Course course) =>
      updateCourse(course.copyWith(status: 'archived'));

  @override
  Future<bool> isCoursesCollectionEmpty() async {
    final snapshot = await _courses.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleCourses(List<Course> courses) async {
    final ids = courses.map((item) => item.id).toList();
    final snapshots = await Future.wait(ids.map((id) => _courses.doc(id).get()));
    return snapshots.where((item) => item.exists).length;
  }

  @override
  Future<void> createMissingSampleCourses(List<Course> courses) async {
    final batch = _firestore.batch();
    for (final course in courses) {
      final ref = _courses.doc(course.id);
      batch.set(ref, course.toFirestore(), SetOptions(merge: false));
    }
    await batch.commit();
  }
}

