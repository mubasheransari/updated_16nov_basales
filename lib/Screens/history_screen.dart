import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/auth_bloc.dart';
import 'package:ords_ba/Data/local_store.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Sales + attendance history of this device (saved after every successful
/// API call).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthBloc>().state.user!;
    final sales = SalesStore(user.storageKey).history();
    final att = AttendanceStore(user.storageKey).all();

    return DefaultTabController(
      length: 2,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('History',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text)),
              ),
            ),
            Container(
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                padding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  gradient: AppGradients.horizontal,
                  borderRadius: BorderRadius.circular(999),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.text,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: const [Tab(text: 'Sales'), Tab(text: 'Attendance')],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _SalesList(sales: sales),
                  _AttendanceList(items: att),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sales});
  final List<SaleRecord> sales;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No sales yet',
        subtitle: 'Sales you submit will appear here.',
      );
    }

    // Group all orders for a date into one daily widget instead of rendering
    // a separate dashboard-style card for every submitted sales entry.
    final groups = <String, List<SaleRecord>>{};
    for (final sale in sales) {
      groups.putIfAbsent(sale.saleDate, () => []).add(sale);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
      itemCount: dates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final date = dates[i];
        final daySales = groups[date]!;
        final totalQty = daySales.fold<int>(0, (sum, sale) => sum + sale.totalQty);
        final totalLines = daySales.fold<int>(0, (sum, sale) => sum + sale.lines.length);
        return Container(
          decoration: cardDecoration(radius: 20),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              iconColor: AppColors.red,
              collapsedIconColor: AppColors.red,
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF17212F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: Colors.white),
              ),
              title: Text(
                fmtDate(DateTime.parse(date)),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              subtitle: Text(
                '${daySales.length} order${daySales.length == 1 ? '' : 's'} · $totalLines product lines',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$totalQty',
                      style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const Text('TOTAL QTY',
                      style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              children: [
                for (var orderIndex = 0; orderIndex < daySales.length; orderIndex++) ...[
                  if (orderIndex > 0) const Divider(height: 18),
                  _DailyOrderDetails(
                    order: daySales[orderIndex],
                    orderNumber: orderIndex + 1,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DailyOrderDetails extends StatelessWidget {
  const _DailyOrderDetails({
    required this.order,
    required this.orderNumber,
  });

  final SaleRecord order;
  final int orderNumber;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Entry $orderNumber · ${DateFormat('hh:mm a').format(order.createdAt)}',
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
            Pill('Qty ${order.totalQty}', filled: true),
          ],
        ),
        const SizedBox(height: 8),
        for (final line in order.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      if (line.blend.isNotEmpty)
                        Text(line.blend,
                            style: const TextStyle(
                                color: AppColors.textDim, fontSize: 11.5)),
                    ],
                  ),
                ),
                Text('× ${line.qty}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: AppColors.red)),
              ],
            ),
          ),
      ],
    );
  }

}

class _AttendanceList extends StatelessWidget {
  const _AttendanceList({required this.items});
  final List<AttendanceRecord> items;

  String _duration(AttendanceRecord r) {
    if (r.outAt == null) return 'On duty';
    final d = r.outAt!.difference(r.inAt);
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.fingerprint_rounded,
        title: 'No attendance yet',
        subtitle: 'Your attendance records will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = items[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(fmtDate(DateTime.parse(r.date)),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Pill(_duration(r),
                      icon: Icons.timer_outlined,
                      color: r.isOpen ? AppColors.success : AppColors.red),
                ],
              ),
              if (r.locationName != null) ...[
                const SizedBox(height: 4),
                Text(r.locationName!,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _InOut(
                        label: 'IN', value: fmtTime(r.inAt), icon: Icons.login_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InOut(
                      label: r.autoOut ? 'OUT (auto 12 AM)' : 'OUT',
                      value: r.outAt == null ? '--:--' : fmtTime(r.outAt),
                      icon: Icons.logout_rounded,
                    ),
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

class _InOut extends StatelessWidget {
  const _InOut({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.redTint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          color: AppColors.textDim,
                          fontWeight: FontWeight.w700)),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );
}
