import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/fee_installment.dart';
import '../../../data/models/payment.dart';
import '../../../data/models/student.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/fee_seed_service.dart';
import '../../../data/services/fee_service.dart';
import '../../../data/services/student_service.dart';

class FeeManagementScreen extends StatefulWidget {
  const FeeManagementScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.feeService,
    this.feeSeedService,
    this.studentService,
    this.batchService,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final FeeService? feeService;
  final FeeSeedService? feeSeedService;
  final StudentService? studentService;
  final BatchService? batchService;

  @override
  State<FeeManagementScreen> createState() => _FeeManagementScreenState();
}

class _FeeManagementScreenState extends State<FeeManagementScreen> {
  late final FeeService _feeService;
  FeeSeedService? _seedService;
  StudentService? _studentService;
  BatchService? _batchService;

  late Stream<List<FeeInstallment>> _installmentsStream;
  late Stream<List<Student>> _studentsStream;
  late Stream<List<Batch>> _batchesStream;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedBatchFilter;
  String _selectedStatusFilter = 'all';
  String _selectedDateFilter = 'all';

  bool _isSeeding = false;

  bool get _canManage => _feeService.canManage(widget.user);
  bool get _canView => _feeService.canView(widget.user);
  bool get _isTrainer => widget.user.role == AppRole.trainer;
  bool get _isCounselor => widget.user.role == AppRole.counselor;

  @override
  void initState() {
    super.initState();
    _feeService = widget.feeService ?? FeeService();

    if (_canView) {
      _seedService = widget.feeSeedService ?? FeeSeedService();
      _studentService = widget.studentService ?? StudentService();
      _batchService = widget.batchService ?? BatchService();

      _installmentsStream = _feeService.watchInstallmentsForUser(widget.user);
      _studentsStream = _studentService!.watchForUser(widget.user);
      _batchesStream = _batchService!.watchForUser(widget.user);
    } else {
      _installmentsStream = Stream.value(const <FeeInstallment>[]);
      _studentsStream = Stream.value(const <Student>[]);
      _batchesStream = Stream.value(const <Batch>[]);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadInstallments() {
    setState(() {
      _installmentsStream = _feeService.watchInstallmentsForUser(widget.user);
    });
  }

  Future<void> _loadSampleFees() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    try {
      final seedService =
          _seedService ?? widget.feeSeedService ?? FeeSeedService();
      final result = await seedService.loadSampleFees();
      if (!mounted) return;
      if (result.alreadyHadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample data check: Fee instalments already exist in Firestore.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample fees loaded: ${result.installmentsCreated} instalments and ${result.paymentsCreated} payments created.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sample fees: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _openAddInstallmentDialog(List<Student> students) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddInstallmentDialog(
        user: widget.user,
        students: students,
        feeService: _feeService,
      ),
    );
  }

  void _openRecordPaymentDialog(FeeInstallment installment) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecordPaymentDialog(
        user: widget.user,
        installment: installment,
        feeService: _feeService,
      ),
    );
  }

  void _openPaymentHistoryDialog(FeeInstallment installment) {
    showDialog<void>(
      context: context,
      builder: (context) => _PaymentHistoryDialog(
        user: widget.user,
        installment: installment,
        feeService: _feeService,
      ),
    );
  }

  List<FeeInstallment> _applyFilters(List<FeeInstallment> list) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();

    return list.where((item) {
      final matchesSearch =
          query.isEmpty ||
          item.studentName.toLowerCase().contains(query) ||
          item.studentId.toLowerCase().contains(query) ||
          item.batchId.toLowerCase().contains(query);

      final matchesBatch =
          _selectedBatchFilter == null || item.batchId == _selectedBatchFilter;

      final derivedStatus = FeeInstallment.deriveStatus(
        amountDue: item.amountDue,
        paidAmount: item.paidAmount,
        dueDate: item.dueDate,
        asOf: now,
      );

      final matchesStatus = switch (_selectedStatusFilter) {
        'pending' => derivedStatus == 'pending',
        'partiallyPaid' => derivedStatus == 'partiallyPaid',
        'paid' => derivedStatus == 'paid',
        'overdue' => derivedStatus == 'overdue',
        _ => true,
      };

      final matchesDate = switch (_selectedDateFilter) {
        'overdue' => derivedStatus == 'overdue',
        'thisMonth' =>
            item.dueDate.year == now.year && item.dueDate.month == now.month,
        'next30Days' =>
            item.dueDate.isAfter(now.subtract(const Duration(days: 1))) &&
            item.dueDate.isBefore(now.add(const Duration(days: 30))),
        _ => true,
      };

      return matchesSearch && matchesBatch && matchesStatus && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isTrainer) {
      return const _RestrictedAccessPage(
        title: 'Fee access not permitted for Trainers',
        message:
            'Trainers do not have access to fee amounts, instalment schedules, or payment records.',
        icon: Icons.lock_outline_rounded,
      );
    }

    if (_isCounselor) {
      return const _RestrictedAccessPage(
        title: 'Financial details restricted',
        message:
            'Counselors are not authorized to view or manage institute fee instalments by default.',
        icon: Icons.shield_outlined,
      );
    }

    if (!_canView) {
      return const _RestrictedAccessPage(
        title: 'Access Restricted',
        message: 'Your role does not have permission to view fee records.',
        icon: Icons.lock_outline_rounded,
      );
    }

    return StreamBuilder<List<Student>>(
      stream: _studentsStream,
      initialData: const <Student>[],
      builder: (context, studentsSnapshot) => StreamBuilder<List<Batch>>(
        stream: _batchesStream,
        initialData: const <Batch>[],
        builder: (context, batchesSnapshot) =>
            StreamBuilder<List<FeeInstallment>>(
              stream: _installmentsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorStateCard(
                    title: 'Unable to load fee instalments',
                    message: snapshot.error.toString(),
                    onRetry: _reloadInstallments,
                  );
                }
                if (!snapshot.hasData) {
                  return const _LoadingCard(label: 'Loading fee records…');
                }

                final installments = snapshot.data!;
                final students = studentsSnapshot.data ?? const <Student>[];
                final batches = batchesSnapshot.data ?? const <Batch>[];
                final summary = _feeService.calculateSummary(installments);
                final filtered = _applyFilters(installments);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Header(
                          canManage: _canManage,
                          isOwner: widget.user.role == AppRole.owner,
                          isSeeding: _isSeeding,
                          onAddInstallment: () =>
                              _openAddInstallmentDialog(students),
                          onLoadSamples: _loadSampleFees,
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
                        _SummaryCardsRow(summary: summary),
                        const SizedBox(height: 24),
                        _FilterBar(
                          searchController: _searchController,
                          batches: batches,
                          selectedBatch: _selectedBatchFilter,
                          selectedStatus: _selectedStatusFilter,
                          selectedDateRange: _selectedDateFilter,
                          onSearchChanged: () => setState(() {}),
                          onBatchChanged: (val) =>
                              setState(() => _selectedBatchFilter = val),
                          onStatusChanged: (val) => setState(
                            () => _selectedStatusFilter = val ?? 'all',
                          ),
                          onDateRangeChanged: (val) => setState(
                            () => _selectedDateFilter = val ?? 'all',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FeeTable(
                          installments: filtered,
                          canManage: _canManage,
                          onRecordPayment: _openRecordPaymentDialog,
                          onViewHistory: _openPaymentHistoryDialog,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER & NOTICES
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.canManage,
    required this.isOwner,
    required this.isSeeding,
    required this.onAddInstallment,
    required this.onLoadSamples,
  });

  final bool canManage;
  final bool isOwner;
  final bool isSeeding;
  final VoidCallback onAddInstallment;
  final VoidCallback onLoadSamples;

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
            'Fee & Instalment Management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track tuition dues, process student payments, and monitor outstanding balances.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          if (isOwner)
            OutlinedButton.icon(
              onPressed: isSeeding ? null : onLoadSamples,
              icon: isSeeding
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: Text(isSeeding ? 'Seeding fees…' : 'Load Sample Fees'),
            ),
          if (canManage)
            FilledButton.icon(
              onPressed: onAddInstallment,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Instalment'),
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
    final message = switch (role) {
      AppRole.owner =>
        'Owner access: Review financial summaries, create instalments, and record payments across the institute.',
      AppRole.accounts =>
        'Accounts Staff access: Create student fee instalments, record payments, and inspect collection history.',
      _ => 'Financial view is restricted.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppTheme.brand, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Note: Client-side role checks drive the demo UI. Production rules require custom auth claims issued by a trusted backend.',
                  style: TextStyle(color: Color(0xFF526277), fontSize: 11),
                ),
              ],
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
// SUMMARY CARDS
// ---------------------------------------------------------------------------

class _SummaryCardsRow extends StatelessWidget {
  const _SummaryCardsRow({required this.summary});

  final FeeSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      final cardWidth = isWide ? (constraints.maxWidth - 48) / 4 : 260.0;

      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _SummaryCard(
            title: 'Total Fees Due',
            amount: summary.totalDue,
            subtitle: 'Aggregate instalment receivables',
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.brand,
            width: cardWidth,
          ),
          _SummaryCard(
            title: 'Payments Received',
            amount: summary.totalPaid,
            subtitle: 'Verified receipts collected',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF047857),
            width: cardWidth,
          ),
          _SummaryCard(
            title: 'Outstanding Balance',
            amount: summary.outstandingBalance,
            subtitle: 'Remaining balance to collect',
            icon: Icons.pending_actions_outlined,
            color: const Color(0xFFD97706),
            width: cardWidth,
          ),
          _SummaryCard(
            title: 'Overdue Instalments',
            amount: summary.overdueAmount,
            subtitle: '${summary.overdueCount} overdue instalments',
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFB42318),
            width: cardWidth,
          ),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.width,
  });

  final String title;
  final double amount;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: .5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// FILTER BAR
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.batches,
    required this.selectedBatch,
    required this.selectedStatus,
    required this.selectedDateRange,
    required this.onSearchChanged,
    required this.onBatchChanged,
    required this.onStatusChanged,
    required this.onDateRangeChanged,
  });

  final TextEditingController searchController;
  final List<Batch> batches;
  final String? selectedBatch;
  final String selectedStatus;
  final String selectedDateRange;
  final VoidCallback onSearchChanged;
  final ValueChanged<String?> onBatchChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onDateRangeChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search student, ID, batch…',
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
            width: 220,
            child: DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: selectedBatch,
              decoration: const InputDecoration(
                labelText: 'Filter by Batch',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Batches')),
                ...batches.map(
                  (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
                ),
              ],
              onChanged: onBatchChanged,
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'partiallyPaid', child: Text('Partially Paid')),
                DropdownMenuItem(value: 'paid', child: Text('Fully Paid')),
                DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selectedDateRange,
              decoration: const InputDecoration(
                labelText: 'Due Date Filter',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Due Dates')),
                DropdownMenuItem(value: 'overdue', child: Text('Overdue Only')),
                DropdownMenuItem(value: 'thisMonth', child: Text('Due This Month')),
                DropdownMenuItem(value: 'next30Days', child: Text('Due in 30 Days')),
              ],
              onChanged: onDateRangeChanged,
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// FEE TABLE
// ---------------------------------------------------------------------------

class _FeeTable extends StatelessWidget {
  const _FeeTable({
    required this.installments,
    required this.canManage,
    required this.onRecordPayment,
    required this.onViewHistory,
  });

  final List<FeeInstallment> installments;
  final bool canManage;
  final ValueChanged<FeeInstallment> onRecordPayment;
  final ValueChanged<FeeInstallment> onViewHistory;

  @override
  Widget build(BuildContext context) {
    if (installments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 48,
                  color: AppTheme.brand,
                ),
                const SizedBox(height: 12),
                Text(
                  'No fee instalments match these filters.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Try modifying your search or click "Add Instalment" to create one.',
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF6F8FC)),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('STUDENT')),
            DataColumn(label: Text('COURSE / BATCH')),
            DataColumn(label: Text('INSTALMENT')),
            DataColumn(label: Text('DUE DATE')),
            DataColumn(label: Text('PAID')),
            DataColumn(label: Text('OUTSTANDING')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('ACTIONS')),
          ],
          rows: installments.map((item) {
            final derivedStatus = FeeInstallment.deriveStatus(
              amountDue: item.amountDue,
              paidAmount: item.paidAmount,
              dueDate: item.dueDate,
              asOf: now,
            );
            final hasBalance = item.outstandingBalance > 0;

            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.studentName.isNotEmpty
                            ? item.studentName
                            : item.studentId,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        item.studentId,
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.courseId.isNotEmpty ? item.courseId : '—'),
                      Text(
                        item.batchId.isNotEmpty ? item.batchId : '—',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    '₹${item.amountDue.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text(_formatDate(item.dueDate))),
                DataCell(
                  Text(
                    '₹${item.paidAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF047857)),
                  ),
                ),
                DataCell(
                  Text(
                    '₹${item.outstandingBalance.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: hasBalance
                          ? (derivedStatus == 'overdue'
                              ? const Color(0xFFB42318)
                              : AppTheme.ink)
                          : const Color(0xFF047857),
                    ),
                  ),
                ),
                DataCell(_PaymentStatusBadge(status: derivedStatus)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canManage && hasBalance)
                        FilledButton.tonal(
                          onPressed: () => onRecordPayment(item),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Record Payment'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.history_rounded, size: 20),
                        tooltip: 'Payment History',
                        onPressed: () => onViewHistory(item),
                      ),
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

class _PaymentStatusBadge extends StatelessWidget {
  const _PaymentStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, color, label) = switch (status) {
      'paid' => (const Color(0xFFECFDF3), const Color(0xFF047857), 'Paid'),
      'partiallyPaid' => (
        const Color(0xFFE0F2FE),
        const Color(0xFF0284C7),
        'Partial',
      ),
      'overdue' => (const Color(0xFFFEE4E2), const Color(0xFFB42318), 'Overdue'),
      _ => (const Color(0xFFFEF3C7), const Color(0xFFD97706), 'Pending'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ADD INSTALMENT DIALOG
// ---------------------------------------------------------------------------

class _AddInstallmentDialog extends StatefulWidget {
  const _AddInstallmentDialog({
    required this.user,
    required this.students,
    required this.feeService,
  });

  final AppUser user;
  final List<Student> students;
  final FeeService feeService;

  @override
  State<_AddInstallmentDialog> createState() => _AddInstallmentDialogState();
}

class _AddInstallmentDialogState extends State<_AddInstallmentDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedStudentId;
  late final TextEditingController _amountController;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    final activeStudents =
        widget.students.where((s) => s.status == 'active').toList();
    if (activeStudents.isNotEmpty) {
      _selectedStudentId = activeStudents.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Student? get _selectedStudent {
    if (_selectedStudentId == null) return null;
    return widget.students.cast<Student?>().firstWhere(
      (s) => s?.id == _selectedStudentId,
      orElse: () => null,
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    final student = _selectedStudent;
    if (student == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an active student.')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount greater than 0.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final draft = FeeInstallment(
        id: '',
        instituteId: student.instituteId,
        studentId: student.id,
        studentName: student.fullName,
        courseId: student.courseId,
        batchId: student.batchId,
        amountDue: amount,
        dueDate: _dueDate,
        createdAt: now,
        updatedAt: now,
        status: FeeInstallment.deriveStatus(
          amountDue: amount,
          paidAmount: 0.0,
          dueDate: _dueDate,
          asOf: now,
        ),
      );

      await widget.feeService.createInstallmentForUser(
        widget.user,
        draft,
        student: student,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Instalment of ₹${amount.toStringAsFixed(0)} created for ${student.fullName}.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create instalment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeStudents =
        widget.students.where((s) => s.status == 'active').toList();
    final student = _selectedStudent;

    return AlertDialog(
      title: const Text('Add Fee Instalment'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedStudentId,
                  decoration: const InputDecoration(labelText: 'Student *'),
                  items: activeStudents
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text('${s.fullName} (${s.id})'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (val) => setState(() => _selectedStudentId = val),
                  validator: (val) => val == null ? 'Student is required' : null,
                ),
                if (student != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Course: ${student.courseName.isNotEmpty ? student.courseName : student.courseId}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Batch: ${student.batchName.isNotEmpty ? student.batchName : student.batchId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Instalment Amount (₹) *',
                    prefixText: '₹ ',
                    hintText: 'e.g. 15000',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Amount is required';
                    }
                    final parsed = double.tryParse(val.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Must be greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDueDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due Date *',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(_formatDate(_dueDate)),
                  ),
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
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Create Instalment'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// RECORD PAYMENT DIALOG
// ---------------------------------------------------------------------------

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({
    required this.user,
    required this.installment,
    required this.feeService,
  });

  final AppUser user;
  final FeeInstallment installment;
  final FeeService feeService;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _refController;

  String _selectedMethod = 'UPI';
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.installment.outstandingBalance.toStringAsFixed(0),
    );
    _refController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _paymentDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount greater than 0.')),
      );
      return;
    }

    if ((amount * 100).round() > widget.installment.balancePaise) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment exceeds outstanding balance of ₹${widget.installment.outstandingBalance.toStringAsFixed(2)}.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payment = await widget.feeService.recordPaymentForUser(
        widget.user,
        installment: widget.installment,
        amount: amount,
        paymentMethod: _selectedMethod,
        referenceNumber: _refController.text.trim(),
        paymentDate: _paymentDate,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment of ₹${payment.amount.toStringAsFixed(0)} recorded successfully.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record payment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.installment;

    return AlertDialog(
      title: const Text('Record Payment'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Due: ₹${item.amountDue.toStringAsFixed(0)}  ·  Paid: ₹${item.paidAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Remaining Balance: ₹${item.outstandingBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB42318),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Payment Amount (₹) *',
                    prefixText: '₹ ',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Amount is required';
                    }
                    final p = double.tryParse(val.trim());
                    if (p == null || p <= 0) return 'Must be > 0';
                    if ((p * 100).round() > item.balancePaise) {
                      return 'Exceeds balance ₹${item.outstandingBalance.toStringAsFixed(2)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedMethod,
                  decoration: const InputDecoration(labelText: 'Payment Method *'),
                  items: Payment.paymentMethods
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: _isSaving ? null : (val) => setState(() => _selectedMethod = val ?? 'UPI'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _refController,
                  decoration: const InputDecoration(
                    labelText: 'Reference / Transaction ID (Optional)',
                    hintText: 'e.g. UTR / Receipt / Cheque No.',
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickPaymentDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Payment Date',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(_formatDate(_paymentDate)),
                  ),
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
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Confirm Payment'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PAYMENT HISTORY DIALOG
// ---------------------------------------------------------------------------

class _PaymentHistoryDialog extends StatelessWidget {
  const _PaymentHistoryDialog({
    required this.user,
    required this.installment,
    required this.feeService,
  });

  final AppUser user;
  final FeeInstallment installment;
  final FeeService feeService;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.history_rounded, color: AppTheme.brand),
        const SizedBox(width: 8),
        Text('Payment History: ${installment.studentName}'),
      ],
    ),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Due: ₹${installment.amountDue.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Due Date: ${_formatDate(installment.dueDate)}',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total Paid: ₹${installment.paidAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Remaining: ₹${installment.outstandingBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: installment.outstandingBalance > 0
                              ? const Color(0xFFB42318)
                              : const Color(0xFF047857),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Recorded Transactions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Payment>>(
              stream: feeService.watchPaymentsForInstallment(
                user,
                installment.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading payments: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final payments = snapshot.data!;
                if (payments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No payments recorded for this instalment yet.'),
                    ),
                  );
                }

                return Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(1.4),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.6),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                      children: [
                        _th('DATE'),
                        _th('AMOUNT'),
                        _th('METHOD'),
                        _th('REFERENCE'),
                      ],
                    ),
                    ...payments.map(
                      (p) => TableRow(
                        children: [
                          _td(_formatDate(p.paymentDate)),
                          _td('₹${p.amount.toStringAsFixed(0)}', bold: true),
                          _td(p.paymentMethod),
                          _td(p.referenceNumber ?? '—'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _th(String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
    ),
  );

  Widget _td(String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontSize: 12,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// RESTRICTED & COMMON WIDGETS
// ---------------------------------------------------------------------------

class _RestrictedAccessPage extends StatelessWidget {
  const _RestrictedAccessPage({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppTheme.brand),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

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
            const SizedBox(height: 14),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _ErrorStateCard extends StatelessWidget {
  const _ErrorStateCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} ${_monthName(value.month)} ${value.year}';

String _monthName(int month) => const <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][month - 1];
