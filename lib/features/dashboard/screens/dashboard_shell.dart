import 'package:flutter/material.dart';

import '../../../core/routing/role_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../auth/controllers/session_controller.dart';
import '../../copilot/screens/copilot_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    required this.user,
    required this.sessionController,
    super.key,
  });

  final AppUser user;
  final SessionController sessionController;

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
              actions: const [
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
      return const CopilotScreen();
    }
    if (_selectedId == 'dashboard') {
      return DashboardOverview(user: widget.user);
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
  const DashboardOverview({required this.user, super.key});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final data = _DashboardData.forRole(user.role);
    final firstName = user.name.split(' ').first;

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
                        data.subtitle,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
                const _DemoModeChip(),
              ],
            ),
            const SizedBox(height: 24),
            const _DemoDataNotice(),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 4
                    : constraints.maxWidth >= 600
                    ? 2
                    : 1;
                const gap = 16.0;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: data.metrics
                      .map(
                        (metric) => SizedBox(
                          width: cardWidth,
                          child: _MetricCard(metric: metric),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your workspace is ready for the next step',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppTheme.ink,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use the navigation to explore placeholder modules '
                            'or try the AI Copilot demo. Live data and actions '
                            'are intentionally not enabled yet.',
                            style: TextStyle(color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
  const _MetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
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
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: AppTheme.ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              metric.label,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
          ],
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
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _DashboardData {
  const _DashboardData({required this.subtitle, required this.metrics});

  final String subtitle;
  final List<_DashboardMetric> metrics;

  factory _DashboardData.forRole(AppRole role) => switch (role) {
    AppRole.owner => const _DashboardData(
      subtitle: 'Here is your institute overview for today.',
      metrics: [
        _DashboardMetric(
          label: 'Total students',
          value: '1,248',
          icon: Icons.people_alt_outlined,
          color: Color(0xFF2563EB),
        ),
        _DashboardMetric(
          label: 'Active batches',
          value: '42',
          icon: Icons.groups_outlined,
          color: Color(0xFF7C3AED),
        ),
        _DashboardMetric(
          label: 'Today\'s classes',
          value: '18',
          icon: Icons.calendar_month_outlined,
          color: Color(0xFF0891B2),
        ),
        _DashboardMetric(
          label: 'Pending approvals',
          value: '7',
          icon: Icons.task_alt_outlined,
          color: Color(0xFFD97706),
        ),
      ],
    ),
    AppRole.counselor => const _DashboardData(
      subtitle: 'Focus on the conversations that need your attention.',
      metrics: [
        _DashboardMetric(
          label: 'Students to follow up',
          value: '24',
          icon: Icons.forum_outlined,
          color: Color(0xFF2563EB),
        ),
        _DashboardMetric(
          label: 'New student enquiries',
          value: '12',
          icon: Icons.mark_email_unread_outlined,
          color: Color(0xFF7C3AED),
        ),
        _DashboardMetric(
          label: 'Students needing support',
          value: '9',
          icon: Icons.volunteer_activism_outlined,
          color: Color(0xFFD97706),
        ),
      ],
    ),
    AppRole.trainer => const _DashboardData(
      subtitle: 'Your training day at a glance.',
      metrics: [
        _DashboardMetric(
          label: 'Assigned batches',
          value: '5',
          icon: Icons.groups_outlined,
          color: Color(0xFF2563EB),
        ),
        _DashboardMetric(
          label: 'Today\'s classes',
          value: '4',
          icon: Icons.calendar_month_outlined,
          color: Color(0xFF7C3AED),
        ),
        _DashboardMetric(
          label: 'Attendance pending',
          value: '2',
          icon: Icons.fact_check_outlined,
          color: Color(0xFFD97706),
        ),
      ],
    ),
    AppRole.accounts => const _DashboardData(
      subtitle: 'A quick view of fee operations for this month.',
      metrics: [
        _DashboardMetric(
          label: 'Pending instalments',
          value: '36',
          icon: Icons.account_balance_wallet_outlined,
          color: Color(0xFF2563EB),
        ),
        _DashboardMetric(
          label: 'Overdue payments',
          value: '14',
          icon: Icons.warning_amber_rounded,
          color: Color(0xFFD97706),
        ),
        _DashboardMetric(
          label: 'Payments recorded this month',
          value: '₹4.8L',
          icon: Icons.payments_outlined,
          color: Color(0xFF059669),
        ),
      ],
    ),
  };
}

class _DemoDataNotice extends StatelessWidget {
  const _DemoDataNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700), size: 20),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Demo data only — these overview values are not connected to Firestore.',
              style: TextStyle(color: Color(0xFF7A4B00)),
            ),
          ),
        ],
      ),
    );
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
