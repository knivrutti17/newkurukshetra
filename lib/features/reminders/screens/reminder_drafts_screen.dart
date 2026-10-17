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
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;

  @override
  State<ReminderDraftsScreen> createState() => _ReminderDraftsScreenState();
}

class _ReminderDraftsScreenState extends State<ReminderDraftsScreen> {
  late final ReminderDraftService _service;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _service = ReminderDraftService();
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
    final filtered = drafts.where((item) {
      final matchesText =
          query.isEmpty ||
          item.studentName.toLowerCase().contains(query) ||
          item.studentId.toLowerCase().contains(query) ||
          item.feeInstallmentId.toLowerCase().contains(query);
      final matchesStatus =
          _statusFilter == 'all' || item.status.value == _statusFilter;
      return matchesText && matchesStatus;
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
      await _service.approveDraftForUser(widget.user, reminder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder draft approved for manual sending.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Approval failed: $error')));
      }
    }
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
                        Row(
                          children: [
                            Expanded(
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
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 180,
                              child: DropdownButtonFormField<String>(
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
                                    child: Text('All'),
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
                          ],
                        ),
                        const SizedBox(height: 14),
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
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredDrafts.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = filteredDrafts[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                            style: TextStyle(
                                              color: Colors.blueGrey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Due: ${DateFormat('dd MMM yyyy').format(item.dueDateAtDraft)} • Created: ${DateFormat('dd MMM yyyy').format(item.createdAt)}',
                                            style: TextStyle(
                                              color: Colors.blueGrey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _statusColor(item.status),
                                              borderRadius:
                                                  BorderRadius.circular(999),
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
                                        if (item.status ==
                                            ReminderDraftStatus.draft)
                                          FilledButton.tonal(
                                            onPressed: () =>
                                                _approveReminder(item),
                                            child: const Text('Approve'),
                                          ),
                                        if (item.status !=
                                            ReminderDraftStatus.cancelled)
                                          TextButton(
                                            onPressed: () =>
                                                _cancelReminder(item),
                                            child: const Text('Cancel'),
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CreateReminderDialog extends StatefulWidget {
  const CreateReminderDialog({required this.user, super.key});

  final AppUser user;

  @override
  State<CreateReminderDialog> createState() => _CreateReminderDialogState();
}

class _CreateReminderDialogState extends State<CreateReminderDialog> {
  final FeeService _feeService = FeeService();
  final ReminderDraftService _service = ReminderDraftService();
  FeeInstallment? _selectedInstallment;
  final TextEditingController _messageController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<List<FeeInstallment>> _loadInstallments() async {
    final installments = await _feeService.getInstallmentsForUser(widget.user);
    return installments.where((item) => item.outstandingBalance > 0).toList();
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.reminder.message);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review reminder draft'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.reminder.studentName} • Due ${DateFormat('dd MMM yyyy').format(widget.reminder.dueDateAtDraft)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
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
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
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
