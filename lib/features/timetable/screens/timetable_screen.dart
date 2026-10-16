import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/trainer.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/clash_detection_engine.dart';
import '../../../data/services/timetable_seed_service.dart';
import '../../../data/services/timetable_service.dart';
import '../../../data/services/trainer_service.dart';

// Zero-dependency date & time helpers
String _formatTime(DateTime dt) {
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}:$minute $period';
}

String _formatDateShort(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

String _formatDateMedium(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatDateFull(DateTime dt) {
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatDateWithDay(DateTime dt) {
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _weekdayShort(DateTime dt) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return weekdays[dt.weekday - 1];
}

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.timetableService,
    this.batchService,
    this.trainerService,
    this.seedService,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final TimetableService? timetableService;
  final BatchService? batchService;
  final TrainerService? trainerService;
  final TimetableSeedService? seedService;

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  late final TimetableService _timetableService;
  late final BatchService _batchService;
  late final TrainerService _trainerService;
  late final TimetableSeedService _seedService;

  late Stream<List<ClassSession>> _sessionsStream;
  late Stream<List<Batch>> _batchesStream;
  late Stream<List<Trainer>> _trainersStream;

  late DateTime _selectedWeekStart;
  String _viewMode = 'calendar'; // 'calendar' or 'list'
  String _batchFilter = 'all';
  String _trainerFilter = 'all';
  String _deliveryModeFilter = 'all';
  bool _isSeeding = false;

  bool get _canManage => _timetableService.canManage(widget.user);
  bool get _isTrainer => widget.user.role == AppRole.trainer;

  @override
  void initState() {
    super.initState();
    _timetableService = widget.timetableService ?? TimetableService();
    _batchService = widget.batchService ?? BatchService();
    _trainerService = widget.trainerService ?? TrainerService();
    _seedService = widget.seedService ??
        TimetableSeedService(
          timetableRepository: _timetableService.timetableRepository
                  is TimetableSeedRepository
              ? _timetableService.timetableRepository as TimetableSeedRepository
              : null,
        );

    final now = DateTime.now();
    _selectedWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));

    _sessionsStream = _timetableService.watchForUser(widget.user);
    _batchesStream = _batchService.watchForUser(widget.user);
    _trainersStream = _trainerService.watchForUser(widget.user);
  }

  void _reloadSessions() {
    setState(() {
      _sessionsStream = _timetableService.watchForUser(widget.user);
    });
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    });
  }

  void _today() {
    final now = DateTime.now();
    setState(() {
      _selectedWeekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
    });
  }

  Future<void> _loadSampleData() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    try {
      final result = await _seedService.loadSampleData(
        referenceDate: _selectedWeekStart,
      );
      if (!mounted) return;
      if (result.alreadyHadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample timetable already loaded in the database.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample schedule loaded: ${result.sessionsCreated} classes created (${result.sessionsSkipped} already existed).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sample timetable: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _openClassForm({
    ClassSession? session,
    List<Batch>? batches,
    List<Trainer>? trainers,
    List<ClassSession>? existingSessions,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ClassSessionFormDialog(
        session: session,
        batches: batches ?? const [],
        trainers: trainers ?? const [],
        existingSessions: existingSessions ?? const [],
        user: widget.user,
        timetableService: _timetableService,
      ),
    );
  }

  void _openClassDetail(
    ClassSession session,
    List<Batch> batches,
    List<Trainer> trainers,
    List<ClassSession> existingSessions,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => _ClassSessionDetailDialog(
        session: session,
        user: widget.user,
        canManage: _canManage,
        onEdit: () {
          Navigator.of(context).pop();
          _openClassForm(
            session: session,
            batches: batches,
            trainers: trainers,
            existingSessions: existingSessions,
          );
        },
        onCancelSession: () async {
          Navigator.of(context).pop();
          await _confirmCancelSession(session);
        },
      ),
    );
  }

  Future<void> _confirmCancelSession(ClassSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CancelSessionConfirmationDialog(session: session),
    );

    if (confirmed == true && mounted) {
      try {
        await _timetableService.cancelSession(widget.user, session.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Class session for "${session.batchName}" cancelled.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel session: $e')),
          );
        }
      }
    }
  }

  List<ClassSession> _filterSessions(List<ClassSession> sessions) {
    return sessions.where((s) {
      if (_batchFilter != 'all' && s.batchId != _batchFilter) {
        return false;
      }
      if (_trainerFilter != 'all' && s.trainerId != _trainerFilter) {
        return false;
      }
      if (_deliveryModeFilter != 'all' &&
          s.deliveryMode != _deliveryModeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  int _countClashes(
    List<ClassSession> sessions,
    List<Trainer> trainers,
    List<Batch> batches,
  ) {
    var clashCount = 0;
    final activeSessions = sessions.where((s) => !s.isCancelled).toList();
    final trainersMap = {for (final t in trainers) t.id: t};
    final batchesMap = {for (final b in batches) b.id: b};

    for (var i = 0; i < activeSessions.length; i++) {
      final current = activeSessions[i];
      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: current,
        existingSessions: activeSessions,
        trainer: trainersMap[current.trainerId],
        batch: batchesMap[current.batchId],
      );
      if (conflicts.isNotEmpty) {
        clashCount++;
      }
    }
    return clashCount;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Batch>>(
      stream: _batchesStream,
      builder: (context, batchesSnapshot) {
        final batches = batchesSnapshot.data ?? const <Batch>[];

        return StreamBuilder<List<Trainer>>(
          stream: _trainersStream,
          builder: (context, trainersSnapshot) {
            final trainers = trainersSnapshot.data ?? const <Trainer>[];

            return StreamBuilder<List<ClassSession>>(
              stream: _sessionsStream,
              builder: (context, sessionsSnapshot) {
                if (sessionsSnapshot.hasError) {
                  return _ErrorCard(
                    title: 'Unable to load timetable',
                    message: sessionsSnapshot.error.toString(),
                    onRetry: _reloadSessions,
                  );
                }

                if (!sessionsSnapshot.hasData) {
                  return const _LoadingCard(
                    label: 'Loading class schedules…',
                  );
                }

                final allSessions = sessionsSnapshot.data!;
                final filteredSessions = _filterSessions(allSessions);

                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final weekEnd =
                    _selectedWeekStart.add(const Duration(days: 7));

                final todaySessions = allSessions.where((s) {
                  return !s.isCancelled &&
                      s.startAt.year == today.year &&
                      s.startAt.month == today.month &&
                      s.startAt.day == today.day;
                }).toList();

                final weeklySessions = allSessions.where((s) {
                  return !s.isCancelled &&
                      !s.startAt.isBefore(_selectedWeekStart) &&
                      s.startAt.isBefore(weekEnd);
                }).toList();

                final conflictsCount = _countClashes(
                  weeklySessions,
                  trainers,
                  batches,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(
                          canManage: _canManage,
                          isTrainer: _isTrainer,
                          isSeeding: _isSeeding,
                          onLoadSamples:
                              _canManage ? _loadSampleData : null,
                          onAddClass: _canManage
                              ? () => _openClassForm(
                                    batches: batches,
                                    trainers: trainers,
                                    existingSessions: allSessions,
                                  )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _RoleBanner(
                          role: widget.user.role,
                          userName: widget.user.name,
                        ),
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
                        _OverviewCards(
                          todayClassesCount: todaySessions.length,
                          weeklyClassesCount: weeklySessions.length,
                          conflictsCount: conflictsCount,
                          inPersonCount: weeklySessions
                              .where((s) => s.isInPerson)
                              .length,
                          onlineCount: weeklySessions
                              .where((s) => s.isOnline || s.isHybrid)
                              .length,
                        ),
                        const SizedBox(height: 20),
                        _WeekControlBar(
                          selectedWeekStart: _selectedWeekStart,
                          viewMode: _viewMode,
                          onPreviousWeek: _previousWeek,
                          onNextWeek: _nextWeek,
                          onToday: _today,
                          onViewModeChanged: (mode) =>
                              setState(() => _viewMode = mode),
                        ),
                        const SizedBox(height: 16),
                        _FilterBar(
                          batchFilter: _batchFilter,
                          trainerFilter: _trainerFilter,
                          deliveryModeFilter: _deliveryModeFilter,
                          batches: batches,
                          trainers: trainers,
                          showTrainerFilter: !_isTrainer,
                          onBatchChanged: (v) =>
                              setState(() => _batchFilter = v),
                          onTrainerChanged: (v) =>
                              setState(() => _trainerFilter = v),
                          onDeliveryModeChanged: (v) =>
                              setState(() => _deliveryModeFilter = v),
                        ),
                        const SizedBox(height: 20),
                        if (filteredSessions.isEmpty)
                          _EmptyStateCard(
                            canManage: _canManage,
                            hasAnySessions: allSessions.isNotEmpty,
                            onAddClass: () => _openClassForm(
                              batches: batches,
                              trainers: trainers,
                              existingSessions: allSessions,
                            ),
                          )
                        else if (_viewMode == 'calendar')
                          _WeeklyCalendarView(
                            weekStart: _selectedWeekStart,
                            sessions: filteredSessions,
                            onSessionTap: (session) => _openClassDetail(
                              session,
                              batches,
                              trainers,
                              allSessions,
                            ),
                          )
                        else
                          _DailyListView(
                            sessions: filteredSessions,
                            weekStart: _selectedWeekStart,
                            canManage: _canManage,
                            onSessionTap: (session) => _openClassDetail(
                              session,
                              batches,
                              trainers,
                              allSessions,
                            ),
                            onEditSession: (session) => _openClassForm(
                              session: session,
                              batches: batches,
                              trainers: trainers,
                              existingSessions: allSessions,
                            ),
                            onCancelSession: _confirmCancelSession,
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header & Role Banner
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.canManage,
    required this.isTrainer,
    required this.isSeeding,
    required this.onLoadSamples,
    required this.onAddClass,
  });

  final bool canManage;
  final bool isTrainer;
  final bool isSeeding;
  final VoidCallback? onLoadSamples;
  final VoidCallback? onAddClass;

  @override
  Widget build(BuildContext context) {
    final title = isTrainer ? 'My Timetable & Sessions' : 'Timetable Management';
    final subtitle = isTrainer
        ? 'View assigned class sessions, classroom allocations, and online join links.'
        : 'Manage class sessions, weekly schedules, classroom reservations, and avoid conflicts.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        if (canManage) ...[
          OutlinedButton.icon(
            onPressed: isSeeding ? null : onLoadSamples,
            icon: isSeeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text(isSeeding ? 'Seeding…' : 'Load Sample Schedule'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              side: const BorderSide(color: Color(0xFFD8DFEB)),
              foregroundColor: AppTheme.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onAddClass,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add Class'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
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
          'Full Schedule Administration',
          'Signed in as $userName (Owner). You have unrestricted permissions to create, reschedule, cancel classes, assign classrooms, and override clash warnings.',
          const Color(0xFF1D4ED8),
          const Color(0xFFEFF6FF),
        ),
      AppRole.counselor => (
          'Counselor Schedule Access',
          'Signed in as $userName (Counselor). Viewing institutional schedules, batch timetables, and room allocations.',
          const Color(0xFF0D9488),
          const Color(0xFFF0FDFA),
        ),
      AppRole.trainer => (
          'Trainer Personalized Schedule',
          'Signed in as $userName (Trainer). Showing classes specifically assigned to your cohorts.',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF),
        ),
      AppRole.accounts => (
          'Accounts View-Only Timetable',
          'Signed in as $userName (Accounts Staff). Read-only schedule visibility.',
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
          Icon(Icons.verified_user_rounded, color: color, size: 20),
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
// Overview Metric Cards
// ---------------------------------------------------------------------------

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({
    required this.todayClassesCount,
    required this.weeklyClassesCount,
    required this.conflictsCount,
    required this.inPersonCount,
    required this.onlineCount,
  });

  final int todayClassesCount;
  final int weeklyClassesCount;
  final int conflictsCount;
  final int inPersonCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final cardWidth = isNarrow
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: "Today's Classes",
                value: '$todayClassesCount',
                subtitle: 'Active sessions scheduled today',
                icon: Icons.today_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Weekly Classes',
                value: '$weeklyClassesCount',
                subtitle: 'Classes in current view week',
                icon: Icons.calendar_view_week_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Clash Status',
                value: conflictsCount == 0 ? '0' : '$conflictsCount',
                subtitle: conflictsCount == 0
                    ? 'All schedules conflict-free'
                    : 'Overlapping bookings detected',
                icon: conflictsCount == 0
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                iconColor: conflictsCount == 0
                    ? const Color(0xFF059669)
                    : const Color(0xFFDC2626),
                iconBg: conflictsCount == 0
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFEF2F2),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Delivery Modes',
                value: '$inPersonCount / $onlineCount',
                subtitle: 'In-Person vs Online / Hybrid',
                icon: Icons.devices_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBg: const Color(0xFFF5F3FF),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
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

// ---------------------------------------------------------------------------
// Week Navigation & View Mode Toggle Bar
// ---------------------------------------------------------------------------

class _WeekControlBar extends StatelessWidget {
  const _WeekControlBar({
    required this.selectedWeekStart,
    required this.viewMode,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onToday,
    required this.onViewModeChanged,
  });

  final DateTime selectedWeekStart;
  final String viewMode;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onToday;
  final ValueChanged<String> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final endOfWeek = selectedWeekStart.add(const Duration(days: 6));
    final rangeText =
        '${_formatDateMedium(selectedWeekStart)} - ${_formatDateMedium(endOfWeek)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPreviousWeek,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous week',
            splashRadius: 20,
          ),
          TextButton(
            onPressed: onToday,
            child: const Text(
              'Today',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onNextWeek,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next week',
            splashRadius: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rangeText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'calendar',
                label: Text('Weekly Grid'),
                icon: Icon(Icons.calendar_view_week_rounded, size: 18),
              ),
              ButtonSegment<String>(
                value: 'list',
                label: Text('Daily List'),
                icon: Icon(Icons.view_agenda_outlined, size: 18),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                onViewModeChanged(selected.first);
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.batchFilter,
    required this.trainerFilter,
    required this.deliveryModeFilter,
    required this.batches,
    required this.trainers,
    required this.showTrainerFilter,
    required this.onBatchChanged,
    required this.onTrainerChanged,
    required this.onDeliveryModeChanged,
  });

  final String batchFilter;
  final String trainerFilter;
  final String deliveryModeFilter;
  final List<Batch> batches;
  final List<Trainer> trainers;
  final bool showTrainerFilter;
  final ValueChanged<String> onBatchChanged;
  final ValueChanged<String> onTrainerChanged;
  final ValueChanged<String> onDeliveryModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          final dropdownWidth = isNarrow ? constraints.maxWidth : 220.0;

          return Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: dropdownWidth,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: batchFilter,
                  decoration: const InputDecoration(
                    labelText: 'Filter Batch',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Batches'),
                    ),
                    ...batches.map(
                      (b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) onBatchChanged(val);
                  },
                ),
              ),
              if (showTrainerFilter)
                SizedBox(
                  width: dropdownWidth,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: trainerFilter,
                    decoration: const InputDecoration(
                      labelText: 'Filter Trainer',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Trainers'),
                      ),
                      ...trainers.map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            t.fullName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) onTrainerChanged(val);
                    },
                  ),
                ),
              SizedBox(
                width: dropdownWidth,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: deliveryModeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Delivery Mode',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('All Modes'),
                    ),
                    DropdownMenuItem(
                      value: 'in_person',
                      child: Text('In-Person'),
                    ),
                    DropdownMenuItem(
                      value: 'online',
                      child: Text('Online Live'),
                    ),
                    DropdownMenuItem(
                      value: 'hybrid',
                      child: Text('Hybrid'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) onDeliveryModeChanged(val);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly Calendar Grid View
// ---------------------------------------------------------------------------

class _WeeklyCalendarView extends StatelessWidget {
  const _WeeklyCalendarView({
    required this.weekStart,
    required this.sessions,
    required this.onSessionTap,
  });

  final DateTime weekStart;
  final List<ClassSession> sessions;
  final ValueChanged<ClassSession> onSessionTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Monday (0) to Saturday (5)
    final days = List.generate(6, (i) => weekStart.add(Duration(days: i)));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - (5 * 10)) / 6;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: days.map((day) {
              final isToday = day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;

              final daySessions = sessions.where((s) {
                return s.startAt.year == day.year &&
                    s.startAt.month == day.month &&
                    s.startAt.day == day.day;
              }).toList()
                ..sort((a, b) => a.startAt.compareTo(b.startAt));

              return Container(
                width: columnWidth < 180 ? 180 : columnWidth,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isToday
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isToday
                        ? AppTheme.brand.withAlpha(120)
                        : const Color(0xFFE2E8F0),
                    width: isToday ? 1.8 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Column Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppTheme.brand.withAlpha(20)
                            : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13),
                        ),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _weekdayShort(day),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isToday
                                  ? AppTheme.brand
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDateShort(day),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isToday
                                  ? AppTheme.ink
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: daySessions.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No classes',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            )
                          : Column(
                              children: daySessions
                                  .map(
                                    (session) => _CalendarSessionCard(
                                      session: session,
                                      onTap: () => onSessionTap(session),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CalendarSessionCard extends StatelessWidget {
  const _CalendarSessionCard({
    required this.session,
    required this.onTap,
  });

  final ClassSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${_formatTime(session.startAt)} - ${_formatTime(session.endAt)}';

    final (chipBg, chipFg) = switch (session.deliveryMode) {
      'in_person' => (const Color(0xFFECFDF5), const Color(0xFF065F46)),
      'online' => (const Color(0xFFEFF6FF), const Color(0xFF1E40AF)),
      'hybrid' => (const Color(0xFFFAF5FF), const Color(0xFF6B21A8)),
      _ => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: session.isCancelled ? const Color(0xFFFEF2F2) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: session.isCancelled
                ? const Color(0xFFFCA5A5)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: session.isCancelled
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF1D4ED8),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    session.deliveryModeLabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: chipFg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              session.batchName,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                decoration: session.isCancelled
                    ? TextDecoration.lineThrough
                    : null,
                color: session.isCancelled
                    ? const Color(0xFF991B1B)
                    : AppTheme.ink,
              ),
            ),
            Text(
              session.courseName,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 13,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    session.trainerName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (session.roomName.isNotEmpty ||
                session.meetingLink.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    session.isInPerson
                        ? Icons.meeting_room_outlined
                        : Icons.link_rounded,
                    size: 13,
                    color: const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      session.isInPerson
                          ? session.roomName
                          : (session.isHybrid && session.roomName.isNotEmpty
                              ? session.roomName
                              : 'Live Meeting Link'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (session.isCancelled) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CANCELLED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily List View
// ---------------------------------------------------------------------------

class _DailyListView extends StatelessWidget {
  const _DailyListView({
    required this.sessions,
    required this.weekStart,
    required this.canManage,
    required this.onSessionTap,
    required this.onEditSession,
    required this.onCancelSession,
  });

  final List<ClassSession> sessions;
  final DateTime weekStart;
  final bool canManage;
  final ValueChanged<ClassSession> onSessionTap;
  final ValueChanged<ClassSession> onEditSession;
  final ValueChanged<ClassSession> onCancelSession;

  @override
  Widget build(BuildContext context) {
    // Group sessions by calendar day
    final grouped = <DateTime, List<ClassSession>>{};
    for (final s in sessions) {
      final key = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
      grouped.putIfAbsent(key, () => []).add(s);
    }

    final sortedDates = grouped.keys.toList()..sort();

    return Column(
      children: sortedDates.map((date) {
        final daySessions = grouped[date]!
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 20,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatDateWithDay(date),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${daySessions.length} classes',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...daySessions.map((session) {
                final timeStr =
                    '${_formatTime(session.startAt)} - ${_formatTime(session.endAt)}';

                return InkWell(
                  onTap: () => onSessionTap(session),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: session.isCancelled
                                      ? const Color(0xFF991B1B)
                                      : AppTheme.brand,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                session.deliveryModeLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.batchName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  decoration: session.isCancelled
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: session.isCancelled
                                      ? const Color(0xFF991B1B)
                                      : AppTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                session.courseName,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.trainerName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                session.roomName.isNotEmpty
                                    ? session.roomName
                                    : (session.meetingLink.isNotEmpty
                                        ? 'Virtual Link'
                                        : 'No Room Assigned'),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (session.isCancelled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Cancelled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          )
                        else if (canManage) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Edit Class',
                            onPressed: () => onEditSession(session),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel_outlined,
                              size: 20,
                              color: Color(0xFFDC2626),
                            ),
                            tooltip: 'Cancel Class',
                            onPressed: () => onCancelSession(session),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit Class Session Form Dialog
// ---------------------------------------------------------------------------

class _ClassSessionFormDialog extends StatefulWidget {
  const _ClassSessionFormDialog({
    required this.session,
    required this.batches,
    required this.trainers,
    required this.existingSessions,
    required this.user,
    required this.timetableService,
  });

  final ClassSession? session;
  final List<Batch> batches;
  final List<Trainer> trainers;
  final List<ClassSession> existingSessions;
  final AppUser user;
  final TimetableService timetableService;

  @override
  State<_ClassSessionFormDialog> createState() =>
      _ClassSessionFormDialogState();
}

class _ClassSessionFormDialogState extends State<_ClassSessionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late String? _selectedBatchId;
  late String? _selectedTrainerId;
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _deliveryMode;
  late TextEditingController _roomController;
  late TextEditingController _meetingLinkController;

  bool _isSaving = false;
  bool _forceOverride = false;
  String? _errorMessage;
  List<ScheduleConflict> _liveConflicts = const [];

  bool get _isEditing => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    final now = DateTime.now();

    _selectedBatchId = s?.batchId ??
        (widget.batches.isNotEmpty ? widget.batches.first.id : null);
    _selectedTrainerId = s?.trainerId ??
        (widget.trainers.isNotEmpty ? widget.trainers.first.id : null);
    _selectedDate = s?.startAt ?? now;
    _startTime = s != null
        ? TimeOfDay(hour: s.startAt.hour, minute: s.startAt.minute)
        : const TimeOfDay(hour: 9, minute: 0);
    _endTime = s != null
        ? TimeOfDay(hour: s.endAt.hour, minute: s.endAt.minute)
        : const TimeOfDay(hour: 11, minute: 0);
    _deliveryMode = s?.deliveryMode ?? 'in_person';
    _roomController = TextEditingController(text: s?.roomName ?? 'Lab 101');
    _meetingLinkController =
        TextEditingController(text: s?.meetingLink ?? '');

    _evaluateLiveClashes();
  }

  @override
  void dispose() {
    _roomController.dispose();
    _meetingLinkController.dispose();
    super.dispose();
  }

  ClassSession _buildCandidate() {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final end = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    final batch = widget.batches.cast<Batch?>().firstWhere(
          (b) => b?.id == _selectedBatchId,
          orElse: () => null,
        );
    final trainer = widget.trainers.cast<Trainer?>().firstWhere(
          (t) => t?.id == _selectedTrainerId,
          orElse: () => null,
        );

    final now = DateTime.now();
    return ClassSession(
      id: widget.session?.id ?? '',
      instituteId: 'demo-institute',
      batchId: _selectedBatchId ?? '',
      batchName: batch?.name ?? '',
      courseId: batch?.courseId ?? '',
      courseName: batch?.courseName ?? '',
      trainerId: _selectedTrainerId ?? '',
      trainerName: trainer?.fullName ?? '',
      startAt: start,
      endAt: end,
      deliveryMode: _deliveryMode,
      roomId: _roomController.text.trim().replaceAll(' ', '-').toLowerCase(),
      roomName: _roomController.text.trim(),
      meetingLink: _meetingLinkController.text.trim(),
      status: widget.session?.status ?? 'scheduled',
      createdAt: widget.session?.createdAt ?? now,
      updatedAt: now,
    );
  }

  void _evaluateLiveClashes() {
    final candidate = _buildCandidate();
    final trainer = widget.trainers.cast<Trainer?>().firstWhere(
          (t) => t?.id == _selectedTrainerId,
          orElse: () => null,
        );
    final batch = widget.batches.cast<Batch?>().firstWhere(
          (b) => b?.id == _selectedBatchId,
          orElse: () => null,
        );

    final conflicts = ClashDetectionEngine.detectConflicts(
      candidate: candidate,
      existingSessions: widget.existingSessions,
      trainer: trainer,
      batch: batch,
    );

    setState(() {
      _liveConflicts = conflicts;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2027, 12, 31),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _evaluateLiveClashes();
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
      _evaluateLiveClashes();
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
      _evaluateLiveClashes();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_liveConflicts.isNotEmpty && !_forceOverride) {
      setState(() {
        _errorMessage =
            'Scheduling conflict detected: ${_liveConflicts.first.message}. Please adjust the time/room or select "Force Schedule".';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final candidate = _buildCandidate();
      if (_isEditing) {
        await widget.timetableService.updateSession(
          widget.user,
          candidate,
          allowClashOverride: _forceOverride,
        );
      } else {
        await widget.timetableService.createSession(
          widget.user,
          candidate,
          allowClashOverride: _forceOverride,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Class session updated successfully.'
                  : 'New class session added to timetable.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditing
                ? Icons.edit_calendar_rounded
                : Icons.add_alarm_rounded,
            color: AppTheme.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isEditing ? 'Edit Class Session' : 'Add Class Session',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Live conflict feedback banner
                if (_liveConflicts.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFD97706),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_liveConflicts.length} Conflict(s) Detected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._liveConflicts.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• [${c.typeLabel}] ${c.message}',
                                style: const TextStyle(
                                  color: Color(0xFF78350F),
                                  fontSize: 12,
                                ),
                              ),
                            )),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Checkbox(
                              value: _forceOverride,
                              onChanged: (v) =>
                                  setState(() => _forceOverride = v ?? false),
                            ),
                            const Expanded(
                              child: Text(
                                'Force schedule despite conflict (Owner Override)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Batch Selection
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: 'Select Batch *',
                    helperText:
                        'Course will be automatically populated from batch',
                  ),
                  items: widget.batches
                      .map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text('${b.name} (${b.courseName})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedBatchId = v;
                      final b = widget.batches.cast<Batch?>().firstWhere(
                            (item) => item?.id == v,
                            orElse: () => null,
                          );
                      if (b != null && b.trainerId.isNotEmpty) {
                        _selectedTrainerId = b.trainerId;
                      }
                    });
                    _evaluateLiveClashes();
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Batch is required' : null,
                ),
                const SizedBox(height: 16),

                // Trainer Selection
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedTrainerId,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Trainer *',
                    helperText: 'Trainer teaching this session',
                  ),
                  items: widget.trainers
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text('${t.fullName} (${t.email})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedTrainerId = v);
                    _evaluateLiveClashes();
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Trainer is required' : null,
                ),
                const SizedBox(height: 16),

                // Date Picker
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Session Date *',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                    ),
                    child: Text(_formatDateWithDay(_selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),

                // Time Pickers
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickStartTime,
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Time *',
                            suffixIcon: Icon(Icons.schedule_rounded, size: 20),
                          ),
                          child: Text(_startTime.format(context)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        onTap: _pickEndTime,
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Time *',
                            suffixIcon: Icon(Icons.schedule_rounded, size: 20),
                          ),
                          child: Text(_endTime.format(context)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Delivery Mode
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _deliveryMode,
                  decoration:
                      const InputDecoration(labelText: 'Delivery Mode *'),
                  items: const [
                    DropdownMenuItem(
                      value: 'in_person',
                      child: Text('In-Person (Classroom)'),
                    ),
                    DropdownMenuItem(
                      value: 'online',
                      child: Text('Online Live (Virtual Link)'),
                    ),
                    DropdownMenuItem(
                      value: 'hybrid',
                      child: Text('Hybrid (In-Person + Live Broadcast)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _deliveryMode = v);
                      _evaluateLiveClashes();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Classroom Name (Required if in_person or hybrid)
                if (_deliveryMode == 'in_person' ||
                    _deliveryMode == 'hybrid') ...[
                  TextFormField(
                    controller: _roomController,
                    decoration: const InputDecoration(
                      labelText: 'Classroom / Lab Name *',
                      hintText: 'e.g. Lab 101, Ground Floor',
                    ),
                    onChanged: (_) => _evaluateLiveClashes(),
                    validator: (v) {
                      if (_deliveryMode != 'online' &&
                          (v == null || v.trim().isEmpty)) {
                        return 'Classroom name is required for in-person or hybrid classes';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Meeting Link
                if (_deliveryMode == 'online' ||
                    _deliveryMode == 'hybrid') ...[
                  TextFormField(
                    controller: _meetingLinkController,
                    decoration: const InputDecoration(
                      labelText: 'Meeting Link',
                      hintText: 'e.g. https://meet.google.com/xyz',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brand,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEditing ? 'Save Changes' : 'Schedule Class'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Class Session Detail Dialog
// ---------------------------------------------------------------------------

class _ClassSessionDetailDialog extends StatelessWidget {
  const _ClassSessionDetailDialog({
    required this.session,
    required this.user,
    required this.canManage,
    required this.onEdit,
    required this.onCancelSession,
  });

  final ClassSession session;
  final AppUser user;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onCancelSession;

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${_formatTime(session.startAt)} - ${_formatTime(session.endAt)}';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            session.isInPerson
                ? Icons.school_rounded
                : (session.isOnline
                    ? Icons.videocam_rounded
                    : Icons.devices_rounded),
            color: AppTheme.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              session.batchName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: session.isCancelled
                  ? const Color(0xFFFEE2E2)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              session.statusLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: session.isCancelled
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailItem(label: 'Course', value: session.courseName),
            _DetailItem(label: 'Assigned Trainer', value: session.trainerName),
            _DetailItem(
              label: 'Date',
              value: _formatDateFull(session.startAt),
            ),
            _DetailItem(
              label: 'Scheduled Time',
              value: '$timeStr (${session.duration.inMinutes} mins)',
            ),
            _DetailItem(
              label: 'Delivery Mode',
              value: session.deliveryModeLabel,
            ),
            if (session.roomName.isNotEmpty)
              _DetailItem(label: 'Classroom / Lab', value: session.roomName),
            if (session.meetingLink.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Online Live Link:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                session.meetingLink,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (canManage && !session.isCancelled) ...[
          TextButton.icon(
            onPressed: onCancelSession,
            icon: const Icon(
              Icons.cancel_outlined,
              size: 18,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              'Cancel Class',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Class'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
            ),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cancel Session Confirmation Dialog
// ---------------------------------------------------------------------------

class _CancelSessionConfirmationDialog extends StatelessWidget {
  const _CancelSessionConfirmationDialog({required this.session});

  final ClassSession session;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cancel Class Session',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to cancel the scheduled session for "${session.batchName}"?\n\n'
        '• The record will be preserved with status "cancelled" for auditing.\n'
        '• Classroom and trainer booking will be immediately freed up for other sessions.',
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep Class'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          child: const Text('Cancel Class'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State Cards (Empty, Error, Loading)
// ---------------------------------------------------------------------------

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.canManage,
    required this.hasAnySessions,
    required this.onAddClass,
  });

  final bool canManage;
  final bool hasAnySessions;
  final VoidCallback onAddClass;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              size: 40,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasAnySessions
                ? 'No matching class sessions found'
                : 'No class sessions scheduled yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasAnySessions
                ? 'Try adjusting your batch, trainer, or delivery mode filters.'
                : 'Get started by clicking "Load Sample Schedule" above or schedule your first class.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
            ),
          ),
          if (canManage && !hasAnySessions) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAddClass,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Schedule First Class'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brand,
                foregroundColor: Colors.white,
              ),
            ),
          ],
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
