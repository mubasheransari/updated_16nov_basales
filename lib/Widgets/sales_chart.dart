import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:ords_ba/Bloc/dashboard_cubit.dart';
import 'package:ords_ba/Model/dashboard_models.dart';
import 'package:ords_ba/Model/models.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/* -------------------------- modern sales chart -------------------------- */

class _SalesLinePainter extends CustomPainter {
  _SalesLinePainter({
    required this.bars,
    required this.selectedIndex,
    required this.bestIndex,
    required this.animation,
  });

  final List<_Bar> bars;
  final int? selectedIndex;
  final int bestIndex;
  final double animation;

  static const Color _lineColor = Color(0xFFD32F2F);
  static const Color _fillColor = Color(0xFFD32F2F);

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;

    const left = 14.0;
    const right = 14.0;
    const top = 25.0;
    const bottom = 10.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final maxValue = bars.fold<int>(
      0,
      (maximum, bar) => bar.qty > maximum ? bar.qty : maximum,
    );

    final safeMax = maxValue == 0 ? 1.0 : maxValue.toDouble();

    final points = <Offset>[];

    for (var i = 0; i < bars.length; i++) {
      final x = bars.length == 1
          ? size.width / 2
          : left + (chartWidth * i / (bars.length - 1));

      final normalized = bars[i].qty / safeMax;
      final targetY = top + chartHeight * (1 - normalized);

      // Keep zero values slightly above the baseline.
      final y = bars[i].qty == 0
          ? top + chartHeight
          : targetY;

      final animatedY =
          (top + chartHeight) -
          ((top + chartHeight - y) * animation);

      points.add(Offset(x, animatedY));
    }

    // Horizontal guide lines.
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EAF0)
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = top + chartHeight * i / 3;

      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    if (points.isEmpty) return;

    // Create a smooth line path.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);

    if (points.length == 1) {
      linePath.lineTo(points.first.dx + 0.1, points.first.dy);
    } else {
      for (var i = 0; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final middleX = (current.dx + next.dx) / 2;

        linePath.cubicTo(
          middleX,
          current.dy,
          middleX,
          next.dy,
          next.dx,
          next.dy,
        );
      }
    }

    // Fill the area below the curve.
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, top + chartHeight)
      ..lineTo(points.first.dx, top + chartHeight)
      ..close();

    final fillRect = Rect.fromLTWH(
      left,
      top,
      chartWidth,
      chartHeight,
    );

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x42D32F2F),
          Color(0x08D32F2F),
        ],
      ).createShader(fillRect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Main sales trend line.
    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    // Selected point indicator.
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final selected = points[selectedIndex!];

      final indicatorPaint = Paint()
        ..color = _lineColor.withValues(alpha: 0.20)
        ..strokeWidth = 1.5;

      canvas.drawLine(
        Offset(selected.dx, top),
        Offset(selected.dx, top + chartHeight),
        indicatorPaint,
      );

      _drawValueBubble(
        canvas,
        selected,
        bars[selectedIndex!].qty,
        size,
      );
    }

    // Data points.
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final isSelected = i == selectedIndex;
      final isBest = i == bestIndex;

      if (bars[i].qty == 0 && !isSelected) continue;

      if (isSelected || isBest) {
        canvas.drawCircle(
          point,
          isSelected ? 7 : 5.5,
          Paint()..color = Colors.white,
        );
      }

      canvas.drawCircle(
        point,
        isSelected ? 4.5 : isBest ? 3.5 : 2.5,
        Paint()
          ..color = isSelected || isBest
              ? _lineColor
              : _lineColor.withValues(alpha: 0.65),
      );
    }
  }

  void _drawValueBubble(
    Canvas canvas,
    Offset point,
    int value,
    Size size,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$value units',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      //textDirection: TextDirection.LTR,
    )..layout();

    const horizontalPadding = 8.0;
    const verticalPadding = 5.0;

    final bubbleWidth = textPainter.width + horizontalPadding * 2;
    final bubbleHeight = textPainter.height + verticalPadding * 2;

    final left = (point.dx - bubbleWidth / 2)
        .clamp(2.0, size.width - bubbleWidth - 2.0)
        .toDouble();

    final top = (point.dy - bubbleHeight - 10)
        .clamp(0.0, size.height - bubbleHeight)
        .toDouble();

    final rect = Rect.fromLTWH(
      left,
      top,
      bubbleWidth,
      bubbleHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF9F2027),
    );

    textPainter.paint(
      canvas,
      Offset(
        left + horizontalPadding,
        top + verticalPadding,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _SalesLinePainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.bestIndex != bestIndex ||
        oldDelegate.animation != animation;
  }
}

/// Time ranges of the home dashboard chart.
enum ChartRange { week, twoWeeks, month, year }

extension on ChartRange {
  String get chip => switch (this) {
        ChartRange.week => '7 Days',
        ChartRange.twoWeeks => '2 Weeks',
        ChartRange.month => '1 Month',
        ChartRange.year => '1 Year',
      };

  String get title => switch (this) {
        ChartRange.week => 'Last 7 days',
        ChartRange.twoWeeks => 'Last 2 weeks',
        ChartRange.month => 'Last 30 days',
        ChartRange.year => 'Last 12 months',
      };

  String get previous => switch (this) {
        ChartRange.week => 'previous 7 days',
        ChartRange.twoWeeks => 'previous 2 weeks',
        ChartRange.month => 'previous 30 days',
        ChartRange.year => 'previous 12 months',
      };

  /// Number of bars.
  int get count => switch (this) {
        ChartRange.week => 7,
        ChartRange.twoWeeks => 14,
        ChartRange.month => 30,
        ChartRange.year => 12,
      };

  /// The value sent to the server as ?period=
  String get code => switch (this) {
        ChartRange.week => '7d',
        ChartRange.twoWeeks => '2w',
        ChartRange.month => '1m',
        ChartRange.year => '1y',
      };

  /// The year view groups sales by month, the others by day.
  bool get monthly => this == ChartRange.year;
}

ChartRange _rangeFromCode(String code) => ChartRange.values
    .firstWhere((r) => r.code == code, orElse: () => ChartRange.week);

/* ------------------------------- the data ------------------------------- */

class _Bar {
  _Bar(this.start);

  /// First day of the bucket (the day itself, or the 1st of the month).
  final DateTime start;
  int qty = 0;
}

class _Data {
  const _Data({
    required this.bars,
    required this.total,
    required this.previous,
    required this.orders,
  });

  /// Chart built from the server answer (GET dashboard/sales).
  factory _Data.fromStats(DashboardStats s) => _Data(
        bars: [for (final p in s.points) _Bar(p.date)..qty = p.units],
        total: s.total,
        previous: s.previousTotal,
        orders: s.orders,
      );

  final List<_Bar> bars;
  final int total; // units in the selected range
  final int previous; // units in the same-length period before it
  final int orders; // number of sales in the selected range

  int get max => bars.fold(0, (a, b) => b.qty > a ? b.qty : a);

  /// Index of the highest bar, or -1 when there are no sales.
  int get best {
    var idx = -1;
    var top = 0;
    for (var i = 0; i < bars.length; i++) {
      if (bars[i].qty > top) {
        top = bars[i].qty;
        idx = i;
      }
    }
    return idx;
  }
}

/// Everything the chart shows is computed from the sales list and the
/// selected range, so changing the filter changes bars, labels, totals,
/// averages and the comparison at once.
_Data _compute(List<SaleRecord> sales, ChartRange range, DateTime now) {
  final n = range.count;
  final today = DateTime(now.year, now.month, now.day);
  final starts = range.monthly
      ? [for (var i = n - 1; i >= 0; i--) DateTime(today.year, today.month - i, 1)]
      : [for (var i = n - 1; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
  final bars = [for (final s in starts) _Bar(s)];

  final first = starts.first;
  final firstUtc = DateTime.utc(first.year, first.month, first.day);
  var total = 0;
  var previous = 0;
  var orders = 0;

  for (final s in sales) {
    final d = DateTime.tryParse(s.saleDate);
    if (d == null) continue;
    final int idx = range.monthly
        ? (d.year - first.year) * 12 + (d.month - first.month)
        : DateTime.utc(d.year, d.month, d.day).difference(firstUtc).inDays;
    if (idx >= 0 && idx < n) {
      bars[idx].qty += s.totalQty;
      total += s.totalQty;
      orders++;
    } else if (idx < 0 && idx >= -n) {
      previous += s.totalQty;
    }
  }
  return _Data(bars: bars, total: total, previous: previous, orders: orders);
}

String _units(int n) => '$n unit${n == 1 ? '' : 's'}';

String _compact(int n) =>
    n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

/* -------------------------------- the card -------------------------------- */

/// Home dashboard chart with a 7 days / 2 weeks / 1 month / 1 year filter.
/// 7 days is selected by default. Tap a bar to see that day (or month).
class SalesChart extends StatefulWidget {
  const SalesChart({super.key, required this.sales});
  final List<SaleRecord> sales;

  @override
  State<SalesChart> createState() => _SalesChartState();
}

class _SalesChartState extends State<SalesChart> {
  /// Set from the cubit on every build (the cubit keeps the selected filter).
  ChartRange _range = ChartRange.week;
  int? _sel;

  @override
  void initState() {
    super.initState();
    final c = context.read<DashboardCubit>();
    c.ensure(c.state.period);
  }

  void _setRange(ChartRange r) {
    if (r == _range) return;
    HapticFeedback.selectionClick();
    setState(() => _sel = null);
    context.read<DashboardCubit>().select(r.code);
  }

  void _toggle(int i) => setState(() => _sel = _sel == i ? null : i);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, ds) {
        _range = _rangeFromCode(ds.period);

        // Server data when we have it; otherwise the sales saved on this
        // phone, so the card is never empty while loading or offline.
        final stats = ds.data[ds.period];
        final fromServer = stats != null && stats.points.length == _range.count;
        final data = fromServer
            ? _Data.fromStats(stats)
            : _compute(widget.sales, _range, DateTime.now());
        final syncing = ds.loading.contains(ds.period);
        final offline = !fromServer && ds.failed.contains(ds.period);
        final sel = (_sel != null && _sel! < data.bars.length) ? _sel : null;

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: cardDecoration(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Sales overview',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.text)),
                  if (syncing) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.red),
                    ),
                  ],
                  const Spacer(),
                  Pill(_units(data.total), icon: Icons.trending_up_rounded),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 24,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _subline(data, sel),
                ),
              ),
              const SizedBox(height: 10),
              _RangeSelector(selected: _range, onChanged: _setRange),
              const SizedBox(height: 16),
              _chart(data, sel, fromServer),
              if (data.total == 0 && !syncing)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Center(
                    child: Text('No sales recorded in this period.',
                        style:
                            TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ),
                ),
              if (offline)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_rounded,
                          size: 14, color: AppColors.textDim),
                      SizedBox(width: 6),
                      Text('Offline: showing sales saved on this phone.',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 11.5)),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              _stats(data),
            ],
          ),
        );
      },
    );
  }

  /* ------------------------------ sub line ------------------------------ */

  Widget _subline(_Data data, int? sel) {
    if (sel != null) {
      final b = data.bars[sel];
      final label = _range.monthly
          ? DateFormat('MMMM yyyy').format(b.start)
          : DateFormat('EEE, dd MMM yyyy').format(b.start);
      return Row(
        key: ValueKey('sel-$_range-$sel'),
        children: [
          const Icon(Icons.touch_app_rounded, size: 16, color: AppColors.red),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label  -  ${_units(b.qty)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: AppColors.redDeep),
            ),
          ),
        ],
      );
    }

    final int? pct = data.previous > 0
        ? (((data.total - data.previous) / data.previous) * 100).round()
        : null;

    return Row(
      key: ValueKey('sum-$_range'),
      children: [
        Text(_range.title,
            style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 13.5,
                fontWeight: FontWeight.w600)),
        if (pct != null) ...[
          const SizedBox(width: 8),
          _DeltaChip(pct: pct),
          const SizedBox(width: 6),
          Flexible(
            child: Text('vs ${_range.previous}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim, fontSize: 11.5)),
          ),
        ],
      ],
    );
  }

  /* -------------------------------- chart -------------------------------- */

  String _axisLabel(int i, _Data data) {
    final d = data.bars[i].start;
    return switch (_range) {
      ChartRange.week => DateFormat('E').format(d),
      ChartRange.twoWeeks => '${d.day}',
      // today, then every 5th day going back
      ChartRange.month => (data.bars.length - 1 - i) % 5 == 0 ? '${d.day}' : '',
      ChartRange.year => DateFormat('MMM').format(d),
    };
  }

   /* -------------------------------- chart -------------------------------- */

  Widget _chart(_Data data, int? sel, bool fromServer) {
    final n = data.bars.length;

    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDF0F5)),
      ),
      child: TweenAnimationBuilder<double>(
        key: ValueKey('$_range-$fromServer'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, animation, _) {
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (n == 0) return;

                        final width = constraints.maxWidth;
                        const horizontalPadding = 14.0;
                        final usableWidth = width - horizontalPadding * 2;

                        if (usableWidth <= 0) return;

                        final dx = details.localPosition.dx -
                            horizontalPadding;

                        final index = n == 1
                            ? 0
                            : (dx / usableWidth * (n - 1))
                                .round()
                                .clamp(0, n - 1)
                                .toInt();

                        _toggle(index);
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SalesLinePainter(
                          bars: data.bars,
                          selectedIndex: sel,
                          bestIndex: data.best,
                          animation: animation,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 17,
                child: Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Text(
                          _axisLabel(i, data),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: _range == ChartRange.month ? 9 : 10,
                            fontWeight: i == n - 1
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: i == n - 1
                                ? AppColors.red
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar({
    required _Data data,
    required int i,
    required int? sel,
    required int max,
    required int best,
    required double t,
    required double gap,
    required double radius,
    required double valueSize,
    required double axisSize,
  }) {
    final b = data.bars[i];
    final has = b.qty > 0;
    final isCurrent = i == data.bars.length - 1;
    final isSel = sel == i;
    final dim = sel != null && !isSel;

    final target = max == 0 ? 5.0 : 5 + (b.qty / max) * 90;
    final h = 5 + (target - 5) * t;

    // 30 bars are too narrow for numbers: only the best / tapped bar get one.
    final showValue = has &&
        (_range == ChartRange.month ? (isSel || i == best) : true);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(i),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: dim ? 0.4 : 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showValue)
              _Lbl(
                _compact(b.qty),
                TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.redDeep),
              ),
            const SizedBox(height: 3),
            Container(
              margin: EdgeInsets.symmetric(horizontal: gap),
              height: h,
              decoration: BoxDecoration(
                gradient: has ? AppGradients.primary : null,
                color: has ? null : AppColors.redLight,
                borderRadius: BorderRadius.circular(radius),
                border: isSel
                    ? Border.all(color: AppColors.redDeep, width: 1.5)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            _Lbl(
              _axisLabel(i, data),
              TextStyle(
                fontSize: axisSize,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                color: isCurrent ? AppColors.red : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* -------------------------------- stats -------------------------------- */

  Widget _stats(_Data data) {
    final avg = data.total / _range.count;
    final avgText = avg >= 10 ? '${avg.round()}' : avg.toStringAsFixed(1);
    final best = data.best;
    final bestBar = best < 0 ? null : data.bars[best];
    final bestText = bestBar == null
        ? '-'
        : _range.monthly
            ? DateFormat('MMM yy').format(bestBar.start)
            : DateFormat('dd MMM').format(bestBar.start);

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.receipt_long_rounded,
            value: '${data.orders}',
            label: data.orders == 1 ? 'Order' : 'Orders',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.speed_rounded,
            value: avgText,
            label: _range.monthly ? 'Avg / month' : 'Avg / day',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.emoji_events_rounded,
            value: bestText,
            label: bestBar == null
                ? (_range.monthly ? 'Best month' : 'Best day')
                : '${_range.monthly ? 'Best month' : 'Best day'} - ${bestBar.qty}',
          ),
        ),
      ],
    );
  }
}

/* ------------------------------- small parts ------------------------------- */

/// One-line label that may be wider than its (narrow) bar column without
/// wrapping, centred under / over the bar.
class _Lbl extends StatelessWidget {
  const _Lbl(this.text, this.style);
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        width: double.infinity,
        child: OverflowBox(
          maxWidth: 48,
          child: Text(text, softWrap: false, maxLines: 1, style: style),
        ),
      );
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});
  final ChartRange selected;
  final ValueChanged<ChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.redTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final r in ChartRange.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: r == selected ? AppGradients.horizontal : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    r.chip,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: r == selected ? Colors.white : AppColors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final up = pct > 0;
    final flat = pct == 0;
    final color = flat
        ? AppColors.textDim
        : up
            ? AppColors.success
            : AppColors.redDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove_rounded
                : up
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 2),
          Text('${pct.abs()}%',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          color: AppColors.redTint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.red),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.text)),
            ),
            const SizedBox(height: 1),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim)),
          ],
        ),
      );
}
