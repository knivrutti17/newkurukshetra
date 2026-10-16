import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/course.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/course_service.dart';
import '../../../data/services/reports_service.dart';

// Indian currency and number formatter helper
String _formatCurrency(num value) {
  final integerPart = value.round().abs().toString();
  if (integerPart.length <= 3) {
    return '₹${value.isNegative ? '-' : ''}$integerPart';
  }

  final lastThree = integerPart.substring(integerPart.length - 3);
  final remaining = integerPart.substring(0, integerPart.length - 3);

  final buffer = StringBuffer();
  for (var i = 0; i < remaining.length; i++) {
    if (i > 0 && (remaining.length - i) % 2 == 0) {
      buffer.write(',');
    }
    buffer.write(remaining[i]);
  }
  buffer.write(',');
  buffer.write(lastThree);

  return '₹${value.isNegative ? '-' : ''}${buffer.toString()}';
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.reportsService,
    this.batchService,
    this.courseService,
    this.initialTab = 0,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final ReportsService? reportsService;
  final BatchService? batchService;
  final CourseService? courseService;
  final int initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final ReportsService _reportsService;
  late final BatchService _batchService;
  late final CourseService _courseService;

  late TabController _tabController;
  late List<_ReportTabItem> _visibleTabs;

  // Filter state
  String _selectedBatchId = 'all';
  String _selectedCourseId = 'all';
  double _attendanceThreshold = 75.0;

  // Data state
  bool _isLoading = true;
  String? _errorMessage;

  OperationalSummaryData? _operationalSummary;
  StudentReportData? _studentReport;
  AttendanceReportData? _attendanceReport;
  FeeReportData? _feeReport;
  TrainerTimetableReportData? _trainerTimetableReport;
  List<Batch> _batches = [];
  List<Course> _courses = [];

  @override
  void initState() {
    super.initState();
    _reportsService = widget.reportsService ?? ReportsService();
    _batchService = widget.batchService ?? BatchService();
    _courseService = widget.courseService ?? CourseService();

    _configureTabs();
    _loadAllReports();
  }

  void _configureTabs() {
    final role = widget.user.role;
    _visibleTabs = switch (role) {
      AppRole.owner => const [
          _ReportTabItem(id: 'overview', label: 'Operational Overview', icon: Icons.dashboard_customize_rounded),
          _ReportTabItem(id: 'students', label: 'Student Enrollments', icon: Icons.people_alt_outlined),
          _ReportTabItem(id: 'attendance', label: 'Attendance Analytics', icon: Icons.fact_check_outlined),
          _ReportTabItem(id: 'fees', label: 'Fee & Financials', icon: Icons.account_balance_wallet_outlined),
          _ReportTabItem(id: 'faculty', label: 'Faculty & Timetable', icon: Icons.calendar_month_outlined),
        ],
      AppRole.counselor => const [
          _ReportTabItem(id: 'overview', label: 'Counseling Overview', icon: Icons.dashboard_customize_rounded),
          _ReportTabItem(id: 'students', label: 'Student Enrollments', icon: Icons.people_alt_outlined),
          _ReportTabItem(id: 'attendance', label: 'Attendance Analytics', icon: Icons.fact_check_outlined),
        ],
      AppRole.trainer => const [
          _ReportTabItem(id: 'attendance', label: 'Cohort Attendance', icon: Icons.fact_check_outlined),
          _ReportTabItem(id: 'faculty', label: 'Class Timetable', icon: Icons.calendar_month_outlined),
        ],
      AppRole.accounts => const [
          _ReportTabItem(id: 'overview', label: 'Financial Overview', icon: Icons.dashboard_customize_rounded),
          _ReportTabItem(id: 'fees', label: 'Fee & Revenue Reports', icon: Icons.receipt_long_outlined),
        ],
    };

    final safeInitial = widget.initialTab.clamp(0, _visibleTabs.length - 1);
    _tabController = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: safeInitial,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final role = widget.user.role;
      final batchesFuture = _batchService.getForUser(widget.user);
      final coursesFuture = _courseService.getForUser(widget.user);

      final results = await Future.wait([
        batchesFuture,
        coursesFuture,
        if (role == AppRole.owner || role == AppRole.counselor || role == AppRole.accounts)
          _reportsService.getOperationalSummary(),
        if (role == AppRole.owner || role == AppRole.counselor)
          _reportsService.getStudentReport(
            courseFilter: _selectedCourseId,
            batchFilter: _selectedBatchId,
          ),
        if (role == AppRole.owner || role == AppRole.counselor || role == AppRole.trainer)
          _reportsService.getAttendanceReport(
            batchId: _selectedBatchId,
            threshold: _attendanceThreshold,
          ),
        if (role == AppRole.owner || role == AppRole.accounts)
          _reportsService.getFeeReport(),
        if (role == AppRole.owner || role == AppRole.trainer)
          _reportsService.getTrainerTimetableReport(),
      ]);

      if (!mounted) return;

      var index = 0;
      _batches = results[index++] as List<Batch>;
      _courses = results[index++] as List<Course>;

      if (role == AppRole.owner || role == AppRole.counselor || role == AppRole.accounts) {
        _operationalSummary = results[index++] as OperationalSummaryData?;
      }
      if (role == AppRole.owner || role == AppRole.counselor) {
        _studentReport = results[index++] as StudentReportData?;
      }
      if (role == AppRole.owner || role == AppRole.counselor || role == AppRole.trainer) {
        _attendanceReport = results[index++] as AttendanceReportData?;
      }
      if (role == AppRole.owner || role == AppRole.accounts) {
        _feeReport = results[index++] as FeeReportData?;
      }
      if (role == AppRole.owner || role == AppRole.trainer) {
        _trainerTimetableReport = results[index++] as TrainerTimetableReportData?;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                user: widget.user,
                onRefresh: _loadAllReports,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),
              _RoleBanner(role: widget.user.role, userName: widget.user.name),
              if (widget.firebaseSetupMessage != null) ...[
                const SizedBox(height: 12),
                _NoticeBox(
                  message: widget.firebaseSetupMessage!,
                  icon: Icons.warning_amber_rounded,
                  background: const Color(0xFFFFF3E5),
                  textColor: const Color(0xFF7A4B00),
                ),
              ],
              const SizedBox(height: 20),

              // Tab Bar Container
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppTheme.brand,
                  unselectedLabelColor: const Color(0xFF64748B),
                  indicatorColor: AppTheme.brand,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  tabs: _visibleTabs.map((t) {
                    return Tab(
                      icon: Icon(t.icon, size: 18),
                      text: t.label,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Content Body
              if (_isLoading)
                const _LoadingCard(label: 'Aggregating live institutional analytics from Firestore…')
              else if (_errorMessage != null)
                _ErrorCard(
                  title: 'Unable to calculate reports',
                  message: _errorMessage!,
                  onRetry: _loadAllReports,
                )
              else
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    final currentTab = _visibleTabs[_tabController.index];
                    return switch (currentTab.id) {
                      'overview' => _OverviewReportView(
                          summary: _operationalSummary!,
                          role: widget.user.role,
                        ),
                      'students' => _StudentReportView(
                          data: _studentReport!,
                          courses: _courses,
                          batches: _batches,
                          selectedCourse: _selectedCourseId,
                          selectedBatch: _selectedBatchId,
                          onCourseChanged: (v) {
                            setState(() => _selectedCourseId = v);
                            _loadAllReports();
                          },
                          onBatchChanged: (v) {
                            setState(() => _selectedBatchId = v);
                            _loadAllReports();
                          },
                        ),
                      'attendance' => _AttendanceReportView(
                          data: _attendanceReport!,
                          batches: _batches,
                          selectedBatch: _selectedBatchId,
                          threshold: _attendanceThreshold,
                          onBatchChanged: (v) {
                            setState(() => _selectedBatchId = v);
                            _loadAllReports();
                          },
                          onThresholdChanged: (v) {
                            setState(() => _attendanceThreshold = v);
                            _loadAllReports();
                          },
                        ),
                      'fees' => _FeeReportView(data: _feeReport!),
                      'faculty' => _FacultyTimetableReportView(
                          data: _trainerTimetableReport!,
                        ),
                      _ => const SizedBox.shrink(),
                    };
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportTabItem {
  const _ReportTabItem({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

// ---------------------------------------------------------------------------
// Header & Role Banner
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.onRefresh,
    required this.isLoading,
  });

  final AppUser user;
  final VoidCallback onRefresh;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports & Analytics',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Real-time institutional intelligence computed directly from Cloud Firestore collections.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(isLoading ? 'Refreshing…' : 'Refresh Data'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: const BorderSide(color: Color(0xFFD8DFEB)),
            foregroundColor: AppTheme.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.role, required this.userName});

  final AppRole role;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final (label, description, color, bg) = switch (role) {
      AppRole.owner => (
          'Comprehensive Institute Reports',
          'Signed in as $userName (Owner). Full institutional access across enrollments, attendance, revenue collections, and timetable analytics.',
          const Color(0xFF1D4ED8),
          const Color(0xFFEFF6FF),
        ),
      AppRole.counselor => (
          'Academic & Enrollment Analytics',
          'Signed in as $userName (Counselor). Viewing student enrollment and attendance performance trends. Financial summaries are hidden.',
          const Color(0xFF0D9488),
          const Color(0xFFF0FDFA),
        ),
      AppRole.trainer => (
          'Faculty Cohort Reports',
          'Signed in as $userName (Trainer). Scoped visibility into assigned batch attendance rates and class execution metrics.',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF),
        ),
      AppRole.accounts => (
          'Financial & Revenue Intelligence',
          'Signed in as $userName (Accounts Staff). Focused visibility on fee collection, pending dues, and overdue instalment tracking.',
          const Color(0xFFB45309),
          const Color(0xFFFFFBEB),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: AppTheme.ink),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.message,
    required this.icon,
    required this.background,
    required this.textColor,
  });

  final String message;
  final IconData icon;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW 1: Operational Summary
// ---------------------------------------------------------------------------

class _OverviewReportView extends StatelessWidget {
  const _OverviewReportView({
    required this.summary,
    required this.role,
  });

  final OperationalSummaryData summary;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final showFinancials =
        role == AppRole.owner || role == AppRole.accounts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _StatCard(
              title: 'Total Students',
              value: '${summary.totalStudents}',
              subtitle: 'Active student registry',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
            ),
            _StatCard(
              title: 'Active Cohorts',
              value: '${summary.activeBatches}',
              subtitle: 'Batches currently in progress',
              icon: Icons.groups_rounded,
              color: const Color(0xFF059669),
              bg: const Color(0xFFECFDF5),
            ),
            if (showFinancials)
              _StatCard(
                title: 'Fee Collection Rate',
                value: '${summary.overallFeeCollectionRate.toStringAsFixed(1)}%',
                subtitle: 'Total revenue collected vs billed',
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF7C3AED),
                bg: const Color(0xFFF5F3FF),
              ),
            _StatCard(
              title: 'Pending Approvals',
              value: '${summary.pendingApprovals}',
              subtitle: 'Requests requiring review',
              icon: Icons.hourglass_top_rounded,
              color: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
            ),
            _StatCard(
              title: 'Open Risk Alerts',
              value: '${summary.openAlerts}',
              subtitle: 'Students flagged for intervention',
              icon: Icons.health_and_safety_rounded,
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
            ),
            _StatCard(
              title: "Today's Classes",
              value: '${summary.todayClasses}',
              subtitle: 'Sessions scheduled today',
              icon: Icons.today_rounded,
              color: const Color(0xFF0D9488),
              bg: const Color(0xFFF0FDFA),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW 2: Student Report
// ---------------------------------------------------------------------------

class _StudentReportView extends StatelessWidget {
  const _StudentReportView({
    required this.data,
    required this.courses,
    required this.batches,
    required this.selectedCourse,
    required this.selectedBatch,
    required this.onCourseChanged,
    required this.onBatchChanged,
  });

  final StudentReportData data;
  final List<Course> courses;
  final List<Batch> batches;
  final String selectedCourse;
  final String selectedBatch;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<String> onBatchChanged;

  @override
  Widget build(BuildContext context) {
    final activeRate = data.totalStudents == 0
        ? 0.0
        : (data.activeStudents / data.totalStudents) * 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedCourse,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Course',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Courses')),
                    ...courses.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) onCourseChanged(v);
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedBatch,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Batch',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Batches')),
                    ...batches.map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(b.name, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) onBatchChanged(v);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary KPI
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _StatCard(
              title: 'Total Enrolled',
              value: '${data.totalStudents}',
              subtitle: 'Students in filtered scope',
              icon: Icons.school_rounded,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
            ),
            _StatCard(
              title: 'Active Students',
              value: '${data.activeStudents} (${activeRate.toStringAsFixed(1)}%)',
              subtitle: 'Currently attending classes',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF059669),
              bg: const Color(0xFFECFDF5),
            ),
            _StatCard(
              title: 'Inactive / On Leave',
              value: '${data.inactiveStudents}',
              subtitle: 'Discontinued or on sabbatical',
              icon: Icons.pause_circle_outline_rounded,
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Distribution breakdowns
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DistributionCard(
                title: 'Students by Course',
                items: data.studentsByCourse,
                total: data.totalStudents,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _DistributionCard(
                title: 'Students by Cohort / Batch',
                items: data.studentsByBatch,
                total: data.totalStudents,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW 3: Attendance Report
// ---------------------------------------------------------------------------

class _AttendanceReportView extends StatelessWidget {
  const _AttendanceReportView({
    required this.data,
    required this.batches,
    required this.selectedBatch,
    required this.threshold,
    required this.onBatchChanged,
    required this.onThresholdChanged,
  });

  final AttendanceReportData data;
  final List<Batch> batches;
  final String selectedBatch;
  final double threshold;
  final ValueChanged<String> onBatchChanged;
  final ValueChanged<double> onThresholdChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls Row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedBatch,
                  decoration: const InputDecoration(
                    labelText: 'Select Cohort / Batch',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Batches')),
                    ...batches.map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(b.name, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) onBatchChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Defaulter Threshold: ${threshold.round()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    Slider(
                      value: threshold,
                      min: 50,
                      max: 95,
                      divisions: 9,
                      label: '${threshold.round()}%',
                      onChanged: onThresholdChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary cards
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _StatCard(
              title: 'Total Logs',
              value: '${data.totalRecords}',
              subtitle: 'Individual student session records',
              icon: Icons.fact_check_rounded,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
            ),
            _StatCard(
              title: 'Present Sessions',
              value: '${data.presentCount} (${data.overallPercentage.toStringAsFixed(1)}%)',
              subtitle: 'Classroom attendance mark',
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF059669),
              bg: const Color(0xFFECFDF5),
            ),
            _StatCard(
              title: 'Absent & Late Marks',
              value: '${data.absentCount} abs / ${data.lateCount} late',
              subtitle: 'Unexcused absences & tardiness',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
            ),
            _StatCard(
              title: 'Students Below Threshold',
              value: '${data.studentsBelowThreshold.length}',
              subtitle: 'Attendance < ${threshold.round()}%',
              icon: Icons.health_and_safety_rounded,
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Defaulters Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Students Below ${threshold.round()}% Attendance Requirement (${data.studentsBelowThreshold.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              if (data.studentsBelowThreshold.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Excellent! No students currently fall below the attendance threshold.',
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                      columns: const [
                        DataColumn(label: Text('Student Name')),
                        DataColumn(label: Text('Cohort / Batch')),
                        DataColumn(label: Text('Recorded Sessions')),
                        DataColumn(label: Text('Attendance %')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: data.studentsBelowThreshold.map((s) {
                        return DataRow(
                          cells: [
                            DataCell(Text(s.studentName, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(s.batchName)),
                            DataCell(Text('${s.totalSessions} sessions')),
                            DataCell(
                              Text(
                                '${s.percentage.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Action Needed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW 4: Fee & Financial Report
// ---------------------------------------------------------------------------

class _FeeReportView extends StatelessWidget {
  const _FeeReportView({required this.data});

  final FeeReportData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _StatCard(
              title: 'Total Tuition Billed',
              value: _formatCurrency(data.totalDue),
              subtitle: 'Cumulative scheduled fee commitments',
              icon: Icons.account_balance_rounded,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
            ),
            _StatCard(
              title: 'Total Collected',
              value: _formatCurrency(data.totalCollected),
              subtitle: '${data.collectionRate.toStringAsFixed(1)}% recovery rate',
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF059669),
              bg: const Color(0xFFECFDF5),
            ),
            _StatCard(
              title: 'Outstanding Balance',
              value: _formatCurrency(data.outstandingBalance),
              subtitle: 'Pending future & overdue instalments',
              icon: Icons.pending_actions_rounded,
              color: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
            ),
            _StatCard(
              title: 'Overdue Instalments',
              value: _formatCurrency(data.overdueAmount),
              subtitle: '${data.overdueCount} instalments past due date',
              icon: Icons.error_outline_rounded,
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Collection Progress Visualizer
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Institute Tuition Collection Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  Text(
                    '${data.collectionRate.toStringAsFixed(1)}% Collected',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: (data.collectionRate / 100).clamp(0.0, 1.0),
                  minHeight: 18,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF059669)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collected: ${_formatCurrency(data.totalCollected)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF059669),
                    ),
                  ),
                  Text(
                    'Remaining Dues: ${_formatCurrency(data.outstandingBalance)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW 5: Faculty & Timetable Report
// ---------------------------------------------------------------------------

class _FacultyTimetableReportView extends StatelessWidget {
  const _FacultyTimetableReportView({required this.data});

  final TrainerTimetableReportData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _StatCard(
              title: 'Active Instructors',
              value: '${data.activeTrainers} / ${data.totalTrainers}',
              subtitle: 'Active trainers on faculty roster',
              icon: Icons.co_present_rounded,
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
            ),
            _StatCard(
              title: 'Total Classes Scheduled',
              value: '${data.totalClasses}',
              subtitle: '${data.completedClasses} completed / ${data.scheduledClasses} upcoming',
              icon: Icons.event_available_rounded,
              color: const Color(0xFF059669),
              bg: const Color(0xFFECFDF5),
            ),
            _StatCard(
              title: 'Cancelled Classes',
              value: '${data.cancelledClasses}',
              subtitle: 'Historical cancelled sessions',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFDC2626),
              bg: const Color(0xFFFEF2F2),
            ),
            _StatCard(
              title: 'Delivery Modes',
              value: '${data.inPersonClasses} / ${data.onlineClasses} / ${data.hybridClasses}',
              subtitle: 'In-Person / Online / Hybrid',
              icon: Icons.devices_rounded,
              color: const Color(0xFF7C3AED),
              bg: const Color(0xFFF5F3FF),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Trainer Cohort Allocations Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Faculty Cohort Allocations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columns: const [
                      DataColumn(label: Text('Instructor Name')),
                      DataColumn(label: Text('Assigned Active Batches')),
                      DataColumn(label: Text('Teaching Load Status')),
                    ],
                    rows: data.trainerBatchAssignments.entries.map((e) {
                      final count = e.value;
                      final loadText = count == 0
                          ? 'Available for Assignment'
                          : (count <= 2 ? 'Optimal Load' : 'High Load');
                      final (badgeBg, badgeFg) = count == 0
                          ? (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8))
                          : (count <= 2
                              ? (const Color(0xFFECFDF5), const Color(0xFF065F46))
                              : (const Color(0xFFFFFBEB), const Color(0xFFB45309)));

                      return DataRow(
                        cells: [
                          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text('$count cohorts')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                loadText,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: badgeFg,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SHARED STAT CARDS & VISUALIZERS
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bg,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.title,
    required this.items,
    required this.total,
  });

  final String title;
  final Map<String, int> items;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Text(
              'No distribution data available.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            )
          else
            ...items.entries.map((e) {
              final pct = total == 0 ? 0.0 : (e.value / total);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        Text(
                          '${e.value} (${(pct * 100).toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation(AppTheme.brand),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Color(0xFFDC2626),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
