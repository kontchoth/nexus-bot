import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';
import 'spx_greeks_panel.dart';

class SpxPositionsScreen extends StatelessWidget {
  const SpxPositionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      builder: (context, state) {
        if (state.positions.isEmpty) return const _EmptyPositions();
        return ListView.builder(
          primary: false,
          padding: const EdgeInsets.all(10),
          itemCount: state.positions.length,
          itemBuilder: (context, i) =>
              _PositionCard(position: state.positions[i]),
        );
      },
    );
  }
}

class _PositionCard extends StatelessWidget {
  final SpxPosition position;
  const _PositionCard({required this.position});

  @override
  Widget build(BuildContext context) {
    final pnl = position.unrealizedPnL;
    final pnlPct = position.pnlPercent;
    final isProfit = pnl >= 0;
    final pnlColor = isProfit ? AppTheme.green : AppTheme.red;
    final contract = position.contract;
    final isCall = contract.side == OptionsSide.call;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(
          color: position.isDteWarning
              ? AppTheme.red.withValues(alpha: 0.4)
              : AppTheme.border,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isCall ? AppTheme.green : AppTheme.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    isCall ? 'CALL' : 'PUT',
                    style: GoogleFonts.syne(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isCall ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${NexusFormatters.usd(contract.strike, decimals: 0)}  ·  ${contract.daysToExpiry}DTE',
                    style: GoogleFonts.syne(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                // P&L
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NexusFormatters.usd(pnl, signed: true),
                      style: GoogleFonts.syne(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: pnlColor),
                    ),
                    Text(
                      '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: pnlColor),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Entry / current premium ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                _PremiumChip(
                  label: 'Entry',
                  value: NexusFormatters.usd(position.entryPremium),
                ),
                const SizedBox(width: 12),
                _PremiumChip(
                  label: 'Current',
                  value: NexusFormatters.usd(position.currentPremium),
                  color: pnlColor,
                ),
                const SizedBox(width: 12),
                _PremiumChip(
                  label: 'Contracts',
                  value: '${position.contracts}×',
                ),
                const Spacer(),
                if (position.isDteWarning)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('⚠ DTE RISK',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.red)),
                  ),
              ],
            ),
          ),

          // ── P&L progress bar ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: _PnLBar(pnlPct: pnlPct),
          ),

          // ── Greeks panel ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: SpxGreeksPanel(
              greeks: contract.greeks,
              impliedVolatility: contract.impliedVolatility,
              ivRank: contract.ivRank,
            ),
          ),

          // ── Close button ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: GestureDetector(
              onTap: () =>
                  context.read<SpxBloc>().add(CloseSpxPosition(position.id)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: pnlColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: pnlColor.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'CLOSE POSITION',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: pnlColor,
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

class _PremiumChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PremiumChip({
    required this.label,
    required this.value,
    this.color = AppTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, color: AppTheme.textMuted)),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _PnLBar extends StatelessWidget {
  final double pnlPct; // e.g. +38.5 or -12.0
  const _PnLBar({required this.pnlPct});

  @override
  Widget build(BuildContext context) {
    // Map [-100, +100] onto [0, 1] with 0.5 = breakeven
    final fraction = ((pnlPct + 100) / 200).clamp(0.0, 1.0);
    final isProfit = pnlPct >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('P&L',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8, color: AppTheme.textMuted, letterSpacing: 1)),
            Text('${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    color: isProfit ? AppTheme.green : AppTheme.red)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: AppTheme.bg3,
            valueColor: AlwaysStoppedAnimation<Color>(
              isProfit ? AppTheme.green : AppTheme.red,
            ),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

class _EmptyPositions extends StatelessWidget {
  const _EmptyPositions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 40, color: AppTheme.textDim),
          const SizedBox(height: 12),
          Text('No open SPX positions',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textDim)),
          const SizedBox(height: 6),
          Text('Buy a contract from the Chain tab',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
