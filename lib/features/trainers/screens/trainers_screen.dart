import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/trainer.dart';
import '../../../data/repositories/trainer_repository.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/trainer_seed_service.dart';
import '../../../data/services/trainer_service.dart';

class TrainersScreen extends StatefulWidget {
  const TrainersScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.trainerService,
    this.batchService,
    this.seedService,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final TrainerService? trainerService;
  final BatchService? batchService;
  final TrainerSeedService? seedService;

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  late final TrainerService _trainerService;
  late final BatchService _batchService;
  late final TrainerSeedService _seedService;

  late Stream<List<Trainer>> _trainersStream;
  late Stream<List<Batch>> _batchesStream;

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _assignmentFilter = 'all';
  String? _expertiseFilter;
  bool _isSeeding = false;

  bool get _canManage => _trainerService.canManage(widget.user);

  @override
  void initState() {
    super.initState();
    _trainerService = widget.trainerService ?? TrainerService();
    _batchService = widget.batchService ?? BatchService();
    _seedService = widget.seedService ??
        TrainerSeedService(
          trainerRepository: _trainerService.repository is TrainerSeedRepository
              ? _trainerService.repository as TrainerSeedRepository
              : null,
          batchRepository: _trainerService.batchRepository,
        );

    _trainersStream = _trainerService.watchForUser(widget.user);
    _batchesStream = _batchService.watchForUser(widget.user);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadTrainers() {
    setState(() {
      _trainersStream = _trainerService.watchForUser(widget.user);
    });
  }

  Future<void> _loadSampleData() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    try {
      final result = await _seedService.loadSampleData();
      if (!mounted) return;
      if (result.alreadyHadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample data check: Sample trainers already exist in the database.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample data loaded: ${result.trainersCreated} trainers created (${result.trainersSkipped} already existed).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sample trainers: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _openTrainerForm([Trainer? trainer]) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TrainerFormDialog(
        user: widget.user,
        trainer: trainer,
        trainerService: _trainerService,
      ),
    );
  }

  void _openTrainerDetail(Trainer trainer, List<Batch> batches) {
    showDialog<void>(
      context: context,
      builder: (context) => _TrainerDetailDialog(
        trainer: trainer,
        batches: batches,
        user: widget.user,
        canManage: _canManage,
        trainerService: _trainerService,
        batchService: _batchService,
        onEdit: () {
          Navigator.of(context).pop();
          _openTrainerForm(trainer);
        },
      ),
    );
  }

  void _openAssignBatchDialog(Trainer trainer, List<Batch> batches) {
    showDialog<void>(
      context: context,
      builder: (context) => _AssignBatchDialog(
        trainer: trainer,
        batches: batches,
        user: widget.user,
        trainerService: _trainerService,
      ),
    );
  }

  Future<void> _toggleTrainerStatus(
    Trainer trainer,
    List<Batch> batches,
  ) async {
    if (trainer.isActive) {
      final assignedActiveBatches = batches
          .where((b) => !b.isArchived && b.trainerId == trainer.id)
          .toList();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _DeactivateConfirmationDialog(
          trainer: trainer,
          assignedBatches: assignedActiveBatches,
        ),
      );

      if (confirmed == true && mounted) {
        try {
          await _trainerService.deactivateTrainer(widget.user, trainer.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Trainer "${trainer.fullName}" has been deactivated.',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to deactivate trainer: $e')),
            );
          }
        }
      }
    } else {
      // Re-activating
      try {
        await _trainerService.activateTrainer(widget.user, trainer.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Trainer "${trainer.fullName}" has been activated.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to activate trainer: $e')),
          );
        }
      }
    }
  }

  List<Trainer> _filterTrainers(
    List<Trainer> trainers,
    List<Batch> batches,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    return trainers.where((trainer) {
      final matchesQuery = query.isEmpty ||
          trainer.fullName.toLowerCase().contains(query) ||
          trainer.email.toLowerCase().contains(query) ||
          trainer.phone.toLowerCase().contains(query) ||
          trainer.expertise.any((e) => e.toLowerCase().contains(query));

      final matchesStatus = switch (_statusFilter) {
        'active' => trainer.isActive,
        'inactive' => trainer.isInactive,
        _ => true,
      };

      final hasAssignments =
          batches.any((b) => !b.isArchived && b.trainerId == trainer.id);
      final matchesAssignment = switch (_assignmentFilter) {
        'assigned' => hasAssignments,
        'unassigned' => !hasAssignments,
        _ => true,
      };

      final matchesExpertise = _expertiseFilter == null ||
          trainer.expertise.contains(_expertiseFilter);

      return matchesQuery &&
          matchesStatus &&
          matchesAssignment &&
          matchesExpertise;
    }).toList();
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
            if (trainersSnapshot.hasError) {
              return _ErrorCard(
                title: 'Unable to load trainers',
                message: trainersSnapshot.error.toString(),
                onRetry: _reloadTrainers,
              );
            }

            if (!trainersSnapshot.hasData) {
              return const _LoadingCard(label: 'Loading trainers…');
            }

            final allTrainers = trainersSnapshot.data!;
            final filteredTrainers = _filterTrainers(allTrainers, batches);

            // Calculate overview metrics from real data
            final activeTrainers =
                allTrainers.where((t) => t.isActive).toList();
            final assignedTrainersCount = activeTrainers
                .where((t) =>
                    batches.any((b) => !b.isArchived && b.trainerId == t.id))
                .length;
            final unassignedTrainersCount =
                activeTrainers.length - assignedTrainersCount;
            final totalActiveBatchAssignments = batches
                .where((b) => !b.isArchived && b.trainerId.isNotEmpty)
                .length;

            final allExpertise = allTrainers
                .expand((t) => t.expertise)
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      canManage: _canManage,
                      isSeeding: _isSeeding,
                      onLoadSamples: _canManage ? _loadSampleData : null,
                      onAddTrainer: _canManage ? () => _openTrainerForm() : null,
                    ),
                    const SizedBox(height: 16),
                    _RoleBanner(role: widget.user.role),
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
                      totalActiveTrainers: activeTrainers.length,
                      assignedTrainersCount: assignedTrainersCount,
                      unassignedTrainersCount: unassignedTrainersCount,
                      totalBatchAssignments: totalActiveBatchAssignments,
                    ),
                    const SizedBox(height: 20),
                    _FilterBar(
                      searchController: _searchController,
                      statusFilter: _statusFilter,
                      assignmentFilter: _assignmentFilter,
                      expertiseFilter: _expertiseFilter,
                      allExpertise: allExpertise,
                      onSearchChanged: () => setState(() {}),
                      onStatusChanged: (val) =>
                          setState(() => _statusFilter = val),
                      onAssignmentChanged: (val) =>
                          setState(() => _assignmentFilter = val),
                      onExpertiseChanged: (val) =>
                          setState(() => _expertiseFilter = val),
                    ),
                    const SizedBox(height: 16),
                    if (filteredTrainers.isEmpty)
                      _EmptyStateCard(
                        totalTrainers: allTrainers.length,
                        canManage: _canManage,
                        onAddTrainer: () => _openTrainerForm(),
                      )
                    else
                      _TrainerTable(
                        trainers: filteredTrainers,
                        batches: batches,
                        canManage: _canManage,
                        onViewDetail: (t) => _openTrainerDetail(t, batches),
                        onEdit: (t) => _openTrainerForm(t),
                        onAssignBatch: (t) =>
                            _openAssignBatchDialog(t, batches),
                        onToggleStatus: (t) =>
                            _toggleTrainerStatus(t, batches),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER & BANNERS
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.canManage,
    required this.isSeeding,
    required this.onLoadSamples,
    required this.onAddTrainer,
  });

  final bool canManage;
  final bool isSeeding;
  final VoidCallback? onLoadSamples;
  final VoidCallback? onAddTrainer;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trainer Management',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage instructor profiles, areas of expertise, teaching availability, and batch assignments.',
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
          if (canManage)
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: isSeeding ? null : onLoadSamples,
                  icon: isSeeding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(
                    isSeeding ? 'Seeding trainers…' : 'Load Sample Trainers',
                  ),
                ),
                FilledButton.icon(
                  onPressed: onAddTrainer,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Add Trainer'),
                ),
              ],
            ),
        ],
      );
}

class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (role) {
      AppRole.owner => (
          Icons.admin_panel_settings_outlined,
          'Owner access: Add, edit, deactivate trainers, and assign instructors to active course batches.',
        ),
      AppRole.counselor => (
          Icons.visibility_outlined,
          'Counselor view: Inspect instructor availability, qualifications, and batch teaching schedules.',
        ),
      AppRole.trainer => (
          Icons.co_present_outlined,
          'Trainer view: View your teaching profile, verified availability, and assigned course batches.',
        ),
      AppRole.accounts => (
          Icons.account_balance_wallet_outlined,
          'Accounts Staff view: View trainer allocations for administrative and operational coordination.',
        ),
    };

    return _NoticeBox(
      message: message,
      icon: icon,
      background: const Color(0xFFEAF2FF),
      textColor: AppTheme.ink,
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
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: textColor))),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// OVERVIEW CARDS
// ---------------------------------------------------------------------------

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({
    required this.totalActiveTrainers,
    required this.assignedTrainersCount,
    required this.unassignedTrainersCount,
    required this.totalBatchAssignments,
  });

  final int totalActiveTrainers;
  final int assignedTrainersCount;
  final int unassignedTrainersCount;
  final int totalBatchAssignments;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Active Trainers',
                value: '$totalActiveTrainers',
                icon: Icons.co_present_outlined,
                color: const Color(0xFF2563EB),
                subtitle: 'Verified instructors',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Assigned to Batches',
                value: '$assignedTrainersCount',
                icon: Icons.groups_outlined,
                color: const Color(0xFF059669),
                subtitle: 'Active in >= 1 batch',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'No Batch Assignments',
                value: '$unassignedTrainersCount',
                icon: Icons.person_search_outlined,
                color: const Color(0xFFD97706),
                subtitle: 'Available for scheduling',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Active Batch Allocations',
                value: '$totalBatchAssignments',
                icon: Icons.school_outlined,
                color: const Color(0xFF7C3AED),
                subtitle: 'Assigned active batches',
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
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FILTER BAR
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.statusFilter,
    required this.assignmentFilter,
    required this.expertiseFilter,
    required this.allExpertise,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onAssignmentChanged,
    required this.onExpertiseChanged,
  });

  final TextEditingController searchController;
  final String statusFilter;
  final String assignmentFilter;
  final String? expertiseFilter;
  final List<String> allExpertise;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onAssignmentChanged;
  final ValueChanged<String?> onExpertiseChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchController,
                onChanged: (_) => onSearchChanged(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search trainers, expertise…',
                  isDense: true,
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged();
                          },
                        )
                      : null,
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: statusFilter,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                  DropdownMenuItem(value: 'active', child: Text('Active Only')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (val) => onStatusChanged(val ?? 'all'),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: assignmentFilter,
                decoration: const InputDecoration(
                  labelText: 'Batch Allocation',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Trainers')),
                  DropdownMenuItem(
                      value: 'assigned', child: Text('Assigned Batches')),
                  DropdownMenuItem(
                      value: 'unassigned', child: Text('Unassigned Only')),
                ],
                onChanged: (val) => onAssignmentChanged(val ?? 'all'),
              ),
            ),
            if (allExpertise.isNotEmpty)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: expertiseFilter,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Expertise',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Areas of Expertise'),
                    ),
                    ...allExpertise.map(
                      (e) => DropdownMenuItem(value: e, child: Text(e)),
                    ),
                  ],
                  onChanged: onExpertiseChanged,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TRAINER TABLE & ROWS
// ---------------------------------------------------------------------------

class _TrainerTable extends StatelessWidget {
  const _TrainerTable({
    required this.trainers,
    required this.batches,
    required this.canManage,
    required this.onViewDetail,
    required this.onEdit,
    required this.onAssignBatch,
    required this.onToggleStatus,
  });

  final List<Trainer> trainers;
  final List<Batch> batches;
  final bool canManage;
  final ValueChanged<Trainer> onViewDetail;
  final ValueChanged<Trainer> onEdit;
  final ValueChanged<Trainer> onAssignBatch;
  final ValueChanged<Trainer> onToggleStatus;

  int _countAssignedBatches(String trainerId) => batches
      .where((b) => !b.isArchived && b.trainerId == trainerId)
      .length;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              const WidgetStatePropertyAll(Color(0xFFF6F8FC)),
          columnSpacing: 16,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 74,
          columns: const [
            DataColumn(label: Text('TRAINER')),
            DataColumn(label: Text('CONTACT')),
            DataColumn(label: Text('EXPERTISE')),
            DataColumn(label: Text('ASSIGNED BATCHES')),
            DataColumn(label: Text('AVAILABILITY')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('ACTIONS')),
          ],
          rows: trainers.map((trainer) {
            final assignedCount = _countAssignedBatches(trainer.id);

            return DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => onViewDetail(trainer),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFE8F0FF),
                            child: Text(
                              trainer.fullName.isNotEmpty
                                  ? trainer.fullName.substring(0, 1).toUpperCase()
                                  : 'T',
                              style: const TextStyle(
                                color: AppTheme.brand,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trainer.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                trainer.id,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trainer.email, style: const TextStyle(fontSize: 13)),
                      if (trainer.phone.isNotEmpty)
                        Text(
                          trainer.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: trainer.expertise.take(3).map((exp) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            exp,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        );
                      }).toList()
                        ..addAll(
                          trainer.expertise.length > 3
                              ? [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${trainer.expertise.length - 3}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                ]
                              : [],
                        ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: assignedCount > 0
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: assignedCount > 0
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Text(
                          '$assignedCount active',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: assignedCount > 0
                                ? const Color(0xFF047857)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                      if (canManage && trainer.isActive) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.add_link_rounded, size: 18),
                          tooltip: 'Assign to Batch',
                          onPressed: () => onAssignBatch(trainer),
                        ),
                      ],
                    ],
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      trainer.availability.summary,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(_StatusBadge(isActive: trainer.isActive)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 19),
                        tooltip: 'View Profile & Batches',
                        onPressed: () => onViewDetail(trainer),
                      ),
                      if (canManage) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          tooltip: 'Edit Trainer',
                          onPressed: () => onEdit(trainer),
                        ),
                        IconButton(
                          icon: Icon(
                            trainer.isActive
                                ? Icons.pause_circle_outline_rounded
                                : Icons.play_circle_outline_rounded,
                            size: 19,
                            color: trainer.isActive
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF16A34A),
                          ),
                          tooltip: trainer.isActive
                              ? 'Deactivate Trainer'
                              : 'Activate Trainer',
                          onPressed: () => onToggleStatus(trainer),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? const Color(0xFFE7F8EE) : const Color(0xFFF3F4F6);
    final text = isActive ? const Color(0xFF0E7A3D) : const Color(0xFF4B5563);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.totalTrainers,
    required this.canManage,
    required this.onAddTrainer,
  });

  final int totalTrainers;
  final bool canManage;
  final VoidCallback onAddTrainer;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                const Icon(
                  Icons.co_present_outlined,
                  size: 48,
                  color: AppTheme.brand,
                ),
                const SizedBox(height: 12),
                Text(
                  totalTrainers == 0
                      ? 'No trainers registered yet.'
                      : 'No trainers match the selected filters.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  totalTrainers == 0
                      ? (canManage
                          ? 'Click "Add Trainer" or "Load Sample Trainers" to begin.'
                          : 'Instructors will appear here once registered by an Owner.')
                      : 'Try resetting your search query or status filters.',
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
                if (totalTrainers == 0 && canManage) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAddTrainer,
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Add Trainer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// TRAINER FORM DIALOG (ADD / EDIT)
// ---------------------------------------------------------------------------

class _TrainerFormDialog extends StatefulWidget {
  const _TrainerFormDialog({
    required this.user,
    required this.trainerService,
    this.trainer,
  });

  final AppUser user;
  final Trainer? trainer;
  final TrainerService trainerService;

  @override
  State<_TrainerFormDialog> createState() => _TrainerFormDialogState();
}

class _TrainerFormDialogState extends State<_TrainerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _expertiseController;
  late final TextEditingController _qualificationsController;
  late final TextEditingController _experienceController;

  // Availability fields
  late List<String> _selectedWeekdays;
  late final TextEditingController _preferredTimeController;
  late final TextEditingController _unavailableNotesController;
  late final TextEditingController _generalNotesController;

  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.trainer;
    _nameController = TextEditingController(text: t?.fullName ?? '');
    _emailController = TextEditingController(text: t?.email ?? '');
    _phoneController = TextEditingController(text: t?.phone ?? '');
    _expertiseController =
        TextEditingController(text: t != null ? t.expertise.join(', ') : '');
    _qualificationsController =
        TextEditingController(text: t?.qualifications ?? '');
    _experienceController = TextEditingController(
      text: t != null ? t.experienceYears.toString() : '3',
    );

    final avail = t?.availability ?? const TrainerAvailability();
    _selectedWeekdays = List<String>.from(avail.weekdays);
    _preferredTimeController =
        TextEditingController(text: avail.preferredTimeRange);
    _unavailableNotesController =
        TextEditingController(text: avail.unavailableNotes);
    _generalNotesController =
        TextEditingController(text: avail.generalNotes);

    _status = t?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _expertiseController.dispose();
    _qualificationsController.dispose();
    _experienceController.dispose();
    _preferredTimeController.dispose();
    _unavailableNotesController.dispose();
    _generalNotesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;

    final expertiseList = _expertiseController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final experience =
        int.tryParse(_experienceController.text.trim()) ?? 0;

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final draftAvailability = TrainerAvailability(
        weekdays: _selectedWeekdays,
        preferredTimeRange: _preferredTimeController.text.trim(),
        unavailableNotes: _unavailableNotesController.text.trim(),
        generalNotes: _generalNotesController.text.trim(),
      );

      final draft = Trainer(
        id: widget.trainer?.id ?? '',
        instituteId: widget.trainer?.instituteId ?? 'demo-institute',
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        emailNormalized: _emailController.text.trim().toLowerCase(),
        phone: _phoneController.text.trim(),
        expertise: expertiseList,
        qualifications: _qualificationsController.text.trim(),
        experienceYears: experience,
        availability: draftAvailability,
        status: _status,
        createdAt: widget.trainer?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.trainer == null) {
        await widget.trainerService.createTrainer(widget.user, draft);
      } else {
        await widget.trainerService.updateTrainer(widget.user, draft);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.trainer == null
                ? 'Trainer "${draft.fullName}" created successfully.'
                : 'Trainer "${draft.fullName}" updated successfully.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save trainer: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.trainer == null ? 'Add Trainer' : 'Edit Trainer'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Rohan Kulkarni',
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Full name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          hintText: 'trainer@example.com',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!RegExp(r'^[\w\.\-]+@[\w\-]+(\.[\w\-]+)+$')
                              .hasMatch(val.trim())) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+91 98201 00000',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _expertiseController,
                  decoration: const InputDecoration(
                    labelText: 'Areas of Expertise / Subjects',
                    hintText:
                        'e.g. Flutter, Dart, Node.js (comma-separated)',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qualificationsController,
                        decoration: const InputDecoration(
                          labelText: 'Qualifications',
                          hintText: 'e.g. M.Tech, NID, B.E.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        controller: _experienceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Experience (Years)',
                        ),
                        validator: (val) {
                          if (val != null && val.trim().isNotEmpty) {
                            final years = int.tryParse(val.trim());
                            if (years == null || years < 0) {
                              return 'Enter valid years';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 6),
                const Text(
                  'Availability & Scheduling',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: TrainerAvailability.allWeekdays.map((day) {
                    final isSelected = _selectedWeekdays.contains(day);
                    return FilterChip(
                      label: Text(day.substring(0, 3)),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedWeekdays.add(day);
                          } else {
                            _selectedWeekdays.remove(day);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _preferredTimeController,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Teaching Hours',
                    hintText: 'e.g. Morning (09:00 AM - 01:00 PM)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unavailableNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Unavailable Periods / Days',
                    hintText: 'e.g. Unavailable on Sunday afternoons',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _generalNotesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Scheduling Notes',
                    hintText:
                        'Special cohort preferences, lab session requirements…',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (val) => setState(() => _status = val ?? 'active'),
                ),
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
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(widget.trainer == null ? 'Create Trainer' : 'Save Changes'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TRAINER DETAIL DIALOG
// ---------------------------------------------------------------------------

class _TrainerDetailDialog extends StatelessWidget {
  const _TrainerDetailDialog({
    required this.trainer,
    required this.batches,
    required this.user,
    required this.canManage,
    required this.trainerService,
    required this.batchService,
    required this.onEdit,
  });

  final Trainer trainer;
  final List<Batch> batches;
  final AppUser user;
  final bool canManage;
  final TrainerService trainerService;
  final BatchService batchService;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final assignedBatches =
        batches.where((b) => b.trainerId == trainer.id).toList();

    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE8F0FF),
            child: Text(
              trainer.fullName.isNotEmpty
                  ? trainer.fullName.substring(0, 1).toUpperCase()
                  : 'T',
              style: const TextStyle(
                color: AppTheme.brand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trainer.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'ID: ${trainer.id}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusBadge(isActive: trainer.isActive),
        ],
      ),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contact details
              Card(
                color: const Color(0xFFF8FAFC),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.blueGrey.shade100),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              trainer.email,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Phone',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              trainer.phone.isNotEmpty ? trainer.phone : '—',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Experience',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${trainer.experienceYears} Years',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Qualifications & Expertise
              if (trainer.qualifications.isNotEmpty) ...[
                const Text(
                  'Qualifications',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 4),
                Text(trainer.qualifications),
                const SizedBox(height: 12),
              ],

              const Text(
                'Areas of Expertise',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              if (trainer.expertise.isEmpty)
                const Text('None specified')
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: trainer.expertise.map((exp) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        exp,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),

              // Availability Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 18, color: AppTheme.brand),
                        SizedBox(width: 6),
                        Text(
                          'Availability & Schedule Details',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Weekdays: ${trainer.availability.weekdays.join(", ")}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (trainer.availability.preferredTimeRange.isNotEmpty)
                      Text(
                        'Preferred Times: ${trainer.availability.preferredTimeRange}',
                      ),
                    if (trainer.availability.unavailableNotes.isNotEmpty)
                      Text(
                        'Unavailable: ${trainer.availability.unavailableNotes}',
                        style: const TextStyle(color: Color(0xFF991B1B)),
                      ),
                    if (trainer.availability.generalNotes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Notes: ${trainer.availability.generalNotes}',
                          style: TextStyle(color: Colors.blueGrey.shade700),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Assigned Batches Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assigned Batches (${assignedBatches.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.ink,
                    ),
                  ),
                  if (canManage && trainer.isActive)
                    TextButton.icon(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => _AssignBatchDialog(
                            trainer: trainer,
                            batches: batches,
                            user: user,
                            trainerService: trainerService,
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Assign to Batch'),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (assignedBatches.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Center(
                    child: Text(
                      'No batches are currently assigned to this trainer.',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                  ),
                )
              else
                ...assignedBatches.map((b) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                '${b.courseName} • ${b.scheduleDescription}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: b.isArchived
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                b.isArchived ? 'Archived' : 'Active Batch',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: b.isArchived
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF047857),
                                ),
                              ),
                            ),
                            if (canManage) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.link_off_rounded,
                                    size: 18),
                                tooltip: 'Unassign from batch',
                                onPressed: () async {
                                  try {
                                    await trainerService
                                        .unassignTrainerFromBatch(
                                      user,
                                      batchId: b.id,
                                    );
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Unassigned ${trainer.fullName} from ${b.name}',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('Failed: $e'),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        if (canManage)
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Details'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ASSIGN BATCH DIALOG
// ---------------------------------------------------------------------------

class _AssignBatchDialog extends StatefulWidget {
  const _AssignBatchDialog({
    required this.trainer,
    required this.batches,
    required this.user,
    required this.trainerService,
  });

  final Trainer trainer;
  final List<Batch> batches;
  final AppUser user;
  final TrainerService trainerService;

  @override
  State<_AssignBatchDialog> createState() => _AssignBatchDialogState();
}

class _AssignBatchDialogState extends State<_AssignBatchDialog> {
  String? _selectedBatchId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final activeBatches =
        widget.batches.where((b) => !b.isArchived).toList();
    if (activeBatches.isNotEmpty) {
      _selectedBatchId = activeBatches.first.id;
    }
  }

  Future<void> _submit() async {
    if (_isSaving || _selectedBatchId == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.trainerService.assignTrainerToBatch(
        widget.user,
        batchId: _selectedBatchId!,
        trainerId: widget.trainer.id,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Trainer "${widget.trainer.fullName}" successfully assigned to batch.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign batch: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeBatches =
        widget.batches.where((b) => !b.isArchived).toList();

    final selectedBatch = activeBatches.cast<Batch?>().firstWhere(
          (b) => b?.id == _selectedBatchId,
          orElse: () => null,
        );

    return AlertDialog(
      title: Text('Assign ${widget.trainer.fullName} to Batch'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select an active course batch to assign this trainer as lead instructor:',
            ),
            const SizedBox(height: 14),
            if (activeBatches.isEmpty)
              const Text('No active batches available.')
            else ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedBatchId,
                decoration: const InputDecoration(labelText: 'Select Batch'),
                items: activeBatches.map((b) {
                  return DropdownMenuItem(
                    value: b.id,
                    child: Text('${b.name} (${b.courseName})'),
                  );
                }).toList(),
                onChanged: _isSaving
                    ? null
                    : (val) => setState(() => _selectedBatchId = val),
              ),
              if (selectedBatch != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Course: ${selectedBatch.courseName}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('Schedule: ${selectedBatch.scheduleDescription}'),
                      const SizedBox(height: 4),
                      Text(
                        selectedBatch.trainerId.isNotEmpty
                            ? 'Currently assigned to: ${selectedBatch.trainerName}'
                            : 'Currently unassigned',
                        style: TextStyle(
                          fontSize: 12,
                          color: selectedBatch.trainerId == widget.trainer.id
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _selectedBatchId == null ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Confirm Assignment'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DEACTIVATE CONFIRMATION DIALOG WITH BATCH WARNING
// ---------------------------------------------------------------------------

class _DeactivateConfirmationDialog extends StatefulWidget {
  const _DeactivateConfirmationDialog({
    required this.trainer,
    required this.assignedBatches,
  });

  final Trainer trainer;
  final List<Batch> assignedBatches;

  @override
  State<_DeactivateConfirmationDialog> createState() =>
      _DeactivateConfirmationDialogState();
}

class _DeactivateConfirmationDialogState
    extends State<_DeactivateConfirmationDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final hasActiveBatches = widget.assignedBatches.isNotEmpty;

    return AlertDialog(
      title: const Text('Deactivate Trainer'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to deactivate "${widget.trainer.fullName}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Historical attendance and student records will not be deleted.',
              style: TextStyle(fontSize: 13),
            ),
            if (hasActiveBatches) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFB45309), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Active Batch Assignment Warning',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This trainer is currently assigned to ${widget.assignedBatches.length} active batch(es):',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...widget.assignedBatches.map(
                      (b) => Text(
                        '• ${b.name} (${b.courseName})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                title: const Text(
                  'I acknowledge these batches will have an inactive instructor until reassigned.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (val) =>
                    setState(() => _acknowledged = val ?? false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: hasActiveBatches && !_acknowledged
              ? null
              : () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: const Text('Deactivate Trainer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// FEEDBACK & HELPER WIDGETS
// ---------------------------------------------------------------------------

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
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
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFFF1F0),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFCF1322)),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFCF1322),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(color: Color(0xFF5C0011))),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
