import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/fee_installment.dart';
import '../../../data/models/reminder_draft.dart';
import '../../../data/services/fee_service.dart';
import '../../../data/services/reminder_draft_service.dart';

class ReminderDraftsScreen extends StatefulWidget {
  const ReminderDraftsScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.service,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final ReminderDraftService? service;

  @override
  State<ReminderDraftsScreen> createState() => _ReminderDraftsScreenState();
}

class _ReminderDraftsScreenState extends State<ReminderDraftsScreen> {
  late final ReminderDraftService _service;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _dueDateFilter = 'all';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReminderDraftService();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<ReminderDraft>> get _draftStream =>
      _service.watchDraftsForUser(widget.user);

  List<ReminderDraft> _applyFilters(List<ReminderDraft> drafts) {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final filtered = drafts.where((item) {
      final matchesText =
          query.isEmpty ||
          item.studentName.toLowerCase().contains(query) ||
          item.studentId.toLowerCase().contains(query) ||
          item.feeInstallmentId.toLowerCase().contains(query);
      final matchesStatus =
          _statusFilter == 'all' || item.status.value == _statusFilter;

      final itemDueDate = DateTime(
        item.dueDateAtDraft.year,
        item.dueDateAtDraft.month,
        item.dueDateAtDraft.day,
      );

      final matchesDueDate = switch (_dueDateFilter) {
        'overdue' => itemDueDate.isBefore(today),
        'next7' =>
          !itemDueDate.isBefore(today) &&
              itemDueDate.isBefore(today.add(const Duration(days: 8))),
        'next30' =>
          !itemDueDate.isBefore(today) &&
              itemDueDate.isBefore(today.add(const Duration(days: 31))),
        _ => true,
      };

      return matchesText && matchesStatus && matchesDueDate;
    }).toList();
    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  Future<void> _createReminder() async {
    final created = await showDialog<ReminderDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateReminderDialog(user: widget.user),
    );
    if (created == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder draft saved in Firestore.')),
    );
  }

  Future<void> _editReminder(ReminderDraft reminder) async {
    final updated = await showDialog<ReminderDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditReminderDialog(
        user: widget.user,
        reminder: reminder,
        service: _service,
      ),
    );
    if (updated != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder draft updated.')));
    }
  }

  Future<void> _cancelReminder(ReminderDraft reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel reminder draft?'),
        content: const Text(
          'This action marks the reminder as cancelled. It does not send any message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _service.cancelDraftForUser(widget.user, reminder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder draft cancelled.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to cancel reminder: $error')),
        );
      }
    }
  }

  Future<void> _approveReminder(ReminderDraft reminder) async {
    try {
      final feeService = FeeService();
      final latest = await feeService.getInstallmentById(
        widget.user,
        reminder.feeInstallmentId,
      );
      if (latest != null &&
          (latest.isPaid ||
              latest.outstandingBalance <= 0 ||
              reminder.isObsoleteForInstallment(latest))) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot Approve Reminder'),
            content: const Text(
              'This instalment is now fully paid. This draft is obsolete and cannot be approved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await _service.approveDraftForUser(widget.user, reminder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder draft approved for manual sending.'),
            backgroundColor: Color(0xFF067647),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $error')),
        );
      }
    }
  }

  Future<void> _openInstalmentDetails(ReminderDraft item) async {
    showDialog<void>(
      context: context,
      builder: (context) => FutureBuilder<FeeInstallment?>(
        future: FeeService().getInstallmentById(
          widget.user,
          item.feeInstallmentId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final installment = snapshot.data;
          if (installment == null) {
            return AlertDialog(
              title: const Text('Instalment Not Found'),
              content: Text(
                'Could not load instalment ${item.feeInstallmentId} from Firestore.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.brand,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Instalment ${installment.id}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow(
                    'Student',
                    '${installment.studentName} (${installment.studentId})',
                  ),
                  _detailRow(
                    'Course / Batch',
                    '${installment.courseId} • ${installment.batchId}',
                  ),
                  _detailRow(
                    'Due Date',
                    DateFormat('dd MMMM yyyy').format(installment.dueDate),
                  ),
                  _detailRow(
                    'Amount Due',
                    '₹${installment.amountDue.toStringAsFixed(2)}',
                  ),
                  _detailRow(
                    'Paid Amount',
                    '₹${installment.paidAmount.toStringAsFixed(2)}',
                  ),
                  _detailRow(
                    'Outstanding Balance',
                    '₹${installment.outstandingBalance.toStringAsFixed(2)}',
                    highlight: installment.outstandingBalance > 0,
                  ),
                  _detailRow('Status', installment.status.toUpperCase()),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
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
    if (!_service.canView(widget.user)) {
      return const _RestrictedView(
        title: 'Financial information is restricted',
        message:
            'Only Owner/Admin and Accounts Staff can access reminder drafts.',
      );
    }

    return StreamBuilder<List<ReminderDraft>>(
      stream: _draftStream,
      initialData: const <ReminderDraft>[],
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            title: 'Unable to load reminder drafts',
            message: snapshot.error.toString(),
          );
        }

        final drafts = snapshot.data ?? const <ReminderDraft>[];
        final overview = _service.calculateOverview(drafts);
        final filteredDrafts = _applyFilters(drafts);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reminder Drafts',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createReminder,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create reminder'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'Total drafts',
                        value: overview.total.toString(),
                        color: AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Awaiting review',
                        value: overview.awaitingReview.toString(),
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Approved',
                        value: overview.approved.toString(),
                        color: const Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Cancelled',
                        value: overview.cancelled.toString(),
                        color: const Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 300,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search by student or instalment',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _statusFilter,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  labelText: 'Status',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Statuses'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'draft',
                                    child: Text('Draft'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'approved',
                                    child: Text('Approved'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'cancelled',
                                    child: Text('Cancelled'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _statusFilter = value);
                                  }
                                },
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _dueDateFilter,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  labelText: 'Due Date',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Due Dates'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'overdue',
                                    child: Text('Overdue'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'next7',
                                    child: Text('Next 7 Days'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'next30',
                                    child: Text('Next 30 Days'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _dueDateFilter = value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (filteredDrafts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.mark_email_unread_outlined,
                                    size: 42,
                                    color: AppTheme.brand,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No reminder drafts found.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Create a reminder when an outstanding instalment needs follow-up.',
                                    style: TextStyle(
                                      color: Colors.blueGrey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth >= 960) {
                                return _buildDataTable(filteredDrafts);
                              }
                              return _buildCardList(filteredDrafts);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDataTable(List<ReminderDraft> drafts) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 64,
          dataRowMaxHeight: 74,
          columnSpacing: 20,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFD)),
          columns: const [
            DataColumn(label: Text('STUDENT')),
            DataColumn(label: Text('INSTALMENT')),
            DataColumn(label: Text('OUTSTANDING')),
            DataColumn(label: Text('DUE DATE')),
            DataColumn(label: Text('CREATED')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('LAST UPDATED')),
            DataColumn(label: Text('ACTIONS')),
          ],
          rows: drafts.map((item) {
            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        item.studentId,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => _openInstalmentDetails(item),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.feeInstallmentId,
                          style: const TextStyle(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: AppTheme.brand,
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '₹${item.outstandingAmountAtDraft.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
                DataCell(
                  Text(DateFormat('dd MMM yyyy').format(item.dueDateAtDraft)),
                ),
                DataCell(
                  Text(DateFormat('dd MMM yyyy').format(item.createdAt)),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(item.status),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(item.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Text(DateFormat('dd MMM, h:mm a').format(item.updatedAt)),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => _editReminder(item),
                        child: const Text('View / Edit'),
                      ),
                      const SizedBox(width: 6),
                      if (item.status == ReminderDraftStatus.draft) ...[
                        FilledButton.tonal(
                          onPressed: () => _approveReminder(item),
                          child: const Text('Approve'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (item.status != ReminderDraftStatus.cancelled) ...[
                        TextButton(
                          onPressed: () => _cancelReminder(item),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        tooltip: 'Open associated instalment',
                        onPressed: () => _openInstalmentDetails(item),
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

  Widget _buildCardList(List<ReminderDraft> drafts) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: drafts.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = drafts[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.studentName} (${item.studentId})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Instalment: ${item.feeInstallmentId} • Outstanding: ₹${item.outstandingAmountAtDraft.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: ${DateFormat('dd MMM yyyy').format(item.dueDateAtDraft)} • Created: ${DateFormat('dd MMM yyyy').format(item.createdAt)}',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(item.status),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(item.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  TextButton(
                    onPressed: () => _editReminder(item),
                    child: const Text('View / Edit'),
                  ),
                  if (item.status == ReminderDraftStatus.draft)
                    FilledButton.tonal(
                      onPressed: () => _approveReminder(item),
                      child: const Text('Approve'),
                    ),
                  if (item.status != ReminderDraftStatus.cancelled)
                    TextButton(
                      onPressed: () => _cancelReminder(item),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      child: const Text('Cancel'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    tooltip: 'Open associated instalment',
                    onPressed: () => _openInstalmentDetails(item),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class CreateReminderDialog extends StatefulWidget {
  const CreateReminderDialog({
    required this.user,
    this.initialInstallment,
    super.key,
  });

  final AppUser user;
  final FeeInstallment? initialInstallment;

  @override
  State<CreateReminderDialog> createState() => _CreateReminderDialogState();
}

class _CreateReminderDialogState extends State<CreateReminderDialog> {
  final FeeService _feeService = FeeService();
  final ReminderDraftService _service = ReminderDraftService();
  FeeInstallment? _selectedInstallment;
  late final TextEditingController _messageController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedInstallment = widget.initialInstallment;
    final initialMessage = _selectedInstallment != null
        ? _service.buildTemplateMessage(
            studentName: _selectedInstallment!.studentName,
            outstandingAmount: _selectedInstallment!.outstandingBalance,
            dueDate: _selectedInstallment!.dueDate,
          )
        : '';
    _messageController = TextEditingController(text: initialMessage);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<List<FeeInstallment>> _loadInstallments() async {
    final installments = await _feeService.getInstallmentsForUser(widget.user);
    final outstanding =
        installments.where((item) => item.outstandingBalance > 0).toList();
    if (_selectedInstallment != null &&
        !outstanding.any((item) => item.id == _selectedInstallment!.id)) {
      outstanding.insert(0, _selectedInstallment!);
    }
    return outstanding;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedInstallment != null && _messageController.text.isEmpty) {
      _messageController.text = _service.buildTemplateMessage(
        studentName: _selectedInstallment!.studentName,
        outstandingAmount: _selectedInstallment!.outstandingBalance,
        dueDate: _selectedInstallment!.dueDate,
      );
    }

    return AlertDialog(
      title: const Text('Create reminder draft'),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<FeeInstallment>>(
          future: _loadInstallments(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('Unable to load instalments: ${snapshot.error}');
            }

            final items = snapshot.data ?? const <FeeInstallment>[];
            if (items.isEmpty) {
              return const Text(
                'There are no outstanding instalments available for a reminder.',
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<FeeInstallment>(
                  initialValue: _selectedInstallment,
                  decoration: const InputDecoration(
                    labelText: 'Outstanding instalment *',
                  ),
                  items: items.map((item) {
                    return DropdownMenuItem<FeeInstallment>(
                      value: item,
                      child: Text(
                        '${item.studentName} • ₹${item.outstandingBalance.toStringAsFixed(2)}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedInstallment = value;
                      if (value != null) {
                        _messageController.text = _service.buildTemplateMessage(
                          studentName: value.studentName,
                          outstandingAmount: value.outstandingBalance,
                          dueDate: value.dueDate,
                        );
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  minLines: 5,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'Reminder message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _selectedInstallment == null
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final navigator = Navigator.of(context);
                  setState(() => _isSaving = true);
                  try {
                    final draft = ReminderDraft.buildFromInstallment(
                      id: ReminderDraft.documentId(
                        instituteId: _selectedInstallment!.instituteId,
                        feeInstallmentId: _selectedInstallment!.id,
                      ),
                      instituteId: _selectedInstallment!.instituteId,
                      studentId: _selectedInstallment!.studentId,
                      studentName: _selectedInstallment!.studentName,
                      feeInstallmentId: _selectedInstallment!.id,
                      createdBy: widget.user.id,
                      installment: _selectedInstallment!,
                      messageTemplate: _messageController.text,
                    );
                    final saved = await _service.saveDraftForUser(
                      widget.user,
                      draft.copyWith(message: _messageController.text.trim()),
                    );
                    if (!mounted) {
                      return;
                    }
                    navigator.pop(saved);
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text('Unable to save reminder: $error'),
                      ),
                    );
                  } finally {
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save draft'),
        ),
      ],
    );
  }
}

class EditReminderDialog extends StatefulWidget {
  const EditReminderDialog({
    required this.user,
    required this.reminder,
    required this.service,
    super.key,
  });

  final AppUser user;
  final ReminderDraft reminder;
  final ReminderDraftService service;

  @override
  State<EditReminderDialog> createState() => _EditReminderDialogState();
}

class _EditReminderDialogState extends State<EditReminderDialog> {
  late final TextEditingController _controller;
  final FeeService _feeService = FeeService();
  bool _isSaving = false;
  bool _isLoadingInstallment = true;
  FeeInstallment? _currentInstallment;
  late double _currentOutstanding;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.reminder.message);
    _currentOutstanding = widget.reminder.outstandingAmountAtDraft;
    _checkInstallmentStatus();
  }

  Future<void> _checkInstallmentStatus() async {
    try {
      final installment = await _feeService.getInstallmentById(
        widget.user,
        widget.reminder.feeInstallmentId,
      );
      if (mounted) {
        setState(() {
          _currentInstallment = installment;
          _isLoadingInstallment = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingInstallment = false);
      }
    }
  }

  void _updateToCurrentBalance() {
    if (_currentInstallment == null) return;
    setState(() {
      _currentOutstanding = _currentInstallment!.outstandingBalance;
      _controller.text = widget.service.buildTemplateMessage(
        studentName: widget.reminder.studentName,
        outstandingAmount: _currentInstallment!.outstandingBalance,
        dueDate: _currentInstallment!.dueDate,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPaidOrObsolete = _currentInstallment != null &&
        (_currentInstallment!.isPaid ||
            _currentInstallment!.outstandingBalance <= 0 ||
            widget.reminder.isObsoleteForInstallment(_currentInstallment!));

    final balanceChanged = _currentInstallment != null &&
        !isPaidOrObsolete &&
        (_currentInstallment!.outstandingBalance -
                    widget.reminder.outstandingAmountAtDraft)
                .abs() >
            0.01;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Review reminder draft')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(widget.reminder.status),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _statusLabel(widget.reminder.status),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.reminder.studentName} (${widget.reminder.studentId})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Instalment: ${widget.reminder.feeInstallmentId} • Due ${DateFormat('dd MMM yyyy').format(widget.reminder.dueDateAtDraft)}',
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 14),
              if (_isLoadingInstallment)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Verifying current instalment status from Firestore…',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              if (isPaidOrObsolete) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This instalment is now fully paid in Firestore. This reminder draft is obsolete and cannot be approved.',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (balanceChanged) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Balance changed: ₹${_currentInstallment!.outstandingBalance.toStringAsFixed(2)} current vs ₹${widget.reminder.outstandingAmountAtDraft.toStringAsFixed(2)} at draft.',
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _updateToCurrentBalance,
                        child: const Text('Update Message'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _controller,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Reminder content',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (widget.reminder.status == ReminderDraftStatus.draft)
          FilledButton.tonal(
            onPressed: _isSaving || isPaidOrObsolete
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final navigator = Navigator.of(context);
                    setState(() => _isSaving = true);
                    try {
                      final updated = widget.reminder.copyWith(
                        message: _controller.text.trim(),
                        outstandingAmountAtDraft: _currentOutstanding,
                      );
                      final saved = await widget.service.approveDraftForUser(
                        widget.user,
                        updated,
                      );
                      if (!mounted) return;
                      navigator.pop(saved);
                    } catch (error) {
                      if (!mounted) return;
                      messenger?.showSnackBar(
                        SnackBar(content: Text('Approval failed: $error')),
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _isSaving = false);
                      }
                    }
                  },
            child: const Text('Approve'),
          ),
        FilledButton(
          onPressed: _isSaving
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final navigator = Navigator.of(context);
                  setState(() => _isSaving = true);
                  try {
                    final updated = widget.reminder.copyWith(
                      message: _controller.text.trim(),
                      outstandingAmountAtDraft: _currentOutstanding,
                    );
                    final saved = await widget.service.updateDraftForUser(
                      widget.user,
                      updated,
                    );
                    if (!mounted) return;
                    navigator.pop(saved);
                  } catch (error) {
                    if (!mounted) return;
                    messenger?.showSnackBar(
                      SnackBar(content: Text('Unable to update draft: $error')),
                    );
                  } finally {
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictedView extends StatelessWidget {
  const _RestrictedView({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 36,
                color: AppTheme.brand,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
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
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: Color(0xFFD97706),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
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
    );
  }
}

Color _statusColor(ReminderDraftStatus status) => switch (status) {
  ReminderDraftStatus.draft => const Color(0xFF2563EB),
  ReminderDraftStatus.approved => const Color(0xFF059669),
  ReminderDraftStatus.cancelled => const Color(0xFFD97706),
};

String _statusLabel(ReminderDraftStatus status) => switch (status) {
  ReminderDraftStatus.draft => 'Draft',
  ReminderDraftStatus.approved => 'Approved',
  ReminderDraftStatus.cancelled => 'Cancelled',
};
