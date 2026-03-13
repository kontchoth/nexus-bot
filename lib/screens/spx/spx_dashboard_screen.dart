import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/shared_widgets.dart';

class SpxDashboardScreen extends StatelessWidget {
  const SpxDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _PnLSection(state: state),
            const SizedBox(height: 12),
            _StatsGrid(state: state),
            const SizedBox(height: 12),
            _IntradayLevelsPanel(state: state),
            const SizedBox(height: 12),
            _GexPanel(state: state),
            const SizedBox(height: 12),
            _StrategyPanel(state: state),
            const SizedBox(height: 12),
            _ScannerSignals(state: state),
            const SizedBox(height: 12),
            _ScannerToggle(state: state),
            const SizedBox(height: 12),
            const _SpxRiskNotice(),
          ],
        );
      },
    );
  }
}

// ── P&L section ───────────────────────────────────────────────────────────────

class _PnLSection extends StatelessWidget {
  final SpxState state;
  const _PnLSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text('SPX Options Performance',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          _DashboardMarketChip(isOpen: state.isMarketOpen),
          const SizedBox(height: 16),
          PnLArc(
            value: state.realizedPnL.clamp(0, double.infinity),
            target: 500,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PnLChip(
                label: 'Realized',
                value: NexusFormatters.usd(state.realizedPnL),
                color: state.realizedPnL >= 0 ? AppTheme.green : AppTheme.red,
              ),
              const SizedBox(width: 16),
              _PnLChip(
                label: 'Unrealized',
                value: NexusFormatters.usd(state.unrealizedPnL),
                color: state.unrealizedPnL >= 0 ? AppTheme.green : AppTheme.red,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardMarketChip extends StatelessWidget {
  final bool isOpen;
  const _DashboardMarketChip({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isOpen ? AppTheme.greenBg : AppTheme.redBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOpen
              ? AppTheme.green.withValues(alpha: 0.45)
              : AppTheme.red.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        isOpen ? 'Market Open' : 'Market Closed',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isOpen ? AppTheme.green : AppTheme.red,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PnLChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PnLChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.syne(
                fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final SpxState state;
  const _StatsGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return GridView.count(
          crossAxisCount: wide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: wide ? 1.95 : 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            StatBox(
              label: 'Total Trades',
              value: '${state.totalTrades}',
              valueColor: AppTheme.blue,
            ),
            StatBox(
              label: 'Win Rate',
              value: state.totalTrades == 0
                  ? '—'
                  : '${state.winRate.toStringAsFixed(0)}%',
              valueColor: AppTheme.gold,
            ),
            StatBox(
              label: 'Open Positions',
              value: '${state.positions.length}',
              valueColor: AppTheme.textPrimary,
            ),
            StatBox(
              label: 'Buy Signals',
              value: '${state.buySignals.length}',
              valueColor: AppTheme.green,
            ),
          ],
        );
      },
    );
  }
}

// ── Intraday levels panel ────────────────────────────────────────────────────

class _IntradayLevelsPanel extends StatelessWidget {
  final SpxState state;
  const _IntradayLevelsPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final strategy = state.strategySnapshot;
    final candles = state.intradayCandles;
    final open = state.sessionOpenPrice ?? state.spotPrice;
    final sessionHigh = state.sessionHighPrice ?? state.spotPrice;
    final sessionLow = state.sessionLowPrice ?? state.spotPrice;
    final expectedMove = state.impliedDailyExpectedMove;
    final expectedHigh = expectedMove == null ? null : open + expectedMove;
    final expectedLow = expectedMove == null ? null : open - expectedMove;
    final moveFromOpen = state.spotPrice - open;
    final moveColor = moveFromOpen >= 0 ? AppTheme.green : AppTheme.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SPX INTRADAY LEVELS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatSpxPrice(state.spotPrice),
                      style: GoogleFonts.syne(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatSignedPoints(moveFromOpen)} from open',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: moveColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bg4,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.border2),
                ),
                child: Text(
                  state.dataMode == SpxDataMode.live ? 'LIVE' : 'SIM',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: state.dataMode == SpxDataMode.live
                        ? AppTheme.blue
                        : AppTheme.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LevelStatChip(
                label: 'Open',
                value: _formatSpxPrice(open),
                color: AppTheme.blue,
              ),
              _LevelStatChip(
                label: 'Day High',
                value: _formatSpxPrice(sessionHigh),
                color: AppTheme.textPrimary,
              ),
              _LevelStatChip(
                label: 'Day Low',
                value: _formatSpxPrice(sessionLow),
                color: AppTheme.textMuted,
              ),
              _LevelStatChip(
                label: 'OR High',
                value: strategy?.minute14High == null
                    ? '—'
                    : _formatSpxPrice(strategy!.minute14High!),
                color: AppTheme.red,
              ),
              _LevelStatChip(
                label: 'OR Low',
                value: strategy?.minute14Low == null
                    ? '—'
                    : _formatSpxPrice(strategy!.minute14Low!),
                color: AppTheme.green,
              ),
              _LevelStatChip(
                label: '1D IV Move',
                value: expectedMove == null ? '—' : _formatPoints(expectedMove),
                color: AppTheme.gold,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _IntradayCandlesMacdChart(
            candles: candles,
            markers: state.intradayMarkers,
            currentSpot: state.spotPrice,
            sessionHigh: sessionHigh,
            sessionLow: sessionLow,
            openingRangeHigh: strategy?.minute14High,
            openingRangeLow: strategy?.minute14Low,
            expectedMoveHigh: expectedHigh,
            expectedMoveLow: expectedLow,
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LevelLegendChip(
                label: 'Candles',
                color: AppTheme.blue,
              ),
              _LevelLegendChip(
                label: 'Spot',
                color: AppTheme.blue,
              ),
              _LevelLegendChip(
                label: 'Day Range',
                color: AppTheme.textPrimary,
              ),
              _LevelLegendChip(
                label: 'Opening Range',
                color: AppTheme.red,
              ),
              _LevelLegendChip(
                label: 'IV Day Band',
                color: AppTheme.gold,
              ),
              _LevelLegendChip(
                label: 'MACD',
                color: AppTheme.blue,
              ),
              _LevelLegendChip(
                label: 'Signal Line',
                color: AppTheme.gold,
              ),
              _LevelLegendChip(
                label: 'Scanner',
                color: AppTheme.gold,
              ),
              _LevelLegendChip(
                label: 'Entry',
                color: AppTheme.green,
              ),
              _LevelLegendChip(
                label: 'Exit',
                color: AppTheme.textPrimary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            expectedMove == null
                ? 'Minute candles and MACD build from the live session tape. IV day band appears once the selected chain has valid ATM IV.'
                : 'Minute candles and MACD build from the live session tape. IV day band uses the nearest ATM call/put implied volatility around the session open.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: AppTheme.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

enum _IntradayChartTimeframe { oneMinute, fiveMinute, fifteenMinute }

extension on _IntradayChartTimeframe {
  int get minutes => switch (this) {
        _IntradayChartTimeframe.oneMinute => 1,
        _IntradayChartTimeframe.fiveMinute => 5,
        _IntradayChartTimeframe.fifteenMinute => 15,
      };

  String get label => switch (this) {
        _IntradayChartTimeframe.oneMinute => '1m',
        _IntradayChartTimeframe.fiveMinute => '5m',
        _IntradayChartTimeframe.fifteenMinute => '15m',
      };
}

class _IntradayCandlesMacdChart extends StatefulWidget {
  final List<SpxCandleSample> candles;
  final List<SpxIntradayMarker> markers;
  final double currentSpot;
  final double sessionHigh;
  final double sessionLow;
  final double? openingRangeHigh;
  final double? openingRangeLow;
  final double? expectedMoveHigh;
  final double? expectedMoveLow;

  const _IntradayCandlesMacdChart({
    required this.candles,
    required this.markers,
    required this.currentSpot,
    required this.sessionHigh,
    required this.sessionLow,
    this.openingRangeHigh,
    this.openingRangeLow,
    this.expectedMoveHigh,
    this.expectedMoveLow,
  });

  @override
  State<_IntradayCandlesMacdChart> createState() =>
      _IntradayCandlesMacdChartState();
}

class _IntradayCandlesMacdChartState extends State<_IntradayCandlesMacdChart> {
  _IntradayChartTimeframe _timeframe = _IntradayChartTimeframe.oneMinute;

  @override
  Widget build(BuildContext context) {
    if (widget.candles.length < 2) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: AppTheme.bg4,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border2),
        ),
        alignment: Alignment.center,
        child: Text(
          'Collecting intraday candles…',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: AppTheme.textMuted,
          ),
        ),
      );
    }

    final aggregatedCandles = _aggregateCandles(
      widget.candles,
      timeframeMinutes: _timeframe.minutes,
    );
    final visibleCandles = _visibleCandles(aggregatedCandles);
    final visibleMarkers = _visibleMarkers(
      widget.markers,
      visibleCandles,
      timeframeMinutes: _timeframe.minutes,
    );

    if (visibleCandles.length < 2) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: AppTheme.bg4,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border2),
        ),
        child: Column(
          children: [
            _TimeframeToggleRow(
              selected: _timeframe,
              onSelected: (next) {
                setState(() {
                  _timeframe = next;
                });
              },
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Need at least two ${_timeframe.label} candles.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    final macdSamples = _buildMacdSamples(visibleCandles);
    final lastMacd = macdSamples.isEmpty ? null : macdSamples.last;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.bg4,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Column(
        children: [
          _TimeframeToggleRow(
            selected: _timeframe,
            onSelected: (next) {
              setState(() {
                _timeframe = next;
              });
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 214,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpxCandlestickPainter(
                candles: visibleCandles,
                markers: visibleMarkers,
                timeframeMinutes: _timeframe.minutes,
                currentSpot: widget.currentSpot,
                sessionHigh: widget.sessionHigh,
                sessionLow: widget.sessionLow,
                openingRangeHigh: widget.openingRangeHigh,
                openingRangeLow: widget.openingRangeLow,
                expectedMoveHigh: widget.expectedMoveHigh,
                expectedMoveLow: widget.expectedMoveLow,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpxMacdPainter(samples: macdSamples),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MacdMetricChip(
                label: 'MACD',
                value:
                    lastMacd == null ? '—' : _formatSignedPoints(lastMacd.macd),
                color: AppTheme.blue,
              ),
              const SizedBox(width: 8),
              _MacdMetricChip(
                label: 'Signal',
                value: lastMacd == null
                    ? '—'
                    : _formatSignedPoints(lastMacd.signal),
                color: AppTheme.gold,
              ),
              const SizedBox(width: 8),
              _MacdMetricChip(
                label: 'Hist',
                value: lastMacd == null
                    ? '—'
                    : _formatSignedPoints(lastMacd.histogram),
                color: lastMacd != null && lastMacd.histogram >= 0
                    ? AppTheme.green
                    : AppTheme.red,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TimeAxisLabel(
                  value: _formatIntradayTime(visibleCandles.first.bucketStart)),
              _TimeAxisLabel(
                value: _formatIntradayTime(
                  visibleCandles[(visibleCandles.length / 2).floor()]
                      .bucketStart,
                ),
              ),
              _TimeAxisLabel(
                  value: _formatIntradayTime(visibleCandles.last.bucketStart)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeframeToggleRow extends StatelessWidget {
  final _IntradayChartTimeframe selected;
  final ValueChanged<_IntradayChartTimeframe> onSelected;

  const _TimeframeToggleRow({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'TIMEFRAME',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        Wrap(
          spacing: 6,
          children: _IntradayChartTimeframe.values.map((timeframe) {
            final isSelected = timeframe == selected;
            return GestureDetector(
              onTap: () => onSelected(timeframe),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.blue.withValues(alpha: 0.12)
                      : AppTheme.bg2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? AppTheme.blue : AppTheme.border2,
                  ),
                ),
                child: Text(
                  timeframe.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: isSelected ? AppTheme.blue : AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _MacdMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacdMetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 8,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeAxisLabel extends StatelessWidget {
  final String value;

  const _TimeAxisLabel({required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 9,
        color: AppTheme.textMuted,
      ),
    );
  }
}

class _SpxCandlestickPainter extends CustomPainter {
  final List<SpxCandleSample> candles;
  final List<SpxIntradayMarker> markers;
  final int timeframeMinutes;
  final double currentSpot;
  final double sessionHigh;
  final double sessionLow;
  final double? openingRangeHigh;
  final double? openingRangeLow;
  final double? expectedMoveHigh;
  final double? expectedMoveLow;

  const _SpxCandlestickPainter({
    required this.candles,
    required this.markers,
    required this.timeframeMinutes,
    required this.currentSpot,
    required this.sessionHigh,
    required this.sessionLow,
    this.openingRangeHigh,
    this.openingRangeLow,
    this.expectedMoveHigh,
    this.expectedMoveLow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 42.0;
    const rightPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 12.0;
    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      math.max(0, size.width - leftPadding - rightPadding),
      math.max(0, size.height - topPadding - bottomPadding),
    );
    if (chartRect.width <= 0 || chartRect.height <= 0) return;

    final markerLevels = [
      currentSpot,
      sessionHigh,
      sessionLow,
      if (openingRangeHigh != null) openingRangeHigh!,
      if (openingRangeLow != null) openingRangeLow!,
      if (expectedMoveHigh != null) expectedMoveHigh!,
      if (expectedMoveLow != null) expectedMoveLow!,
      for (final candle in candles) candle.high,
      for (final candle in candles) candle.low,
    ];
    final rawMin = markerLevels.reduce(math.min);
    final rawMax = markerLevels.reduce(math.max);
    final span = math.max(rawMax - rawMin, 8.0);
    final minY = rawMin - (span * 0.10);
    final maxY = rawMax + (span * 0.10);
    final yInterval = _niceYAxisInterval(span);

    final backgroundPaint = Paint()
      ..color = AppTheme.bg2.withValues(alpha: 0.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chartRect, const Radius.circular(6)),
      backgroundPaint,
    );
    canvas.save();
    canvas.clipRect(chartRect);

    if (expectedMoveLow != null && expectedMoveHigh != null) {
      final bandTop = _mapValueToY(expectedMoveHigh!, minY, maxY, chartRect);
      final bandBottom = _mapValueToY(expectedMoveLow!, minY, maxY, chartRect);
      canvas.drawRect(
        Rect.fromLTRB(chartRect.left, bandTop, chartRect.right, bandBottom),
        Paint()..color = AppTheme.gold.withValues(alpha: 0.08),
      );
    }

    for (double tick = (minY / yInterval).floor() * yInterval;
        tick <= maxY + yInterval;
        tick += yInterval) {
      final y = _mapValueToY(tick, minY, maxY, chartRect);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        Paint()
          ..color = AppTheme.border.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    _drawDashedHorizontalLine(
      canvas,
      chartRect,
      _mapValueToY(currentSpot, minY, maxY, chartRect),
      Paint()
        ..color = AppTheme.blue.withValues(alpha: 0.55)
        ..strokeWidth = 1.4,
    );
    _drawDashedHorizontalLine(
      canvas,
      chartRect,
      _mapValueToY(sessionHigh, minY, maxY, chartRect),
      Paint()
        ..color = AppTheme.textPrimary.withValues(alpha: 0.32)
        ..strokeWidth = 1,
      dashLength: 4,
      gapLength: 4,
    );
    _drawDashedHorizontalLine(
      canvas,
      chartRect,
      _mapValueToY(sessionLow, minY, maxY, chartRect),
      Paint()
        ..color = AppTheme.textMuted.withValues(alpha: 0.55)
        ..strokeWidth = 1,
      dashLength: 4,
      gapLength: 4,
    );

    if (openingRangeHigh != null) {
      final y = _mapValueToY(openingRangeHigh!, minY, maxY, chartRect);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        Paint()
          ..color = AppTheme.red.withValues(alpha: 0.75)
          ..strokeWidth = 1.4,
      );
    }
    if (openingRangeLow != null) {
      final y = _mapValueToY(openingRangeLow!, minY, maxY, chartRect);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        Paint()
          ..color = AppTheme.green.withValues(alpha: 0.75)
          ..strokeWidth = 1.4,
      );
    }

    final slotWidth = chartRect.width / candles.length;
    final bodyWidth = (slotWidth * 0.56).clamp(4.0, 12.0);
    for (var index = 0; index < candles.length; index += 1) {
      final candle = candles[index];
      final centerX = chartRect.left + (slotWidth * index) + (slotWidth / 2);
      final highY = _mapValueToY(candle.high, minY, maxY, chartRect);
      final lowY = _mapValueToY(candle.low, minY, maxY, chartRect);
      final openY = _mapValueToY(candle.open, minY, maxY, chartRect);
      final closeY = _mapValueToY(candle.close, minY, maxY, chartRect);
      final isUp = candle.close >= candle.open;
      final bodyColor = isUp ? AppTheme.green : AppTheme.red;

      canvas.drawLine(
        Offset(centerX, highY),
        Offset(centerX, lowY),
        Paint()
          ..color = bodyColor.withValues(alpha: 0.85)
          ..strokeWidth = 1.2,
      );

      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyRect = Rect.fromLTRB(
        centerX - (bodyWidth / 2),
        bodyTop,
        centerX + (bodyWidth / 2),
        math.max(bodyTop + 2, bodyBottom),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(1.5)),
        Paint()..color = bodyColor,
      );
    }

    _drawIntradayMarkers(
      canvas,
      chartRect: chartRect,
      candles: candles,
      markers: markers,
      timeframeMinutes: timeframeMinutes,
      minY: minY,
      maxY: maxY,
      slotWidth: slotWidth,
    );

    canvas.restore();

    for (double tick = (minY / yInterval).floor() * yInterval;
        tick <= maxY + yInterval;
        tick += yInterval) {
      final y = _mapValueToY(tick, minY, maxY, chartRect);
      _paintChartText(
        canvas,
        text: NexusFormatters.number(tick, decimals: 0),
        offset: Offset(0, y - 7),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          color: AppTheme.textMuted,
        ),
        maxWidth: leftPadding - 8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpxCandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.markers != markers ||
        oldDelegate.timeframeMinutes != timeframeMinutes ||
        oldDelegate.currentSpot != currentSpot ||
        oldDelegate.sessionHigh != sessionHigh ||
        oldDelegate.sessionLow != sessionLow ||
        oldDelegate.openingRangeHigh != openingRangeHigh ||
        oldDelegate.openingRangeLow != openingRangeLow ||
        oldDelegate.expectedMoveHigh != expectedMoveHigh ||
        oldDelegate.expectedMoveLow != expectedMoveLow;
  }
}

class _SpxMacdPainter extends CustomPainter {
  final List<_MacdSample> samples;

  const _SpxMacdPainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 42.0;
    const rightPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 12.0;
    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      math.max(0, size.width - leftPadding - rightPadding),
      math.max(0, size.height - topPadding - bottomPadding),
    );
    if (chartRect.width <= 0 || chartRect.height <= 0 || samples.isEmpty) {
      return;
    }

    final values = <double>[
      0,
      for (final sample in samples) sample.macd,
      for (final sample in samples) sample.signal,
      for (final sample in samples) sample.histogram,
    ];
    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
    final span = math.max(rawMax - rawMin, 0.6);
    final minY = rawMin - (span * 0.18);
    final maxY = rawMax + (span * 0.18);
    final yInterval = _niceMacdInterval(span);

    final backgroundPaint = Paint()
      ..color = AppTheme.bg2.withValues(alpha: 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chartRect, const Radius.circular(6)),
      backgroundPaint,
    );
    canvas.save();
    canvas.clipRect(chartRect);

    for (double tick = (minY / yInterval).floor() * yInterval;
        tick <= maxY + yInterval;
        tick += yInterval) {
      final y = _mapValueToY(tick, minY, maxY, chartRect);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        Paint()
          ..color = AppTheme.border.withValues(alpha: 0.28)
          ..strokeWidth = tick == 0 ? 1.2 : 1,
      );
    }

    final zeroY = _mapValueToY(0, minY, maxY, chartRect);
    final slotWidth = chartRect.width / samples.length;
    final barWidth = math.max(3.0, slotWidth * 0.6);
    final macdPath = Path();
    final signalPath = Path();
    for (var index = 0; index < samples.length; index += 1) {
      final sample = samples[index];
      final centerX = chartRect.left + (slotWidth * index) + (slotWidth / 2);
      final histogramY = _mapValueToY(sample.histogram, minY, maxY, chartRect);
      final macdY = _mapValueToY(sample.macd, minY, maxY, chartRect);
      final signalY = _mapValueToY(sample.signal, minY, maxY, chartRect);
      final barTop = math.min(zeroY, histogramY);
      final barBottom = math.max(zeroY, histogramY);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            centerX - (barWidth / 2),
            barTop,
            centerX + (barWidth / 2),
            math.max(barTop + 1.5, barBottom),
          ),
          const Radius.circular(1),
        ),
        Paint()
          ..color = (sample.histogram >= 0 ? AppTheme.green : AppTheme.red)
              .withValues(alpha: 0.42),
      );

      if (index == 0) {
        macdPath.moveTo(centerX, macdY);
        signalPath.moveTo(centerX, signalY);
      } else {
        macdPath.lineTo(centerX, macdY);
        signalPath.lineTo(centerX, signalY);
      }
    }

    canvas.drawPath(
      macdPath,
      Paint()
        ..color = AppTheme.blue
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      signalPath,
      Paint()
        ..color = AppTheme.gold
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    final yLabels = <double>{minY, 0, maxY}.toList()..sort();
    for (final tick in yLabels) {
      final y = _mapValueToY(tick, minY, maxY, chartRect);
      _paintChartText(
        canvas,
        text: tick == 0
            ? '0'
            : NexusFormatters.number(tick, decimals: span < 3 ? 2 : 1),
        offset: Offset(0, y - 7),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          color: AppTheme.textMuted,
        ),
        maxWidth: leftPadding - 8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpxMacdPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}

class _MacdSample {
  final DateTime bucketStart;
  final double macd;
  final double signal;
  final double histogram;

  const _MacdSample({
    required this.bucketStart,
    required this.macd,
    required this.signal,
    required this.histogram,
  });
}

List<SpxCandleSample> _aggregateCandles(
  List<SpxCandleSample> candles, {
  required int timeframeMinutes,
}) {
  if (timeframeMinutes <= 1 || candles.length <= 1) return candles;

  final aggregated = <SpxCandleSample>[];
  for (final candle in candles) {
    final bucketStart = _floorCandleBucket(
      candle.bucketStart,
      timeframeMinutes: timeframeMinutes,
    );
    if (aggregated.isEmpty || aggregated.last.bucketStart != bucketStart) {
      aggregated.add(
        SpxCandleSample(
          bucketStart: bucketStart,
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          sampleCount: candle.sampleCount,
        ),
      );
      continue;
    }

    final last = aggregated.removeLast();
    aggregated.add(
      SpxCandleSample(
        bucketStart: last.bucketStart,
        open: last.open,
        high: math.max(last.high, candle.high),
        low: math.min(last.low, candle.low),
        close: candle.close,
        sampleCount: last.sampleCount + candle.sampleCount,
      ),
    );
  }
  return aggregated;
}

List<SpxCandleSample> _visibleCandles(
  List<SpxCandleSample> candles, {
  int maxCandles = 48,
}) {
  if (candles.length <= maxCandles) return candles;
  return candles.sublist(candles.length - maxCandles);
}

List<SpxIntradayMarker> _visibleMarkers(
  List<SpxIntradayMarker> markers,
  List<SpxCandleSample> candles, {
  required int timeframeMinutes,
  int maxMarkers = 8,
}) {
  if (markers.isEmpty || candles.isEmpty) return const [];
  final windowStart = candles.first.bucketStart;
  final windowEnd =
      candles.last.bucketStart.add(Duration(minutes: timeframeMinutes));
  final visible = markers
      .where((marker) =>
          !marker.timestamp.isBefore(windowStart) &&
          marker.timestamp.isBefore(windowEnd))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (visible.length <= maxMarkers) return visible;
  return visible.sublist(visible.length - maxMarkers);
}

List<_MacdSample> _buildMacdSamples(List<SpxCandleSample> candles) {
  if (candles.isEmpty) return const [];

  const fastPeriod = 12;
  const slowPeriod = 26;
  const signalPeriod = 9;
  const fastMultiplier = 2 / (fastPeriod + 1);
  const slowMultiplier = 2 / (slowPeriod + 1);
  const signalMultiplier = 2 / (signalPeriod + 1);

  double? fastEma;
  double? slowEma;
  double? signalEma;
  final samples = <_MacdSample>[];

  for (final candle in candles) {
    final close = candle.close;
    fastEma = fastEma == null
        ? close
        : ((close - fastEma) * fastMultiplier) + fastEma;
    slowEma = slowEma == null
        ? close
        : ((close - slowEma) * slowMultiplier) + slowEma;
    final macd = fastEma - slowEma;
    signalEma = signalEma == null
        ? macd
        : ((macd - signalEma) * signalMultiplier) + signalEma;
    samples.add(
      _MacdSample(
        bucketStart: candle.bucketStart,
        macd: macd,
        signal: signalEma,
        histogram: macd - signalEma,
      ),
    );
  }

  return samples;
}

DateTime _floorCandleBucket(
  DateTime value, {
  required int timeframeMinutes,
}) {
  final flooredMinute = (value.minute ~/ timeframeMinutes) * timeframeMinutes;
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    flooredMinute,
  );
}

void _drawIntradayMarkers(
  Canvas canvas, {
  required Rect chartRect,
  required List<SpxCandleSample> candles,
  required List<SpxIntradayMarker> markers,
  required int timeframeMinutes,
  required double minY,
  required double maxY,
  required double slotWidth,
}) {
  if (markers.isEmpty) return;

  final stackByBucket = <int, int>{};
  for (final marker in markers) {
    final candleIndex = _markerCandleIndex(
      marker.timestamp,
      candles,
      timeframeMinutes: timeframeMinutes,
    );
    if (candleIndex == null) continue;

    final stackIndex = stackByBucket.update(
      candleIndex,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    final centerX =
        chartRect.left + (slotWidth * candleIndex) + (slotWidth / 2);
    final anchorY = _mapValueToY(marker.spotPrice, minY, maxY, chartRect);
    final markerColor = _intradayMarkerColor(marker);
    final direction = stackIndex.isEven ? -1.0 : 1.0;
    final depth = (stackIndex ~/ 2) + 1;
    final bubbleY = (anchorY + (direction * (12 + (depth * 16))))
        .clamp(chartRect.top + 10, chartRect.bottom - 10);

    canvas.drawLine(
      Offset(centerX, anchorY),
      Offset(centerX, bubbleY),
      Paint()
        ..color = markerColor.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(centerX, anchorY),
      3.5,
      Paint()..color = markerColor,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: marker.label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 8,
          color: AppTheme.bg,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, bubbleY),
        width: textPainter.width + 10,
        height: textPainter.height + 6,
      ),
      const Radius.circular(999),
    );
    canvas.drawRRect(
      bubbleRect,
      Paint()..color = markerColor,
    );
    textPainter.paint(
      canvas,
      Offset(
        bubbleRect.left + ((bubbleRect.width - textPainter.width) / 2),
        bubbleRect.top + ((bubbleRect.height - textPainter.height) / 2),
      ),
    );
  }
}

int? _markerCandleIndex(
  DateTime timestamp,
  List<SpxCandleSample> candles, {
  required int timeframeMinutes,
}) {
  for (var index = 0; index < candles.length; index += 1) {
    final candle = candles[index];
    final bucketEnd =
        candle.bucketStart.add(Duration(minutes: timeframeMinutes));
    if (!timestamp.isBefore(candle.bucketStart) &&
        timestamp.isBefore(bucketEnd)) {
      return index;
    }
  }
  return null;
}

Color _intradayMarkerColor(SpxIntradayMarker marker) {
  return switch (marker.type) {
    SpxIntradayMarkerType.signal => AppTheme.gold,
    SpxIntradayMarkerType.entry =>
      marker.side == OptionsSide.put ? AppTheme.red : AppTheme.green,
    SpxIntradayMarkerType.exit => AppTheme.textPrimary,
  };
}

double _mapValueToY(double value, double minY, double maxY, Rect chartRect) {
  final fraction = maxY == minY ? 0.5 : (value - minY) / (maxY - minY);
  return chartRect.bottom - (fraction * chartRect.height);
}

void _drawDashedHorizontalLine(
  Canvas canvas,
  Rect rect,
  double y,
  Paint paint, {
  double dashLength = 5,
  double gapLength = 5,
}) {
  var x = rect.left;
  while (x < rect.right) {
    final next = math.min(x + dashLength, rect.right);
    canvas.drawLine(Offset(x, y), Offset(next, y), paint);
    x = next + gapLength;
  }
}

void _paintChartText(
  Canvas canvas, {
  required String text,
  required Offset offset,
  required TextStyle style,
  TextAlign textAlign = TextAlign.right,
  double? maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  painter.paint(canvas, offset);
}

class _LevelStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LevelStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bg4,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.syne(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelLegendChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LevelLegendChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg4,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

double _niceYAxisInterval(double span) {
  if (span <= 12) return 2;
  if (span <= 24) return 4;
  if (span <= 60) return 10;
  return 20;
}

double _niceMacdInterval(double span) {
  if (span <= 0.8) return 0.2;
  if (span <= 1.6) return 0.4;
  if (span <= 3.2) return 0.8;
  return 1.6;
}

String _formatSpxPrice(double value) =>
    NexusFormatters.number(value, decimals: 1);

String _formatPoints(double value) => NexusFormatters.points(value);

String _formatSignedPoints(double value) =>
    NexusFormatters.points(value, signed: true);

String _formatIntradayTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

// ── GEX panel ─────────────────────────────────────────────────────────────────

class _GexPanel extends StatelessWidget {
  final SpxState state;
  const _GexPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final gex = state.gexData;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('⚡ GAMMA EXPOSURE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (gex != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        gex.isPositiveGex ? AppTheme.greenBg : AppTheme.redBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    gex.isPositiveGex ? 'POSITIVE GEX' : 'NEGATIVE GEX',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: gex.isPositiveGex ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (gex == null)
            Text('Loading GEX…',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: AppTheme.textDim))
          else ...[
            Row(
              children: [
                _GexCell(
                  label: 'Net GEX',
                  value:
                      '${gex.netGex >= 0 ? '+' : ''}${gex.netGex.toStringAsFixed(2)}B',
                  color: gex.isPositiveGex ? AppTheme.green : AppTheme.red,
                ),
                _GexCell(
                  label: 'SPX Spot',
                  value: NexusFormatters.usd(gex.spxSpotPrice),
                  color: AppTheme.textPrimary,
                ),
                _GexCell(
                  label: 'Gamma Wall',
                  value: gex.gammaWall == null
                      ? '—'
                      : NexusFormatters.usd(gex.gammaWall!, decimals: 0),
                  color: AppTheme.gold,
                ),
                _GexCell(
                  label: 'Put Wall',
                  value: gex.putWall == null
                      ? '—'
                      : NexusFormatters.usd(gex.putWall!, decimals: 0),
                  color: AppTheme.red,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              gex.isPositiveGex
                  ? 'Dealers long gamma → price pinning expected near gamma wall.'
                  : 'Dealers short gamma → momentum amplification likely.',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            _GexStrikeHistogram(gex: gex),
          ],
        ],
      ),
    );
  }
}

class _GexCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _GexCell(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 8, color: AppTheme.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.syne(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _GexStrikeHistogram extends StatelessWidget {
  final GexData gex;

  const _GexStrikeHistogram({required this.gex});

  @override
  Widget build(BuildContext context) {
    final entries = _windowedGexEntries(gex);
    if (entries.isEmpty) return const SizedBox.shrink();

    final nearestSpotStrike = entries.reduce((a, b) {
      return (a.key - gex.spxSpotPrice).abs() <=
              (b.key - gex.spxSpotPrice).abs()
          ? a
          : b;
    }).key;
    final maxAbs =
        entries.map((entry) => entry.value.abs()).fold<double>(0.0, math.max);
    final axisMax = math.max(maxAbs * 1.18, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'BY STRIKE',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: AppTheme.textMuted,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              'Gold bar = nearest spot strike',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: AppTheme.textDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              minY: -axisMax,
              maxY: axisMax,
              baselineY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: axisMax / 2,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: value == 0
                      ? AppTheme.textPrimary.withValues(alpha: 0.28)
                      : AppTheme.border.withValues(alpha: 0.35),
                  strokeWidth: value == 0 ? 1.4 : 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: axisMax / 2,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${NexusFormatters.number(value, decimals: 0)}M',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 8,
                          color: AppTheme.textMuted,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= entries.length) {
                        return const SizedBox.shrink();
                      }
                      if (index.isOdd &&
                          entries[index].key != nearestSpotStrike) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          NexusFormatters.number(entries[index].key),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final entry = entries[group.x.toInt()];
                    final sign = entry.value >= 0 ? '+' : '';
                    return BarTooltipItem(
                      '${NexusFormatters.number(entry.key)}\n$sign${entry.value.toStringAsFixed(2)}M',
                      GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < entries.length; i += 1)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: entries[i].value,
                        width: 13,
                        color: entries[i].key == nearestSpotStrike
                            ? AppTheme.gold
                            : (entries[i].value >= 0
                                ? AppTheme.green
                                : AppTheme.red),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<MapEntry<double, double>> _windowedGexEntries(
  GexData gex, {
  int maxBars = 13,
}) {
  final sorted = gex.gexByStrike.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (sorted.isEmpty) return const <MapEntry<double, double>>[];
  if (sorted.length <= maxBars) return sorted;

  var nearestIndex = 0;
  var nearestDistance = double.infinity;
  for (var i = 0; i < sorted.length; i += 1) {
    final distance = (sorted[i].key - gex.spxSpotPrice).abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = i;
    }
  }

  final halfWindow = maxBars ~/ 2;
  var start = math.max(0, nearestIndex - halfWindow);
  var end = math.min(sorted.length, start + maxBars);
  start = math.max(0, end - maxBars);
  return sorted.sublist(start, end);
}

// ── Strategy panel ───────────────────────────────────────────────────────────

class _StrategyPanel extends StatelessWidget {
  final SpxState state;
  const _StrategyPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final strategy = state.strategySnapshot;
    if (strategy == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Building strategy signals…',
          style:
              GoogleFonts.spaceGrotesk(fontSize: 12, color: AppTheme.textDim),
        ),
      );
    }

    final actionColor = switch (strategy.action) {
      SpxStrategyActionType.goLong => AppTheme.green,
      SpxStrategyActionType.goShort => AppTheme.red,
      SpxStrategyActionType.wait => AppTheme.gold,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '🧭 DAILY STRATEGY',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: actionColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  strategy.action.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: actionColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StrategyMiniChip(
                label: 'Gap',
                value: '${strategy.gapPercent.toStringAsFixed(2)}%',
                color: strategy.significantGap
                    ? AppTheme.gold
                    : AppTheme.textMuted,
              ),
              _StrategyMiniChip(
                label: 'S-Time',
                value: '${strategy.minutesFromSessionStart}m',
                color: AppTheme.blue,
              ),
              _StrategyMiniChip(
                label: 'Min14 High',
                value: strategy.minute14High == null
                    ? '—'
                    : _formatSpxPrice(strategy.minute14High!),
                color: AppTheme.red,
              ),
              _StrategyMiniChip(
                label: 'Min14 Low',
                value: strategy.minute14Low == null
                    ? '—'
                    : _formatSpxPrice(strategy.minute14Low!),
                color: AppTheme.green,
              ),
              _StrategyMiniChip(
                label: 'DPL',
                value: strategy.dplDirection.label,
                color: _directionColor(strategy.dplDirection),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            strategy.reason,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'All 7 Signals',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textMuted,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...strategy.signals.map((signal) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _directionColor(signal.direction),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(
                        signal.label,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        signal.direction.label,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: _directionColor(signal.direction),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        signal.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.bg3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              strategy.action == SpxStrategyActionType.goLong
                  ? 'Long plan: Enter near minute-14 low. ITM budget \$2k, OTM budget \$1k at strike (low + 50).'
                  : strategy.action == SpxStrategyActionType.goShort
                      ? 'Short plan: Enter near minute-14 high. ITM budget \$2k, OTM budget \$1k at strike (high - 50).'
                      : 'Wait plan: Keep tracking DPL + signal alignment through the 35-minute confirmation window.',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppTheme.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _directionColor(SpxDirection direction) {
    switch (direction) {
      case SpxDirection.up:
        return AppTheme.green;
      case SpxDirection.down:
        return AppTheme.red;
      case SpxDirection.neutral:
        return AppTheme.textMuted;
    }
  }
}

class _StrategyMiniChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StrategyMiniChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Scanner signals ───────────────────────────────────────────────────────────

class _ScannerSignals extends StatelessWidget {
  final SpxState state;
  const _ScannerSignals({required this.state});

  @override
  Widget build(BuildContext context) {
    final action = state.strategySnapshot?.action;
    final filtered = action == SpxStrategyActionType.goLong
        ? state.buySignals.where((c) => c.side == OptionsSide.call)
        : action == SpxStrategyActionType.goShort
            ? state.buySignals.where((c) => c.side == OptionsSide.put)
            : state.buySignals;
    final signals = filtered.take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text('🎯 TOP SIGNALS',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700)),
          ),
          if (signals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                  action == SpxStrategyActionType.wait
                      ? 'Strategy is in WAIT mode — no entries yet.'
                      : 'Scanning for options signals…',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: AppTheme.textDim)),
            )
          else
            ...signals.map((c) => _SignalTile(
                  contract: c,
                  spot: state.spotPrice,
                )),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  final OptionsContract contract;
  final double spot;

  const _SignalTile({
    required this.contract,
    required this.spot,
  });

  @override
  Widget build(BuildContext context) {
    final isCall = contract.side == OptionsSide.call;
    final moneyness = contract.moneynessForSpot(spot);
    final (moneynessLabel, moneynessColor) = switch (moneyness) {
      SpxContractMoneyness.itm => ('ITM', AppTheme.blue),
      SpxContractMoneyness.atm => ('ATM', AppTheme.gold),
      SpxContractMoneyness.otm => ('OTM', AppTheme.textMuted),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.greenBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(
            isCall ? '🟢 CALL' : '🟢 PUT',
            style: GoogleFonts.syne(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.green),
          ),
          const SizedBox(width: 8),
          Text(NexusFormatters.usd(contract.strike, decimals: 0),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, color: AppTheme.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: moneynessColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: moneynessColor.withValues(alpha: 0.28)),
            ),
            child: Text(
              moneynessLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: moneynessColor,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const Spacer(),
          Text('Δ ${contract.greeks.delta.toStringAsFixed(2)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(width: 10),
          Text('IV ${(contract.impliedVolatility * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(width: 10),
          Text('${contract.daysToExpiry}DTE',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => context
                .read<SpxBloc>()
                .add(BuySpxContract(symbol: contract.symbol)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
              ),
              child: Text('BUY',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.green)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scanner toggle ────────────────────────────────────────────────────────────

class _ScannerToggle extends StatelessWidget {
  final SpxState state;
  const _ScannerToggle({required this.state});

  @override
  Widget build(BuildContext context) {
    final isActive = state.scannerStatus == SpxScannerStatus.active;
    return GestureDetector(
      onTap: () => context.read<SpxBloc>().add(const ToggleSpxScanner()),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.greenBg : AppTheme.bg2,
          border: Border.all(
            color: isActive
                ? AppTheme.green.withValues(alpha: 0.4)
                : AppTheme.border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: isActive ? AppTheme.green : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? 'AUTO-SCANNER ACTIVE' : 'AUTO-SCANNER PAUSED',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive ? AppTheme.green : AppTheme.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    isActive
                        ? 'Automatically enters strategy-aligned signals (max 6 positions)'
                        : 'Tap to enable automatic signal execution',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, color: AppTheme.textDim),
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

// ── Risk notice ───────────────────────────────────────────────────────────────

class _SpxRiskNotice extends StatelessWidget {
  const _SpxRiskNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0500),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Options Risk Notice',
                    style: GoogleFonts.syne(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold)),
                const SizedBox(height: 4),
                Text(
                  'SPX options are highly leveraged instruments. 100% of premium can be lost. This app uses Black-Scholes simulation — not real quotes. Always paper trade before risking real capital.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppTheme.gold.withValues(alpha: 0.7),
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
