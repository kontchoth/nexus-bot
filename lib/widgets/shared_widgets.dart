import 'package:flutter/material.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../utils/number_formatters.dart';

// ── Stat Box ──────────────────────────────────────────────────────────────────

class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.syne(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Big Price Chart ───────────────────────────────────────────────────────────

class PriceChart extends StatelessWidget {
  final List<double> prices;
  final bool isPositive;

  const PriceChart({super.key, required this.prices, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    if (prices.isEmpty) return const SizedBox.shrink();
    final color = isPositive ? AppTheme.green : AppTheme.red;
    final spots = prices
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final priceRange = maxPrice - minPrice;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: priceRange > 0 ? priceRange / 4 : 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '\$${s.y.toStringAsFixed(2)}',
                      GoogleFonts.spaceGrotesk(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 150),
    );
  }
}

// ── Indicator Tile ────────────────────────────────────────────────────────────

class IndicatorTile extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final Color color;

  const IndicatorTile({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textMuted,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.syne(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── PnL Arc Progress ──────────────────────────────────────────────────────────

class PnLArc extends StatelessWidget {
  final double value;
  final double target;

  const PnLArc({super.key, required this.value, required this.target});

  @override
  Widget build(BuildContext context) {
    final pct = (value / target).clamp(0.0, 1.0);
    final color = pct > 0.8
        ? AppTheme.green
        : pct > 0.5
            ? AppTheme.gold
            : AppTheme.blue;

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 8,
              backgroundColor: AppTheme.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                NexusFormatters.usd(value, decimals: 0),
                style: GoogleFonts.syne(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                'of ${NexusFormatters.usd(target, decimals: 0)}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Nexus Button ──────────────────────────────────────────────────────────────

class NexusButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? textColor;
  final bool small;

  const NexusButton({
    super.key,
    required this.label,
    this.onTap,
    this.borderColor,
    this.textColor,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 10 : 14,
          vertical: small ? 4 : 7,
        ),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor ?? AppTheme.border2),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: small ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: textColor ?? AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Risk Bar ──────────────────────────────────────────────────────────────────

class RiskBar extends StatelessWidget {
  final double pct;
  final Color color;
  final double width;

  const RiskBar({
    super.key,
    required this.pct,
    required this.color,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0),
          backgroundColor: AppTheme.border,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}
