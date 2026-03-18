import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/spx/gex_stream_bloc.dart';
import '../../models/gex_stream_models.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/google_fonts_stub.dart';

// ── Strike chart constants (shared by painter + touch handler) ────────────────
const _kStrikeLP = 52.0;  // left axis width
const _kStrikeRP = 44.0;  // right axis width
const _kStrikeTP = 10.0;  // top pad
const _kStrikeBP = 24.0;  // bottom axis height

// ── Colour palette (matches the screenshot aesthetic) ─────────────────────────
const _kPrice = Colors.white;
const _kGex = Color(0xFFD4A017);   // gold
const _kFlow = Color(0xFF00C896);  // teal
const _kIv = Color(0xFF4499FF);    // blue
const _kCallVol = Color(0xFF00FF87);
const _kPutVol = Color(0xFFFF3366);
const _kMaxGamma = Color(0xFF00C896);
const _kZeroGamma = Color(0xFF888888);
const _kMinGamma = Color(0xFF00C896);

// ── Time helpers ──────────────────────────────────────────────────────────────

/// Returns the market-open DateTime (9:30 AM) for the same calendar day as [t].
DateTime _marketOpenFor(DateTime t) => DateTime(t.year, t.month, t.day, 9, 30);

/// Minutes since market open (9:30 AM) for [t]. Can be negative before open.
double _toX(DateTime t) =>
    t.difference(_marketOpenFor(t)).inSeconds / 60.0;

// ── Screen ────────────────────────────────────────────────────────────────────

class SpxGexStreamScreen extends StatefulWidget {
  /// Tradier credentials are passed at construction time so this screen can be
  /// pushed via Navigator.push without needing a SpxBloc in the new route's
  /// widget tree.
  final String? tradierToken;
  final String tradierEnvironment;

  const SpxGexStreamScreen({
    super.key,
    required this.tradierToken,
    required this.tradierEnvironment,
  });

  @override
  State<SpxGexStreamScreen> createState() => _SpxGexStreamScreenState();
}

class _SpxGexStreamScreenState extends State<SpxGexStreamScreen> {
  late final GexStreamBloc _gexBloc;

  // Shared crosshair — nearest point index in the buffer.
  final _touchedIdx = ValueNotifier<int?>(-1);

  // 0 = time-series view, 1 = GEX-by-strike view
  int _viewTab = 0;

  // Zoom: visible time window in minutes. Default = 60 min.
  // The chart x-axis always spans [latestX - windowMinutes .. latestX],
  // anchored to the latest data (or market-close at 16:00).
  double _windowMinutes = 60.0;
  static const _minWindow = 5.0;
  static const _maxWindow = 390.0;

  // Pinch-zoom tracking.
  double _pinchStartWindow = 60.0;

  @override
  void initState() {
    super.initState();
    _gexBloc = GexStreamBloc(
      tradierToken: widget.tradierToken,
      tradierEnvironment: widget.tradierEnvironment,
    );
    _gexBloc.add(const GexStreamStarted());
  }

  @override
  void dispose() {
    _gexBloc.close();
    _touchedIdx.dispose();
    super.dispose();
  }

  void _setWindowMinutes(double v) {
    setState(() {
      _windowMinutes = v.clamp(_minWindow, _maxWindow);
      _touchedIdx.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GexStreamBloc, GexStreamState>(
      bloc: _gexBloc,
      builder: (context, state) {
        final points = state.points;
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: _GexAppBar(
            state: state,
            windowMinutes: _windowMinutes,
            onZoomIn: () => _setWindowMinutes(_windowMinutes * 0.7),
            onZoomOut: () => _setWindowMinutes(_windowMinutes * 1.4),
            onZoomReset: () => _setWindowMinutes(60.0),
          ),
          body: points.isEmpty
              ? _EmptyState(isRunning: state.isRunning)
              : GestureDetector(
                  // Pinch-to-zoom: only intercepts 2-finger scale, does not
                  // conflict with fl_chart's single-finger crosshair pan.
                  onScaleStart: (_) =>
                      _pinchStartWindow = _windowMinutes,
                  onScaleUpdate: (d) {
                    if (d.scale == 1.0) return;
                    _setWindowMinutes(_pinchStartWindow / d.scale);
                  },
                  child: _ChartBody(
                    points: points,
                    strikeBars: state.strikeBars,
                    windowMinutes: _windowMinutes,
                    levels: state.levels,
                    quote: state.quote,
                    touchedIdx: _touchedIdx,
                    onTouch: (i) => _touchedIdx.value = i,
                    viewTab: _viewTab,
                    onTabChange: (t) => setState(() => _viewTab = t),
                  ),
                ),
        );
      },
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

class _GexAppBar extends StatelessWidget implements PreferredSizeWidget {
  final GexStreamState state;
  final double windowMinutes;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  const _GexAppBar({
    required this.state,
    required this.windowMinutes,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final lastUpdate = state.lastUpdated;
    final updateStr = lastUpdate != null
        ? DateFormat('HH:mm:ss').format(lastUpdate)
        : '--';

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppTheme.textPrimary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Text(
                'GEX STREAM',
                style: GoogleFonts.syne(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(width: 8),
              _LiveChip(isRunning: state.isRunning),
              const Spacer(),
              Text(
                updateStr,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 8),
              // Zoom controls
              _ZoomButton(icon: Icons.remove, onTap: onZoomOut),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onZoomReset,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    '${windowMinutes.round()}m',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, color: AppTheme.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _ZoomButton(icon: Icons.add, onTap: onZoomIn),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  final bool isRunning;
  const _LiveChip({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isRunning ? AppTheme.greenBg : AppTheme.bg3,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isRunning
              ? AppTheme.green.withValues(alpha: 0.45)
              : AppTheme.border2,
        ),
      ),
      child: Text(
        isRunning ? 'LIVE' : 'PAUSED',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isRunning ? AppTheme.green : AppTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.border2),
        ),
        child: Icon(icon, size: 13, color: AppTheme.textMuted),
      ),
    );
  }
}

// ── Empty / loading state ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isRunning;
  const _EmptyState({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRunning) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.green),
            ),
            const SizedBox(height: 16),
            Text(
              'Fetching options chain…',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textMuted),
            ),
          ] else ...[
            const Icon(Icons.signal_cellular_off_rounded,
                color: AppTheme.textMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              'No data',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chart body ────────────────────────────────────────────────────────────────

class _ChartBody extends StatelessWidget {
  final List<GexStreamPoint> points;
  final List<GexStrikeBar> strikeBars;
  final double windowMinutes;
  final GexLevels levels;
  final SpxQuoteData quote;
  final ValueNotifier<int?> touchedIdx;
  final ValueChanged<int?> onTouch;
  final int viewTab;
  final ValueChanged<int> onTabChange;

  const _ChartBody({
    required this.points,
    required this.strikeBars,
    required this.windowMinutes,
    required this.levels,
    required this.quote,
    required this.touchedIdx,
    required this.onTouch,
    required this.viewTab,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quote header (price, change, bid/ask/vol)
        if (quote.isPopulated)
          _QuoteHeader(quote: quote),
        // Tab toggle + legend row
        _TabRow(viewTab: viewTab, onTabChange: onTabChange),
        // Today's / 52-week range bars
        if (quote.isPopulated)
          _RangeBars(quote: quote),
        // ── Time-series view ──────────────────────────────────────────────
        if (viewTab == 0) ...[
          Expanded(
            flex: 50,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
              child: ValueListenableBuilder<int?>(
                valueListenable: touchedIdx,
                builder: (_, idx, __) => _PriceChart(
                  points: points,
                  windowMinutes: windowMinutes,
                  levels: levels,
                  touchedIdx: idx,
                  onTouch: onTouch,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 8, 0),
              child: ValueListenableBuilder<int?>(
                valueListenable: touchedIdx,
                builder: (_, idx, __) => _VolumeChart(
                  points: points,
                  windowMinutes: windowMinutes,
                  touchedIdx: idx,
                  onTouch: onTouch,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 22,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 8, 8),
              child: ValueListenableBuilder<int?>(
                valueListenable: touchedIdx,
                builder: (_, idx, __) => _RatioChart(
                  points: points,
                  windowMinutes: windowMinutes,
                  touchedIdx: idx,
                  onTouch: onTouch,
                ),
              ),
            ),
          ),
        ],
        // ── GEX by strike view ────────────────────────────────────────────
        if (viewTab == 1)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: _GexByStrikeChart(
                bars: strikeBars,
                spot: quote.spot,
                levels: levels,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

// ── Quote header ──────────────────────────────────────────────────────────────

class _QuoteHeader extends StatelessWidget {
  final SpxQuoteData quote;
  const _QuoteHeader({required this.quote});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final fmtVol = NumberFormat.compact(locale: 'en_US');
    final changeColor = quote.isUp ? AppTheme.green : AppTheme.red;
    final changeSign = quote.isUp ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Symbol + price block
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SPX',
                style: GoogleFonts.syne(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '\$${fmt.format(quote.spot)}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  Icon(
                    quote.isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: changeColor,
                    size: 14,
                  ),
                  Text(
                    '$changeSign\$${fmt.format(quote.change.abs())} '
                    '($changeSign${quote.changePercent.toStringAsFixed(2)}%)',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: changeColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          const VerticalDivider(color: AppTheme.border, width: 1, thickness: 1),
          const SizedBox(width: 16),
          // Stats grid
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (quote.bid > 0)
                  _StatCell(label: 'Bid', value: '\$${fmt.format(quote.bid)}'),
                if (quote.ask > 0)
                  _StatCell(label: 'Ask', value: '\$${fmt.format(quote.ask)}'),
                if (quote.spread > 0)
                  _StatCell(label: 'Spread', value: '\$${fmt.format(quote.spread)}'),
                _StatCell(label: 'Volume', value: quote.volume > 0 ? fmtVol.format(quote.volume) : '0'),
                _StatCell(label: 'Avg Vol', value: quote.avgVolume > 0 ? fmtVol.format(quote.avgVolume) : '0'),
                _StatCell(
                  label: 'Vol Ratio',
                  value: quote.avgVolume > 0 ? quote.volRatio.toStringAsFixed(2) : '0',
                ),
                _StatCell(
                  label: 'Beta',
                  value: quote.beta != 0 ? quote.beta.toStringAsFixed(2) : '--',
                ),
                _StatCell(
                  label: 'Mkt Cap',
                  value: quote.marketCap > 0 ? '\$${fmtVol.format(quote.marketCap)}' : '--',
                ),
                _StatCell(
                  label: 'P/E',
                  value: quote.peRatio > 0 ? quote.peRatio.toStringAsFixed(1) : '--',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: AppTheme.textMuted,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Range bars ────────────────────────────────────────────────────────────────

class _RangeBars extends StatelessWidget {
  final SpxQuoteData quote;
  const _RangeBars({required this.quote});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _RangeBar(
            label: "TODAY'S RANGE",
            low: quote.dayLow,
            high: quote.dayHigh,
            current: quote.spot,
            color: const Color(0xFF4A90E2),
          )),
          const SizedBox(width: 16),
          Expanded(child: _RangeBar(
            label: '52-WEEK RANGE',
            low: quote.week52Low,
            high: quote.week52High,
            current: quote.spot,
            color: const Color(0xFF4A90E2),
          )),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final String label;
  final double low;
  final double high;
  final double current;
  final Color color;

  const _RangeBar({
    required this.label,
    required this.low,
    required this.high,
    required this.current,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final range = high - low;
    final t = range > 0 ? ((current - low) / range).clamp(0.0, 1.0) : 0.5;
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (_, constraints) {
          final w = constraints.maxWidth;
          const trackH = 6.0;
          const dotR = 9.0;
          return SizedBox(
            height: dotR * 2,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Track background
                Positioned(
                  left: dotR,
                  right: dotR,
                  child: Container(
                    height: trackH,
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Filled portion (low → current)
                Positioned(
                  left: dotR,
                  width: (w - dotR * 2) * t,
                  child: Container(
                    height: trackH,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Current price dot
                Positioned(
                  left: dotR + (w - dotR * 2) * t - dotR,
                  child: Container(
                    width: dotR * 2,
                    height: dotR * 2,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Low: \$${fmt.format(low)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: AppTheme.textMuted),
            ),
            Text(
              'High: \$${fmt.format(high)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: AppTheme.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  final _items = const [
    (_kPrice, 'Price'),
    (_kGex, 'Net GEX'),
    (_kFlow, 'Net Flow'),
    (_kIv, 'Net IV'),
    (_kMaxGamma, 'Max γ'),
    (_kZeroGamma, 'Zero γ'),
    (_kCallVol, 'Call Vol'),
    (_kPutVol, 'Put Vol'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _items.map((item) {
            final (color, label) = item;
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 2,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Finds the index in [pts] whose time is nearest to [xMinutes] (minutes since
/// market open). Used to map a chart touch position back to a buffer index.
int _nearestIdx(List<GexStreamPoint> pts, double xMinutes) {
  if (pts.isEmpty) return 0;
  int best = 0;
  double bestDist = double.infinity;
  for (int i = 0; i < pts.length; i++) {
    final d = (_toX(pts[i].time) - xMinutes).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

// ── Price chart ───────────────────────────────────────────────────────────────

class _PriceChart extends StatelessWidget {
  final List<GexStreamPoint> points;
  final double windowMinutes;
  final GexLevels levels;
  final int? touchedIdx;
  final ValueChanged<int?> onTouch;

  const _PriceChart({
    required this.points,
    required this.windowMinutes,
    required this.levels,
    required this.touchedIdx,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    // Time-based x: minutes since 9:30 AM market open.
    // Left-anchored: data builds from 0 (open) towards the right.
    final marketOpen = _marketOpenFor(points.last.time);
    final latestX = math.max(1.0, _toX(points.last.time));
    const chartMinX = 0.0;
    final chartMaxX = latestX;

    final prices = points.map((p) => p.price).toList();
    final priceMin = prices.reduce(math.min);
    final priceMax = prices.reduce(math.max);
    final pricePad = math.max((priceMax - priceMin) * 0.1, 1.0);
    final yMin = priceMin - pricePad;
    final yMax = priceMax + pricePad;
    final yRange = yMax - yMin;

    final gexValues = points.map((p) => p.netGex).toList();
    final gexMin = gexValues.reduce(math.min);
    final gexMax = gexValues.reduce(math.max);

    final flowValues = points.map((p) => p.netFlow).toList();
    final flowMin = flowValues.reduce(math.min);
    final flowMax = flowValues.reduce(math.max);

    final ivValues = points.map((p) => p.netIv).toList();
    final ivMin = ivValues.reduce(math.min);
    final ivMax = ivValues.reduce(math.max);

    double scaleToPrice(double v, double vMin, double vMax) {
      if (vMax == vMin) return yMin + yRange * 0.3;
      return yMin + ((v - vMin) / (vMax - vMin)) * yRange * 0.45;
    }

    FlSpot toSpot(GexStreamPoint p, double v) => FlSpot(_toX(p.time), v);

    final priceSpots = points.map((p) => toSpot(p, p.price)).toList();
    final gexSpots = points.map((p) => toSpot(p, scaleToPrice(p.netGex, gexMin, gexMax))).toList();
    final flowSpots = points.map((p) => toSpot(p, scaleToPrice(p.netFlow, flowMin, flowMax))).toList();
    final ivSpots = points.map((p) => toSpot(p, scaleToPrice(p.netIv, ivMin, ivMax))).toList();

    List<HorizontalLine> hLines = [];
    if (levels.isPopulated) {
      hLines = [
        _hLine(levels.maxGamma.clamp(yMin, yMax), _kMaxGamma, 'Max γ ${levels.maxGamma.toStringAsFixed(0)}'),
        _hLine(levels.zeroGamma.clamp(yMin, yMax), _kZeroGamma, 'Zero γ ${levels.zeroGamma.toStringAsFixed(0)}'),
        _hLine(levels.minGamma.clamp(yMin, yMax), _kMinGamma, 'Min γ ${levels.minGamma.toStringAsFixed(0)}'),
      ];
    }

    final showTooltip = touchedIdx != null &&
        touchedIdx! >= 0 &&
        touchedIdx! < points.length;

    return LineChart(
      LineChartData(
        minX: chartMinX,
        maxX: chartMaxX,
        minY: yMin,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(yRange / 4, 0.01),
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.border.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: yRange / 4,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(1),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8, color: AppTheme.textMuted),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1.0, windowMinutes / 6),
              getTitlesWidget: (v, _) {
                // v = minutes since market open → reconstruct clock time
                final t = marketOpen.add(Duration(seconds: (v * 60).round()));
                return Text(
                  DateFormat('HH:mm').format(t),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 7, color: AppTheme.textMuted),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(horizontalLines: hLines),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlPanEndEvent ||
                event is FlLongPressEnd) {
              onTouch(null);
            } else if (response?.lineBarSpots?.isNotEmpty == true) {
              onTouch(_nearestIdx(points, response!.lineBarSpots!.first.x));
            }
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: AppTheme.bg3.withValues(alpha: 0.95),
            getTooltipItems: (spots) {
              if (!showTooltip) return spots.map((_) => null).toList();
              final p = points[touchedIdx!];
              final labels = [
                p.price.toStringAsFixed(2),
                'GEX ${p.netGex.toStringAsFixed(1)}M',
                'Flow ${(p.netFlow / 1000).toStringAsFixed(0)}K',
                'IV ${(p.netIv * 100).toStringAsFixed(1)}%',
              ];
              return spots.asMap().entries.map((e) {
                final label = e.key < labels.length ? labels[e.key] : '';
                final colors = [_kPrice, _kGex, _kFlow, _kIv];
                final c = e.key < colors.length ? colors[e.key] : Colors.white;
                return LineTooltipItem(
                  label,
                  GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: c,
                      fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (barData, spots) => spots
              .map((_) => TouchedSpotIndicatorData(
                    const FlLine(color: Colors.white24, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                              radius: 3,
                              color: Colors.white,
                              strokeWidth: 0),
                    ),
                  ))
              .toList(),
        ),
        showingTooltipIndicators: showTooltip
            ? [
                ShowingTooltipIndicators([
                  LineBarSpot(
                    LineChartBarData(spots: priceSpots),
                    0,
                    priceSpots[touchedIdx!],
                  ),
                ]),
              ]
            : [],
        lineBarsData: [
          _line(priceSpots, _kPrice, 1.5),
          _line(gexSpots, _kGex, 1.0),
          _line(flowSpots, _kFlow, 1.0, isStep: true),
          _line(ivSpots, _kIv, 1.0),
        ],
      ),
    );
  }

  HorizontalLine _hLine(double y, Color color, String label) {
    return HorizontalLine(
      y: y,
      color: color.withValues(alpha: 0.6),
      strokeWidth: 1,
      dashArray: [4, 4],
      label: HorizontalLineLabel(
        show: true,
        alignment: Alignment.topRight,
        labelResolver: (_) => label,
        style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600),
      ),
    );
  }

  LineChartBarData _line(
    List<FlSpot> spots,
    Color color,
    double width, {
    bool isStep = false,
  }) {
    return LineChartBarData(
      spots: spots,
      color: color,
      barWidth: width,
      isCurved: !isStep,
      isStepLineChart: isStep,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}

// ── Volume chart ──────────────────────────────────────────────────────────────

class _VolumeChart extends StatelessWidget {
  final List<GexStreamPoint> points;
  final double windowMinutes;
  final int? touchedIdx;
  final ValueChanged<int?> onTouch;

  const _VolumeChart({
    required this.points,
    required this.windowMinutes,
    required this.touchedIdx,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    // All bars shown from session start (left-anchored).
    const sliceOffset = 0;
    final visible = points;

    final groups = visible.asMap().entries.map((e) {
      final i = e.key;
      final p = e.value;
      final origIdx = sliceOffset + i;
      final touched = touchedIdx == origIdx;
      final alpha = touched ? 1.0 : 0.65;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: p.callVol.toDouble(),
            color: _kCallVol.withValues(alpha: alpha),
            width: math.max(1, 400 / visible.length),
            borderRadius: BorderRadius.zero,
          ),
          BarChartRodData(
            toY: p.putVol.toDouble(),
            color: _kPutVol.withValues(alpha: alpha),
            width: math.max(1, 400 / visible.length),
            borderRadius: BorderRadius.zero,
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        barGroups: groups,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlPanEndEvent) {
              onTouch(null);
            } else if (response?.spot != null) {
              onTouch((sliceOffset + response!.spot!.touchedBarGroupIndex).toInt());
            }
          },
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: AppTheme.bg3.withValues(alpha: 0.95),
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              final p = visible[groupIdx];
              final isCall = rodIdx == 0;
              return BarTooltipItem(
                '${isCall ? "C" : "P"} ${isCall ? p.callVol : p.putVol}',
                GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: isCall ? _kCallVol : _kPutVol,
                    fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Ratio chart ───────────────────────────────────────────────────────────────

class _RatioChart extends StatelessWidget {
  final List<GexStreamPoint> points;
  final double windowMinutes;
  final int? touchedIdx;
  final ValueChanged<int?> onTouch;

  const _RatioChart({
    required this.points,
    required this.windowMinutes,
    required this.touchedIdx,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final marketOpen = _marketOpenFor(points.last.time);
    final latestX = math.max(1.0, _toX(points.last.time));
    const chartMinX = 0.0;
    final chartMaxX = latestX;

    FlSpot toSpot(GexStreamPoint p, double v) => FlSpot(_toX(p.time), v);

    final gexSpots = points.map((p) => toSpot(p, p.gexRatio)).toList();
    final flowSpots = points.map((p) => toSpot(p, p.flowRatio)).toList();
    final ivSpots = points.map((p) => toSpot(p, p.ivRatio)).toList();

    final showTooltip = touchedIdx != null &&
        touchedIdx! >= 0 &&
        touchedIdx! < points.length;

    return LineChart(
      LineChartData(
        minX: chartMinX,
        maxX: chartMaxX,
        minY: 0,
        maxY: 1,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.border.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 0.5,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(1),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8, color: AppTheme.textMuted),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 14,
              getTitlesWidget: (_, __) => Text(
                'Ratio',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8, color: AppTheme.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: math.max(1.0, windowMinutes / 6),
              getTitlesWidget: (v, _) {
                final t = marketOpen.add(Duration(seconds: (v * 60).round()));
                return Text(
                  DateFormat('HH:mm').format(t),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 7, color: AppTheme.textMuted),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlPanEndEvent ||
                event is FlLongPressEnd) {
              onTouch(null);
            } else if (response?.lineBarSpots?.isNotEmpty == true) {
              onTouch(_nearestIdx(points, response!.lineBarSpots!.first.x));
            }
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: AppTheme.bg3.withValues(alpha: 0.95),
            getTooltipItems: (spots) {
              if (!showTooltip) return spots.map((_) => null).toList();
              final p = points[touchedIdx!];
              final labels = [
                'GEX ${p.gexRatio.toStringAsFixed(2)}',
                'Flow ${p.flowRatio.toStringAsFixed(2)}',
                'IV ${p.ivRatio.toStringAsFixed(2)}',
              ];
              final colors = [_kGex, _kFlow, _kIv];
              return spots.asMap().entries.map((e) {
                final label = e.key < labels.length ? labels[e.key] : '';
                final c = e.key < colors.length ? colors[e.key] : Colors.white;
                return LineTooltipItem(
                  label,
                  GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: c,
                      fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (barData, spots) => spots
              .map((_) => TouchedSpotIndicatorData(
                    const FlLine(color: Colors.white24, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                              radius: 3,
                              color: Colors.white,
                              strokeWidth: 0),
                    ),
                  ))
              .toList(),
        ),
        lineBarsData: [
          _ratioLine(gexSpots, _kGex),
          _ratioLine(flowSpots, _kFlow),
          _ratioLine(ivSpots, _kIv),
        ],
      ),
    );
  }

  LineChartBarData _ratioLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 1.2,
      isCurved: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.06),
      ),
    );
  }
}

// ── Tab row ───────────────────────────────────────────────────────────────────

class _TabRow extends StatelessWidget {
  final int viewTab;
  final ValueChanged<int> onTabChange;
  const _TabRow({required this.viewTab, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          const SizedBox(width: 12),
          _TabBtn(label: 'STREAM',  active: viewTab == 0, onTap: () => onTabChange(0)),
          const SizedBox(width: 6),
          _TabBtn(label: 'STRIKES', active: viewTab == 1, onTap: () => onTabChange(1)),
          const SizedBox(width: 8),
          if (viewTab == 0) const Expanded(child: _Legend()),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTheme.bg3 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? AppTheme.border2 : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: active ? AppTheme.textPrimary : AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── GEX by Strike chart ───────────────────────────────────────────────────────

enum _StrikeChartMode { net, split }

class _GexByStrikeChart extends StatefulWidget {
  final List<GexStrikeBar> bars;
  final double spot;
  final GexLevels levels;

  const _GexByStrikeChart({
    required this.bars,
    required this.spot,
    required this.levels,
  });

  @override
  State<_GexByStrikeChart> createState() => _GexByStrikeChartState();
}

class _GexByStrikeChartState extends State<_GexByStrikeChart> {
  final _hovered = ValueNotifier<double?>(null);

  // ── Chart mode ────────────────────────────────────────────────────────────
  _StrikeChartMode _chartMode = _StrikeChartMode.net;

  // ── Layer visibility toggles ──────────────────────────────────────────────
  bool _showBars       = true;
  bool _showAggLine    = true;   // net mode only
  bool _showAbsLine    = true;   // split mode only
  bool _showWalls      = true;
  bool _showGammaFlip  = true;
  bool _showSpotLine   = true;
  bool _showBgZones    = true;

  List<GexStrikeBar> get _visible {
    if (widget.bars.isEmpty) return [];
    if (widget.spot <= 0 || widget.bars.length <= 80) return widget.bars;
    int closestIdx = 0;
    double closestDist = double.infinity;
    for (int i = 0; i < widget.bars.length; i++) {
      final d = (widget.bars[i].strike - widget.spot).abs();
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }
    final start = math.max(0, closestIdx - 40);
    final end = math.min(widget.bars.length, closestIdx + 40);
    return widget.bars.sublist(start, end);
  }

  void _onTouch(Offset pos, Size size) {
    final vis = _visible;
    if (vis.isEmpty) return;
    final plotW = size.width - _kStrikeLP - _kStrikeRP;
    final minS = vis.first.strike;
    final maxS = vis.last.strike;
    final range = maxS - minS;
    if (range == 0) return;
    final relX = (pos.dx - _kStrikeLP).clamp(0.0, plotW);
    final target = minS + relX / plotW * range;
    GexStrikeBar? best;
    double bestD = double.infinity;
    for (final b in vis) {
      final d = (b.strike - target).abs();
      if (d < bestD) { bestD = d; best = b; }
    }
    _hovered.value = best?.strike;
  }

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visible;
    if (vis.isEmpty) {
      return Center(
        child: Text(
          'Waiting for options chain…',
          style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }

    final maxAbsGex = _chartMode == _StrikeChartMode.split
        ? vis.map((b) => b.callGexRaw + b.putGexRaw).fold(0.0, math.max)
        : vis.map((b) => b.netGexRaw.abs()).fold(0.0, math.max);
    final cumVals = vis.map((b) => b.cumulativeGexB).toList();
    final cumMin = cumVals.reduce(math.min);
    final cumMax = cumVals.reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode toggle
        Padding(
          padding: const EdgeInsets.only(left: _kStrikeLP, bottom: 6),
          child: Row(
            children: [
              _modeButton('Net GEX', _StrikeChartMode.net),
              const SizedBox(width: 6),
              _modeButton('Split GEX', _StrikeChartMode.split),
            ],
          ),
        ),
        // Legend / toggles
        Padding(
          padding: const EdgeInsets.only(left: _kStrikeLP, bottom: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _chartMode == _StrikeChartMode.net
                ? [
                    _toggleChip(color: const Color(0xFFFF8C00), label: 'GEX Bars',    active: _showBars,      dot: true,    onTap: () => setState(() => _showBars      = !_showBars)),
                    _toggleChip(color: const Color(0xFF87CEEB), label: 'Agg GEX',     active: _showAggLine,   line: true,   onTap: () => setState(() => _showAggLine   = !_showAggLine)),
                    _toggleChip(color: const Color(0xFF888888), label: 'Walls',        active: _showWalls,     dashed: true, onTap: () => setState(() => _showWalls     = !_showWalls)),
                    _toggleChip(color: AppTheme.red,            label: 'Gamma Flip',   active: _showGammaFlip, dashed: true, onTap: () => setState(() => _showGammaFlip = !_showGammaFlip)),
                    _toggleChip(color: AppTheme.green,          label: 'Last Price',   active: _showSpotLine,  line: true,   onTap: () => setState(() => _showSpotLine  = !_showSpotLine)),
                    _toggleChip(color: AppTheme.green,          label: 'BG Zones',     active: _showBgZones,   dot: true,    onTap: () => setState(() => _showBgZones   = !_showBgZones)),
                  ]
                : [
                    _toggleChip(color: const Color(0xFF4499FF), label: 'Call GEX',    active: _showBars,      dot: true,    onTap: () => setState(() => _showBars      = !_showBars)),
                    _toggleChip(color: const Color(0xFFFF8C00), label: 'Put GEX',     active: _showBars,      dot: true,    onTap: () => setState(() => _showBars      = !_showBars)),
                    _toggleChip(color: const Color(0xFF00C896), label: 'Abs Exposure', active: _showAbsLine,   line: true,   onTap: () => setState(() => _showAbsLine   = !_showAbsLine)),
                    _toggleChip(color: const Color(0xFF888888), label: 'Walls',        active: _showWalls,     dashed: true, onTap: () => setState(() => _showWalls     = !_showWalls)),
                    _toggleChip(color: AppTheme.red,            label: 'Gamma Flip',   active: _showGammaFlip, dashed: true, onTap: () => setState(() => _showGammaFlip = !_showGammaFlip)),
                    _toggleChip(color: AppTheme.green,          label: 'Last Price',   active: _showSpotLine,  line: true,   onTap: () => setState(() => _showSpotLine  = !_showSpotLine)),
                    _toggleChip(color: AppTheme.green,          label: 'BG Zones',     active: _showBgZones,   dot: true,    onTap: () => setState(() => _showBgZones   = !_showBgZones)),
                  ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        onTapDown:   (d) => _onTouch(d.localPosition, size),
        onPanStart:  (d) => _onTouch(d.localPosition, size),
        onPanUpdate: (d) => _onTouch(d.localPosition, size),
        onPanEnd:    (_) => _hovered.value = null,
        onTapCancel: ()  => _hovered.value = null,
        child: ValueListenableBuilder<double?>(
          valueListenable: _hovered,
          builder: (_, hovered, __) {
            final hoveredBar = hovered == null
                ? null
                : vis.where((b) => b.strike == hovered).firstOrNull;
            return Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _chartMode == _StrikeChartMode.net
                      ? _StrikeChartPainter(
                          visible:       vis,
                          spot:          widget.spot,
                          gammaFlip:     widget.levels.zeroGamma,
                          callWall:      widget.levels.maxGamma,
                          putWall:       widget.levels.minGamma,
                          maxAbsGex:     math.max(maxAbsGex, 1.0),
                          cumMin:        cumMin,
                          cumMax:        cumMax,
                          hoveredStrike: hovered,
                          showBars:      _showBars,
                          showAggLine:   _showAggLine,
                          showWalls:     _showWalls,
                          showGammaFlip: _showGammaFlip,
                          showSpotLine:  _showSpotLine,
                          showBgZones:   _showBgZones,
                        )
                      : _SplitGexPainter(
                          visible:       vis,
                          spot:          widget.spot,
                          gammaFlip:     widget.levels.zeroGamma,
                          callWall:      widget.levels.maxGamma,
                          putWall:       widget.levels.minGamma,
                          maxAbsGex:     math.max(maxAbsGex, 1.0),
                          hoveredStrike: hovered,
                          showBars:      _showBars,
                          showAbsLine:   _showAbsLine,
                          showWalls:     _showWalls,
                          showGammaFlip: _showGammaFlip,
                          showSpotLine:  _showSpotLine,
                          showBgZones:   _showBgZones,
                        ),
                ),
                if (hoveredBar != null)
                  _StrikeTooltip(
                    bar: hoveredBar,
                    xFraction: _xFraction(hoveredBar.strike, vis),
                    size: size,
                    chartMode: _chartMode,
                  ),
              ],
            );
          },
        ),
      );
          }),
        ),
      ],
    );
  }

  Widget _modeButton(String label, _StrikeChartMode mode) {
    final active = _chartMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _chartMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.green.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? AppTheme.green.withValues(alpha: 0.5) : AppTheme.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? AppTheme.green : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required Color color,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool dot = false,
    bool line = false,
    bool dashed = false,
  }) {
    final effectiveColor = active ? color : AppTheme.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.12)
                : AppTheme.border.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.4) : AppTheme.border,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 10,
                child: CustomPaint(
                  painter: _LegendIconPainter(
                    color: effectiveColor,
                    dot: dot,
                    line: line,
                    dashed: dashed,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: active ? Colors.white : AppTheme.textMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _xFraction(double strike, List<GexStrikeBar> vis) {
    if (vis.isEmpty) return 0.5;
    final minS = vis.first.strike;
    final maxS = vis.last.strike;
    final range = maxS - minS;
    if (range == 0) return 0.5;
    return (strike - minS) / range;
  }
}

// ── Legend icon painter ───────────────────────────────────────────────────────

class _LegendIconPainter extends CustomPainter {
  final Color color;
  final bool dot;
  final bool line;
  final bool dashed;

  const _LegendIconPainter({
    required this.color,
    this.dot = false,
    this.line = false,
    this.dashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.5;
    final midY = size.height / 2;
    if (dot) {
      canvas.drawCircle(Offset(size.width / 2, midY), 4, paint..style = PaintingStyle.fill);
    } else if (line) {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint..style = PaintingStyle.stroke);
    } else if (dashed) {
      double x = 0;
      bool drawing = true;
      while (x < size.width) {
        final end = math.min(x + 3, size.width);
        if (drawing) canvas.drawLine(Offset(x, midY), Offset(end, midY), paint..style = PaintingStyle.stroke);
        x += drawing ? 3 : 2;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(_LegendIconPainter old) => color != old.color;
}

// ── Strike chart painter ──────────────────────────────────────────────────────

class _StrikeChartPainter extends CustomPainter {
  final List<GexStrikeBar> visible;
  final double spot;
  final double gammaFlip;
  final double callWall;
  final double putWall;
  final double maxAbsGex;
  final double cumMin;
  final double cumMax;
  final double? hoveredStrike;
  final bool showBars;
  final bool showAggLine;
  final bool showWalls;
  final bool showGammaFlip;
  final bool showSpotLine;
  final bool showBgZones;

  const _StrikeChartPainter({
    required this.visible,
    required this.spot,
    required this.gammaFlip,
    required this.callWall,
    required this.putWall,
    required this.maxAbsGex,
    required this.cumMin,
    required this.cumMax,
    required this.hoveredStrike,
    this.showBars       = true,
    this.showAggLine    = true,
    this.showWalls      = true,
    this.showGammaFlip  = true,
    this.showSpotLine   = true,
    this.showBgZones    = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (visible.isEmpty) return;

    final plotW  = size.width  - _kStrikeLP - _kStrikeRP;
    final plotH  = size.height - _kStrikeTP - _kStrikeBP;
    const pL     = _kStrikeLP;
    const pT     = _kStrikeTP;
    final pR     = pL + plotW;
    final pB     = pT + plotH;
    final midY   = pT + plotH / 2;

    final minS = visible.first.strike;
    final maxS = visible.last.strike;
    final sRange = maxS == minS ? 1.0 : maxS - minS;
    final cumRange = cumMax == cumMin ? 1.0 : cumMax - cumMin;

    double sx(double s) => pL + (s - minS) / sRange * plotW;
    double gy(double gex) => midY - (gex / maxAbsGex) * (plotH * 0.46);
    double cy(double cum) => pB - ((cum - cumMin) / cumRange) * plotH;

    final clipRect = Rect.fromLTRB(pL, pT, pR, pB);
    canvas.save();
    canvas.clipRect(clipRect);

    // 1. Background zones
    final flipX = sx(gammaFlip).clamp(pL, pR);
    if (showBgZones) {
      canvas.drawRect(
        Rect.fromLTRB(pL, pT, flipX, pB),
        Paint()..color = AppTheme.red.withValues(alpha: 0.06),
      );
      canvas.drawRect(
        Rect.fromLTRB(flipX, pT, pR, pB),
        Paint()..color = AppTheme.green.withValues(alpha: 0.06),
      );
    }

    // 2. Grid lines (horizontal)
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final y = midY - (i / 2) * (plotH * 0.46);
      if (y >= pT && y <= pB) {
        canvas.drawLine(Offset(pL, y), Offset(pR, y), gridPaint);
      }
    }

    // 3. GEX bars
    final y0 = gy(0);
    if (showBars) {
      final barW = math.max(2.0, plotW / visible.length * 0.65);
      for (final bar in visible) {
        final x     = sx(bar.strike);
        final y1    = gy(bar.netGexRaw);
        final isPos = bar.netGexRaw >= 0;
        final isHov = hoveredStrike == bar.strike;
        final color = isPos
            ? const Color(0xFF4499FF).withValues(alpha: isHov ? 1.0 : 0.75)
            : const Color(0xFFFF8C00).withValues(alpha: isHov ? 1.0 : 0.75);
        final rect = Rect.fromLTRB(
          x - barW / 2, math.min(y0, y1),
          x + barW / 2, math.max(y0, y1),
        );
        canvas.drawRect(rect, Paint()..color = color);
        if (isHov) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
    }

    // 4. Zero GEX line
    _drawDashed(canvas, Offset(pL, y0), Offset(pR, y0),
        Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 0.5);

    // 5. Cumulative line + subtle fill
    if (showAggLine) {
      final linePath = Path();
      bool first = true;
      for (final bar in visible) {
        final x = sx(bar.strike);
        final y = cy(bar.cumulativeGexB);
        if (first) { linePath.moveTo(x, y); first = false; }
        else        { linePath.lineTo(x, y); }
      }
      final fillPath = Path.from(linePath)
        ..lineTo(pR, pB)..lineTo(pL, pB)..close();
      canvas.drawPath(fillPath,
          Paint()..color = const Color(0xFF87CEEB).withValues(alpha: 0.07));
      canvas.drawPath(
        linePath,
        Paint()
          ..color = const Color(0xFF87CEEB).withValues(alpha: 0.9)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // 6. Vertical lines — spot + gamma flip + walls
    final spotX = sx(spot).clamp(pL, pR);

    if (showWalls) {
      if (putWall > 0) {
        final pwX = sx(putWall).clamp(pL, pR);
        _drawDashed(canvas, Offset(pwX, pT), Offset(pwX, pB),
            Paint()..color = const Color(0xFF888888)..strokeWidth = 1.0);
        _paintText(canvas, 'Put Wall', Offset(pwX + 2, pT + 2),
            const TextStyle(fontSize: 8, color: Color(0xFF888888), fontFamily: 'monospace'),
            TextAlign.left, 48);
      }
      if (callWall > 0) {
        final cwX = sx(callWall).clamp(pL, pR);
        _drawDashed(canvas, Offset(cwX, pT), Offset(cwX, pB),
            Paint()..color = const Color(0xFF888888)..strokeWidth = 1.0);
        _paintText(canvas, 'Call Wall', Offset(cwX + 2, pT + 2),
            const TextStyle(fontSize: 8, color: Color(0xFF888888), fontFamily: 'monospace'),
            TextAlign.left, 48);
      }
    }

    if (showGammaFlip) {
      _drawDashed(canvas, Offset(flipX, pT), Offset(flipX, pB),
          Paint()..color = AppTheme.red..strokeWidth = 1.0);
      _paintText(canvas, 'Gamma Flip', Offset(flipX + 2, pT + 12),
          const TextStyle(fontSize: 8, color: AppTheme.red, fontFamily: 'monospace'),
          TextAlign.left, 56);
    }

    if (showSpotLine) {
      canvas.drawLine(Offset(spotX, pT), Offset(spotX, pB),
          Paint()..color = AppTheme.green..strokeWidth = 1.5);
      final spotLabel = 'Last: ${spot.toStringAsFixed(0)}';
      final spotLabelX = (spotX + 2).clamp(pL, pR - 52.0);
      _paintText(canvas, spotLabel, Offset(spotLabelX, pT + 2),
          const TextStyle(fontSize: 8, color: AppTheme.green, fontFamily: 'monospace'),
          TextAlign.left, 52);
    }

    // 7. Hovered crosshair
    if (hoveredStrike != null) {
      final hx = sx(hoveredStrike!).clamp(pL, pR);
      canvas.drawLine(Offset(hx, pT), Offset(hx, pB),
          Paint()..color = Colors.white.withValues(alpha: 0.25)..strokeWidth = 1);
    }

    canvas.restore();

    // 8. Axes
    _drawAxes(canvas, size, pL, pT, pR, pB, plotW, plotH, midY,
        minS, maxS, sRange, cumMin, cumMax, cumRange);
  }

  void _drawAxes(
    Canvas canvas, Size size,
    double pL, double pT, double pR, double pB,
    double plotW, double plotH, double midY,
    double minS, double maxS, double sRange,
    double cumMin, double cumMax, double cumRange,
  ) {
    const style = TextStyle(
      fontSize: 8,
      color: Color(0xFF6677AA),
      fontFamily: 'monospace',
    );

    // Left axis: bar GEX labels (in billions)
    final leftVals = [-maxAbsGex, -maxAbsGex * 0.5, 0, maxAbsGex * 0.5, maxAbsGex];
    for (final v in leftVals) {
      final y = midY - (v / maxAbsGex) * (plotH * 0.46);
      if (y < pT || y > pB) continue;
      final label = '${(v / 1e9).toStringAsFixed(1)}B';
      _paintText(canvas, label, Offset(0, y - 4), style, TextAlign.right, _kStrikeLP - 4);
    }

    // Right axis: cumulative GEX labels
    for (int i = 0; i <= 4; i++) {
      final v = cumMin + (cumMax - cumMin) * i / 4;
      final y = pB - (i / 4) * plotH;
      final label = '${v.toStringAsFixed(1)}B';
      _paintText(canvas, label, Offset(pR + 3, y - 4), style, TextAlign.left, _kStrikeRP - 3);
    }

    // Bottom axis: strike labels
    final step = math.max(1, visible.length ~/ 8);
    for (int i = 0; i < visible.length; i += step) {
      final s = visible[i].strike;
      final x = pL + (s - minS) / sRange * plotW;
      _paintText(
        canvas,
        s.toStringAsFixed(0),
        Offset(x - 16, pB + 4),
        style,
        TextAlign.center,
        32,
      );
    }
  }

  void _paintText(Canvas canvas, String text, Offset offset,
      TextStyle style, TextAlign align, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  void _drawDashed(Canvas canvas, Offset p1, Offset p2, Paint paint,
      [double dash = 4, double gap = 4]) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    double dist = 0;
    bool drawing = true;
    while (dist < len) {
      final segLen = drawing ? dash : gap;
      final end = math.min(dist + segLen, len);
      if (drawing) {
        canvas.drawLine(
          Offset(p1.dx + ux * dist, p1.dy + uy * dist),
          Offset(p1.dx + ux * end,  p1.dy + uy * end),
          paint,
        );
      }
      dist += segLen;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(_StrikeChartPainter old) =>
      !identical(visible, old.visible) ||
      hoveredStrike != old.hoveredStrike ||
      spot != old.spot ||
      callWall != old.callWall ||
      putWall != old.putWall ||
      gammaFlip != old.gammaFlip ||
      showBars != old.showBars ||
      showAggLine != old.showAggLine ||
      showWalls != old.showWalls ||
      showGammaFlip != old.showGammaFlip ||
      showSpotLine != old.showSpotLine ||
      showBgZones != old.showBgZones;
}

// ── Split GEX painter ─────────────────────────────────────────────────────────
// Shows call GEX (blue, above zero) and put GEX (orange, below zero) as
// separate bars, plus an absolute-exposure green line.

class _SplitGexPainter extends CustomPainter {
  final List<GexStrikeBar> visible;
  final double spot;
  final double gammaFlip;
  final double callWall;
  final double putWall;
  final double maxAbsGex;
  final double? hoveredStrike;
  final bool showBars;
  final bool showAbsLine;
  final bool showWalls;
  final bool showGammaFlip;
  final bool showSpotLine;
  final bool showBgZones;

  const _SplitGexPainter({
    required this.visible,
    required this.spot,
    required this.gammaFlip,
    required this.callWall,
    required this.putWall,
    required this.maxAbsGex,
    required this.hoveredStrike,
    this.showBars      = true,
    this.showAbsLine   = true,
    this.showWalls     = true,
    this.showGammaFlip = true,
    this.showSpotLine  = true,
    this.showBgZones   = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (visible.isEmpty) return;

    final plotW = size.width  - _kStrikeLP - _kStrikeRP;
    final plotH = size.height - _kStrikeTP - _kStrikeBP;
    const pL    = _kStrikeLP;
    const pT    = _kStrikeTP;
    final pR    = pL + plotW;
    final pB    = pT + plotH;
    final midY  = pT + plotH / 2;

    final minS   = visible.first.strike;
    final maxS   = visible.last.strike;
    final sRange = maxS == minS ? 1.0 : maxS - minS;

    double sx(double s) => pL + (s - minS) / sRange * plotW;
    // Maps a positive value to canvas y: 0 → midY, maxAbsGex → pT+pad
    double gy(double v) => midY - (v / maxAbsGex) * (plotH * 0.46);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(pL, pT, pR, pB));

    // 1. Background zones
    final flipX = sx(gammaFlip).clamp(pL, pR);
    if (showBgZones) {
      canvas.drawRect(Rect.fromLTRB(pL, pT, flipX, pB),
          Paint()..color = AppTheme.red.withValues(alpha: 0.06));
      canvas.drawRect(Rect.fromLTRB(flipX, pT, pR, pB),
          Paint()..color = AppTheme.green.withValues(alpha: 0.06));
    }

    // 2. Grid lines
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final y = midY - (i / 2) * (plotH * 0.46);
      if (y >= pT && y <= pB) canvas.drawLine(Offset(pL, y), Offset(pR, y), gridPaint);
    }

    // 3. Zero line
    _drawDashedLine(canvas, Offset(pL, midY), Offset(pR, midY),
        Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 0.5);

    // 4. Split bars: call above midY, put below midY
    if (showBars) {
      final barW = math.max(2.0, plotW / visible.length * 0.65);
      for (final bar in visible) {
        final x     = sx(bar.strike);
        final isHov = hoveredStrike == bar.strike;

        // Call bar (blue, above zero)
        if (bar.callGexRaw > 0) {
          final yTop  = gy(bar.callGexRaw);
          final callRect = Rect.fromLTRB(x - barW / 2, yTop, x + barW / 2, midY);
          canvas.drawRect(callRect,
              Paint()..color = const Color(0xFF4499FF).withValues(alpha: isHov ? 1.0 : 0.75));
          if (isHov) canvas.drawRect(callRect,
              Paint()..color = Colors.white.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1);
        }

        // Put bar (orange, below zero — putGexRaw is positive magnitude)
        if (bar.putGexRaw > 0) {
          final yBot  = gy(-bar.putGexRaw);
          final putRect = Rect.fromLTRB(x - barW / 2, midY, x + barW / 2, yBot);
          canvas.drawRect(putRect,
              Paint()..color = const Color(0xFFFF8C00).withValues(alpha: isHov ? 1.0 : 0.75));
          if (isHov) canvas.drawRect(putRect,
              Paint()..color = Colors.white.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1);
        }
      }
    }

    // 5. Absolute exposure line (callGexRaw + putGexRaw, always positive → above midY)
    if (showAbsLine && visible.isNotEmpty) {
      final linePath = Path();
      bool first = true;
      for (final bar in visible) {
        final x = sx(bar.strike);
        final y = gy(bar.callGexRaw + bar.putGexRaw);
        if (first) { linePath.moveTo(x, y); first = false; }
        else        { linePath.lineTo(x, y); }
      }
      canvas.drawPath(linePath,
          Paint()
            ..color = const Color(0xFF00C896).withValues(alpha: 0.9)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);
    }

    // 6. Vertical lines — walls, gamma flip, spot
    final spotX = sx(spot).clamp(pL, pR);

    if (showWalls) {
      if (putWall > 0) {
        final pwX = sx(putWall).clamp(pL, pR);
        _drawDashedLine(canvas, Offset(pwX, pT), Offset(pwX, pB),
            Paint()..color = const Color(0xFF888888)..strokeWidth = 1.0);
        _paintLabel(canvas, 'Put Wall', Offset(pwX + 2, pT + 2),
            const TextStyle(fontSize: 8, color: Color(0xFF888888), fontFamily: 'monospace'), 48);
      }
      if (callWall > 0) {
        final cwX = sx(callWall).clamp(pL, pR);
        _drawDashedLine(canvas, Offset(cwX, pT), Offset(cwX, pB),
            Paint()..color = const Color(0xFF888888)..strokeWidth = 1.0);
        _paintLabel(canvas, 'Call Wall', Offset(cwX + 2, pT + 2),
            const TextStyle(fontSize: 8, color: Color(0xFF888888), fontFamily: 'monospace'), 48);
      }
    }

    if (showGammaFlip) {
      _drawDashedLine(canvas, Offset(flipX, pT), Offset(flipX, pB),
          Paint()..color = AppTheme.red..strokeWidth = 1.0);
      _paintLabel(canvas, 'Gamma Flip', Offset(flipX + 2, pT + 12),
          const TextStyle(fontSize: 8, color: AppTheme.red, fontFamily: 'monospace'), 56);
    }

    if (showSpotLine) {
      canvas.drawLine(Offset(spotX, pT), Offset(spotX, pB),
          Paint()..color = AppTheme.green..strokeWidth = 1.5);
      final lx = (spotX + 2).clamp(pL, pR - 52.0);
      _paintLabel(canvas, 'Last: ${spot.toStringAsFixed(0)}', Offset(lx, pT + 2),
          const TextStyle(fontSize: 8, color: AppTheme.green, fontFamily: 'monospace'), 52);
    }

    // 7. Hovered crosshair
    if (hoveredStrike != null) {
      final hx = sx(hoveredStrike!).clamp(pL, pR);
      canvas.drawLine(Offset(hx, pT), Offset(hx, pB),
          Paint()..color = Colors.white.withValues(alpha: 0.25)..strokeWidth = 1);
    }

    canvas.restore();

    // 8. Axes — left only (right axis unused in split mode)
    _drawSplitAxes(canvas, size, pL, pT, pR, pB, plotW, midY, minS, maxS, sRange);
  }

  void _drawSplitAxes(Canvas canvas, Size size,
      double pL, double pT, double pR, double pB,
      double plotW, double midY, double minS, double maxS, double sRange) {
    const style = TextStyle(fontSize: 8, color: Color(0xFF6677AA), fontFamily: 'monospace');

    // Left axis: ±maxAbsGex labels
    for (int i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final v = (i / 2) * maxAbsGex;
      final y = midY - (v / maxAbsGex) * ((pB - pT - _kStrikeBP) * 0.46);
      if (y < pT || y > pB) continue;
      final label = '${(v / 1e9).toStringAsFixed(1)}B';
      _paintLabel(canvas, label, Offset(0, y - 4), style, _kStrikeLP - 4);
    }

    // Bottom axis: strike labels
    final step = math.max(1, visible.length ~/ 8);
    for (int i = 0; i < visible.length; i += step) {
      final s = visible[i].strike;
      final x = pL + (s - minS) / sRange * plotW;
      _paintLabel(canvas, s.toStringAsFixed(0), Offset(x - 16, pB + 4), style, 32);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint,
      [double dash = 4, double gap = 4]) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len; final uy = dy / len;
    double dist = 0; bool drawing = true;
    while (dist < len) {
      final segLen = drawing ? dash : gap;
      final end = math.min(dist + segLen, len);
      if (drawing) canvas.drawLine(
        Offset(p1.dx + ux * dist, p1.dy + uy * dist),
        Offset(p1.dx + ux * end,  p1.dy + uy * end), paint);
      dist += segLen; drawing = !drawing;
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset offset,
      TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_SplitGexPainter old) =>
      !identical(visible, old.visible) ||
      hoveredStrike != old.hoveredStrike ||
      spot != old.spot ||
      callWall != old.callWall ||
      putWall != old.putWall ||
      gammaFlip != old.gammaFlip ||
      showBars != old.showBars ||
      showAbsLine != old.showAbsLine ||
      showWalls != old.showWalls ||
      showGammaFlip != old.showGammaFlip ||
      showSpotLine != old.showSpotLine ||
      showBgZones != old.showBgZones;
}

// ── Strike tooltip ────────────────────────────────────────────────────────────

class _StrikeTooltip extends StatelessWidget {
  final GexStrikeBar bar;
  final double xFraction;
  final Size size;
  final _StrikeChartMode chartMode;

  const _StrikeTooltip({
    required this.bar,
    required this.xFraction,
    required this.size,
    required this.chartMode,
  });

  @override
  Widget build(BuildContext context) {
    const w = 220.0;
    final fmtK      = NumberFormat.compact(locale: 'en_US');
    final fmtStrike = NumberFormat('#,##0.00', 'en_US');

    final xAnchor = _kStrikeLP + xFraction * (size.width - _kStrikeLP - _kStrikeRP);
    final left = xFraction > 0.6 ? xAnchor - w - 8 : xAnchor + 8;

    return Positioned(
      left: left.clamp(0, size.width - w),
      top: _kStrikeTP + 4,
      width: w,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            RichText(
              text: TextSpan(
                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppTheme.textMuted),
                children: [
                  const TextSpan(text: 'Strike: '),
                  TextSpan(
                    text: fmtStrike.format(bar.strike),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // GEX rows — differ by mode
            if (chartMode == _StrikeChartMode.net) ...[
              _bulletRow(
                color: bar.netGexRaw >= 0 ? const Color(0xFF4499FF) : const Color(0xFFFF8C00),
                label: 'Net Gamma Exposure: ',
                value: '${bar.netGexRaw >= 0 ? '+' : ''}${(bar.netGexRaw / 1e6).toStringAsFixed(0)}M',
                valueColor: bar.netGexRaw >= 0 ? const Color(0xFF4499FF) : const Color(0xFFFF8C00),
              ),
              const SizedBox(height: 2),
              _bulletRow(
                color: const Color(0xFF87CEEB),
                label: 'Aggregate Gamma Exposure: ',
                value: '${bar.cumulativeGexB >= 0 ? '+' : ''}${bar.cumulativeGexB.toStringAsFixed(2)}B',
                valueColor: const Color(0xFF87CEEB),
              ),
            ] else ...[
              _bulletRow(
                color: const Color(0xFF4499FF),
                label: 'Call Gamma Exposure: ',
                value: '+${(bar.callGexRaw / 1e6).toStringAsFixed(0)}M',
                valueColor: const Color(0xFF4499FF),
              ),
              const SizedBox(height: 2),
              _bulletRow(
                color: const Color(0xFFFF8C00),
                label: 'Put Gamma Exposure: ',
                value: '-${(bar.putGexRaw / 1e6).toStringAsFixed(0)}M',
                valueColor: const Color(0xFFFF8C00),
              ),
              const SizedBox(height: 2),
              _bulletRow(
                color: const Color(0xFF00C896),
                label: 'Absolute Exposure: ',
                value: '${((bar.callGexRaw + bar.putGexRaw) / 1e6).toStringAsFixed(0)}M',
                valueColor: const Color(0xFF00C896),
              ),
            ],
            const SizedBox(height: 8),
            _inlineRow('Call Open Interest: ', fmtK.format(bar.callOi)),
            const SizedBox(height: 2),
            _inlineRow('Put Open Interest: ',  fmtK.format(bar.putOi)),
            const SizedBox(height: 8),
            _inlineRow('Call Volume: ', fmtK.format(bar.callVol)),
            const SizedBox(height: 2),
            _inlineRow('Put Volume: ',  fmtK.format(bar.putVol)),
          ],
        ),
      ),
    );
  }

  Widget _bulletRow({
    required Color color,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppTheme.textMuted),
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _inlineRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppTheme.textMuted),
        children: [
          TextSpan(text: label),
          TextSpan(
            text: value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
