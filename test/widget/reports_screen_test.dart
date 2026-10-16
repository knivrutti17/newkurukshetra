import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/approval_action.dart';
import 'package:kurukshetra/data/models/attendance_record.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/class_session.dart';
import 'package:kurukshetra/data/models/course.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/models/student_alert.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/approval_repository.dart';
import 'package:kurukshetra/data/repositories/attendance_repository.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/course_repository.dart';
import 'package:kurukshetra/data/repositories/fee_repository.dart';
import 'package:kurukshetra/data/repositories/student_alert_repository.dart';
import 'package:kurukshetra/data/repositories/student_repository.dart';
import 'package:kurukshetra/data/repositories/timetable_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/batch_service.dart';
import 'package:kurukshetra/data/services/course_service.dart';
import 'package:kurukshetra/data/services/reports_service.dart';
import 'package:kurukshetra/data/services/risk_rule_engine.dart';
import 'package:kurukshetra/features/reports/screens/reports_screen.dart';

class _FakeStudentRepository implements StudentRepository {
  List<Student> students = [];

  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) => Stream.value(students);

  @override
  Future<Student> createStudent(Student s) async => s;
  @override
  Future<Student> updateStudent(Student s) async => s;
  @override
  Future<Student> archiveStudent(Student s) async => s;
  @override
  Future<bool> isStudentsCollectionEmpty() async => students.isEmpty;
}

class _FakeAttendanceRepository implements AttendanceRepository {
  List<AttendanceRecord> records = [];

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory({
    required AttendanceAccessScope scope,
    int limit = 500,
  }) => Stream.value(records);

  @override
  Future<List<AttendanceRecord>> getSessionRecords({
    required AttendanceAccessScope scope,
    required String batchId,
    required DateTime classDate,
    required List<String> studentIds,
  }) async => records;

  @override
  Future<void> upsertAttendanceRecords(List<AttendanceRecord> recs) async {}
}

class _FakeFeeRepository implements FeeRepository {
  List<FeeInstallment> installments = [];

  @override
  Future<List<FeeInstallment>> getInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
  }) async => installments;

  @override
  Stream<List<FeeInstallment>> watchInstallments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 200,
  }) => Stream.value(installments);

  @override
  Future<FeeInstallment?> getInstallment(String id) async => null;
  @override
  Future<FeeInstallment> createInstallment(FeeInstallment i) async => i;
  @override
  Stream<List<Payment>> watchPaymentsForInstallment(String id) => Stream.value([]);
  @override
  Future<List<Payment>> getPaymentsForInstallment(String id) async => [];
  @override
  Stream<List<Payment>> watchAllPayments({
    FeeAccessScope scope = const FeeAccessScope(),
    int limit = 500,
  }) => Stream.value([]);
  @override
  Future<Payment> recordPayment({
    required FeeInstallment installment,
    required Payment payment,
  }) async => payment;
  @override
  Future<bool> isFeeInstallmentsEmpty() async => installments.isEmpty;
}

class _FakeBatchRepository implements BatchRepository {
  List<Batch> batches = [];

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async => batches;

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) => Stream.value(batches);

  @override
  Future<Batch> createBatch(Batch b) async => b;
  @override
  Future<Batch> updateBatch(Batch b) async => b;
  @override
  Future<Batch> archiveBatch(Batch b) async => b;
  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;
}

class _FakeCourseRepository implements CourseRepository {
  List<Course> courses = [];

  @override
  Future<List<Course>> getCourses({
    CourseAccessScope scope = const CourseAccessScope(),
  }) async => courses;

  @override
  Stream<List<Course>> watchCourses({
    CourseAccessScope scope = const CourseAccessScope(),
    int limit = 200,
  }) => Stream.value(courses);

  @override
  Future<Course> createCourse(Course c) async => c;
  @override
  Future<Course> updateCourse(Course c) async => c;
  @override
  Future<Course> archiveCourse(Course c) async => c;
  @override
  Future<bool> isCoursesCollectionEmpty() async => courses.isEmpty;
}

class _FakeTrainerRepository implements TrainerRepository {
  List<Trainer> trainers = [];

  @override
  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  }) async => trainers;

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) => Stream.value(trainers);

  @override
  Future<Trainer?> getTrainerById(String id) async => null;
  @override
  Future<Trainer> createTrainer(Trainer t) async => t;
  @override
  Future<Trainer> updateTrainer(Trainer t) async => t;
  @override
  Future<bool> isTrainersCollectionEmpty() async => trainers.isEmpty;
  @override
  Future<bool> isEmailTaken(String instituteId, String emailNormalized, {String? excludeTrainerId}) async => false;
  @override
  Future<Trainer> setTrainerStatus(String id, String status) async => trainers.first;
}

class _FakeTimetableRepository implements TimetableRepository {
  List<ClassSession> sessions = [];

  @override
  Future<List<ClassSession>> getSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
  }) async => sessions;

  @override
  Stream<List<ClassSession>> watchSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
    int limit = 200,
  }) => Stream.value(sessions);

  @override
  Future<ClassSession?> getSessionById(String id) async => null;
  @override
  Future<ClassSession> createSession(ClassSession s) async => s;
  @override
  Future<ClassSession> updateSession(ClassSession s) async => s;
  @override
  Future<ClassSession> cancelSession(String id) async => sessions.first;
  @override
  Future<bool> isSessionsCollectionEmpty() async => sessions.isEmpty;
}

class _FakeStudentAlertRepository implements StudentAlertRepository {
  List<StudentAlert> alerts = [];

  @override
  Future<List<StudentAlert>> getAlertsForScan(String instituteId) async => alerts;

  @override
  Stream<List<StudentAlert>> watchAlerts(AlertAccessScope scope) =>
      Stream.value(alerts);

  @override
  Future<AlertScanWriteResult> synchronizeScan({
    required String instituteId,
    required List<ProposedStudentAlert> candidates,
    required DateTime now,
  }) async => const AlertScanWriteResult(created: 0, updated: 0, preservedClosed: 0);

  @override
  Future<StudentAlert> updateFollowUp({
    required String alertId,
    required AlertFollowUpUpdate update,
    required DateTime now,
  }) async => alerts.first;

  @override
  Future<DateTime?> getLastSuccessfulScan(String instituteId) async => null;

  @override
  Future<void> recordSuccessfulScan({
    required String instituteId,
    required DateTime completedAt,
    required String completedBy,
  }) async {}
}

class _FakeApprovalRepository implements ApprovalRepository {
  List<ApprovalAction> actions = [];

  @override
  Future<List<ApprovalAction>> getActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
  }) async => actions;

  @override
  Stream<List<ApprovalAction>> watchActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
    int limit = 300,
  }) => Stream.value(actions);

  @override
  Future<ApprovalAction?> getActionById(String id) async => null;
  @override
  Future<ApprovalAction> createAction(ApprovalAction a) async => a;
  @override
  Future<ApprovalAction> updateDecision(
    String id, {
    required String status,
    String? reviewer,
    String? rejectionReason,
    required DateTime decisionAt,
  }) async => actions.first;
  @override
  Future<bool> isActionsCollectionEmpty() async => actions.isEmpty;
}

void main() {
  const owner = AppUser(
    id: 'owner-1',
    name: 'Aarav Mehta',
    email: 'owner@demo.com',
    role: AppRole.owner,
  );

  const counselor = AppUser(
    id: 'counselor-1',
    name: 'Priya Sharma',
    email: 'counselor@demo.com',
    role: AppRole.counselor,
  );

  const trainer = AppUser(
    id: 'trainer-1',
    name: 'Rohan Kulkarni',
    email: 'trainer@demo.com',
    role: AppRole.trainer,
  );

  const accounts = AppUser(
    id: 'accounts-1',
    name: 'Vikram Joshi',
    email: 'accounts@demo.com',
    role: AppRole.accounts,
  );

  final now = DateTime.now();

  group('ReportsScreen Widget Tests', () {
    late _FakeStudentRepository studentRepo;
    late _FakeAttendanceRepository attendanceRepo;
    late _FakeFeeRepository feeRepo;
    late _FakeBatchRepository batchRepo;
    late _FakeCourseRepository courseRepo;
    late _FakeTrainerRepository trainerRepo;
    late _FakeTimetableRepository timetableRepo;
    late _FakeStudentAlertRepository alertRepo;
    late _FakeApprovalRepository approvalRepo;

    late ReportsService reportsService;
    late BatchService batchService;
    late CourseService courseService;

    setUp(() {
      studentRepo = _FakeStudentRepository();
      attendanceRepo = _FakeAttendanceRepository();
      feeRepo = _FakeFeeRepository();
      batchRepo = _FakeBatchRepository();
      courseRepo = _FakeCourseRepository();
      trainerRepo = _FakeTrainerRepository();
      timetableRepo = _FakeTimetableRepository();
      alertRepo = _FakeStudentAlertRepository();
      approvalRepo = _FakeApprovalRepository();

      reportsService = ReportsService(
        studentRepository: studentRepo,
        attendanceRepository: attendanceRepo,
        feeRepository: feeRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
        timetableRepository: timetableRepo,
        alertRepository: alertRepo,
        approvalRepository: approvalRepo,
      );

      batchService = BatchService(repository: batchRepo);
      courseService = CourseService(repository: courseRepo);

      // Seed baseline data
      studentRepo.students = [
        Student(
          id: 's-1',
          instituteId: 'demo-institute',
          fullName: 'Aarav Mehta',
          email: 'aarav@demo.com',
          phone: '9876543210',
          courseId: 'c-1',
          courseName: 'Flutter Masterclass',
          batchId: 'b-1',
          batchName: 'Morning Batch',
          enrollmentDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      batchRepo.batches = [
        Batch(
          id: 'b-1',
          instituteId: 'demo-institute',
          name: 'Morning Batch',
          courseId: 'c-1',
          courseName: 'Flutter Masterclass',
          trainerId: 'tr-1',
          trainerName: 'Rohan Kulkarni',
          startDate: now,
          endDate: now.add(const Duration(days: 90)),
          capacity: 30,
          scheduleDescription: 'Daily 10am',
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      courseRepo.courses = [
        Course(
          id: 'c-1',
          instituteId: 'demo-institute',
          name: 'Flutter Masterclass',
          description: 'Full stack Flutter',
          duration: '12 weeks',
          feeAmount: 35000,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      feeRepo.installments = [
        FeeInstallment(
          id: 'f-1',
          instituteId: 'demo-institute',
          studentId: 's-1',
          studentName: 'Aarav Mehta',
          courseId: 'c-1',
          batchId: 'b-1',
          amountDue: 35000,
          paidAmount: 20000,
          dueDate: now.add(const Duration(days: 10)),
          status: 'partiallyPaid',
          createdAt: now,
          updatedAt: now,
        ),
      ];
    });

    testWidgets('Owner sees all 5 report tabs and operational overview metrics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              user: owner,
              reportsService: reportsService,
              batchService: batchService,
              courseService: courseService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify all 5 tab labels are visible for Owner
      expect(find.text('Operational Overview'), findsOneWidget);
      expect(find.text('Student Enrollments'), findsOneWidget);
      expect(find.text('Attendance Analytics'), findsOneWidget);
      expect(find.text('Fee & Financials'), findsOneWidget);
      expect(find.text('Faculty & Timetable'), findsOneWidget);

      // Verify Operational Overview cards
      expect(find.text('Total Students'), findsOneWidget);
      expect(find.text('Active Cohorts'), findsOneWidget);
      expect(find.text('Fee Collection Rate'), findsOneWidget);
    });

    testWidgets('Counselor sees enrollment and attendance tabs, but fee and faculty tabs are hidden',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              user: counselor,
              reportsService: reportsService,
              batchService: batchService,
              courseService: courseService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Counseling Overview'), findsOneWidget);
      expect(find.text('Student Enrollments'), findsOneWidget);
      expect(find.text('Attendance Analytics'), findsOneWidget);

      // Financial and faculty tabs must NOT be present
      expect(find.text('Fee & Financials'), findsNothing);
      expect(find.text('Faculty & Timetable'), findsNothing);
    });

    testWidgets('Trainer sees cohort attendance and timetable tabs only',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              user: trainer,
              reportsService: reportsService,
              batchService: batchService,
              courseService: courseService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cohort Attendance'), findsOneWidget);
      expect(find.text('Class Timetable'), findsOneWidget);

      // Financial and enrollment tabs must NOT be present
      expect(find.text('Fee & Financials'), findsNothing);
      expect(find.text('Student Enrollments'), findsNothing);
      expect(find.text('Operational Overview'), findsNothing);
    });

    testWidgets('Accounts staff sees financial overview and fee reports only',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              user: accounts,
              reportsService: reportsService,
              batchService: batchService,
              courseService: courseService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Financial Overview'), findsOneWidget);
      expect(find.text('Fee & Revenue Reports'), findsOneWidget);

      // Faculty and enrollment tabs must NOT be present
      expect(find.text('Student Enrollments'), findsNothing);
      expect(find.text('Attendance Analytics'), findsNothing);
      expect(find.text('Faculty & Timetable'), findsNothing);
    });

    testWidgets('Attendance Analytics displays defaulter students below threshold',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Seed student and attendance
      studentRepo.students = [
        Student(
          id: 'defaulter-1',
          instituteId: 'demo-institute',
          fullName: 'Karan Defaulter',
          email: 'karan@demo.com',
          phone: '9876543210',
          courseId: 'c-1',
          courseName: 'Flutter Masterclass',
          batchId: 'b-1',
          batchName: 'Morning Batch',
          enrollmentDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      attendanceRepo.records = [
        AttendanceRecord(
          id: 'att-1',
          instituteId: 'demo-institute',
          studentId: 'defaulter-1',
          batchId: 'b-1',
          classDate: now,
          status: AttendanceStatus.absent,
          createdAt: now,
          updatedAt: now,
          recordedBy: 'trainer-1',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(
              user: owner,
              reportsService: reportsService,
              batchService: batchService,
              courseService: courseService,
              initialTab: 2, // Open Attendance Analytics directly
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Attendance tab content
      expect(find.text('Attendance Analytics'), findsWidgets);
      expect(find.text('Karan Defaulter'), findsOneWidget);
      expect(find.text('0.0%'), findsWidgets); // 0% attendance
    });
  });
}
