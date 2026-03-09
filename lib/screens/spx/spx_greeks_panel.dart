import 'package:flutter/material.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';

/// Compact panel showing delta/gamma/theta/vega + IV for a single contract.
class SpxGreeksPanel extends StatelessWidget {
  final OptionsGreeks greeks;
  final double impliedVolatility;
  final double ivRank;

  const SpxGreeksPanel({
    super.key,
    required this.greeks,
    required this.impliedVolatility,
    required this.ivRank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GREEKS',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              _GreekCell(label: 'Δ Delta',  value: greeks.delta.toStringAsFixed(3),
                  color: greeks.delta >= 0 ? AppTheme.green : AppTheme.red),
              _GreekCell(label: 'Γ Gamma',  value: greeks.gamma.toStringAsFixed(4)),
              _GreekCell(label: 'Θ Theta',  value: greeks.theta.toStringAsFixed(3),
                  color: AppTheme.red),
              _GreekCell(label: 'V Vega',   value: greeks.vega.toStringAsFixed(3),
                  color: AppTheme.blue),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _GreekCell(
                label: 'IV',
                value: '${(impliedVolatility * 100).toStringAsFixed(1)}%',
                color: impliedVolatility > 0.20 ? AppTheme.gold : AppTheme.textPrimary,
              ),
              _GreekCell(
                label: 'IV Rank',
                value: ivRank.toStringAsFixed(0),
                color: ivRank > 75
                    ? AppTheme.red
                    : ivRank < 25
                        ? AppTheme.green
                        : AppTheme.gold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GreekCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _GreekCell({
    required this.label,
    required this.value,
    this.color = AppTheme.textPrimary,
  });

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
