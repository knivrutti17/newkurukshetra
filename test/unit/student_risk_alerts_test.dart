import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/attendance_record.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/payment.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/models/student_alert.dart';
import 'package:kurukshetra/data/repositories/risk_scan_data_repository.dart';
import 'package:kurukshetra/data/repositories/student_alert_repository.dart';
import 'package:kurukshetra/data/services/risk_rule_engine.dart';
import 'package:kurukshetra/data/services/student_risk_alert_service.dart';

void main() {
  final asOf = DateTime(2026, 10, 17);

  group('RiskRuleEngine', () {
    test('calculates low attendance from recorded sessions only', () {
      final alerts = RiskRuleEngine().evaluate(
        students: [_student()],
        attendance: [
          _record(
            AttendanceStatus.present,
            asOf.subtract(const Duration(days: 5)),
          ),
          _record(
            AttendanceStatus.present,
            asOf.subtract(const Duration(days: 4)),
          ),
          _record(
            AttendanceStatus.present,
            asOf.subtract(const Duration(days: 3)),
          ),
          _record(
            AttendanceStatus.absent,
            asOf.subtract(const Duration(days: 2)),
          ),
          _record(
            AttendanceStatus.late,
            asOf.subtract(const Duration(days: 1)),
          ),
        ],
        installments: const [],
        payments: const [],
        asOf: asOf,
      );

      final low = alerts.singleWhere(
        (alert) => alert.type == StudentAlertType.lowAttendance,
      );
      expect(low.evidence['presentSessions'], 3);
      expect(low.evidence['recordedSessions'], 5);
      expect(low.evidence['attendancePercentage'], 60.0);
      expect(low.reason, contains('3 of 5 recorded sessions'));
    });

    test('does not flag low attendance until five recorded sessions exist', () {
      final alerts = RiskRuleEngine().evaluate(
        students: [_student()],
        attendance: List.generate(
          4,
          (index) => _record(
            AttendanceStatus.absent,
            asOf.subtract(Duration(days: index)),
          ),
        ),
        installments: const [],
        payments: const [],
        asOf: asOf,
      );
      expect(
        alerts.where((alert) => alert.type == StudentAlertType.lowAttendance),
        isEmpty,
      );
    });

    test('finds repeated absences in the configured recent period', () {
      final alerts = RiskRuleEngine().evaluate(
        students: [_student()],
        attendance: [
          _record(AttendanceStatus.absent, asOf),
          _record(
            AttendanceStatus.absent,
            asOf.subtract(const Duration(days: 9)),
          ),
          _record(
            AttendanceStatus.absent,
            asOf.subtract(const Duration(days: 29)),
          ),
          _record(
            AttendanceStatus.absent,
            asOf.subtract(const Duration(days: 35)),
          ),
        ],
        installments: const [],
        payments: const [],
        asOf: asOf,
      );
      final repeated = alerts.singleWhere(
        (alert) => alert.type == StudentAlertType.repeatedAbsence,
      );
      expect(repeated.evidence['absenceCount'], 3);
      expect(repeated.reason, contains('not assumed to be consecutive'));
    });

    test(
      'does not flag fully paid instalments and creates a combined risk',
      () {
        final student = _student();
        final fullyPaid = _installment(
          id: 'paid',
          dueDate: asOf.subtract(const Duration(days: 2)),
          paidAmount: 1000,
        );
        final overdue = _installment(
          id: 'overdue',
          dueDate: asOf.subtract(const Duration(days: 4)),
          paidAmount: 250,
        );
        final alerts = RiskRuleEngine().evaluate(
          students: [student],
          attendance: [
            _record(
              AttendanceStatus.present,
              asOf.subtract(const Duration(days: 6)),
            ),
            _record(
              AttendanceStatus.absent,
              asOf.subtract(const Duration(days: 5)),
            ),
            _record(
              AttendanceStatus.absent,
              asOf.subtract(const Duration(days: 4)),
            ),
            _record(
              AttendanceStatus.absent,
              asOf.subtract(const Duration(days: 3)),
            ),
            _record(
              AttendanceStatus.present,
              asOf.subtract(const Duration(days: 2)),
            ),
          ],
          installments: [fullyPaid, overdue],
          payments: const [],
          asOf: asOf,
        );

        final fee = alerts.singleWhere(
          (alert) => alert.type == StudentAlertType.overdueFees,
        );
        expect(fee.evidence['overdueInstalmentCount'], 1);
        expect(fee.evidence['outstandingBalance'], 750.0);
        expect(
          alerts.map((alert) => alert.type),
          contains(StudentAlertType.combinedRisk),
        );
      },
    );

    test('uses payment records when they exist for overdue balance', () {
      final installment = _installment(
        id: 'inst',
        dueDate: asOf.subtract(const Duration(days: 1)),
        paidAmount: 0,
      );
      final payment = Payment(
        id: 'payment',
        instituteId: 'demo-institute',
        feeInstallmentId: 'inst',
        studentId: 'student-1',
        amount: 1000,
        paymentDate: asOf,
        paymentMethod: 'UPI',
        recordedBy: 'accounts',
        createdAt: asOf,
      );
      final alerts = RiskRuleEngine().evaluate(
        students: [_student()],
        attendance: const [],
        installments: [installment],
        payments: [payment],
        asOf: asOf,
      );
      expect(alerts, isEmpty);
    });
  });

  group('StudentRiskAlertService', () {
    test(
      'deduplicates scan alerts and preserves follow-up notes on refresh',
      () async {
        final repository = _MemoryAlertRepository();
        final data = _MemoryScanData(
          RiskScanData(
            students: [_student()],
            attendance: [
              _record(
                AttendanceStatus.present,
                asOf.subtract(const Duration(days: 5)),
              ),
              _record(
                AttendanceStatus.absent,
                asOf.subtract(const Duration(days: 4)),
              ),
              _record(
                AttendanceStatus.absent,
                asOf.subtract(const Duration(days: 3)),
              ),
              _record(
                AttendanceStatus.absent,
                asOf.subtract(const Duration(days: 2)),
              ),
              _record(
                AttendanceStatus.present,
                asOf.subtract(const Duration(days: 1)),
              ),
            ],
            installments: const [],
            payments: const [],
          ),
        );
        final service = StudentRiskAlertService(
          alertRepository: repository,
          scanDataRepository: data,
        );
        final owner = _user(AppRole.owner, 'owner');

        final first = await service.runScan(owner, now: asOf);
        expect(first.created, 2); // low attendance and repeated absences
        expect(repository.alerts, hasLength(2));
        final low = repository.alerts.values.firstWhere(
          (alert) => alert.alertType == StudentAlertType.lowAttendance,
        );
        await service.updateFollowUp(
          user: owner,
          alert: low,
          status: StudentAlertStatus.followUp,
          note: 'Counselor will check in on Monday.',
          assignedTo: 'demo-counselor',
          now: asOf.add(const Duration(hours: 1)),
        );

        final second = await service.runScan(
          owner,
          now: asOf.add(const Duration(days: 1)),
        );
        expect(second.created, 0);
        expect(second.updated, 2);
        expect(repository.alerts, hasLength(2));
        final refreshed = repository.alerts[low.id]!;
        expect(refreshed.status, StudentAlertStatus.followUp);
        expect(refreshed.followUpNote, 'Counselor will check in on Monday.');
        expect(refreshed.assignedTo, 'demo-counselor');
        expect(refreshed.followUpHistory, hasLength(1));
      },
    );

    test('enforces status transitions and role-specific visibility', () async {
      final repository = _MemoryAlertRepository();
      final academic = _alert(
        type: StudentAlertType.lowAttendance,
        counselorId: 'counselor',
        trainerId: 'trainer',
      );
      final financial = _alert(id: 'fee', type: StudentAlertType.overdueFees);
      repository.alerts[academic.id] = academic;
      repository.alerts[financial.id] = financial;
      final service = StudentRiskAlertService(
        alertRepository: repository,
        scanDataRepository: _MemoryScanData(
          const RiskScanData(
            students: [],
            attendance: [],
            installments: [],
            payments: [],
          ),
        ),
      );
      final counselor = _user(AppRole.counselor, 'counselor');
      final trainer = _user(AppRole.trainer, 'trainer');
      final accounts = _user(AppRole.accounts, 'accounts');
      final owner = _user(AppRole.owner, 'owner');

      expect(service.canView(counselor, academic), isTrue);
      expect(service.canView(counselor, financial), isFalse);
      expect(service.canView(trainer, academic), isTrue);
      expect(service.canView(accounts, financial), isTrue);
      expect(service.canView(accounts, academic), isFalse);

      await expectLater(
        service.updateFollowUp(
          user: counselor,
          alert: academic,
          status: StudentAlertStatus.resolved,
          closureReason: 'Not needed',
        ),
        throwsA(isA<RiskAlertAccessException>()),
      );
      await expectLater(
        service.updateFollowUp(
          user: owner,
          alert: academic,
          status: StudentAlertStatus.resolved,
        ),
        throwsA(isA<RiskAlertAccessException>()),
      );
      final resolved = await service.updateFollowUp(
        user: owner,
        alert: academic,
        status: StudentAlertStatus.resolved,
        closureReason: 'Reviewed with the student.',
      );
      expect(resolved.status, StudentAlertStatus.resolved);
    });
  });
}

class _MemoryScanData implements RiskScanDataRepository {
  const _MemoryScanData(this.data);
  final RiskScanData data;
  @override
  Future<RiskScanData> loadInstituteData(String instituteId) async => data;
}

class _MemoryAlertRepository implements StudentAlertRepository {
  final Map<String, StudentAlert> alerts = <String, StudentAlert>{};
  DateTime? lastScan;

  @override
  Future<List<StudentAlert>> getAlertsForScan(String instituteId) async =>
      alerts.values.toList();

  @override
  Future<DateTime?> getLastSuccessfulScan(String instituteId) async => lastScan;

  @override
  Future<void> recordSuccessfulScan({
    required String instituteId,
    required DateTime completedAt,
    required String completedBy,
  }) async {
    lastScan = completedAt;
  }

  @override
  Future<AlertScanWriteResult> synchronizeScan({
    required String instituteId,
    required List<ProposedStudentAlert> candidates,
    required DateTime now,
  }) async {
    var created = 0;
    var updated = 0;
    var preservedClosed = 0;
    for (final candidate in candidates) {
      final current = alerts[candidate.id];
      if (current?.status.isClosed ?? false) {
        preservedClosed++;
      } else if (current == null) {
        created++;
        alerts[candidate.id] = _fromCandidate(candidate, now);
      } else {
        updated++;
        alerts[candidate.id] = StudentAlert(
          id: current.id,
          instituteId: current.instituteId,
          studentId: current.studentId,
          studentName: candidate.student.fullName,
          batchId: candidate.student.batchId,
          batchName: candidate.student.batchName,
          alertType: current.alertType,
          severity: candidate.severity,
          title: candidate.title,
          reason: candidate.reason,
          evidence: candidate.evidence,
          status: current.status,
          createdAt: current.createdAt,
          updatedAt: now,
          counselorId: candidate.student.counselorId,
          trainerId: candidate.student.trainerId,
          assignedTo: current.assignedTo,
          followUpNote: current.followUpNote,
          followUpHistory: current.followUpHistory,
        );
      }
    }
    return AlertScanWriteResult(
      created: created,
      updated: updated,
      preservedClosed: preservedClosed,
    );
  }

  @override
  Future<StudentAlert> updateFollowUp({
    required String alertId,
    required AlertFollowUpUpdate update,
    required DateTime now,
  }) async {
    final current = alerts[alertId]!;
    final next = current.copyWith(
      status: update.status,
      assignedTo: update.assignedTo,
      followUpNote: update.note,
      updatedAt: now,
      followUpHistory: [
        ...current.followUpHistory,
        AlertFollowUpEntry(
          at: now,
          actorId: update.actorId,
          actorName: update.actorName,
          note: update.note ?? '',
          status: update.status,
        ),
      ],
    );
    alerts[alertId] = next;
    return next;
  }

  @override
  Stream<List<StudentAlert>> watchAlerts(AlertAccessScope scope) =>
      Stream.value(alerts.values.toList());
}

AppUser _user(AppRole role, String id) =>
    AppUser(id: id, name: id, email: '$id@test.invalid', role: role);

Student _student() {
  final date = DateTime(2026, 1, 1);
  return Student(
    id: 'student-1',
    instituteId: 'demo-institute',
    fullName: 'Aisha Khan',
    email: 'aisha@test.invalid',
    phone: '',
    courseId: 'course',
    courseName: 'Course',
    batchId: 'batch-1',
    batchName: 'Batch One',
    enrollmentDate: date,
    status: 'active',
    createdAt: date,
    updatedAt: date,
    counselorId: 'counselor',
    trainerId: 'trainer',
  );
}

AttendanceRecord _record(AttendanceStatus status, DateTime date) =>
    AttendanceRecord(
      id: 'record-${date.millisecondsSinceEpoch}-$status',
      instituteId: 'demo-institute',
      studentId: 'student-1',
      batchId: 'batch-1',
      classDate: date,
      status: status,
      createdAt: date,
      updatedAt: date,
      recordedBy: 'owner',
      counselorId: 'counselor',
      trainerId: 'trainer',
    );

FeeInstallment _installment({
  required String id,
  required DateTime dueDate,
  required double paidAmount,
}) => FeeInstallment(
  id: id,
  instituteId: 'demo-institute',
  studentId: 'student-1',
  studentName: 'Aisha Khan',
  courseId: 'course',
  batchId: 'batch-1',
  amountDue: 1000,
  dueDate: dueDate,
  createdAt: dueDate,
  updatedAt: dueDate,
  status: 'pending',
  paidAmount: paidAmount,
);

StudentAlert _alert({
  String id = 'academic',
  required StudentAlertType type,
  String? counselorId,
  String? trainerId,
}) {
  final date = DateTime(2026, 10, 1);
  return StudentAlert(
    id: id,
    instituteId: 'demo-institute',
    studentId: 'student-1',
    studentName: 'Aisha Khan',
    batchId: 'batch-1',
    batchName: 'Batch One',
    alertType: type,
    severity: StudentAlertSeverity.medium,
    title: 'Alert',
    reason: 'Reason',
    evidence: const {},
    status: StudentAlertStatus.newAlert,
    createdAt: date,
    updatedAt: date,
    counselorId: counselorId,
    trainerId: trainerId,
  );
}

StudentAlert _fromCandidate(ProposedStudentAlert candidate, DateTime now) =>
    StudentAlert(
      id: candidate.id,
      instituteId: candidate.student.instituteId,
      studentId: candidate.student.id,
      studentName: candidate.student.fullName,
      batchId: candidate.student.batchId,
      batchName: candidate.student.batchName,
      alertType: candidate.type,
      severity: candidate.severity,
      title: candidate.title,
      reason: candidate.reason,
      evidence: candidate.evidence,
      status: StudentAlertStatus.newAlert,
      createdAt: now,
      updatedAt: now,
      counselorId: candidate.student.counselorId,
      trainerId: candidate.student.trainerId,
    );
