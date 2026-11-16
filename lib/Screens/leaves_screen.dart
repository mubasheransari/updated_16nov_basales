import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Screens/new_leave_screen.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';
import 'package:ords_ba/Widgets/leave_widgets.dart';
import 'package:ords_ba/Widgets/nav.dart';

enum _Filter { all, pending, approved, declined, cancelled }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.pending => 'Pending',
        _Filter.approved => 'Approved',
        _Filter.declined => 'Declined',
        _Filter.cancelled => 'Cancelled',
      };

  String get status => name.toUpperCase();
}

/// The BA's leave requests: summary card, filter pills and one tile per
/// request. Tap a request to see its details (and cancel it when allowed).
/// Chat with the admin is not available yet.
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> {
  _Filter _filter = _Filter.all;
  List<Map<String, dynamic>> _leaves = const [];
  bool _loading = true;
  String? _error;

  Repository get _repo => context.read<Repository>();
  String get _token => context.read<AuthBloc>().state.token ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool spinner = true}) async {
    if (!mounted) return;
    if (spinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _repo.fetchLeaves(token: _token, filter: 'all');
      if (!mounted) return;
      setState(() {
        _leaves = rows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errText(e);
        _loading = false;
      });
      if (_leaves.isNotEmpty) showToast(context, errText(e));
    }
  }

  String _statusOf(Map<String, dynamic> l) =>
      '${l['status'] ?? 'PENDING'}'.toUpperCase();

  int _count(_Filter f) => f == _Filter.all
      ? _leaves.length
      : _leaves.where((l) => _statusOf(l) == f.status).length;

  List<Map<String, dynamic>> get _visible => _filter == _Filter.all
      ? _leaves
      : _leaves.where((l) => _statusOf(l) == _filter.status).toList();

  Future<void> _openDetails(Map<String, dynamic> leave) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LeaveSheet(leave: leave, repo: _repo, token: _token),
    );
    if (changed == true && mounted) _load(spinner: false);
  }

  Future<void> _apply() async {
    final id = await pushWithBlocs<int>(context, const NewLeaveScreen());
    if (!mounted) return;
    if (id == null) return; // cancelled
    await _load(spinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaves')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _apply,
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_calendar_rounded),
        label: const Text('Apply for leave',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () => _load(spinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            _SummaryCard(pending: _count(_Filter.pending)),
            const SizedBox(height: 14),
            _FilterBar(
              filter: _filter,
              count: _count,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 70),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.red),
                ),
              )
            else if (_error != null && _leaves.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Column(
                  children: [
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load leaves',
                      subtitle: _error,
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: _leaves.isEmpty
                      ? 'No leave requests yet'
                      : 'No ${_filter.label.toLowerCase()} leaves',
                  subtitle: _leaves.isEmpty
                      ? 'Need a day off? Tap "Apply for leave".'
                      : 'Nothing to show in this list.',
                ),
              )
            else
              for (final l in list) ...[
                _LeaveTile(
                  leave: l,
                  onTap: () => _openDetails(l),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ summary ------------------------------ */

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.pending});
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apply for leave',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  pending > 0
                      ? '$pending waiting for approval'
                      : 'Track approval right here in the app.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------ filters ------------------------------ */

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.count,
    required this.onChanged,
  });

  final _Filter filter;
  final int Function(_Filter) count;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_Filter f) {
      final on = filter == f;
      return GestureDetector(
        onTap: () => onChanged(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? AppGradients.horizontal : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${f.label} (${count(f)})',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: on ? Colors.white : AppColors.text,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final f in _Filter.values) chip(f)]),
      ),
    );
  }
}

/* ------------------------------- a row ------------------------------- */

class _LeaveTile extends StatelessWidget {
  const _LeaveTile({required this.leave, required this.onTap});
  final Map<String, dynamic> leave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = leave;
    final status = '${l['status'] ?? 'PENDING'}';
    final color = leaveStatusColor(status);
    final reason = '${l['reason'] ?? l['snippet'] ?? ''}'.trim();
    final when = fmtInboxTime(parseServerDate(l['created_at']));

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(radius: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(leaveStatusIcon(status), color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fmtLeaveRange(l['from_date'], l['to_date']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (when.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(when,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textDim)),
                      ],
                    ],
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.25,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      LeaveStatusChip(status: status),
                      const SizedBox(width: 8),
                      Pill(
                        fmtDays(l['total_days']),
                        icon: Icons.date_range_rounded,
                        color: AppColors.textDim,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------------- details sheet ----------------------------- */

/// Read-only details of one leave request, with a Cancel button while the
/// request can still be cancelled. Pops `true` when it was cancelled.
class _LeaveSheet extends StatefulWidget {
  const _LeaveSheet({
    required this.leave,
    required this.repo,
    required this.token,
  });

  final Map<String, dynamic> leave;
  final Repository repo;
  final String token;

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final id = int.tryParse('${widget.leave['leave_id']}');
    if (id == null || _cancelling) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: const Text('The request will be marked as cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel leave'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await widget.repo.cancelLeave(token: widget.token, id: id);
      if (!mounted) return;
      showToast(context, 'Leave request cancelled.', error: false);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      showToast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.leave;
    final status = '${l['status'] ?? 'PENDING'}';
    final reason = '${l['reason'] ?? ''}'.trim();
    final note = '${l['decision_note'] ?? ''}'.trim();
    final applied = parseServerDate(l['created_at']);
    final canCancel =
        isTrue(l['can_cancel']) || status.toUpperCase() == 'PENDING';
    final color = leaveStatusColor(status);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(fmtLeaveRange(l['from_date'], l['to_date']),
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                LeaveStatusChip(status: status),
                Pill(fmtDays(l['total_days']),
                    icon: Icons.date_range_rounded, color: AppColors.textDim),
                if (applied != null)
                  Pill('Applied ${fmtInboxTime(applied)}',
                      icon: Icons.schedule_rounded, color: AppColors.textDim),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Reason',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDim)),
              const SizedBox(height: 3),
              Text(reason,
                  style: const TextStyle(
                      fontSize: 14.5, height: 1.4, color: AppColors.text)),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin note',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    const SizedBox(height: 3),
                    Text(note,
                        style: const TextStyle(
                            fontSize: 14, height: 1.3, color: AppColors.text)),
                  ],
                ),
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelling ? null : _cancel,
                  icon: _cancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.block_rounded),
                  label: const Text('Cancel request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
