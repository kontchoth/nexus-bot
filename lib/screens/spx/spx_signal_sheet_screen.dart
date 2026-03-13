import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';

class SpxSignalSheetScreen extends StatelessWidget {
  const SpxSignalSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      builder: (context, state) {
        final snap = state.strategySnapshot;
        final gex = state.gexData;
        return ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _HeaderCard(state: state),
            const SizedBox(height: 10),
            _DecisionBanner(snap: snap),
            const SizedBox(height: 10),
            _KpiStrip(state: state, gex: gex),
            const SizedBox(height: 10),
            if (snap != null) ...[
              _SignalsCard(snap: snap),
              const SizedBox(height: 10),
              _ContextCard(snap: snap),
              const SizedBox(height: 10),
              _EntryReferenceCard(snap: snap),
              const SizedBox(height: 10),
            ],
            _PnLCard(state: state),
          ],
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final SpxState state;
  const _HeaderCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final snap = state.strategySnapshot;
    final mins = snap?.minutesFromSessionStart ?? 0;
    final h = mins ~/ 60;
    final m = mins % 60;
    final timeStr = snap == null
        ? '--'
        : '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} into session';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPX DAILY SIGNAL SHEET',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusDot(isOpen: state.isMarketOpen),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
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

class _StatusDot extends StatelessWidget {
  final bool isOpen;
  const _StatusDot({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOpen ? AppTheme.green : AppTheme.textMuted,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          isOpen ? 'MARKET OPEN' : 'MARKET CLOSED',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isOpen ? AppTheme.green : AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Decision Banner ───────────────────────────────────────────────────────────

class _DecisionBanner extends StatelessWidget {
  final SpxStrategySnapshot? snap;
  const _DecisionBanner({required this.snap});

  @override
  Widget build(BuildContext context) {
    if (snap == null) {
      return _banner(
        label: 'AWAITING DATA',
        sub: 'Start the scanner to compute signals',
        bg: AppTheme.bg3,
        border: AppTheme.border,
        textColor: AppTheme.textMuted,
      );
    }

    final Color bg;
    final Color border;
    final Color textColor;

    switch (snap!.action) {
      case SpxStrategyActionType.goLong:
        bg = AppTheme.greenBg;
        border = AppTheme.green.withValues(alpha: 0.5);
        textColor = AppTheme.green;
      case SpxStrategyActionType.goShort:
        bg = AppTheme.redBg;
        border = AppTheme.red.withValues(alpha: 0.5);
        textColor = AppTheme.red;
      case SpxStrategyActionType.wait:
        bg = const Color(0xFF2A2200);
        border = const Color(0xFFFFB300).withValues(alpha: 0.4);
        textColor = const Color(0xFFFFB300);
    }

    return _banner(
      label: snap!.action.label,
      sub: snap!.reason,
      bg: bg,
      border: border,
      textColor: textColor,
    );
  }

  Widget _banner({
    required String label,
    required String sub,
    required Color bg,
    required Color border,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.syne(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI Strip ─────────────────────────────────────────────────────────────────

class _KpiStrip extends StatelessWidget {
  final SpxState state;
  final GexData? gex;
  const _KpiStrip({required this.state, required this.gex});

  @override
  Widget build(BuildContext context) {
    final netGex = gex?.netGex ?? 0.0;
    final gammaWall = gex?.gammaWall ?? 0.0;
    final putWall = gex?.putWall ?? 0.0;
    final spot = state.spotPrice;
    final move = state.impliedDailyExpectedMove;
    final regime = (gex?.isPositiveGex ?? true) ? 'POSITIVE' : 'NEGATIVE';
    final regimeColor =
        (gex?.isPositiveGex ?? true) ? AppTheme.green : AppTheme.red;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiChip(
                label: 'NET GEX',
                value: netGex == 0
                    ? '—'
                    : '${netGex < 0 ? '-' : '+'}\$${NexusFormatters.compactNumber(netGex.abs())}B',
                valueColor: netGex < 0 ? AppTheme.red : AppTheme.green,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KpiChip(
                label: 'REGIME',
                value: regime,
                valueColor: regimeColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KpiChip(
                label: 'GAMMA WALL',
                value: gammaWall > 0
                    ? NexusFormatters.number(gammaWall, decimals: 0)
                    : '—',
                valueColor: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _KpiChip(
                label: 'PUT WALL',
                value: putWall > 0
                    ? NexusFormatters.number(putWall, decimals: 0)
                    : '—',
                valueColor: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KpiChip(
                label: 'RANGE EST.',
                value: move != null
                    ? '±${NexusFormatters.number(move, decimals: 1)}'
                    : '—',
                valueColor: AppTheme.blue,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KpiChip(
                label: 'SPOT',
                value: spot > 0
                    ? NexusFormatters.number(spot, decimals: 2)
                    : '—',
                valueColor: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _KpiChip({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Signals Card ──────────────────────────────────────────────────────────────

class _SignalsCard extends StatelessWidget {
  final SpxStrategySnapshot snap;
  const _SignalsCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _CardHeader(
            title: '7-SIGNAL CONSENSUS',
            trailing:
                '${snap.upSignals}↑  ${snap.downSignals}↓  ${snap.neutralSignals}—',
          ),
          ...snap.signals.map((s) => _SignalRow(signal: s)),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  final SpxStrategySignal signal;
  const _SignalRow({required this.signal});

  @override
  Widget build(BuildContext context) {
    final Color dirColor;
    final String dirLabel;
    final IconData dirIcon;

    switch (signal.direction) {
      case SpxDirection.up:
        dirColor = AppTheme.green;
        dirLabel = 'LONG';
        dirIcon = Icons.arrow_upward_rounded;
      case SpxDirection.down:
        dirColor = AppTheme.red;
        dirLabel = 'SHORT';
        dirIcon = Icons.arrow_downward_rounded;
      case SpxDirection.neutral:
        dirColor = AppTheme.textMuted;
        dirLabel = 'NEUTRAL';
        dirIcon = Icons.remove_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (signal.detail.isNotEmpty)
                  Text(
                    signal.detail,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: dirColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: dirColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(dirIcon, size: 11, color: dirColor),
                const SizedBox(width: 4),
                Text(
                  dirLabel,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: dirColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Context Card ──────────────────────────────────────────────────────────────

class _ContextCard extends StatelessWidget {
  final SpxStrategySnapshot snap;
  const _ContextCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    final dplColor = switch (snap.dplDirection) {
      SpxDirection.up => AppTheme.green,
      SpxDirection.down => AppTheme.red,
      SpxDirection.neutral => AppTheme.textMuted,
    };
    final domColor = switch (snap.dominantDirection) {
      SpxDirection.up => AppTheme.green,
      SpxDirection.down => AppTheme.red,
      SpxDirection.neutral => AppTheme.textMuted,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const _CardHeader(title: 'SESSION CONTEXT'),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ContextItem(
                        label: 'SIGNIFICANT GAP',
                        value: snap.significantGap ? 'YES' : 'NO',
                        valueColor: snap.significantGap
                            ? const Color(0xFFFFB300)
                            : AppTheme.textMuted,
                      ),
                    ),
                    Expanded(
                      child: _ContextItem(
                        label: 'GAP %',
                        value: snap.gapPercent == 0
                            ? '—'
                            : '${NexusFormatters.number(snap.gapPercent, decimals: 2, signed: true)}%',
                        valueColor: snap.gapPercent > 0
                            ? AppTheme.green
                            : snap.gapPercent < 0
                                ? AppTheme.red
                                : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ContextItem(
                        label: 'DPL DIRECTION',
                        value: snap.dplDirection.label.toUpperCase(),
                        valueColor: dplColor,
                      ),
                    ),
                    Expanded(
                      child: _ContextItem(
                        label: 'DOMINANT DIR.',
                        value: snap.dominantDirection.label.toUpperCase(),
                        valueColor: domColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ContextItem(
                        label: 'SIGNALS UNIFIED',
                        value: snap.allSignalsAligned ? 'YES' : 'NO',
                        valueColor: snap.allSignalsAligned
                            ? AppTheme.green
                            : AppTheme.textMuted,
                      ),
                    ),
                    Expanded(
                      child: _ContextItem(
                        label: 'MINS FROM OPEN',
                        value: '${snap.minutesFromSessionStart}',
                        valueColor: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _ContextItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── Entry Reference Card ──────────────────────────────────────────────────────

class _EntryReferenceCard extends StatelessWidget {
  final SpxStrategySnapshot snap;
  const _EntryReferenceCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    final min14H = snap.minute14High;
    final min14L = snap.minute14Low;
    final longStrike = snap.longOtmStrike;
    final shortStrike = snap.shortOtmStrike;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const _CardHeader(title: 'ENTRY REFERENCE (MIN-14)'),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _RefBox(
                        label: 'MIN-14 HIGH',
                        value: min14H != null
                            ? NexusFormatters.number(min14H, decimals: 2)
                            : '—',
                        color: AppTheme.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RefBox(
                        label: 'MIN-14 LOW',
                        value: min14L != null
                            ? NexusFormatters.number(min14L, decimals: 2)
                            : '—',
                        color: AppTheme.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RefBox(
                        label: 'LONG OTM STRIKE',
                        value: longStrike != null
                            ? NexusFormatters.number(longStrike, decimals: 0)
                            : '—',
                        color: AppTheme.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RefBox(
                        label: 'SHORT OTM STRIKE',
                        value: shortStrike != null
                            ? NexusFormatters.number(shortStrike, decimals: 0)
                            : '—',
                        color: AppTheme.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RefBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RefBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── P&L Card ──────────────────────────────────────────────────────────────────

class _PnLCard extends StatelessWidget {
  final SpxState state;
  const _PnLCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final realized = state.realizedPnL;
    final unrealized = state.unrealizedPnL;
    final winRate = state.winRate;
    final total = state.totalTrades;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const _CardHeader(title: 'SESSION P&L'),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _ContextItem(
                    label: 'REALIZED',
                    value: NexusFormatters.usd(realized, signed: true),
                    valueColor:
                        realized >= 0 ? AppTheme.green : AppTheme.red,
                  ),
                ),
                Expanded(
                  child: _ContextItem(
                    label: 'UNREALIZED',
                    value: NexusFormatters.usd(unrealized, signed: true),
                    valueColor:
                        unrealized >= 0 ? AppTheme.green : AppTheme.red,
                  ),
                ),
                Expanded(
                  child: _ContextItem(
                    label: 'WIN RATE',
                    value: total == 0
                        ? '—'
                        : '${NexusFormatters.number(winRate, decimals: 0)}% ($total)',
                    valueColor:
                        winRate >= 50 ? AppTheme.green : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  const _CardHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
