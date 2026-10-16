import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/approval_action.dart';
import 'package:kurukshetra/data/models/attendance_record.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/class_session.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/models/student_alert.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/approval_repository.dart';
import 'package:kurukshetra/data/repositories/attendance_repository.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/fee_repository.dart';
import 'package:kurukshetra/data/repositories/student_alert_repository.dart';
import 'package:kurukshetra/data/repositories/student_repository.dart';
import 'package:kurukshetra/data/repositories/timetable_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/reports_service.dart';
import 'package:kurukshetra/data/services/risk_rule_engine.dart';

class _FakeStudentRepository implements StudentRepository {
  List<Student> students = [];

  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) {
    return Stream.value(students);
  }

  @override
  Future<Student> createStudent(Student student) async => student;
  @override
  Future<Student> updateStudent(Student student) async => student;
  @override
  Future<Student> archiveStudent(Student student) async => student;
  @override
  Future<bool> isStudentsCollectionEmpty() async => students.isEmpty;
}

class _FakeAttendanceRepository implements AttendanceRepository {
  List<AttendanceRecord> records = [];

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory({
    required AttendanceAccessScope scope,
    int limit = 500,
  }) {
    return Stream.value(records);
  }

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
  Stream<List<Payment>> watchPaymentsForInstallment(String id) =>
      Stream.value([]);
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
  Future<List<StudentAlert>> getAlertsForScan(String instituteId) async =>
      alerts;

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
  final now = DateTime(2026, 3, 1, 10, 0);

  Student makeStudent({
    required String id,
    required String name,
    required String courseId,
    required String courseName,
    required String batchId,
    required String batchName,
    String status = 'active',
  }) {
    return Student(
      id: id,
      instituteId: 'demo-institute',
      fullName: name,
      email: '$id@demo.com',
      phone: '9876543210',
      courseId: courseId,
      courseName: courseName,
      batchId: batchId,
      batchName: batchName,
      enrollmentDate: now,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  AttendanceRecord makeAttendance({
    required String id,
    required String studentId,
    required String batchId,
    required AttendanceStatus status,
    required DateTime date,
  }) {
    return AttendanceRecord(
      id: id,
      studentId: studentId,
      batchId: batchId,
      classDate: date,
      status: status,
      createdAt: date,
      updatedAt: date,
      recordedBy: 'trainer-1',
      instituteId: 'demo-institute',
    );
  }

  FeeInstallment makeInstallment({
    required String id,
    required String studentId,
    required double amountDue,
    required double paidAmount,
    required DateTime dueDate,
    required String status,
  }) {
    return FeeInstallment(
      id: id,
      instituteId: 'demo-institute',
      studentId: studentId,
      studentName: 'Student $studentId',
      courseId: 'c-1',
      batchId: 'b-1',
      amountDue: amountDue,
      paidAmount: paidAmount,
      dueDate: dueDate,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('ReportsService Analytics Calculations', () {
    late _FakeStudentRepository studentRepo;
    late _FakeAttendanceRepository attendanceRepo;
    late _FakeFeeRepository feeRepo;
    late _FakeBatchRepository batchRepo;
    late _FakeTrainerRepository trainerRepo;
    late _FakeTimetableRepository timetableRepo;
    late _FakeStudentAlertRepository alertRepo;
    late _FakeApprovalRepository approvalRepo;
    late ReportsService reportsService;

    setUp(() {
      studentRepo = _FakeStudentRepository();
      attendanceRepo = _FakeAttendanceRepository();
      feeRepo = _FakeFeeRepository();
      batchRepo = _FakeBatchRepository();
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
    });

    test('getStudentReport aggregates active vs inactive and filters by course/batch', () async {
      studentRepo.students = [
        makeStudent(
          id: 's1',
          name: 'Aarav',
          courseId: 'c-flutter',
          courseName: 'Flutter Development',
          batchId: 'b-morn',
          batchName: 'Morning Cohort',
          status: 'active',
        ),
        makeStudent(
          id: 's2',
          name: 'Diya',
          courseId: 'c-flutter',
          courseName: 'Flutter Development',
          batchId: 'b-eve',
          batchName: 'Evening Cohort',
          status: 'active',
        ),
        makeStudent(
          id: 's3',
          name: 'Rohan',
          courseId: 'c-python',
          courseName: 'Python AI',
          batchId: 'b-py',
          batchName: 'Weekend Cohort',
          status: 'inactive',
        ),
      ];

      final allData = await reportsService.getStudentReport();
      expect(allData.totalStudents, 3);
      expect(allData.activeStudents, 2);
      expect(allData.inactiveStudents, 1);
      expect(allData.studentsByCourse['Flutter Development'], 2);
      expect(allData.studentsByCourse['Python AI'], 1);

      // Filtering by course
      final flutterOnly = await reportsService.getStudentReport(courseFilter: 'c-flutter');
      expect(flutterOnly.totalStudents, 2);
      expect(flutterOnly.activeStudents, 2);
      expect(flutterOnly.inactiveStudents, 0);

      // Filtering by batch
      final mornOnly = await reportsService.getStudentReport(batchFilter: 'b-morn');
      expect(mornOnly.totalStudents, 1);
      expect(mornOnly.studentsByBatch['Morning Cohort'], 1);
    });

    test('getAttendanceReport calculates percentages and flags defaulters below threshold', () async {
      studentRepo.students = [
        makeStudent(
          id: 's1',
          name: 'Aarav Good',
          courseId: 'c-1',
          courseName: 'Course 1',
          batchId: 'b-1',
          batchName: 'Batch 1',
        ),
        makeStudent(
          id: 's2',
          name: 'Diya Defaulter',
          courseId: 'c-1',
          courseName: 'Course 1',
          batchId: 'b-1',
          batchName: 'Batch 1',
        ),
      ];

      // s1: 4 present, 0 absent = 100%
      // s2: 1 present, 3 absent = 25% (defaulter below 75%)
      attendanceRepo.records = [
        makeAttendance(id: 'a1', studentId: 's1', batchId: 'b-1', status: AttendanceStatus.present, date: now),
        makeAttendance(id: 'a2', studentId: 's1', batchId: 'b-1', status: AttendanceStatus.present, date: now.add(const Duration(days: 1))),
        makeAttendance(id: 'a3', studentId: 's1', batchId: 'b-1', status: AttendanceStatus.present, date: now.add(const Duration(days: 2))),
        makeAttendance(id: 'a4', studentId: 's1', batchId: 'b-1', status: AttendanceStatus.present, date: now.add(const Duration(days: 3))),
        makeAttendance(id: 'a5', studentId: 's2', batchId: 'b-1', status: AttendanceStatus.present, date: now),
        makeAttendance(id: 'a6', studentId: 's2', batchId: 'b-1', status: AttendanceStatus.absent, date: now.add(const Duration(days: 1))),
        makeAttendance(id: 'a7', studentId: 's2', batchId: 'b-1', status: AttendanceStatus.absent, date: now.add(const Duration(days: 2))),
        makeAttendance(id: 'a8', studentId: 's2', batchId: 'b-1', status: AttendanceStatus.absent, date: now.add(const Duration(days: 3))),
      ];

      final report = await reportsService.getAttendanceReport(threshold: 75.0);
      expect(report.totalRecords, 8);
      expect(report.presentCount, 5);
      expect(report.absentCount, 3);
      expect(report.lateCount, 0);
      expect(report.overallPercentage, (5 / 8) * 100);

      expect(report.studentsBelowThreshold.length, 1);
      final defaulter = report.studentsBelowThreshold.first;
      expect(defaulter.studentId, 's2');
      expect(defaulter.studentName, 'Diya Defaulter');
      expect(defaulter.percentage, 25.0);
    });

    test('getFeeReport accurately sums billed, collected, balance, and overdue amounts', () async {
      feeRepo.installments = [
        makeInstallment(
          id: 'inst-1',
          studentId: 's1',
          amountDue: 20000.0,
          paidAmount: 20000.0,
          dueDate: now.subtract(const Duration(days: 10)),
          status: 'paid',
        ),
        makeInstallment(
          id: 'inst-2',
          studentId: 's2',
          amountDue: 30000.0,
          paidAmount: 10000.0,
          dueDate: now.subtract(const Duration(days: 5)),
          status: 'overdue',
        ),
        makeInstallment(
          id: 'inst-3',
          studentId: 's3',
          amountDue: 25000.0,
          paidAmount: 0.0,
          dueDate: DateTime.now().add(const Duration(days: 15)),
          status: 'pending',
        ),
      ];

      final feeReport = await reportsService.getFeeReport();
      expect(feeReport.totalDue, 75000.0);
      expect(feeReport.totalCollected, 30000.0);
      expect(feeReport.outstandingBalance, 45000.0);
      expect(feeReport.overdueCount, 1);
      expect(feeReport.overdueAmount, 20000.0); // 30000 - 10000
      expect(feeReport.collectionRate, closeTo(40.0, 0.01)); // 30k / 75k * 100 = 40%
    });

    test('getTrainerTimetableReport aggregates faculty assignments and session delivery modes', () async {
      trainerRepo.trainers = [
        Trainer(
          id: 'tr-1',
          instituteId: 'demo-institute',
          fullName: 'Rohan Kulkarni',
          email: 'rohan@demo.com',
          emailNormalized: 'rohan@demo.com',
          phone: '9876543210',
          expertise: const ['Flutter'],
          qualifications: 'B.Tech',
          experienceYears: 6,
          availability: const TrainerAvailability(),
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
        Trainer(
          id: 'tr-2',
          instituteId: 'demo-institute',
          fullName: 'Pooja Verma',
          email: 'pooja@demo.com',
          emailNormalized: 'pooja@demo.com',
          phone: '9876543211',
          expertise: const ['UI/UX'],
          qualifications: 'M.Des',
          experienceYears: 4,
          availability: const TrainerAvailability(),
          status: 'inactive',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      batchRepo.batches = [
        Batch(
          id: 'b-1',
          instituteId: 'demo-institute',
          name: 'Flutter Batch 1',
          courseId: 'c-1',
          courseName: 'Flutter',
          trainerId: 'tr-1',
          trainerName: 'Rohan Kulkarni',
          startDate: now,
          endDate: now.add(const Duration(days: 90)),
          capacity: 30,
          scheduleDescription: 'Mon-Fri 10am',
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      timetableRepo.sessions = [
        ClassSession(
          id: 'sess-1',
          instituteId: 'demo-institute',
          batchId: 'b-1',
          batchName: 'Flutter Batch 1',
          courseId: 'c-1',
          courseName: 'Flutter',
          trainerId: 'tr-1',
          trainerName: 'Rohan Kulkarni',
          startAt: now,
          endAt: now.add(const Duration(hours: 2)),
          deliveryMode: 'in_person',
          roomId: 'room-1',
          roomName: 'Lab 1',
          meetingLink: '',
          status: 'scheduled',
          createdAt: now,
          updatedAt: now,
        ),
        ClassSession(
          id: 'sess-2',
          instituteId: 'demo-institute',
          batchId: 'b-1',
          batchName: 'Flutter Batch 1',
          courseId: 'c-1',
          courseName: 'Flutter',
          trainerId: 'tr-1',
          trainerName: 'Rohan Kulkarni',
          startAt: now.subtract(const Duration(days: 1)),
          endAt: now.subtract(const Duration(days: 1, hours: -2)),
          deliveryMode: 'online',
          roomId: '',
          roomName: '',
          meetingLink: 'https://meet.google.com/abc',
          status: 'completed',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final facultyReport = await reportsService.getTrainerTimetableReport();
      expect(facultyReport.totalTrainers, 2);
      expect(facultyReport.activeTrainers, 1);
      expect(facultyReport.inactiveTrainers, 1);
      expect(facultyReport.trainerBatchAssignments['Rohan Kulkarni'], 1);
      expect(facultyReport.totalClasses, 2);
      expect(facultyReport.scheduledClasses, 1);
      expect(facultyReport.completedClasses, 1);
      expect(facultyReport.inPersonClasses, 1);
      expect(facultyReport.onlineClasses, 1);
    });

    test('getOperationalSummary calculates unified dashboard metrics', () async {
      studentRepo.students = [
        makeStudent(
          id: 's1',
          name: 'Aarav',
          courseId: 'c-1',
          courseName: 'Course 1',
          batchId: 'b-1',
          batchName: 'Batch 1',
        ),
      ];

      batchRepo.batches = [
        Batch(
          id: 'b-1',
          instituteId: 'demo-institute',
          name: 'Active Batch',
          courseId: 'c-1',
          courseName: 'Course 1',
          trainerId: 'tr-1',
          trainerName: 'Rohan',
          startDate: now,
          endDate: now.add(const Duration(days: 60)),
          capacity: 25,
          scheduleDescription: 'Daily',
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      approvalRepo.actions = [
        ApprovalAction(
          id: 'act-1',
          instituteId: 'demo-institute',
          type: 'fee_concession',
          title: 'Concession',
          description: 'Desc',
          payload: const {},
          requestedBy: 'Counselor',
          requestedAt: now,
          status: 'pending',
          updatedAt: now,
        ),
      ];

      alertRepo.alerts = [
        StudentAlert(
          id: 'al-1',
          instituteId: 'demo-institute',
          studentId: 's1',
          studentName: 'Aarav',
          batchId: 'b-1',
          batchName: 'Active Batch',
          alertType: StudentAlertType.lowAttendance,
          severity: StudentAlertSeverity.high,
          title: 'Low attendance alert',
          reason: 'Reason',
          evidence: const {},
          status: StudentAlertStatus.newAlert,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final realNow = DateTime.now();
      final today = DateTime(realNow.year, realNow.month, realNow.day, 14, 0);
      timetableRepo.sessions = [
        ClassSession(
          id: 'sess-today',
          instituteId: 'demo-institute',
          batchId: 'b-1',
          batchName: 'Active Batch',
          courseId: 'c-1',
          courseName: 'Course 1',
          trainerId: 'tr-1',
          trainerName: 'Rohan',
          startAt: today,
          endAt: today.add(const Duration(hours: 2)),
          deliveryMode: 'in_person',
          roomId: 'r1',
          roomName: 'Lab 1',
          meetingLink: '',
          status: 'scheduled',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      feeRepo.installments = [
        makeInstallment(
          id: 'f1',
          studentId: 's1',
          amountDue: 10000,
          paidAmount: 8000,
          dueDate: now,
          status: 'partiallyPaid',
        ),
      ];

      final summary = await reportsService.getOperationalSummary();
      expect(summary.totalStudents, 1);
      expect(summary.activeBatches, 1);
      expect(summary.pendingApprovals, 1);
      expect(summary.openAlerts, 1);
      expect(summary.overallFeeCollectionRate, 80.0);
    });
  });
}
