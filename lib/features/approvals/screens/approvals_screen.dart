import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/approval_action.dart';
import '../../../data/repositories/approval_repository.dart';
import '../../../data/services/approval_seed_service.dart';
import '../../../data/services/approval_service.dart';

// Zero-dependency date formatter
String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • ${hour.toString().padLeft(2, '0')}:$minute $period';
}

String _formatDateShort(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({
    required this.user,
    this.firebaseSetupMessage,
    this.approvalService,
    this.seedService,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;
  final ApprovalService? approvalService;
  final ApprovalSeedService? seedService;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  late final ApprovalService _approvalService;
  late final ApprovalSeedService _seedService;

  late Stream<List<ApprovalAction>> _actionsStream;

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _isSeeding = false;

  bool get _canManage => _approvalService.canManage(widget.user);

  @override
  void initState() {
    super.initState();
    _approvalService = widget.approvalService ?? ApprovalService();
    _seedService = widget.seedService ??
        ApprovalSeedService(
          approvalRepository: _approvalService.repository is ApprovalSeedRepository
              ? _approvalService.repository as ApprovalSeedRepository
              : null,
        );

    _actionsStream = _approvalService.watchForUser(widget.user);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadActions() {
    setState(() {
      _actionsStream = _approvalService.watchForUser(widget.user);
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
              'Sample approvals already loaded in the database.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample approvals loaded: ${result.actionsCreated} requests created (${result.actionsSkipped} already existed).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sample approvals: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  List<ApprovalAction> _filterActions(List<ApprovalAction> actions) {
    final query = _searchController.text.trim().toLowerCase();
    return actions.where((a) {
      if (_statusFilter != 'all' && a.status != _statusFilter) {
        return false;
      }
      if (_typeFilter != 'all' && a.type != _typeFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final matches = a.title.toLowerCase().contains(query) ||
            a.description.toLowerCase().contains(query) ||
            a.requestedBy.toLowerCase().contains(query) ||
            a.typeLabel.toLowerCase().contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openActionDetail(ApprovalAction action) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ApprovalDetailDialog(
        action: action,
        user: widget.user,
        approvalService: _approvalService,
        onApproved: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Action "${action.title}" has been approved.',
              ),
            ),
          );
        },
        onRejected: (reason) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Action "${action.title}" rejected: $reason',
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ApprovalAction>>(
      stream: _actionsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorCard(
            title: 'Unable to load approvals',
            message: snapshot.error.toString(),
            onRetry: _reloadActions,
          );
        }

        if (!snapshot.hasData) {
          return const _LoadingCard(
            label: 'Loading pending approvals & requests…',
          );
        }

        final allActions = snapshot.data!;
        final filteredActions = _filterActions(allActions);

        final pendingCount = allActions.where((a) => a.isPending).length;
        final approvedCount = allActions.where((a) => a.isApproved).length;
        final rejectedCount = allActions.where((a) => a.isRejected).length;

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
                  pendingCount: pendingCount,
                  approvedCount: approvedCount,
                  rejectedCount: rejectedCount,
                  totalCount: allActions.length,
                ),
                const SizedBox(height: 20),
                _FilterBar(
                  searchController: _searchController,
                  statusFilter: _statusFilter,
                  typeFilter: _typeFilter,
                  onSearchChanged: () => setState(() {}),
                  onStatusChanged: (v) => setState(() => _statusFilter = v),
                  onTypeChanged: (v) => setState(() => _typeFilter = v),
                ),
                const SizedBox(height: 20),
                if (filteredActions.isEmpty)
                  _EmptyStateCard(
                    hasAnyActions: allActions.isNotEmpty,
                    canManage: _canManage,
                    onLoadSamples: _loadSampleData,
                  )
                else
                  _ApprovalsTable(
                    actions: filteredActions,
                    user: widget.user,
                    approvalService: _approvalService,
                    onInspect: _openActionDetail,
                  ),
              ],
            ),
          ),
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
    required this.isSeeding,
    required this.onLoadSamples,
  });

  final bool canManage;
  final bool isSeeding;
  final VoidCallback? onLoadSamples;

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
                'Approvals Center',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Review and decide administrative requests, fee concessions, and cohort transfers with full audit trail.',
                style: TextStyle(
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
            label: Text(isSeeding ? 'Seeding…' : 'Load Sample Approvals'),
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
          'Executive Decision Authority',
          'Signed in as $userName (Owner). Unrestricted permission to review, approve, and reject all institutional requests.',
          const Color(0xFF1D4ED8),
          const Color(0xFFEFF6FF),
        ),
      AppRole.accounts => (
          'Financial Approval Authority',
          'Signed in as $userName (Accounts Staff). Authorized to review and decide fee concession and refund requests.',
          const Color(0xFFB45309),
          const Color(0xFFFFFBEB),
        ),
      AppRole.counselor => (
          'Counselor Submission View',
          'Signed in as $userName (Counselor). Viewing status of submitted cohort transfers and student concession requests.',
          const Color(0xFF0D9488),
          const Color(0xFFF0FDFA),
        ),
      AppRole.trainer => (
          'Faculty Request View',
          'Signed in as $userName (Trainer). Viewing status of submitted attendance waivers and lab schedule requests.',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF),
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
// Overview Cards
// ---------------------------------------------------------------------------

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({
    required this.pendingCount,
    required this.approvedCount,
    required this.rejectedCount,
    required this.totalCount,
  });

  final int pendingCount;
  final int approvedCount;
  final int rejectedCount;
  final int totalCount;

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
                title: 'Pending Review',
                value: '$pendingCount',
                subtitle: 'Awaiting decision',
                icon: Icons.hourglass_top_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFFFBEB),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Approved Actions',
                value: '$approvedCount',
                subtitle: 'Decided & ready/awaiting execution',
                icon: Icons.task_alt_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Rejected Actions',
                value: '$rejectedCount',
                subtitle: 'Declined with reason',
                icon: Icons.cancel_outlined,
                iconColor: const Color(0xFFDC2626),
                iconBg: const Color(0xFFFEF2F2),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Total Requests',
                value: '$totalCount',
                subtitle: 'Historical workflow volume',
                icon: Icons.receipt_long_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
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
// Filter Bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.statusFilter,
    required this.typeFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onTypeChanged,
  });

  final TextEditingController searchController;
  final String statusFilter;
  final String typeFilter;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;

          return Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 300,
                child: TextField(
                  controller: searchController,
                  onChanged: (_) => onSearchChanged(),
                  decoration: InputDecoration(
                    hintText: 'Search title, requester, reason…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                width: isNarrow ? constraints.maxWidth : 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (v) {
                    if (v != null) onStatusChanged(v);
                  },
                ),
              ),
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: typeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Action Type',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Types')),
                    DropdownMenuItem(
                      value: 'fee_concession',
                      child: Text('Fee Concession'),
                    ),
                    DropdownMenuItem(
                      value: 'batch_transfer',
                      child: Text('Batch Transfer'),
                    ),
                    DropdownMenuItem(
                      value: 'attendance_override',
                      child: Text('Attendance Override'),
                    ),
                    DropdownMenuItem(
                      value: 'refund_request',
                      child: Text('Refund Request'),
                    ),
                    DropdownMenuItem(
                      value: 'schedule_override',
                      child: Text('Schedule Override'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) onTypeChanged(v);
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
// Approvals Table
// ---------------------------------------------------------------------------

class _ApprovalsTable extends StatelessWidget {
  const _ApprovalsTable({
    required this.actions,
    required this.user,
    required this.approvalService,
    required this.onInspect,
  });

  final List<ApprovalAction> actions;
  final AppUser user;
  final ApprovalService approvalService;
  final ValueChanged<ApprovalAction> onInspect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            columns: const [
              DataColumn(label: Text('Action Title & Type')),
              DataColumn(label: Text('Requested By')),
              DataColumn(label: Text('Request Date')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Reviewer / Decision')),
              DataColumn(label: Text('Actions')),
            ],
            rows: actions.map((action) {
              final (statusBg, statusFg) = switch (action.status) {
                'pending' => (const Color(0xFFFFFBEB), const Color(0xFFB45309)),
                'approved' => (const Color(0xFFECFDF5), const Color(0xFF065F46)),
                'rejected' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
                _ => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
              };

              final canReviewThis = approvalService.canReview(user, action);

              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          action.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            action.typeLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(action.requestedBy),
                      ],
                    ),
                  ),
                  DataCell(Text(_formatDateShort(action.requestedAt))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        action.statusLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: statusFg,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      action.isApproved
                          ? (action.approvedBy ?? 'Approved')
                          : (action.isRejected
                              ? (action.rejectedBy ?? 'Rejected')
                              : 'Pending Review'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: action.isPending
                            ? const Color(0xFF94A3B8)
                            : AppTheme.ink,
                      ),
                    ),
                  ),
                  DataCell(
                    ElevatedButton.icon(
                      onPressed: () => onInspect(action),
                      icon: Icon(
                        action.isPending && canReviewThis
                            ? Icons.rate_review_outlined
                            : Icons.visibility_outlined,
                        size: 15,
                      ),
                      label: Text(
                        action.isPending && canReviewThis
                            ? 'Decide'
                            : 'Details',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: action.isPending && canReviewThis
                            ? AppTheme.brand
                            : const Color(0xFFF1F5F9),
                        foregroundColor: action.isPending && canReviewThis
                            ? Colors.white
                            : AppTheme.ink,
                        elevation: 0,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Action Detail & Decision Dialog
// ---------------------------------------------------------------------------

class _ApprovalDetailDialog extends StatefulWidget {
  const _ApprovalDetailDialog({
    required this.action,
    required this.user,
    required this.approvalService,
    required this.onApproved,
    required this.onRejected,
  });

  final ApprovalAction action;
  final AppUser user;
  final ApprovalService approvalService;
  final VoidCallback onApproved;
  final ValueChanged<String> onRejected;

  @override
  State<_ApprovalDetailDialog> createState() => _ApprovalDetailDialogState();
}

class _ApprovalDetailDialogState extends State<_ApprovalDetailDialog> {
  bool _isProcessing = false;
  String? _errorMessage;

  bool get _canReview =>
      widget.approvalService.canReview(widget.user, widget.action);

  Future<void> _approve() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await widget.approvalService.approveAction(
        widget.user,
        widget.action.id,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onApproved();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _promptReject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectReasonDialog(),
    );

    if (reason != null && reason.trim().isNotEmpty && mounted) {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      try {
        await widget.approvalService.rejectAction(
          widget.user,
          widget.action.id,
          reason: reason,
        );
        if (mounted) {
          Navigator.of(context).pop();
          widget.onRejected(reason);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isProcessing = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.rule_rounded, color: AppTheme.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              a.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: switch (a.status) {
                'pending' => const Color(0xFFFFFBEB),
                'approved' => const Color(0xFFECFDF5),
                'rejected' => const Color(0xFFFEF2F2),
                _ => const Color(0xFFF1F5F9),
              },
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              a.statusLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: switch (a.status) {
                  'pending' => const Color(0xFFD97706),
                  'approved' => const Color(0xFF059669),
                  'rejected' => const Color(0xFFDC2626),
                  _ => const Color(0xFF475569),
                },
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
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
              _DetailRow(label: 'Action Type', value: a.typeLabel),
              _DetailRow(label: 'Requested By', value: a.requestedBy),
              _DetailRow(
                label: 'Request Date',
                value: _formatDate(a.requestedAt),
              ),
              const SizedBox(height: 8),
              const Text(
                'Description / Justification:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  a.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
              ),
              if (a.payload.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Request Parameters:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: a.payload.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 160,
                              child: Text(
                                '${e.key}:',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value.toString(),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (a.isApproved) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Approved by ${a.approvedBy ?? 'Administrator'} on ${_formatDate(a.approvedAt ?? a.updatedAt)}.\n'
                          'Status: Approved (Awaiting Execution).',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF065F46),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (a.isRejected) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.cancel_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Rejected by ${a.rejectedBy ?? 'Administrator'} on ${_formatDate(a.rejectedAt ?? a.updatedAt)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                      if (a.rejectionReason != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Reason: ${a.rejectionReason}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF7F1D1D),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (a.isPending && _canReview) ...[
          TextButton.icon(
            onPressed: _isProcessing ? null : _promptReject,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              'Reject Action',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _approve,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Approve Action'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
// Rejection Reason Prompt Dialog
// ---------------------------------------------------------------------------

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_reasonController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reject Action Request',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please provide a clear and mandatory reason explaining why this request is being rejected:',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _reasonController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason *',
                  hintText: 'e.g. Request submitted after deadline, quota exceeded…',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Rejection reason is mandatory.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm Rejection'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State Cards
// ---------------------------------------------------------------------------

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.hasAnyActions,
    required this.canManage,
    required this.onLoadSamples,
  });

  final bool hasAnyActions;
  final bool canManage;
  final VoidCallback onLoadSamples;

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
              Icons.task_alt_rounded,
              size: 40,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasAnyActions
                ? 'No matching approval actions found'
                : 'No pending approvals yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasAnyActions
                ? 'Try adjusting your status, type, or search filters.'
                : 'All clear! Click "Load Sample Approvals" above to explore sample fee concessions and cohort transfer requests.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
            ),
          ),
          if (canManage && !hasAnyActions) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onLoadSamples,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Load Sample Approvals'),
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

