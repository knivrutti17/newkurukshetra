import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/routing/role_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../auth/controllers/session_controller.dart';
import '../../approvals/screens/approvals_screen.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../copilot/screens/copilot_screen.dart';
import '../../courses_batches/screens/courses_batches_screen.dart';
import '../../fees/screens/fee_management_screen.dart';
import '../../reminders/screens/reminder_drafts_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../risk_alerts/screens/student_risk_alerts_screen.dart';
import '../../students/screens/students_screen.dart';
import '../../timetable/screens/timetable_screen.dart';
import '../../trainers/screens/trainers_screen.dart';
import 'accounts_dashboard_screen.dart';
import 'owner_dashboard_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    required this.user,
    required this.sessionController,
    this.firebaseSetupMessage,
    super.key,
  });

  final AppUser user;
  final SessionController sessionController;
  final String? firebaseSetupMessage;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = navigationForRole(widget.user.role).first.id;
  }

  void _selectSection(String id, {bool closeDrawer = false}) {
    setState(() => _selectedId = id);
    if (closeDrawer) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _logout() => widget.sessionController.signOut();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final sections = navigationForRole(widget.user.role);

    return Scaffold(
      appBar: compact
          ? AppBar(
              titleSpacing: 8,
              title: const _AppBarBrand(),
              actions: _selectedId == 'dashboard'
                  ? const []
                  : const [
                      Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: _DemoModeChip(),
                      ),
                    ],
            )
          : null,
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: _NavigationPanel(
                  user: widget.user,
                  sections: sections,
                  selectedId: _selectedId,
                  isDrawer: true,
                  onSelected: (id) => _selectSection(id, closeDrawer: true),
                  onLogout: _logout,
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            SizedBox(
              width: 280,
              child: _NavigationPanel(
                user: widget.user,
                sections: sections,
                selectedId: _selectedId,
                onSelected: _selectSection,
                onLogout: _logout,
              ),
            ),
          Expanded(child: _buildContent(sections)),
        ],
      ),
    );
  }

  Widget _buildContent(List<NavigationSection> sections) {
    if (_selectedId == 'copilot') {
      return CopilotScreen(user: widget.user);
    }
    if (_selectedId == 'dashboard') {
      return DashboardOverview(
        user: widget.user,
        onSectionSelected: _selectSection,
      );
    }
    if (_selectedId == 'students') {
      return StudentsScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'attendance') {
      return AttendanceScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'risk-alerts') {
      return StudentRiskAlertsScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'courses-batches' || _selectedId == 'my-batches') {
      return CoursesBatchesScreen(
        user: widget.user,
        initialTab: _selectedId == 'my-batches' ? 1 : 0,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'trainers') {
      return TrainersScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'fees' ||
        _selectedId == 'fee-management' ||
        _selectedId == 'payments') {
      return FeeManagementScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'timetable' || _selectedId == 'my-timetable') {
      return TimetableScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'approvals') {
      return ApprovalsScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'reports' || _selectedId == 'fee-reports') {
      return ReportsScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    if (_selectedId == 'reminder-drafts') {
      return ReminderDraftsScreen(
        user: widget.user,
        firebaseSetupMessage: widget.firebaseSetupMessage,
      );
    }
    final section = sections.firstWhere((item) => item.id == _selectedId);
    return PlaceholderSection(section: section, user: widget.user);
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.user,
    required this.sections,
    required this.selectedId,
    required this.onSelected,
    required this.onLogout,
    this.isDrawer = false,
  });

  final AppUser user;
  final List<NavigationSection> sections;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Future<void> Function() onLogout;
  final bool isDrawer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppTheme.ink),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 18, 20),
            child: Row(
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'InstituteOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'AI operations workspace',
                        style: TextStyle(
                          color: Color(0xFFAEBAD2),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDrawer)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Close navigation',
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF30405F)),
          _UserPanel(user: user),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 10, 22, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'WORKSPACE',
                style: TextStyle(
                  color: Color(0xFF8796B5),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                final selected = section.id == selectedId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      selected: selected,
                      selectedTileColor: const Color(0xFF2D5FCB),
                      leading: Icon(
                        section.icon,
                        color: selected
                            ? Colors.white
                            : const Color(0xFFB4C0D8),
                        size: 20,
                      ),
                      title: Text(
                        section.label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFD8E0F0),
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () => onSelected(section.id),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFF30405F)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDCE6F9),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFBBD0FF),
            child: Text(
              user.name.substring(0, 1),
              style: const TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.role.label,
                  style: const TextStyle(
                    color: Color(0xFFAEBAD2),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardOverview extends StatelessWidget {
  const DashboardOverview({
    required this.user,
    this.onSectionSelected,
    super.key,
  });

  final AppUser user;
  final ValueChanged<String>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    if (user.role == AppRole.owner) {
      return OwnerDashboardScreen(
        user: user,
        onSectionSelected: onSectionSelected,
      );
    }
    if (user.role == AppRole.accounts) {
      return AccountsDashboardScreen(
        user: user,
        onSectionSelected: onSectionSelected,
      );
    }
    return _StaffDashboardScreen(
      user: user,
      onSectionSelected: onSectionSelected,
    );
  }
}

class _StaffDashboardScreen extends StatefulWidget {
  const _StaffDashboardScreen({required this.user, this.onSectionSelected});

  final AppUser user;
  final ValueChanged<String>? onSectionSelected;

  @override
  State<_StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<_StaffDashboardScreen> {
  late Future<List<_DashboardMetric>> _metrics;

  @override
  void initState() {
    super.initState();
    _metrics = _loadMetrics();
  }

  Future<List<_DashboardMetric>> _loadMetrics() async {
    final firestore = FirebaseFirestore.instance;
    if (widget.user.role == AppRole.counselor) {
      final result = await _dashboardQuery(
        'assigned active student count',
        firestore
            .collection('students')
            .where('instituteId', isEqualTo: widget.user.instituteId)
            .where('counselorId', isEqualTo: widget.user.id)
            .where('status', isEqualTo: 'active')
            .count()
            .get(),
      );
      return [
        _DashboardMetric(
          label: 'Assigned active students',
          value: '${result.count ?? 0}',
          icon: Icons.people_alt_outlined,
          color: const Color(0xFF2563EB),
          destinationId: 'students',
        ),
      ];
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfTomorrow = startOfDay.add(const Duration(days: 1));
    final assignedBatches = _dashboardQuery(
      'assigned active batch count',
      firestore
          .collection('batches')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('trainerId', isEqualTo: widget.user.id)
          .where('status', isEqualTo: 'active')
          .count()
          .get(),
    );
    final todaysClasses = _dashboardQuery(
      "today's scheduled classes",
      firestore
          .collection('classSessions')
          .where('instituteId', isEqualTo: widget.user.instituteId)
          .where('trainerId', isEqualTo: widget.user.id)
          .where(
            'startAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('startAt', isLessThan: Timestamp.fromDate(startOfTomorrow))
          .get(),
    );
    final results = await Future.wait([assignedBatches, todaysClasses]);
    final classes = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final scheduledCount = classes.docs
        .where((document) => document.data()['status'] == 'scheduled')
        .length;

    return [
      _DashboardMetric(
        label: 'Assigned active batches',
        value: '${(results[0] as AggregateQuerySnapshot).count ?? 0}',
        icon: Icons.groups_outlined,
        color: const Color(0xFF2563EB),
        destinationId: 'my-batches',
      ),
      _DashboardMetric(
        label: "Today's scheduled classes",
        value: '$scheduledCount',
        icon: Icons.calendar_month_outlined,
        color: const Color(0xFF0891B2),
        destinationId: 'my-timetable',
      ),
    ];
  }

  void _refresh() => setState(() => _metrics = _loadMetrics());

  @override
  Widget build(BuildContext context) {
    final firstName = widget.user.name.split(' ').first;
    final unavailableText = widget.user.role == AppRole.counselor
        ? 'Follow-up tasks and student request tracking are unavailable until a persisted workflow is configured.'
        : 'Attendance completion counts and correction requests are unavailable until attendance sessions are linked to scheduled classes.';

    return FutureBuilder<List<_DashboardMetric>>(
      future: _metrics,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final metrics = snapshot.data ?? const <_DashboardMetric>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good to see you, $firstName.',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: AppTheme.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.user.role == AppRole.counselor
                                ? 'Your assigned student records.'
                                : 'Your assigned training schedule.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh dashboard',
                      onPressed: isLoading ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (snapshot.hasError)
                  _DashboardLoadError(error: snapshot.error!, onRetry: _refresh)
                else if (isLoading)
                  const LinearProgressIndicator()
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: metrics
                        .map(
                          (metric) => SizedBox(
                            width: 260,
                            child: _MetricCard(
                              metric: metric,
                              onTap: widget.onSectionSelected == null
                                  ? null
                                  : () => widget.onSectionSelected!(
                                      metric.destinationId!,
                                    ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 20),
                Text(
                  unavailableText,
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlaceholderSection extends StatelessWidget {
  const PlaceholderSection({
    required this.section,
    required this.user,
    super.key,
  });

  final NavigationSection section;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final message =
        'This ${section.label.toLowerCase()} workspace is prepared for '
        '${user.role.label.toLowerCase()}. It is a frontend placeholder; no '
        'live institute data or actions are available in demo mode.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(section.icon, color: AppTheme.brand, size: 30),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    section.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                  const SizedBox(height: 20),
                  const _DemoModeChip(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, this.onTap});

  final _DashboardMetric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(metric.icon, color: metric.color, size: 21),
              ),
              const SizedBox(height: 20),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.label,
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.destinationId,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? destinationId;
}

class _DashboardLoadError extends StatelessWidget {
  const _DashboardLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  String get _message {
    if (error is _DashboardQueryFailure) {
      final failure = error as _DashboardQueryFailure;
      if (failure.requiresIndex) {
        return 'Firestore needs a composite index for ${failure.queryName}. '
            'Deploy the configured index and wait for it to finish building, '
            'then retry. ${failure.firebaseError.message ?? ''}';
      }
      return '${failure.queryName} failed: '
          '${failure.firebaseError.message ?? failure.firebaseError.code}';
    }
    return 'Dashboard data is unavailable: $error';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xFFB42318)),
          const SizedBox(width: 12),
          Expanded(child: Text(_message)),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _DashboardQueryFailure implements Exception {
  const _DashboardQueryFailure(this.queryName, this.firebaseError);

  final String queryName;
  final FirebaseException firebaseError;

  bool get requiresIndex =>
      firebaseError.code == 'failed-precondition' &&
      (firebaseError.message?.toLowerCase().contains('index') ?? false);
}

Future<T> _dashboardQuery<T>(String queryName, Future<T> query) async {
  try {
    return await query;
  } on FirebaseException catch (error) {
    throw _DashboardQueryFailure(queryName, error);
  }
}

class _DemoModeChip extends StatelessWidget {
  const _DemoModeChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'DEMO MODE',
        style: TextStyle(
          color: AppTheme.brand,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _AppBarBrand extends StatelessWidget {
  const _AppBarBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_rounded, color: AppTheme.brand, size: 21),
        SizedBox(width: 7),
        Text('InstituteOS', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
