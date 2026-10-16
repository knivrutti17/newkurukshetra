import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/student_alert.dart';
import 'package:kurukshetra/data/repositories/risk_scan_data_repository.dart';
import 'package:kurukshetra/data/repositories/student_alert_repository.dart';
import 'package:kurukshetra/data/services/risk_rule_engine.dart';
import 'package:kurukshetra/data/services/student_risk_alert_service.dart';
import 'package:kurukshetra/features/risk_alerts/screens/student_risk_alerts_screen.dart';

void main() {
  final now = DateTime(2026, 10, 17, 10, 30);

  group('StudentRiskAlertsScreen Widget Tests', () {
    testWidgets('Owner sees summary cards, action buttons, table rows and opens detail dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _WidgetMemoryAlertRepository();
      final alert1 = _createAlert(
        id: 'alert-1',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        type: StudentAlertType.lowAttendance,
        severity: StudentAlertSeverity.high,
        status: StudentAlertStatus.newAlert,
        reason: '3 of 5 recorded sessions were present (60.0%), below the 75% threshold.',
        createdAt: now,
      );
      final alert2 = _createAlert(
        id: 'alert-2',
        studentId: 'student-2',
        studentName: 'Vikram Rao',
        type: StudentAlertType.overdueFees,
        severity: StudentAlertSeverity.medium,
        status: StudentAlertStatus.followUp,
        reason: '₹15,000.00 is outstanding across 1 overdue instalment; due 01/10/2026.',
        createdAt: now,
      );
      repo.alerts[alert1.id] = alert1;
      repo.alerts[alert2.id] = alert2;

      final service = StudentRiskAlertService(
        alertRepository: repo,
        scanDataRepository: _WidgetEmptyScanData(),
      );

      final owner = const AppUser(
        id: 'owner-1',
        name: 'Aarav Patel',
        email: 'owner@institute.test',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentRiskAlertsScreen(
              user: owner,
              riskAlertService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Screen Header & Buttons
      expect(find.text('Student Risk Alerts & Follow-up'), findsOneWidget);
      expect(find.text('Refresh Risk Scan'), findsOneWidget);

      // Summary Cards
      expect(find.text('New alerts'), findsOneWidget);
      expect(find.text('High priority'), findsOneWidget);
      expect(find.text('Awaiting follow-up'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      // Alert Table Rows
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('Vikram Rao'), findsOneWidget);
      expect(find.text('Low attendance'), findsOneWidget);
      expect(find.text('Overdue instalments'), findsOneWidget);

      // Open detail dialog for Aisha Khan
      final openButtons = find.widgetWithText(OutlinedButton, 'Open');
      expect(openButtons, findsNWidgets(2));
      await tester.tap(openButtons.first);
      await tester.pumpAndSettle();

      // Detail dialog contents
      expect(find.text('Student and alert'), findsOneWidget);
      expect(find.text('Why this indicator exists'), findsOneWidget);
      expect(find.text('Follow-up'), findsOneWidget);
      expect(find.text('Follow-up owner'), findsOneWidget); // Owner can assign
      expect(find.text('Add follow-up note'), findsOneWidget);

      // Add a note and save follow-up
      await tester.enterText(
        find.widgetWithText(TextField, 'Add follow-up note'),
        'Spoke with student regarding attendance.',
      );
      await tester.tap(find.text('Save follow-up'));
      await tester.pumpAndSettle();

      expect(find.text('Alert follow-up saved.'), findsOneWidget);
      expect(repo.alerts[alert1.id]!.followUpNote, 'Spoke with student regarding attendance.');
      expect(repo.alerts[alert1.id]!.followUpHistory, hasLength(1));
    });

    testWidgets('Counselor sees only assigned academic alerts without Refresh button or fee details', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _WidgetMemoryAlertRepository();
      final assignedAcademic = _createAlert(
        id: 'alert-counselor',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        type: StudentAlertType.lowAttendance,
        counselorId: 'counselor-1',
        createdAt: now,
      );
      final unassignedAcademic = _createAlert(
        id: 'alert-other-counselor',
        studentId: 'student-2',
        studentName: 'Rahul Verma',
        type: StudentAlertType.repeatedAbsence,
        counselorId: 'counselor-2',
        createdAt: now,
      );
      final financialAlert = _createAlert(
        id: 'alert-fee',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        type: StudentAlertType.overdueFees,
        counselorId: 'counselor-1',
        createdAt: now,
      );
      repo.alerts[assignedAcademic.id] = assignedAcademic;
      repo.alerts[unassignedAcademic.id] = unassignedAcademic;
      repo.alerts[financialAlert.id] = financialAlert;

      final service = StudentRiskAlertService(
        alertRepository: repo,
        scanDataRepository: _WidgetEmptyScanData(),
      );

      final counselor = const AppUser(
        id: 'counselor-1',
        name: 'Priya Sharma',
        email: 'counselor@institute.test',
        role: AppRole.counselor,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentRiskAlertsScreen(
              user: counselor,
              riskAlertService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Counselor sees assigned academic alert
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('Low attendance'), findsOneWidget);

      // Counselor does NOT see unassigned or financial alerts
      expect(find.text('Rahul Verma'), findsNothing);
      expect(find.text('Overdue instalments'), findsNothing);

      // Counselor does NOT have Refresh Risk Scan action
      expect(find.text('Refresh Risk Scan'), findsNothing);

      // Open detail dialog
      await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
      await tester.pumpAndSettle();

      // Counselor cannot assign follow-up owner
      expect(find.text('Follow-up owner'), findsNothing);
    });

    testWidgets('Trainer sees only assigned batch academic alerts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _WidgetMemoryAlertRepository();
      final assigned = _createAlert(
        id: 'alert-trainer',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        type: StudentAlertType.lowAttendance,
        trainerId: 'trainer-1',
        createdAt: now,
      );
      final unassigned = _createAlert(
        id: 'alert-other-trainer',
        studentId: 'student-2',
        studentName: 'Rahul Verma',
        type: StudentAlertType.lowAttendance,
        trainerId: 'trainer-2',
        createdAt: now,
      );
      repo.alerts[assigned.id] = assigned;
      repo.alerts[unassigned.id] = unassigned;

      final service = StudentRiskAlertService(
        alertRepository: repo,
        scanDataRepository: _WidgetEmptyScanData(),
      );

      final trainer = const AppUser(
        id: 'trainer-1',
        name: 'Rohan Kulkarni',
        email: 'trainer@institute.test',
        role: AppRole.trainer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentRiskAlertsScreen(
              user: trainer,
              riskAlertService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('Rahul Verma'), findsNothing);
      expect(find.text('Refresh Risk Scan'), findsNothing);
    });

    testWidgets('Accounts staff sees only overdue fees alerts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _WidgetMemoryAlertRepository();
      final academic = _createAlert(
        id: 'alert-academic',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        type: StudentAlertType.lowAttendance,
        createdAt: now,
      );
      final financial = _createAlert(
        id: 'alert-financial',
        studentId: 'student-2',
        studentName: 'Vikram Rao',
        type: StudentAlertType.overdueFees,
        createdAt: now,
      );
      repo.alerts[academic.id] = academic;
      repo.alerts[financial.id] = financial;

      final service = StudentRiskAlertService(
        alertRepository: repo,
        scanDataRepository: _WidgetEmptyScanData(),
      );

      final accounts = const AppUser(
        id: 'accounts-1',
        name: 'Neha Gupta',
        email: 'accounts@institute.test',
        role: AppRole.accounts,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentRiskAlertsScreen(
              user: accounts,
              riskAlertService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Vikram Rao'), findsOneWidget);
      expect(find.text('Overdue instalments'), findsOneWidget);
      expect(find.text('Aisha Khan'), findsNothing);
      expect(find.text('Low attendance'), findsNothing);
      expect(find.text('Refresh Risk Scan'), findsNothing);
    });

    testWidgets('Empty state displays when no alerts exist', (tester) async {
      final service = StudentRiskAlertService(
        alertRepository: _WidgetMemoryAlertRepository(),
        scanDataRepository: _WidgetEmptyScanData(),
      );

      final owner = const AppUser(
        id: 'owner-1',
        name: 'Aarav Patel',
        email: 'owner@institute.test',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudentRiskAlertsScreen(
              user: owner,
              riskAlertService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No risk alerts yet'), findsOneWidget);
      expect(
        find.textContaining('Owners can run Refresh Risk Scan'),
        findsOneWidget,
      );
    });
  });
}

StudentAlert _createAlert({
  required String id,
  required String studentId,
  required String studentName,
  required StudentAlertType type,
  StudentAlertSeverity severity = StudentAlertSeverity.medium,
  StudentAlertStatus status = StudentAlertStatus.newAlert,
  String reason = 'Test reason for alert',
  String? counselorId,
  String? trainerId,
  required DateTime createdAt,
}) => StudentAlert(
  id: id,
  instituteId: 'demo-institute',
  studentId: studentId,
  studentName: studentName,
  batchId: 'batch-1',
  batchName: 'Batch One',
  alertType: type,
  severity: severity,
  title: type.label,
  reason: reason,
  evidence: const <String, dynamic>{'testKey': 'testValue'},
  status: status,
  createdAt: createdAt,
  updatedAt: createdAt,
  counselorId: counselorId,
  trainerId: trainerId,
);

class _WidgetEmptyScanData implements RiskScanDataRepository {
  @override
  Future<RiskScanData> loadInstituteData(String instituteId) async =>
      const RiskScanData(
        students: [],
        attendance: [],
        installments: [],
        payments: [],
      );
}

class _WidgetMemoryAlertRepository implements StudentAlertRepository {
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
  }) async => const AlertScanWriteResult(created: 0, updated: 0, preservedClosed: 0);

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
