import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';

/// Optional data constraints used by the demo's non-authoritative role UI.
class StudentAccessScope {
  const StudentAccessScope({
    this.instituteId = 'demo-institute',
    this.counselorId,
    this.trainerId,
  });

  final String? instituteId;
  final String? counselorId;
  final String? trainerId;
}

abstract interface class StudentRepository {
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  });

  Future<Student> createStudent(Student student);
  Future<Student> updateStudent(Student student);
  Future<Student> archiveStudent(Student student);
  Future<bool> isStudentsCollectionEmpty();
}

/// Extra repository operations used only for deterministic sample seeding.
abstract interface class StudentSeedRepository {
  Future<bool> isStudentsCollectionEmpty();
  Future<void> createMissingSampleStudents(List<Student> students);
  Future<int> countExistingSampleStudents(List<Student> students);
}

class FirestoreStudentRepository
    implements StudentRepository, StudentSeedRepository {
  FirestoreStudentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query = _students.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.counselorId != null) {
      query = query.where('counselorId', isEqualTo: scope.counselorId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    return query.snapshots().map(
      (snapshot) {
        final students = snapshot.docs.map(Student.fromFirestore).toList();
        students.sort(
          (left, right) => left.fullName.toLowerCase().compareTo(
            right.fullName.toLowerCase(),
          ),
        );
        return students;
      },
    );
  }

  @override
  Future<Student> createStudent(Student student) async {
    final now = DateTime.now();
    final document = _students.doc();
    final saved = student.copyWith(
      id: document.id,
      createdAt: now,
      updatedAt: now,
    );
    await document.set(saved.toFirestore());
    return saved;
  }

  @override
  Future<Student> updateStudent(Student student) async {
    if (student.id.isEmpty) {
      throw ArgumentError.value(student.id, 'student.id', 'Cannot be empty');
    }
    final saved = student.copyWith(updatedAt: DateTime.now());
    await _students.doc(saved.id).update(saved.toUpdateMap());
    return saved;
  }

  @override
  Future<Student> archiveStudent(Student student) => updateStudent(
    student.copyWith(status: 'archived'),
  );

  @override
  Future<bool> isStudentsCollectionEmpty() async {
    final firstDocument = await _students.limit(1).get();
    return firstDocument.docs.isEmpty;
  }

  /// Used only by the sample-data initializer after it has verified that the
  /// collection is empty. Existing document IDs are deliberately never set.
  @override
  Future<void> createMissingSampleStudents(List<Student> students) async {
    final existing = await Future.wait(
      students.map((student) => _students.doc(student.id).get()),
    );
    final missing = <Student>[
      for (var index = 0; index < students.length; index++)
        if (!existing[index].exists) students[index],
    ];
    if (missing.isEmpty) {
      return;
    }

    final write = _firestore.batch();
    for (final student in missing) {
      write.set(_students.doc(student.id), student.toFirestore());
    }
    await write.commit();
  }

  @override
  Future<int> countExistingSampleStudents(List<Student> students) async {
    final existing = await Future.wait(
      students.map((student) => _students.doc(student.id).get()),
    );
    return existing.where((document) => document.exists).length;
  }
}
