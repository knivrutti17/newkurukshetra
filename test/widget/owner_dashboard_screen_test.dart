import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/approval_action.dart';
import 'package:kurukshetra/data/models/class_session.dart';
import 'package:kurukshetra/features/dashboard/screens/owner_dashboard_screen.dart';

ClassSession _createSession({
  String id = 'session-1',
  String courseName = 'Full Stack Development',
  String batchName = 'Batch Alpha',
  String trainerName = 'Arjun Verma',
  DateTime? startAt,
  DateTime? endAt,
  String deliveryMode = 'in_person',
  String status = 'scheduled',
}) {
  final now = DateTime.now();
  final start = startAt ?? DateTime(now.year, now.month, now.day, 10, 0);
  final end = endAt ?? DateTime(now.year, now.month, now.day, 11, 30);
  return ClassSession(
    id: id,
    instituteId: 'demo-institute',
    batchId: 'batch-1',
    batchName: batchName,
    courseId: 'course-1',
    courseName: courseName,
    trainerId: 'trainer-1',
    trainerName: trainerName,
    startAt: start,
    endAt: end,
    deliveryMode: deliveryMode,
    roomId: 'room-1',
    roomName: 'Lab 101',
    meetingLink: '',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

ApprovalAction _createApproval({
  String id = 'approval-1',
  String title = '15% Concession for Rohan Sharma',
  String type = 'fee_concession',
  String requestedBy = 'Priya Counselor',
  DateTime? requestedAt,
  String status = 'pending',
}) {
  final now = DateTime.now();
  return ApprovalAction(
    id: id,
    instituteId: 'demo-institute',
    type: type,
    title: title,
    description: 'Merit-based financial concession',
    payload: const {},
    requestedBy: requestedBy,
    requestedAt: requestedAt ?? now.subtract(const Duration(hours: 2)),
    status: status,
    updatedAt: now,
  );
}

void main() {
  const testUser = AppUser(
    id: 'owner-1',
    name: 'Nivrutti K',
    email: 'owner@demo.com',
    role: AppRole.owner,
    instituteId: 'demo-institute',
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    AppUser user = testUser,
    Future<OwnerDashboardData> Function()? dataLoader,
    ValueChanged<String>? onSectionSelected,
    Size surfaceSize = const Size(1400, 1000),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OwnerDashboardScreen(
          user: user,
          dataLoader: dataLoader,
          onSectionSelected: onSectionSelected,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders header greeting, subtitle, and live connection badge', (
    tester,
  ) async {
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 3,
      todaysSessions: [_createSession()],
      recentPendingApprovals: [_createApproval()],
    );

    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
    );

    expect(find.text('Good to see you, Nivrutti.'), findsOneWidget);
    expect(find.text('Here is your institute overview for today.'), findsOneWidget);
    expect(find.text('Live connected'), findsOneWidget);
    expect(find.text('OWNER'), findsOneWidget);
  });

  testWidgets('renders four KPI cards with real numeric metrics', (tester) async {
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 3,
      todaysSessions: [_createSession()],
      recentPendingApprovals: [_createApproval()],
    );

    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
    );

    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);

    expect(find.text('Active Batches'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    expect(find.text("Today's Classes"), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    expect(find.text('Pending Approvals'), findsWidgets);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('KPI cards trigger onSectionSelected when clicked', (tester) async {
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 12,
      activeBatchesCount: 4,
      todaysClassesCount: 2,
      pendingApprovalsCount: 5,
      todaysSessions: [_createSession()],
      recentPendingApprovals: [_createApproval()],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
    );

    // Tap Active Students
    await tester.tap(find.text('Active Students'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('students'));

    // Tap Active Batches
    await tester.tap(find.text('Active Batches'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('courses-batches'));

    // Tap Today's Classes
    await tester.tap(find.text("Today's Classes"));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('timetable'));

    // Tap Pending Approvals KPI card
    await tester.tap(find.text('Pending Approvals').first);
    await tester.pumpAndSettle();
    expect(tappedSections, contains('approvals'));
  });

  testWidgets('displays today schedule session and navigates to timetable', (
    tester,
  ) async {
    final session = _createSession(
      courseName: 'Cloud DevOps Masterclass',
      batchName: 'Cohort Delta',
      trainerName: 'Vikram Joshi',
    );
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 3,
      todaysSessions: [session],
      recentPendingApprovals: [_createApproval()],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
    );

    expect(find.text('Cloud DevOps Masterclass • Cohort Delta'), findsOneWidget);
    expect(find.text('Vikram Joshi'), findsOneWidget);

    // Click session tile
    await tester.tap(find.text('Cloud DevOps Masterclass • Cohort Delta'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('timetable'));
  });

  testWidgets('displays empty schedule state when no sessions scheduled', (
    tester,
  ) async {
    final sampleData = const OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 0,
      pendingApprovalsCount: 3,
      todaysSessions: [],
      recentPendingApprovals: [],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
    );

    expect(find.text('No classes scheduled for today'), findsOneWidget);
    expect(find.text('Open Timetable Management'), findsOneWidget);

    await tester.tap(find.text('Open Timetable Management'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('timetable'));
  });

  testWidgets('displays pending approvals list and review button navigates', (
    tester,
  ) async {
    final approval = _createApproval(
      title: 'Fee waiver for Ankit Patel',
      type: 'fee_concession',
      requestedBy: 'Counselor Priya',
    );
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 1,
      todaysSessions: [_createSession()],
      recentPendingApprovals: [approval],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
    );

    expect(find.text('Fee waiver for Ankit Patel'), findsOneWidget);
    expect(find.text('Fee Concession'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('approvals'));
  });

  testWidgets('displays empty approvals state when no actions pending', (
    tester,
  ) async {
    final sampleData = const OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 0,
      todaysSessions: [],
      recentPendingApprovals: [],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
    );

    expect(find.text('All approvals are up to date'), findsOneWidget);
    expect(find.text('Go to Approvals Center'), findsOneWidget);

    await tester.tap(find.text('Go to Approvals Center'));
    await tester.pumpAndSettle();
    expect(tappedSections, contains('approvals'));
  });

  testWidgets('all six quick actions trigger their corresponding routing id', (
    tester,
  ) async {
    final sampleData = OwnerDashboardData(
      activeStudentsCount: 9,
      activeBatchesCount: 6,
      todaysClassesCount: 1,
      pendingApprovalsCount: 3,
      todaysSessions: [_createSession()],
      recentPendingApprovals: [_createApproval()],
    );

    final List<String> tappedSections = [];
    await pumpDashboard(
      tester,
      dataLoader: () async => sampleData,
      onSectionSelected: (id) => tappedSections.add(id),
      surfaceSize: const Size(1400, 1400),
    );

    // 1. Add Student
    await tester.ensureVisible(find.text('Add Student'));
    await tester.tap(find.text('Add Student'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'students');

    // 2. Open Attendance
    await tester.ensureVisible(find.text('Open Attendance'));
    await tester.tap(find.text('Open Attendance'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'attendance');

    // 3. View Timetable
    await tester.ensureVisible(find.text('View Timetable'));
    await tester.tap(find.text('View Timetable'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'timetable');

    // 4. Review Approvals
    await tester.ensureVisible(find.text('Review Approvals'));
    await tester.tap(find.text('Review Approvals'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'approvals');

    // 5. Open Reports
    await tester.ensureVisible(find.text('Open Reports'));
    await tester.tap(find.text('Open Reports'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'reports');

    // 6. Ask AI Copilot
    await tester.ensureVisible(find.text('Ask AI Copilot'));
    await tester.tap(find.text('Ask AI Copilot'));
    await tester.pumpAndSettle();
    expect(tappedSections.last, 'copilot');
  });

  testWidgets('error state displays message and allows retry', (tester) async {
    int attempts = 0;
    Future<OwnerDashboardData> loader() async {
      attempts++;
      if (attempts == 1) {
        throw Exception('Network unreachable');
      }
      return OwnerDashboardData(
        activeStudentsCount: 9,
        activeBatchesCount: 6,
        todaysClassesCount: 1,
        pendingApprovalsCount: 3,
        todaysSessions: [_createSession()],
        recentPendingApprovals: [_createApproval()],
      );
    }

    await pumpDashboard(
      tester,
      dataLoader: loader,
    );

    expect(find.text('Unable to load live dashboard data'), findsOneWidget);
    expect(find.text('Retry connection'), findsOneWidget);

    // Tap Retry
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load live dashboard data'), findsNothing);
    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });
}
