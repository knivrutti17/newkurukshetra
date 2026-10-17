import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/approval_action.dart';
import '../../../data/models/class_session.dart';

/// Aggregated data payload for the Owner / Admin dashboard.
class OwnerDashboardData {
  const OwnerDashboardData({
    required this.activeStudentsCount,
    required this.activeBatchesCount,
    required this.todaysClassesCount,
    required this.pendingApprovalsCount,
    required this.todaysSessions,
    required this.recentPendingApprovals,
  });

  final int activeStudentsCount;
  final int activeBatchesCount;
  final int todaysClassesCount;
  final int pendingApprovalsCount;
  final List<ClassSession> todaysSessions;
  final List<ApprovalAction> recentPendingApprovals;
}

/// Specialized failure representation when a dashboard query encounters a Firestore issue.
class DashboardQueryFailure implements Exception {
  const DashboardQueryFailure(this.queryName, this.firebaseError);

  final String queryName;
  final FirebaseException firebaseError;

  bool get requiresIndex =>
      firebaseError.code == 'failed-precondition' &&
      (firebaseError.message?.toLowerCase().contains('index') ?? false);

  @override
  String toString() =>
      'DashboardQueryFailure($queryName: ${firebaseError.message})';
}

/// Premium enterprise SaaS dashboard for the Institute Owner/Admin.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({
    required this.user,
    this.onSectionSelected,
    this.dataLoader,
    super.key,
  });

  final AppUser user;
  final ValueChanged<String>? onSectionSelected;

  /// Optional custom loader for testing or alternate providers.
  final Future<OwnerDashboardData> Function()? dataLoader;

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  late Future<OwnerDashboardData> _dashboardData;
  DateTime _lastRefreshedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dashboardData = _loadData();
  }

  Future<OwnerDashboardData> _loadData() {
    _lastRefreshedAt = DateTime.now();
    if (widget.dataLoader != null) {
      return widget.dataLoader!();
    }
    return _loadFirestoreData();
  }

  Future<OwnerDashboardData> _loadFirestoreData() async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfTomorrow = startOfDay.add(const Duration(days: 1));

    Future<T> runQuery<T>(String queryName, Future<T> query) async {
      try {
        return await query;
      } on FirebaseException catch (error) {
        throw DashboardQueryFailure(queryName, error);
      }
    }

    final activeStudentsQuery = runQuery(
      'active student count',
      firestore
          .collection('students')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('status', isEqualTo: 'active')
          .count()
          .get(),
    );

    final activeBatchesQuery = runQuery(
      'active batch count',
      firestore
          .collection('batches')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('status', isEqualTo: 'active')
          .count()
          .get(),
    );

    final pendingApprovalsCountQuery = runQuery(
      'pending approval count',
      firestore
          .collection('pendingActions')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('status', isEqualTo: 'pending')
          .count()
          .get(),
    );

    final todaysClassesQuery = runQuery(
      "today's classes",
      firestore
          .collection('classSessions')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where(
            'startAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('startAt', isLessThan: Timestamp.fromDate(startOfTomorrow))
          .get(),
    );

    final recentApprovalsQuery = runQuery(
      'recent pending approvals',
      firestore
          .collection('pendingActions')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('status', isEqualTo: 'pending')
          .limit(10)
          .get(),
    );

    final results = await Future.wait([
      activeStudentsQuery,
      activeBatchesQuery,
      pendingApprovalsCountQuery,
      todaysClassesQuery,
      recentApprovalsQuery,
    ]);

    final studentsCount = (results[0] as AggregateQuerySnapshot).count ?? 0;
    final batchesCount = (results[1] as AggregateQuerySnapshot).count ?? 0;
    final pendingApprovalsCount =
        (results[2] as AggregateQuerySnapshot).count ?? 0;

    final classSnapshot = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final sessions = classSnapshot.docs
        .map((doc) => ClassSession.fromFirestore(doc))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final activeClassesCount =
        sessions.where((session) => !session.isCancelled).length;

    final approvalsSnapshot =
        results[4] as QuerySnapshot<Map<String, dynamic>>;
    final recentApprovals = approvalsSnapshot.docs
        .map((doc) => ApprovalAction.fromFirestore(doc))
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

    return OwnerDashboardData(
      activeStudentsCount: studentsCount,
      activeBatchesCount: batchesCount,
      todaysClassesCount: activeClassesCount,
      pendingApprovalsCount: pendingApprovalsCount,
      todaysSessions: sessions,
      recentPendingApprovals: recentApprovals,
    );
  }

  void _refresh() {
    setState(() {
      _dashboardData = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OwnerDashboardData>(
      future: _dashboardData,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final data = snapshot.data;
        final hasError = snapshot.hasError;

        return Scaffold(
          backgroundColor: AppTheme.canvas,
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, isLoading: isLoading),
                    const SizedBox(height: 24),
                    if (hasError)
                      _buildErrorState(snapshot.error!)
                    else if (isLoading && data == null)
                      _buildLoadingSkeleton()
                    else if (data != null) ...[
                      _buildKpiGrid(data),
                      const SizedBox(height: 28),
                      _buildOperationalOverview(data),
                      const SizedBox(height: 28),
                      _buildQuickActions(),
                      const SizedBox(height: 20),
                      _buildFooterStatus(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isLoading}) {
    final rawName = widget.user.name.trim();
    final firstName = rawName.isNotEmpty ? rawName.split(' ').first : 'Admin';
    final nowFormatted = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 960;
          final titleColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Good to see you, $firstName.',
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: const Text(
                      'OWNER',
                      style: TextStyle(
                        color: AppTheme.brand,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Here is your institute overview for today.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          );

          final actionsRow = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              // Date badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      nowFormatted,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Live status indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isLoading
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLoading
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isLoading
                            ? const Color(0xFFD97706)
                            : const Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLoading ? 'Syncing...' : 'Live connected',
                      style: TextStyle(
                        color: isLoading
                            ? const Color(0xFFB45309)
                            : const Color(0xFF15803D),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Refresh button
              IconButton.filledTonal(
                tooltip: 'Refresh dashboard',
                onPressed: isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: AppTheme.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleColumn,
                const SizedBox(height: 16),
                actionsRow,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleColumn),
              const SizedBox(width: 16),
              actionsRow,
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiGrid(OwnerDashboardData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 600
                ? 2
                : 1;
        const gap = 16.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final items = [
          _KpiItemData(
            label: 'Active Students',
            value: '${data.activeStudentsCount}',
            detail: 'Enrolled learners',
            icon: Icons.people_alt_rounded,
            accentColor: const Color(0xFF2563EB),
            backgroundColor: const Color(0xFFEFF6FF),
            destinationId: 'students',
          ),
          _KpiItemData(
            label: 'Active Batches',
            value: '${data.activeBatchesCount}',
            detail: 'Running cohorts',
            icon: Icons.groups_rounded,
            accentColor: const Color(0xFF0D9488),
            backgroundColor: const Color(0xFFF0FDFA),
            destinationId: 'courses-batches',
          ),
          _KpiItemData(
            label: "Today's Classes",
            value: '${data.todaysClassesCount}',
            detail:
                '${data.todaysSessions.where((s) => s.isScheduled).length} scheduled',
            icon: Icons.calendar_month_rounded,
            accentColor: const Color(0xFF7C3AED),
            backgroundColor: const Color(0xFFF5F3FF),
            destinationId: 'timetable',
          ),
          _KpiItemData(
            label: 'Pending Approvals',
            value: '${data.pendingApprovalsCount}',
            detail: data.pendingApprovalsCount > 0
                ? 'Requires review'
                : 'All clear',
            icon: Icons.task_alt_rounded,
            accentColor: const Color(0xFFD97706),
            backgroundColor: const Color(0xFFFFFBEB),
            destinationId: 'approvals',
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: cardWidth,
                  child: _ModernKpiCard(
                    data: item,
                    onTap: widget.onSectionSelected == null
                        ? null
                        : () => widget.onSectionSelected!(item.destinationId),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildOperationalOverview(OwnerDashboardData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        const gap = 20.0;

        final schedulePanel = _buildSchedulePanel(data.todaysSessions);
        final approvalsPanel =
            _buildApprovalsPanel(data.recentPendingApprovals);

        if (isDesktop) {
          final halfWidth = (constraints.maxWidth - gap) / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: halfWidth, child: schedulePanel),
              const SizedBox(width: gap),
              SizedBox(width: halfWidth, child: approvalsPanel),
            ],
          );
        }

        return Column(
          children: [
            schedulePanel,
            const SizedBox(height: gap),
            approvalsPanel,
          ],
        );
      },
    );
  }

  Widget _buildSchedulePanel(List<ClassSession> sessions) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calendar_today_rounded,
                    color: Color(0xFF7C3AED),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's Schedule",
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${sessions.length} ${sessions.length == 1 ? 'class session' : 'class sessions'} today',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      widget.onSectionSelected?.call('timetable'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Timetable'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.brand,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Content
          if (sessions.isEmpty)
            _buildEmptyScheduleState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final session = sessions[index];
                return _ScheduleSessionTile(
                  session: session,
                  onTap: () => widget.onSectionSelected?.call('timetable'),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyScheduleState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: Color(0xFF94A3B8),
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No classes scheduled for today',
              style: TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'All cohorts are clear or timetables are yet to be scheduled.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => widget.onSectionSelected?.call('timetable'),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Open Timetable Management'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brand,
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalsPanel(List<ApprovalAction> approvals) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: Color(0xFFD97706),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Approvals',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${approvals.length} ${approvals.length == 1 ? 'request' : 'requests'} awaiting review',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      widget.onSectionSelected?.call('approvals'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View all'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.brand,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          // Content
          if (approvals.isEmpty)
            _buildEmptyApprovalsState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: approvals.take(5).length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final action = approvals[index];
                return _PendingApprovalTile(
                  action: action,
                  onTap: () => widget.onSectionSelected?.call('approvals'),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyApprovalsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF16A34A),
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'All approvals are up to date',
              style: TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'There are no pending requests awaiting your authorization.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => widget.onSectionSelected?.call('approvals'),
              icon: const Icon(Icons.rule_folder_rounded, size: 16),
              label: const Text('Go to Approvals Center'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brand,
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickActionItem(
        label: 'Add Student',
        subtitle: 'Enroll learner',
        icon: Icons.person_add_rounded,
        color: const Color(0xFF2563EB),
        destinationId: 'students',
      ),
      _QuickActionItem(
        label: 'Open Attendance',
        subtitle: 'Record attendance',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF0D9488),
        destinationId: 'attendance',
      ),
      _QuickActionItem(
        label: 'View Timetable',
        subtitle: 'Manage classes',
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFF7C3AED),
        destinationId: 'timetable',
      ),
      _QuickActionItem(
        label: 'Review Approvals',
        subtitle: 'Pending requests',
        icon: Icons.rule_folder_rounded,
        color: const Color(0xFFD97706),
        destinationId: 'approvals',
      ),
      _QuickActionItem(
        label: 'Open Reports',
        subtitle: 'Insights & exports',
        icon: Icons.analytics_rounded,
        color: const Color(0xFF0284C7),
        destinationId: 'reports',
      ),
      _QuickActionItem(
        label: 'Ask AI Copilot',
        subtitle: 'Smart assistance',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF4F46E5),
        destinationId: 'copilot',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppTheme.brand,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Common administrative tasks and operational shortcuts',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 6
                  : constraints.maxWidth >= 640
                      ? 3
                      : 2;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: actions
                    .map(
                      (action) => SizedBox(
                        width: width,
                        child: _QuickActionButton(
                          item: action,
                          onPressed: widget.onSectionSelected == null
                              ? null
                              : () => widget.onSectionSelected!(
                                  action.destinationId,
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooterStatus() {
    final formattedTime = DateFormat('h:mm:ss a').format(_lastRefreshedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_done_rounded,
                size: 14,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(width: 6),
              Text(
                'Live Institute Firestore Database • Synced at $formattedTime',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Text(
            'InstituteOS Enterprise AI Suite',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    String message = 'Dashboard data is temporarily unavailable: $error';
    String? hint;

    if (error is DashboardQueryFailure) {
      if (error.requiresIndex) {
        message = 'Firestore composite index required for ${error.queryName}.';
        hint =
            'Deploy the composite index via Firebase CLI and retry once built. Details: ${error.firebaseError.message}';
      } else {
        message = '${error.queryName} query failed: ${error.firebaseError.message ?? error.firebaseError.code}';
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFDC2626),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unable to load live dashboard data',
                  style: TextStyle(
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint,
                    style: const TextStyle(
                      color: Color(0xFF7F1D1D),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry connection'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1080
                ? 4
                : constraints.maxWidth >= 600
                    ? 2
                    : 1;
            const gap = 16.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: List.generate(
                4,
                (_) => Container(
                  width: width,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }
}

class _KpiItemData {
  const _KpiItemData({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.destinationId,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final String destinationId;
}

class _ModernKpiCard extends StatefulWidget {
  const _ModernKpiCard({required this.data, this.onTap});

  final _KpiItemData data;
  final VoidCallback? onTap;

  @override
  State<_ModernKpiCard> createState() => _ModernKpiCardState();
}

class _ModernKpiCardState extends State<_ModernKpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isHovered
                  ? widget.data.accentColor.withValues(alpha: 0.55)
                  : const Color(0xFFE2E8F0),
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.data.accentColor.withValues(alpha: 0.12)
                    : const Color(0x060F172A),
                blurRadius: _isHovered ? 14 : 8,
                offset: Offset(0, _isHovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.data.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.data.icon,
                      color: widget.data.accentColor,
                      size: 22,
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered ? 1.0 : 0.4,
                    child: Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: widget.data.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.value,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.label,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Text(
                      widget.data.detail,
                      style: TextStyle(
                        color: widget.data.accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleSessionTile extends StatelessWidget {
  const _ScheduleSessionTile({required this.session, required this.onTap});

  final ClassSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startFormatted = DateFormat('h:mm a').format(session.startAt);
    final endFormatted = DateFormat('h:mm a').format(session.endAt);

    Color statusBg = const Color(0xFFEFF6FF);
    Color statusFg = const Color(0xFF1D4ED8);
    if (session.isCompleted) {
      statusBg = const Color(0xFFF1F5F9);
      statusFg = const Color(0xFF475569);
    } else if (session.isCancelled) {
      statusBg = const Color(0xFFFEF2F2);
      statusFg = const Color(0xFFDC2626);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            // Time box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Text(
                    startFormatted,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const Text(
                    'to',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    endFormatted,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Session details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session.courseName} • ${session.batchName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          session.trainerName.isNotEmpty
                              ? session.trainerName
                              : 'Trainer Assigned',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Mode & Status badges
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    session.statusLabel,
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.deliveryModeLabel,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingApprovalTile extends StatelessWidget {
  const _PendingApprovalTile({required this.action, required this.onTap});

  final ApprovalAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormatted = DateFormat('d MMM, h:mm a').format(action.requestedAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.assignment_late_outlined,
                color: Color(0xFFD97706),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          action.typeLabel,
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Requested by ${action.requestedBy} • $dateFormatted',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionItem {
  const _QuickActionItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.destinationId,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String destinationId;
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({required this.item, this.onPressed});

  final _QuickActionItem item;
  final VoidCallback? onPressed;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered ? const Color(0xFFF8FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? widget.item.color : const Color(0xFFE2E8F0),
              width: _isHovered ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.item.color.withValues(alpha: 0.1)
                    : const Color(0x040F172A),
                blurRadius: _isHovered ? 8 : 4,
                offset: Offset(0, _isHovered ? 4 : 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.item.icon,
                  color: widget.item.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      widget.item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
