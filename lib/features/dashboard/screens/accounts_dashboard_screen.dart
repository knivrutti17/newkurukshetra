import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/fee_installment.dart';
import '../../../data/models/payment.dart';
import '../../../data/models/reminder_draft.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/services/fee_service.dart';
import '../../reminders/screens/reminder_drafts_screen.dart';

/// Aggregated data payload for Accounts Staff Dashboard.
class AccountsDashboardData {
  const AccountsDashboardData({
    required this.installments,
    required this.payments,
  });

  final List<FeeInstallment> installments;
  final List<Payment> payments;

  int get pendingCount =>
      installments.where((item) => item.outstandingBalance > 0).length;

  List<FeeInstallment> get overdueInstallments {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final list = installments
        .where(
          (item) =>
              item.outstandingBalance > 0 &&
              item.dueDate.isBefore(endOfToday),
        )
        .toList();
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  int get overdueCount => overdueInstallments.length;

  double get totalOutstandingBalance {
    final paise = installments.fold<int>(
      0,
      (sum, item) => sum + item.balancePaise,
    );
    return paise / 100.0;
  }

  double get monthPaymentsTotal {
    final today = DateTime.now();
    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 0, 23, 59, 59);
    final currentMonthPayments = payments.where((payment) {
      return !payment.paymentDate.isBefore(monthStart) &&
          !payment.paymentDate.isAfter(monthEnd);
    });
    final paise = currentMonthPayments.fold<int>(
      0,
      (sum, item) => sum + item.amountPaise,
    );
    return paise / 100.0;
  }

  List<Payment> get recentPayments {
    final list = List<Payment>.from(payments);
    list.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return list;
  }
}

/// Fully functional Accounts Staff Dashboard with real Firestore metrics.
class AccountsDashboardScreen extends StatefulWidget {
  const AccountsDashboardScreen({
    required this.user,
    this.onSectionSelected,
    this.feeService,
    this.feeRepository,
    this.dataLoader,
    super.key,
  });

  final AppUser user;
  final ValueChanged<String>? onSectionSelected;
  final FeeService? feeService;
  final FeeRepository? feeRepository;
  final Future<AccountsDashboardData> Function()? dataLoader;

  @override
  State<AccountsDashboardScreen> createState() =>
      _AccountsDashboardScreenState();
}

class _AccountsDashboardScreenState extends State<AccountsDashboardScreen> {
  FeeService? _feeService;
  FeeRepository? _feeRepository;
  late Future<AccountsDashboardData> _dashboardData;
  DateTime _lastRefreshedAt = DateTime.now();

  FeeService get _effectiveFeeService =>
      widget.feeService ?? (_feeService ??= FeeService());
  FeeRepository get _effectiveFeeRepository =>
      widget.feeRepository ?? (_feeRepository ??= FirestoreFeeRepository());

  @override
  void initState() {
    super.initState();
    _dashboardData = _loadData();
  }

  Future<AccountsDashboardData> _loadData() async {
    _lastRefreshedAt = DateTime.now();
    if (widget.dataLoader != null) {
      return widget.dataLoader!();
    }

    final installmentsFuture =
        _effectiveFeeService.getInstallmentsForUser(widget.user);
    final paymentsFuture =
        _effectiveFeeRepository.getPaymentsForInstallment(''); // Fallback or getAll
    // Use repository to get all payments for institute
    final allPaymentsFuture = _effectiveFeeRepository is FirestoreFeeRepository
        ? (widget.feeRepository ?? _effectiveFeeRepository)
            .watchAllPayments(
              scope: FeeAccessScope(instituteId: widget.user.instituteId),
            )
            .first
        : paymentsFuture;

    final results = await Future.wait([installmentsFuture, allPaymentsFuture]);
    return AccountsDashboardData(
      installments: results[0] as List<FeeInstallment>,
      payments: results[1] as List<Payment>,
    );
  }

  void _refresh() {
    setState(() {
      _dashboardData = _loadData();
    });
  }

  void _openPaymentDetails(Payment payment, Map<String, FeeInstallment> installmentMap) {
    final installment = installmentMap[payment.feeInstallmentId];
    final studentName = installment?.studentName.isNotEmpty == true
        ? installment!.studentName
        : 'Student ${payment.studentId}';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Payment Details'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Student Name', studentName),
              _detailRow('Student ID', payment.studentId),
              _detailRow('Amount Paid', '₹${payment.amount.toStringAsFixed(2)}'),
              _detailRow(
                'Payment Date',
                DateFormat('dd MMM yyyy, h:mm a').format(payment.paymentDate),
              ),
              _detailRow('Payment Method', payment.paymentMethod),
              _detailRow(
                'Reference Number',
                payment.referenceNumber?.isNotEmpty == true
                    ? payment.referenceNumber!
                    : 'N/A',
              ),
              _detailRow('Fee Instalment ID', payment.feeInstallmentId),
              _detailRow(
                'Recorded By',
                payment.recordedBy.isNotEmpty ? payment.recordedBy : 'Accounts Staff',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openInstalmentDetails(FeeInstallment item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFFD97706),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Instalment Details'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Student Name', item.studentName),
              _detailRow('Student ID', item.studentId),
              _detailRow('Instalment ID', item.id),
              _detailRow('Original Amount Due', '₹${item.amountDue.toStringAsFixed(2)}'),
              _detailRow('Total Paid', '₹${item.paidAmount.toStringAsFixed(2)}'),
              _detailRow(
                'Outstanding Balance',
                '₹${item.outstandingBalance.toStringAsFixed(2)}',
                highlight: true,
              ),
              _detailRow(
                'Due Date',
                DateFormat('dd MMMM yyyy').format(item.dueDate),
              ),
              _detailRow('Status', item.status.toUpperCase()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _createReminderForInstalment(item);
            },
            icon: const Icon(Icons.mark_email_unread_rounded, size: 16),
            label: const Text('Create Reminder Draft'),
          ),
        ],
      ),
    );
  }

  Future<void> _createReminderForInstalment(FeeInstallment item) async {
    final created = await showDialog<ReminderDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateReminderDialog(
        user: widget.user,
        initialInstallment: item,
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder draft saved successfully.'),
          backgroundColor: Color(0xFF067647),
        ),
      );
    }
  }

  Widget _detailRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? const Color(0xFFDC2626) : AppTheme.ink,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountsDashboardData>(
      future: _dashboardData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppTheme.canvas,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 36,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Unable to load financial dashboard',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry connection'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppTheme.canvas,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data ??
            const AccountsDashboardData(installments: [], payments: []);

        final rawName = widget.user.name.trim();
        final firstName = rawName.isNotEmpty ? rawName.split(' ').first : 'Accounts';
        final today = DateTime.now();
        final nowFormatted = DateFormat('EEEE, d MMMM yyyy').format(today);

        final installmentMap = <String, FeeInstallment>{
          for (final inst in data.installments) inst.id: inst,
        };

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
                    // Header
                    _buildHeader(firstName, nowFormatted),
                    const SizedBox(height: 24),

                    // 4 KPI Summary Cards
                    _buildKpiGrid(data),
                    const SizedBox(height: 24),

                    // Two-Column Section: Recent Payments & Overdue Instalments
                    _buildOperationalGrid(data, installmentMap),
                    const SizedBox(height: 24),

                    // Quick Actions
                    _buildQuickActions(),
                    const SizedBox(height: 18),

                    // Footer Status
                    _buildFooterStatus(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String firstName, String nowFormatted) {
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
                      'ACCOUNTS',
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
              Text(
                'Financial overview for ${_monthName(DateTime.now().month)} ${DateTime.now().year}.',
                style: const TextStyle(
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live synced',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh dashboard',
                onPressed: _refresh,
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

  Widget _buildKpiGrid(AccountsDashboardData data) {
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
          _AccountsKpiData(
            label: 'Pending Instalments',
            value: '${data.pendingCount}',
            detail: 'Awaiting completion',
            icon: Icons.account_balance_wallet_rounded,
            accentColor: const Color(0xFF2563EB),
            backgroundColor: const Color(0xFFEFF6FF),
            destinationId: 'fee-management',
          ),
          _AccountsKpiData(
            label: 'Overdue Instalments',
            value: '${data.overdueCount}',
            detail: data.overdueCount > 0 ? 'Action required' : 'None overdue',
            icon: Icons.warning_amber_rounded,
            accentColor: const Color(0xFFD97706),
            backgroundColor: const Color(0xFFFFFBEB),
            destinationId: 'fee-management',
          ),
          _AccountsKpiData(
            label: 'Total Outstanding Balance',
            value: '₹${data.totalOutstandingBalance.toStringAsFixed(2)}',
            detail: 'Total receivable',
            icon: Icons.currency_rupee_rounded,
            accentColor: const Color(0xFF7C3AED),
            backgroundColor: const Color(0xFFF5F3FF),
            destinationId: 'fee-reports',
          ),
          _AccountsKpiData(
            label: 'Payments Received This Month',
            value: '₹${data.monthPaymentsTotal.toStringAsFixed(2)}',
            detail: '${_monthName(DateTime.now().month)} ${DateTime.now().year}',
            icon: Icons.payments_rounded,
            accentColor: const Color(0xFF059669),
            backgroundColor: const Color(0xFFECFDF5),
            destinationId: 'payments',
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: cardWidth,
                  child: _AccountsKpiCard(
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

  Widget _buildOperationalGrid(
    AccountsDashboardData data,
    Map<String, FeeInstallment> installmentMap,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        const gap = 20.0;

        final paymentsPanel = _buildRecentPaymentsPanel(
          data.recentPayments.take(6).toList(),
          installmentMap,
        );
        final overduePanel = _buildOverdueInstalmentsPanel(
          data.overdueInstallments.take(6).toList(),
        );

        if (isDesktop) {
          final halfWidth = (constraints.maxWidth - gap) / 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: halfWidth, child: paymentsPanel),
              const SizedBox(width: gap),
              SizedBox(width: halfWidth, child: overduePanel),
            ],
          );
        }

        return Column(
          children: [
            paymentsPanel,
            const SizedBox(height: gap),
            overduePanel,
          ],
        );
      },
    );
  }

  Widget _buildRecentPaymentsPanel(
    List<Payment> payments,
    Map<String, FeeInstallment> installmentMap,
  ) {
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
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Color(0xFF059669),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Payments',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Confirmed collections and transactions',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => widget.onSectionSelected?.call('payments'),
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
          // List
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Center(
                child: Text(
                  'No payment records found yet.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: payments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final installment = installmentMap[payment.feeInstallmentId];
                final studentName = installment?.studentName.isNotEmpty == true
                    ? installment!.studentName
                    : 'Student ${payment.studentId}';

                return InkWell(
                  onTap: () => _openPaymentDetails(payment, installmentMap),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF16A34A),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${payment.paymentMethod} • Ref: ${payment.referenceNumber ?? "N/A"}',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${payment.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd MMM yyyy').format(payment.paymentDate),
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOverdueInstalmentsPanel(List<FeeInstallment> overdue) {
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
                    Icons.warning_amber_rounded,
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
                        'Overdue Instalments',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${overdue.length} ${overdue.length == 1 ? "instalment" : "instalments"} past due date',
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
                      widget.onSectionSelected?.call('fee-management'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Manage'),
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
          // List
          if (overdue.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Center(
                child: Text(
                  'No overdue instalments right now. All clear!',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: overdue.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = overdue[index];
                final overdueDays =
                    DateTime.now().difference(item.dueDate).inDays;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFFD97706),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.studentName} (${item.studentId})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due: ${DateFormat("dd MMM yyyy").format(item.dueDate)} • $overdueDays days overdue',
                              style: const TextStyle(
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${item.outstandingBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFDC2626),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _openInstalmentDetails(item),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    'Details',
                                    style: TextStyle(
                                      color: AppTheme.brand,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () =>
                                    _createReminderForInstalment(item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: const Text(
                                    'Remind',
                                    style: TextStyle(
                                      color: AppTheme.brand,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _AccountsAction(
        label: 'Fee Management',
        subtitle: 'Instalments & plans',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF2563EB),
        destinationId: 'fee-management',
      ),
      _AccountsAction(
        label: 'Payments',
        subtitle: 'Record & receipts',
        icon: Icons.payments_rounded,
        color: const Color(0xFF059669),
        destinationId: 'payments',
      ),
      _AccountsAction(
        label: 'Risk Alerts',
        subtitle: 'Fee & attendance risk',
        icon: Icons.health_and_safety_rounded,
        color: const Color(0xFFDC2626),
        destinationId: 'risk-alerts',
      ),
      _AccountsAction(
        label: 'Reminder Drafts',
        subtitle: 'Follow-up drafts',
        icon: Icons.mark_email_unread_rounded,
        color: const Color(0xFF7C3AED),
        destinationId: 'reminder-drafts',
      ),
      _AccountsAction(
        label: 'Fee Reports',
        subtitle: 'Financial analytics',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFFD97706),
        destinationId: 'fee-reports',
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
                    'Accounts and financial operations shortcuts',
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
                  ? 5
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
                        child: _AccountsActionButton(
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
                'Live Financial Records • Synced at $formattedTime',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Text(
            'InstituteOS Accounts & Finance Workspace',
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
}

class _AccountsKpiData {
  const _AccountsKpiData({
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

class _AccountsKpiCard extends StatefulWidget {
  const _AccountsKpiCard({required this.data, this.onTap});

  final _AccountsKpiData data;
  final VoidCallback? onTap;

  @override
  State<_AccountsKpiCard> createState() => _AccountsKpiCardState();
}

class _AccountsKpiCardState extends State<_AccountsKpiCard> {
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
                      fontSize: 26,
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

class _AccountsAction {
  const _AccountsAction({
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

class _AccountsActionButton extends StatefulWidget {
  const _AccountsActionButton({required this.item, this.onPressed});

  final _AccountsAction item;
  final VoidCallback? onPressed;

  @override
  State<_AccountsActionButton> createState() => _AccountsActionButtonState();
}

class _AccountsActionButtonState extends State<_AccountsActionButton> {
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

String _monthName(int month) => switch (month) {
  1 => 'January',
  2 => 'February',
  3 => 'March',
  4 => 'April',
  5 => 'May',
  6 => 'June',
  7 => 'July',
  8 => 'August',
  9 => 'September',
  10 => 'October',
  11 => 'November',
  12 => 'December',
  _ => 'Month',
};
