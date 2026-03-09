import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
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
            _GexPanel(state: state),
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
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5)),
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
                value: '\$${state.realizedPnL.toStringAsFixed(2)}',
                color: state.realizedPnL >= 0 ? AppTheme.green : AppTheme.red,
              ),
              const SizedBox(width: 16),
              _PnLChip(
                label: 'Unrealized',
                value: '\$${state.unrealizedPnL.toStringAsFixed(2)}',
                color:
                    state.unrealizedPnL >= 0 ? AppTheme.green : AppTheme.red,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PnLChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PnLChip({required this.label, required this.value, required this.color});

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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      crossAxisSpacing: 1,
      mainAxisSpacing: 1,
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
  }
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
                    color: gex.isPositiveGex
                        ? AppTheme.greenBg
                        : AppTheme.redBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    gex.isPositiveGex ? 'POSITIVE GEX' : 'NEGATIVE GEX',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color:
                          gex.isPositiveGex ? AppTheme.green : AppTheme.red,
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
                  color:
                      gex.isPositiveGex ? AppTheme.green : AppTheme.red,
                ),
                _GexCell(
                  label: 'SPX Spot',
                  value: '\$${gex.spxSpotPrice.toStringAsFixed(2)}',
                  color: AppTheme.textPrimary,
                ),
                _GexCell(
                  label: 'Gamma Wall',
                  value: '\$${gex.gammaWall?.toStringAsFixed(0) ?? '—'}',
                  color: AppTheme.gold,
                ),
                _GexCell(
                  label: 'Put Wall',
                  value: '\$${gex.putWall?.toStringAsFixed(0) ?? '—'}',
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
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  height: 1.4),
            ),
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
  const _GexCell({required this.label, required this.value, required this.color});

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

// ── Scanner signals ───────────────────────────────────────────────────────────

class _ScannerSignals extends StatelessWidget {
  final SpxState state;
  const _ScannerSignals({required this.state});

  @override
  Widget build(BuildContext context) {
    final signals = state.buySignals.take(5).toList();
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
              child: Text('Scanning for options signals…',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: AppTheme.textDim)),
            )
          else
            ...signals.map((c) => _SignalTile(contract: c)),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  final OptionsContract contract;
  const _SignalTile({required this.contract});

  @override
  Widget build(BuildContext context) {
    final isCall = contract.side == OptionsSide.call;
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
          Text('\$${contract.strike.toStringAsFixed(0)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, color: AppTheme.textPrimary)),
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
                      color:
                          isActive ? AppTheme.green : AppTheme.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    isActive
                        ? 'Automatically enters buy signals (max 6 positions)'
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
        border:
            Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
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
