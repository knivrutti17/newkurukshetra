import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/student_alert.dart';
import '../../../data/services/student_risk_alert_service.dart';

class StudentRiskAlertsScreen extends StatefulWidget {
  const StudentRiskAlertsScreen({
    required this.user,
    this.riskAlertService,
    this.firebaseSetupMessage,
    super.key,
  });

  final AppUser user;
  final StudentRiskAlertService? riskAlertService;
  final String? firebaseSetupMessage;

  @override
  State<StudentRiskAlertsScreen> createState() =>
      _StudentRiskAlertsScreenState();
}

class _StudentRiskAlertsScreenState extends State<StudentRiskAlertsScreen> {
  late final StudentRiskAlertService _service;
  late Stream<List<StudentAlert>> _alerts;
  late Future<DateTime?> _lastScan;
  final _searchController = TextEditingController();
  StudentAlertType? _type;
  StudentAlertSeverity? _severity;
  StudentAlertStatus? _status;
  String? _batchId;
  _DateRangeFilter _dateRange = _DateRangeFilter.all;
  bool _runningScan = false;

  @override
  void initState() {
    super.initState();
    _service = widget.riskAlertService ?? StudentRiskAlertService();
    _alerts = _service.watchForUser(widget.user);
    _lastScan = _service.getLastSuccessfulScan();
    _searchController.addListener(_refreshFilters);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshFilters)
      ..dispose();
    super.dispose();
  }

  void _refreshFilters() => setState(() {});

  Future<void> _confirmRiskScan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.manage_search_rounded, color: AppTheme.brand),
        title: const Text('Refresh Risk Scan?'),
        content: const Text(
          'This reads the institute’s existing students, attendance, instalment and payment records, then creates or updates active indicators. Resolved and dismissed alerts are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Run scan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _runningScan = true);
    try {
      final result = await _service.runScan(widget.user);
      if (!mounted) return;
      setState(() => _lastScan = Future.value(result.completedAt));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Risk scan completed: ${result.created} new, ${result.updated} updated, ${result.errors} errors${result.preservedClosed == 0 ? '' : ', ${result.preservedClosed} closed alert(s) preserved'}.',
          ),
          backgroundColor: const Color(0xFF067647),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Risk scan failed (1 error): ${_friendlyError(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _runningScan = false);
    }
  }

  List<StudentAlert> _filtered(List<StudentAlert> alerts) {
    final term = _searchController.text.trim().toLowerCase();
    final cutoff = switch (_dateRange) {
      _DateRangeFilter.all => null,
      _DateRangeFilter.sevenDays => DateTime.now().subtract(
        const Duration(days: 7),
      ),
      _DateRangeFilter.thirtyDays => DateTime.now().subtract(
        const Duration(days: 30),
      ),
      _DateRangeFilter.ninetyDays => DateTime.now().subtract(
        const Duration(days: 90),
      ),
    };
    return alerts.where((alert) {
      final matchesSearch =
          term.isEmpty ||
          alert.studentName.toLowerCase().contains(term) ||
          alert.studentId.toLowerCase().contains(term) ||
          alert.reason.toLowerCase().contains(term);
      return matchesSearch &&
          (_type == null || alert.alertType == _type) &&
          (_severity == null || alert.severity == _severity) &&
          (_status == null || alert.status == _status) &&
          (_batchId == null || alert.batchId == _batchId) &&
          (cutoff == null || alert.createdAt.isAfter(cutoff));
    }).toList();
  }

  void _openDetails(StudentAlert alert) {
    showDialog<void>(
      context: context,
      builder: (context) => _AlertDetailDialog(
        alert: alert,
        user: widget.user,
        service: _service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StudentAlert>>(
    stream: _alerts,
    builder: (context, snapshot) {
      final alerts = snapshot.data ?? const <StudentAlert>[];
      final filtered = _filtered(alerts);
      final batches = <String, String>{
        for (final alert in alerts) alert.batchId: alert.batchName,
      };
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  canRefresh: _service.canRunScan(widget.user),
                  runningScan: _runningScan,
                  onRefresh: _confirmRiskScan,
                  lastScan: _lastScan,
                ),
                if (widget.firebaseSetupMessage != null) ...[
                  const SizedBox(height: 16),
                  _SetupWarning(message: widget.firebaseSetupMessage!),
                ],
                const SizedBox(height: 22),
                _SummaryCards(alerts: alerts),
                const SizedBox(height: 22),
                _FilterPanel(
                  searchController: _searchController,
                  type: _type,
                  severity: _severity,
                  status: _status,
                  batchId: _batchId,
                  batches: batches,
                  dateRange: _dateRange,
                  onType: (value) => setState(() => _type = value),
                  onSeverity: (value) => setState(() => _severity = value),
                  onStatus: (value) => setState(() => _status = value),
                  onBatch: (value) => setState(() => _batchId = value),
                  onDateRange: (value) => setState(() => _dateRange = value),
                  onClear: () => setState(() {
                    _type = null;
                    _severity = null;
                    _status = null;
                    _batchId = null;
                    _dateRange = _DateRangeFilter.all;
                    _searchController.clear();
                  }),
                ),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  _ErrorState(message: _friendlyError(snapshot.error!))
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const _LoadingState()
                else if (filtered.isEmpty)
                  _EmptyState(hasFilters: alerts.isNotEmpty)
                else
                  _AlertList(alerts: filtered, onOpen: _openDetails),
                const SizedBox(height: 14),
                const _IndicatorNote(),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canRefresh,
    required this.runningScan,
    required this.onRefresh,
    required this.lastScan,
  });

  final bool canRefresh;
  final bool runningScan;
  final VoidCallback onRefresh;
  final Future<DateTime?> lastScan;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: constraints.maxWidth > 560
              ? constraints.maxWidth - (canRefresh ? 230 : 0)
              : constraints.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student Risk Alerts & Follow-up',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Explainable indicators from recorded attendance and fee data for human review.',
              ),
              const SizedBox(height: 5),
              FutureBuilder<DateTime?>(
                future: lastScan,
                builder: (context, snapshot) => Text(
                  snapshot.connectionState == ConnectionState.waiting
                      ? 'Checking last successful scan…'
                      : snapshot.data == null
                      ? 'No successful risk scan recorded yet.'
                      : 'Last successful scan: ${_formatDateTime(snapshot.data!)}',
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (canRefresh)
          FilledButton.icon(
            onPressed: runningScan ? null : onRefresh,
            icon: runningScan
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(runningScan ? 'Scanning…' : 'Refresh Risk Scan'),
          ),
      ],
    ),
  );
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.alerts});

  final List<StudentAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final items = [
      _Summary(
        'New alerts',
        alerts.where((a) => a.status == StudentAlertStatus.newAlert).length,
        Icons.mark_email_unread_outlined,
        const Color(0xFF2563EB),
      ),
      _Summary(
        'High priority',
        alerts
            .where(
              (a) =>
                  a.severity == StudentAlertSeverity.high && !a.status.isClosed,
            )
            .length,
        Icons.priority_high_rounded,
        const Color(0xFFB42318),
      ),
      _Summary(
        'Awaiting follow-up',
        alerts.where((a) => a.status == StudentAlertStatus.followUp).length,
        Icons.forum_outlined,
        const Color(0xFFD97706),
      ),
      _Summary(
        'Resolved',
        alerts.where((a) => a.status == StudentAlertStatus.resolved).length,
        Icons.task_alt_rounded,
        const Color(0xFF067647),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((item) => SizedBox(width: width, child: _SummaryCard(item)))
              .toList(),
        );
      },
    );
  }
}

class _Summary {
  const _Summary(this.label, this.count, this.icon, this.color);
  final String label;
  final int count;
  final IconData icon;
  final Color color;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.summary);
  final _Summary summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: summary.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(summary.icon, color: summary.color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${summary.count}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  summary.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.searchController,
    required this.type,
    required this.severity,
    required this.status,
    required this.batchId,
    required this.batches,
    required this.dateRange,
    required this.onType,
    required this.onSeverity,
    required this.onStatus,
    required this.onBatch,
    required this.onDateRange,
    required this.onClear,
  });

  final TextEditingController searchController;
  final StudentAlertType? type;
  final StudentAlertSeverity? severity;
  final StudentAlertStatus? status;
  final String? batchId;
  final Map<String, String> batches;
  final _DateRangeFilter dateRange;
  final ValueChanged<StudentAlertType?> onType;
  final ValueChanged<StudentAlertSeverity?> onSeverity;
  final ValueChanged<StudentAlertStatus?> onStatus;
  final ValueChanged<String?> onBatch;
  final ValueChanged<_DateRangeFilter> onDateRange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Card(
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
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search student, ID or reason',
              ),
            ),
          ),
          _dropdown<StudentAlertType>(
            context,
            width: 180,
            value: type,
            hint: 'Alert type',
            items: StudentAlertType.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: onType,
          ),
          _dropdown<StudentAlertSeverity>(
            context,
            width: 150,
            value: severity,
            hint: 'Severity',
            items: StudentAlertSeverity.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: onSeverity,
          ),
          _dropdown<StudentAlertStatus>(
            context,
            width: 180,
            value: status,
            hint: 'Alert status',
            items: StudentAlertStatus.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: onStatus,
          ),
          _dropdown<String>(
            context,
            width: 175,
            value: batchId,
            hint: 'Batch',
            items: batches.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value.isEmpty ? e.key : e.value,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onBatch,
          ),
          _dropdown<_DateRangeFilter>(
            context,
            width: 170,
            value: dateRange,
            hint: 'Date range',
            items: _DateRangeFilter.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) onDateRange(value);
            },
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear'),
          ),
        ],
      ),
    ),
  );

  Widget _dropdown<T>(
    BuildContext context, {
    required double width,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        hintText: hint,
      ),
      items: [
        DropdownMenuItem<T>(value: null, child: Text('All $hint')),
        ...items,
      ],
      onChanged: onChanged,
    ),
  );
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.alerts, required this.onOpen});
  final List<StudentAlert> alerts;
  final ValueChanged<StudentAlert> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 900
        ? _AlertTable(alerts: alerts, onOpen: onOpen)
        : Column(
            children: alerts
                .map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AlertCard(alert: alert, onOpen: onOpen),
                  ),
                )
                .toList(),
          ),
  );
}

class _AlertTable extends StatelessWidget {
  const _AlertTable({required this.alerts, required this.onOpen});
  final List<StudentAlert> alerts;
  final ValueChanged<StudentAlert> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMinHeight: 72,
        dataRowMaxHeight: 80,
        columnSpacing: 24,
        headingRowColor: WidgetStatePropertyAll(const Color(0xFFF8FAFD)),
        columns: const [
          DataColumn(label: Text('STUDENT')),
          DataColumn(label: Text('BATCH')),
          DataColumn(label: Text('ALERT')),
          DataColumn(label: Text('EXPLANATION')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('CREATED')),
          DataColumn(label: Text('')),
        ],
        rows: alerts
            .map(
              (alert) => DataRow(
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          alert.studentName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          alert.studentId,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(
                        alert.batchName.isEmpty ? '—' : alert.batchName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 170,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            alert.alertType.label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          _SeverityChip(severity: alert.severity),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: Text(
                        alert.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(_StatusChip(status: alert.status)),
                  DataCell(Text(_formatDate(alert.createdAt))),
                  DataCell(
                    OutlinedButton(
                      onPressed: () => onOpen(alert),
                      child: const Text('Open'),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onOpen});
  final StudentAlert alert;
  final ValueChanged<StudentAlert> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
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
                      alert.studentName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${alert.studentId} · ${alert.batchName.isEmpty ? 'No batch' : alert.batchName}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: alert.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text(alert.alertType.label)),
              _SeverityChip(severity: alert.severity),
            ],
          ),
          const SizedBox(height: 10),
          Text(alert.reason),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Created ${_formatDate(alert.createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => onOpen(alert),
                child: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.severity});
  final StudentAlertSeverity severity;
  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      StudentAlertSeverity.low => const Color(0xFF2563EB),
      StudentAlertSeverity.medium => const Color(0xFFD97706),
      StudentAlertSeverity.high => const Color(0xFFB42318),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        severity.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final StudentAlertStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StudentAlertStatus.newAlert => const Color(0xFF2563EB),
      StudentAlertStatus.inReview => const Color(0xFF7C3AED),
      StudentAlertStatus.followUp => const Color(0xFFD97706),
      StudentAlertStatus.resolved => const Color(0xFF067647),
      StudentAlertStatus.dismissed => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AlertDetailDialog extends StatefulWidget {
  const _AlertDetailDialog({
    required this.alert,
    required this.user,
    required this.service,
  });
  final StudentAlert alert;
  final AppUser user;
  final StudentRiskAlertService service;
  @override
  State<_AlertDetailDialog> createState() => _AlertDetailDialogState();
}

class _AlertDetailDialogState extends State<_AlertDetailDialog> {
  late StudentAlertStatus _status;
  late TextEditingController _note;
  late TextEditingController _assignee;
  late TextEditingController _closureReason;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.alert.status;
    _note = TextEditingController();
    _assignee = TextEditingController(text: widget.alert.assignedTo ?? '');
    _closureReason = TextEditingController(
      text: widget.alert.closureReason ?? '',
    );
  }

  @override
  void dispose() {
    _note.dispose();
    _assignee.dispose();
    _closureReason.dispose();
    super.dispose();
  }

  List<StudentAlertStatus> get _availableStatuses {
    if (widget.service.canClose(widget.user)) return StudentAlertStatus.values;
    if (widget.alert.status.isClosed) return [widget.alert.status];
    return <StudentAlertStatus>{
      widget.alert.status,
      StudentAlertStatus.inReview,
      StudentAlertStatus.followUp,
    }.toList();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.updateFollowUp(
        user: widget.user,
        alert: widget.alert,
        status: _status,
        note: _note.text,
        assignedTo: widget.service.canAssign(widget.user)
            ? _assignee.text
            : null,
        closureReason: _status.isClosed ? _closureReason.text : null,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert follow-up saved.'),
            backgroundColor: Color(0xFF067647),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.alert.studentName),
              Text(
                widget.alert.alertType.label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _SeverityChip(severity: widget.alert.severity),
      ],
    ),
    content: SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Student and alert'),
            _KeyValueGrid(
              items: {
                'Student ID': widget.alert.studentId,
                'Batch': widget.alert.batchName.isEmpty
                    ? '—'
                    : widget.alert.batchName,
                'Created': _formatDateTime(widget.alert.createdAt),
                'Last updated': _formatDateTime(widget.alert.updatedAt),
                'Assigned to': widget.alert.assignedTo?.isEmpty ?? true
                    ? 'Unassigned'
                    : widget.alert.assignedTo!,
              },
            ),
            const SizedBox(height: 18),
            _SectionTitle('Why this indicator exists'),
            Text(widget.alert.reason),
            const SizedBox(height: 9),
            _EvidenceCard(evidence: widget.alert.evidence),
            const SizedBox(height: 18),
            _SectionTitle('Follow-up'),
            DropdownButtonFormField<StudentAlertStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _availableStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null) setState(() => _status = v);
                    },
            ),
            const SizedBox(height: 10),
            if (widget.service.canAssign(widget.user)) ...[
              TextField(
                controller: _assignee,
                decoration: const InputDecoration(
                  labelText: 'Follow-up owner',
                  hintText: 'Staff name or ID',
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Add follow-up note',
                hintText: 'Record what was reviewed or the next action.',
              ),
            ),
            if (_status.isClosed) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _closureReason,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resolution / dismissal reason',
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SectionTitle('History'),
            if (widget.alert.followUpHistory.isEmpty)
              Text(
                'No follow-up recorded yet.',
                style: TextStyle(color: Colors.blueGrey.shade600),
              )
            else
              ...widget.alert.followUpHistory.reversed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notes_rounded),
                    title: Text(entry.note),
                    subtitle: Text(
                      '${entry.actorName.isEmpty ? entry.actorId : entry.actorName} · ${_formatDateTime(entry.at)}${entry.status == null ? '' : ' · ${entry.status!.label}'}',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save follow-up'),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
    ),
  );
}

class _KeyValueGrid extends StatelessWidget {
  const _KeyValueGrid({required this.items});

  final Map<String, String> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 12,
    children: items.entries
        .map(
          (entry) => SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.blueGrey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(entry.value),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.evidence});
  final Map<String, dynamic> evidence;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFD),
      border: Border.all(color: const Color(0xFFE6EAF2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: evidence.isEmpty
        ? const Text('No additional evidence was saved.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: evidence.entries
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${_titleize(e.key)}: ${_formatEvidence(e.value)}',
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(50),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters});
  final bool hasFilters;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 42, color: AppTheme.brand),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'No alerts match these filters'
                  : 'No risk alerts yet',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters ? 'Try clearing a filter or changing the search.' : 'Owners can run Refresh Risk Scan to evaluate recorded institute data.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Risk alerts could not be loaded',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SetupWarning extends StatelessWidget {
  const _SetupWarning({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF7A4B00)),
          ),
        ),
      ],
    ),
  );
}

class _IndicatorNote extends StatelessWidget {
  const _IndicatorNote();
  @override
  Widget build(BuildContext context) => Text(
    'Alerts are explainable indicators for human review, not definitive predictions that a student will drop out.',
    style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
  );
}

enum _DateRangeFilter { all, sevenDays, thirtyDays, ninetyDays }

extension on _DateRangeFilter {
  String get label => switch (this) {
    _DateRangeFilter.all => 'All dates',
    _DateRangeFilter.sevenDays => 'Last 7 days',
    _DateRangeFilter.thirtyDays => 'Last 30 days',
    _DateRangeFilter.ninetyDays => 'Last 90 days',
  };
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _titleize(String value) {
  final spaced = value
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
      .trim();
  if (spaced.isEmpty) {
    return spaced;
  }
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _formatEvidence(dynamic value) {
  if (value is DateTime) {
    return _formatDate(value);
  }
  if (value is Timestamp) {
    return _formatDate(value.toDate());
  }
  if (value is List) {
    return value.map(_formatEvidence).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map(
          (e) => '${_titleize(e.key.toString())}: ${_formatEvidence(e.value)}',
        )
        .join('; ');
  }
  if (value is double) {
    return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
  }
  return '$value';
}

String _friendlyError(Object error) {
  if (error is FirebaseException) {
    return 'Firestore ${error.code}: ${error.message ?? 'check Firebase setup and security rules.'}';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
