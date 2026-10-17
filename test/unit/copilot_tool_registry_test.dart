import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/repositories/student_repository.dart';
import 'package:kurukshetra/data/services/student_service.dart';
import 'package:kurukshetra/features/copilot/services/copilot_tool_registry.dart';
import 'package:kurukshetra/features/copilot/services/rule_based_copilot_service.dart';

void main() {
  final now = DateTime(2026, 10, 17);
  final trainer = AppUser(
    id: 'trainer-1',
    name: 'Trainer One',
    email: 'trainer@example.test',
    role: AppRole.trainer,
    instituteId: 'institute-1',
  );
  final accounts = AppUser(
    id: 'accounts-1',
    name: 'Accounts One',
    email: 'accounts@example.test',
    role: AppRole.accounts,
    instituteId: 'institute-1',
  );

  Student student({
    required String id,
    required String name,
    required String trainerId,
  }) => Student(
    id: id,
    instituteId: 'institute-1',
    fullName: name,
    email: '$id@example.test',
    phone: '9999999999',
    courseId: 'course-java',
    courseName: 'Java',
    batchId: 'batch-java-a',
    batchName: 'Java A',
    enrollmentDate: now,
    status: 'active',
    createdAt: now,
    updatedAt: now,
    trainerId: trainerId,
  );

  test(
    'student search uses the role-scoped service and minimizes fields',
    () async {
      final registry = CopilotToolRegistry(
        user: trainer,
        studentService: StudentService(
          repository: _StudentsRepository(<Student>[
            student(
              id: 'student-1',
              name: 'Ada Lovelace',
              trainerId: trainer.id,
            ),
            student(
              id: 'student-2',
              name: 'Grace Hopper',
              trainerId: 'trainer-2',
            ),
          ]),
        ),
      );
      final search = registry.declarations.firstWhere(
        (declaration) => declaration.name == 'search_students',
      );

      final response = await search.callable(<String, Object?>{'query': 'a'});
      final results = registry.takeResults();

      expect(response['query_id'], 'search_students');
      expect(results, hasLength(1));
      expect(results.single.rows, hasLength(1));
      expect(results.single.rows.single['Student'], 'Ada Lovelace');
      expect(results.single.rows.single.containsKey('email'), isFalse);
      expect(results.single.rows.single.containsKey('phone'), isFalse);
    },
  );

  test('trainer registry does not expose finance tools', () {
    final registry = CopilotToolRegistry(
      user: trainer,
      studentService: StudentService(repository: _StudentsRepository(const [])),
    );
    final names = registry.declarations.map((item) => item.name).toSet();

    expect(names, contains('find_low_attendance'));
    expect(names, isNot(contains('list_overdue_instalments')));
    expect(names, isNot(contains('prepare_reminder_draft')));
  });

  test('reminder-draft writes are disabled in the default build', () {
    final registry = CopilotToolRegistry(
      user: accounts,
      studentService: StudentService(repository: _StudentsRepository(const [])),
    );
    final names = registry.declarations.map((item) => item.name).toSet();

    expect(names, contains('list_overdue_instalments'));
    expect(names, isNot(contains('prepare_reminder_draft')));
  });

  test(
    'built-in fallback returns authorized Java students without AI',
    () async {
      final registry = CopilotToolRegistry(
        user: trainer,
        studentService: StudentService(
          repository: _StudentsRepository(<Student>[
            student(
              id: 'student-1',
              name: 'Ada Lovelace',
              trainerId: trainer.id,
            ),
            student(
              id: 'student-2',
              name: 'Grace Hopper',
              trainerId: 'trainer-2',
            ),
          ]),
        ),
      );
      final response = await RuleBasedCopilotService(tools: registry)
          .respond('Show students in the Java batch');

      expect(response.text, contains('built-in authorized lookup'));
      expect(response.toolResults, hasLength(1));
      expect(response.toolResults.single.rows, hasLength(1));
      expect(
        response.toolResults.single.rows.single['Student'],
        'Ada Lovelace',
      );
    },
  );
}

class _StudentsRepository implements StudentRepository {
  const _StudentsRepository(this.students);

  final List<Student> students;

  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) {
    final scoped = students
        .where((student) {
          return (scope.instituteId == null ||
                  student.instituteId == scope.instituteId) &&
              (scope.trainerId == null ||
                  student.trainerId == scope.trainerId) &&
              (scope.counselorId == null ||
                  student.counselorId == scope.counselorId);
        })
        .take(limit)
        .toList(growable: false);
    return Stream<List<Student>>.value(scoped);
  }

  @override
  Future<Student> archiveStudent(Student student) => throw UnimplementedError();

  @override
  Future<Student> createStudent(Student student) => throw UnimplementedError();

  @override
  Future<bool> isStudentsCollectionEmpty() async => students.isEmpty;

  @override
  Future<Student> updateStudent(Student student) => throw UnimplementedError();
}
