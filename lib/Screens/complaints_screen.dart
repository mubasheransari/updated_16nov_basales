import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Bloc/complaints_cubit.dart';
import 'package:ords_ba/Model/complaint_models.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Screens/new_complaint_screen.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';
import 'package:ords_ba/Widgets/complaint_widgets.dart';

enum _Filter { all, open, resolved }

/// The BA's complaints: title, description, date / time and an Open /
/// Resolved badge. (Chat with support is not available yet.)
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    context.read<ComplaintsCubit>().load();
  }

  void _openDetails(Complaint c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ComplaintSheet(complaint: c),
    );
  }

  Future<void> _newComplaint() async {
    final id = await Navigator.of(context, rootNavigator: true).push<int>(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: context.read<ComplaintsCubit>()),
            BlocProvider.value(value: context.read<AuthBloc>()),
          ],
          child: const NewComplaintScreen(),
        ),
      ),
    );
    if (!mounted) return;
    if (id != null) context.read<ComplaintsCubit>().refresh();
  }

  List<Complaint> _visible(List<Complaint> all) => switch (_filter) {
        _Filter.all => all,
        _Filter.open => all.where((c) => c.isOpen).toList(),
        _Filter.resolved => all.where((c) => !c.isOpen).toList(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newComplaint,
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New complaint',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: BlocBuilder<ComplaintsCubit, ComplaintsState>(
        builder: (context, st) {
          final list = _visible(st.complaints);
          return RefreshIndicator(
            color: AppColors.red,
            onRefresh: () => context.read<ComplaintsCubit>().refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
              children: [
                _SummaryCard(state: st),
                const SizedBox(height: 14),
                _FilterBar(
                  filter: _filter,
                  all: st.complaints.length,
                  open: st.openCount,
                  resolved: st.resolvedCount,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 14),
                if (st.load == ComplaintsLoad.loading ||
                    st.load == ComplaintsLoad.initial)
                  const Padding(
                    padding: EdgeInsets.only(top: 70),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.red),
                    ),
                  )
                else if (st.load == ComplaintsLoad.error)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Column(
                      children: [
                        EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load complaints',
                          subtitle: st.error,
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.read<ComplaintsCubit>().load(),
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
                      icon: Icons.forum_outlined,
                      title: st.complaints.isEmpty
                          ? 'No complaints yet'
                          : _filter == _Filter.open
                              ? 'No open complaints'
                              : 'No resolved complaints',
                      subtitle: st.complaints.isEmpty
                          ? 'Facing a problem? Tap "New complaint" and tell us.'
                          : 'Nothing to show in this list.',
                    ),
                  )
                else
                  for (final c in list) ...[
                    _ComplaintTile(complaint: c, onTap: () => _openDetails(c)),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ------------------------------ summary ------------------------------ */

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});
  final ComplaintsState state;

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
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Report a problem',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  state.openCount > 0
                      ? '${state.openCount} still open'
                      : 'Tell us what went wrong.',
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
    required this.all,
    required this.open,
    required this.resolved,
    required this.onChanged,
  });

  final _Filter filter;
  final int all;
  final int open;
  final int resolved;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_Filter f, String label, int n) {
      final on = filter == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? AppGradients.horizontal : null,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$label ($n)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: on ? Colors.white : AppColors.text,
              ),
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
      child: Row(
        children: [
          chip(_Filter.all, 'All', all),
          chip(_Filter.open, 'Open', open),
          chip(_Filter.resolved, 'Resolved', resolved),
        ],
      ),
    );
  }
}

/* ------------------------------- a row ------------------------------- */

String _when(DateTime? d) =>
    d == null ? '' : DateFormat('dd MMM yyyy  -  hh:mm a').format(d);

class _ComplaintTile extends StatelessWidget {
  const _ComplaintTile({required this.complaint, required this.onTap});
  final Complaint complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final open = c.isOpen;
    final accent = open ? AppColors.red : AppColors.success;

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
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                open ? Icons.report_problem_rounded : Icons.check_circle_rounded,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.description,
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
                      StatusChip(open: open),
                      const SizedBox(width: 8),
                      if (c.createdAt != null)
                        Expanded(
                          child: Text(
                            _when(c.createdAt),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textDim),
                          ),
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

class _ComplaintSheet extends StatelessWidget {
  const _ComplaintSheet({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8),
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
              Text(c.title,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusChip(open: c.isOpen),
                  if (c.createdAt != null)
                    Pill(_when(c.createdAt),
                        icon: Icons.schedule_rounded,
                        color: AppColors.textDim),
                  if (c.locationName.isNotEmpty)
                    Pill(c.locationName,
                        icon: Icons.storefront_rounded,
                        color: AppColors.textDim),
                ],
              ),
              if (c.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(c.description,
                    style: const TextStyle(
                        fontSize: 14.5, height: 1.4, color: AppColors.text)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
