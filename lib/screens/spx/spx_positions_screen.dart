import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../services/spx/spx_trade_journal_codes.dart';
import '../../services/spx/spx_trade_journal_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';

class SpxPositionsScreen extends StatelessWidget {
  const SpxPositionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      builder: (context, state) {
        // Only show live trades — skip simulator runs entirely
        if (state.dataMode == SpxDataMode.simulator) {
          return const _SimulatorNotice();
        }

        final openPositions = state.positions;
        final closedToday = state.closedToday;
        final journalRecords = state.journalRecords;

        // Separate today's journal records (earlier sessions today) from history.
        // Exclude IDs already in closedToday to avoid duplicates when a reload
        // happens mid-session.
        final todayKey = _dayKey(DateTime.now());
        final closedTodayIds = closedToday.map((r) => r.id).toSet();
        final journalToday = journalRecords
            .where((r) =>
                _dayKey(r.enteredAt) == todayKey &&
                !closedTodayIds.contains(r.tradeId))
            .toList()
          ..sort((a, b) => b.enteredAt.compareTo(a.enteredAt));

        // Historical records — everything not from today
        final grouped = <String, List<SpxTradeJournalRecord>>{};
        for (final r in journalRecords.where((r) => _dayKey(r.enteredAt) != todayKey)) {
          grouped.putIfAbsent(_dayKey(r.enteredAt), () => []).add(r);
        }
        final pastDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

        final totalTodayClosed = closedToday.length + journalToday.where((r) => r.exitedAt != null).length;
        final totalTodayPnL = state.realizedPnL +
            journalToday.fold<double>(0, (s, r) => s + (r.pnlUsd ?? 0));

        final hasToday = openPositions.isNotEmpty ||
            closedToday.isNotEmpty ||
            journalToday.isNotEmpty;

        if (!hasToday && grouped.isEmpty) return const _EmptyJournal();

        return RefreshIndicator(
          color: AppTheme.blue,
          backgroundColor: AppTheme.bg2,
          onRefresh: () async =>
              context.read<SpxBloc>().add(const LoadJournalHistory()),
          child: ListView(
            primary: false,
            padding: const EdgeInsets.all(10),
            children: [
              // ── Today ─────────────────────────────────────────────────────
              if (hasToday) ...[
                _TodayHeader(
                  openCount: openPositions.length,
                  closedCount: totalTodayClosed,
                  realizedPnL: totalTodayPnL,
                  unrealizedPnL: state.unrealizedPnL,
                ),
                const SizedBox(height: 8),
                // Open positions (current session)
                ...openPositions.map((p) => _OpenPositionCard(position: p)),
                // Closed this session (newest first)
                ...closedToday.reversed.map((r) => _ClosedTodayCard(record: r)),
                // Closed earlier today (from previous sessions)
                ...journalToday.map((r) => _JournalCard(record: r)),
                const SizedBox(height: 14),
              ],

              // ── Historical by day ─────────────────────────────────────────
              for (final day in pastDays) ...[
                _DayHeader(dayKey: day, records: grouped[day]!),
                const SizedBox(height: 8),
                ...grouped[day]!.map((r) => _JournalCard(record: r)),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _dayKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

String _formatDayLabel(String key) {
  final now = DateTime.now();
  final today = _dayKey(now);
  final yesterday =
      _dayKey(now.subtract(const Duration(days: 1)));
  if (key == today) return 'TODAY';
  if (key == yesterday) return 'YESTERDAY';
  final dt = DateTime.tryParse(key);
  if (dt == null) return key;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

String _formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

// ── Today Header ──────────────────────────────────────────────────────────────

class _TodayHeader extends StatelessWidget {
  final int openCount;
  final int closedCount;
  final double realizedPnL;
  final double unrealizedPnL;

  const _TodayHeader({
    required this.openCount,
    required this.closedCount,
    required this.realizedPnL,
    required this.unrealizedPnL,
  });

  @override
  Widget build(BuildContext context) {
    final total = realizedPnL + unrealizedPnL;
    final color = total >= 0 ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TODAY',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (openCount > 0)
                    _Chip(
                        label: '$openCount open', color: AppTheme.blue),
                  if (openCount > 0 && closedCount > 0)
                    const SizedBox(width: 6),
                  if (closedCount > 0)
                    _Chip(
                        label: '$closedCount closed',
                        color: AppTheme.textMuted),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NexusFormatters.usd(total, signed: true),
                style: GoogleFonts.syne(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                'R: ${NexusFormatters.usd(realizedPnL, signed: true)}  '
                'U: ${NexusFormatters.usd(unrealizedPnL, signed: true)}',
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

// ── Day Header (historical) ───────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final String dayKey;
  final List<SpxTradeJournalRecord> records;

  const _DayHeader({required this.dayKey, required this.records});

  @override
  Widget build(BuildContext context) {
    final closed = records.where((r) => r.exitedAt != null).toList();
    final dayPnL = closed.fold<double>(0, (s, r) => s + (r.pnlUsd ?? 0));
    final wins = closed.where((r) => (r.pnlUsd ?? 0) >= 0).length;
    final pnlColor = dayPnL >= 0 ? AppTheme.green : AppTheme.red;

    return Row(
      children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppTheme.textDim,
              borderRadius: BorderRadius.circular(2),
            )),
        const SizedBox(width: 8),
        Text(
          _formatDayLabel(dayKey),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        _Chip(label: '${records.length}', color: AppTheme.textDim),
        const Spacer(),
        if (closed.isNotEmpty) ...[
          Text(
            '$wins/${closed.length}W  ',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, color: AppTheme.textMuted),
          ),
          Text(
            NexusFormatters.usd(dayPnL, signed: true),
            style: GoogleFonts.syne(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: pnlColor,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Open Position Card (current session) ─────────────────────────────────────

class _OpenPositionCard extends StatelessWidget {
  final SpxPosition position;
  const _OpenPositionCard({required this.position});

  @override
  Widget build(BuildContext context) {
    final pnl = position.unrealizedPnL;
    final pnlPct = position.pnlPercent;
    final pnlColor = pnl >= 0 ? AppTheme.green : AppTheme.red;
    final isCall = position.contract.side == OptionsSide.call;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SideBadge(isCall: isCall),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NexusFormatters.usd(position.contract.strike,
                            decimals: 0),
                        style: GoogleFonts.syne(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary),
                      ),
                      Text(
                        '${position.contract.daysToExpiry}DTE · opened ${_formatTime(position.openedAt)}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
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
                      '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: pnlColor),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoChip(
                    label: 'Entry',
                    value: NexusFormatters.usd(position.entryPremium)),
                const SizedBox(width: 12),
                _InfoChip(
                    label: 'Now',
                    value: NexusFormatters.usd(position.currentPremium),
                    valueColor: pnlColor),
                const SizedBox(width: 12),
                _InfoChip(
                    label: 'Qty', value: '${position.contracts}×'),
                const Spacer(),
                _Chip(label: 'OPEN', color: AppTheme.blue),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context
                  .read<SpxBloc>()
                  .add(CloseSpxPosition(position.id)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: pnlColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: pnlColor.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'CLOSE POSITION',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: pnlColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Closed Today Card (current session) ──────────────────────────────────────

class _ClosedTodayCard extends StatelessWidget {
  final SpxClosedPositionRecord record;
  const _ClosedTodayCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final pnlColor = record.isWin ? AppTheme.green : AppTheme.red;
    final isCall = record.side == OptionsSide.call;
    final hold = record.exitAt.difference(record.entryAt).inMinutes;
    final holdLabel = hold < 60 ? '${hold}m' : '${hold ~/ 60}h${hold % 60 == 0 ? '' : '${hold % 60}m'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SideBadge(isCall: isCall, dimmed: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NexusFormatters.usd(record.strike, decimals: 0),
                        style: GoogleFonts.syne(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary
                                .withValues(alpha: 0.8)),
                      ),
                      Text(
                        '${record.dteAtEntry}DTE · ${record.contracts}×',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NexusFormatters.usd(record.pnlUsd, signed: true),
                      style: GoogleFonts.syne(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: pnlColor),
                    ),
                    Text(
                      '${record.pnlPct >= 0 ? '+' : ''}${record.pnlPct.toStringAsFixed(1)}%',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, color: pnlColor),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Timeline(
              entryTime: _formatTime(record.entryAt),
              entryPremium: NexusFormatters.usd(record.entryPremium),
              exitTime: _formatTime(record.exitAt),
              exitPremium: NexusFormatters.usd(record.exitPremium),
              holdLabel: holdLabel,
              pnlColor: pnlColor,
            ),
            const SizedBox(height: 8),
            _ExitBadge(reason: record.exitReason),
          ],
        ),
      ),
    );
  }
}

// ── Journal Card (historical from repository) ─────────────────────────────────

class _JournalCard extends StatelessWidget {
  final SpxTradeJournalRecord record;
  const _JournalCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final isClosed = record.exitedAt != null;
    final pnl = record.pnlUsd ?? 0;
    final pnlPct = record.pnlPct ?? 0;
    final pnlColor = pnl >= 0 ? AppTheme.green : AppTheme.red;
    final isCall = record.side == 'call';

    final holdLabel = isClosed
        ? _holdDuration(record.enteredAt, record.exitedAt!)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isClosed
              ? AppTheme.border.withValues(alpha: 0.5)
              : AppTheme.blue.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                _SideBadge(isCall: isCall, dimmed: isClosed),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        NexusFormatters.usd(record.strike, decimals: 0),
                        style: GoogleFonts.syne(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary
                              .withValues(alpha: isClosed ? 0.8 : 1.0),
                        ),
                      ),
                      Text(
                        '${record.dteEntry}DTE · ${record.contracts}× · '
                        '${record.entrySource == 'auto' ? 'AUTO' : 'MANUAL'}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                if (isClosed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NexusFormatters.usd(pnl, signed: true),
                        style: GoogleFonts.syne(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: pnlColor),
                      ),
                      Text(
                        '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(1)}%',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, color: pnlColor),
                      ),
                    ],
                  )
                else
                  _Chip(label: 'OPEN', color: AppTheme.blue),
              ],
            ),
            const SizedBox(height: 10),
            // Timeline
            if (isClosed)
              _Timeline(
                entryTime: _formatTime(record.enteredAt),
                entryPremium: NexusFormatters.usd(record.entryPremium),
                exitTime: _formatTime(record.exitedAt!),
                exitPremium: NexusFormatters.usd(record.exitPremium ?? 0),
                holdLabel: holdLabel!,
                pnlColor: pnlColor,
              )
            else
              Row(
                children: [
                  _InfoChip(
                      label: 'In',
                      value: _formatTime(record.enteredAt)),
                  const SizedBox(width: 12),
                  _InfoChip(
                      label: 'Entry',
                      value: NexusFormatters.usd(record.entryPremium)),
                ],
              ),
            if (isClosed && record.exitReasonCode != null) ...[
              const SizedBox(height: 8),
              _ExitBadge(reason: record.exitReasonCode!),
            ],
            if (record.signalScore > 0) ...[
              const SizedBox(height: 6),
              _SignalScore(score: record.signalScore),
            ],
          ],
        ),
      ),
    );
  }

  String _holdDuration(DateTime from, DateTime to) {
    final mins = to.difference(from).inMinutes;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h${m}m';
  }
}

// ── Timeline widget ───────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final String entryTime;
  final String entryPremium;
  final String exitTime;
  final String exitPremium;
  final String holdLabel;
  final Color pnlColor;

  const _Timeline({
    required this.entryTime,
    required this.entryPremium,
    required this.exitTime,
    required this.exitPremium,
    required this.holdLabel,
    required this.pnlColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _TimelineNode(label: 'IN', time: entryTime, premium: entryPremium, color: AppTheme.blue)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              const Icon(Icons.arrow_forward_rounded, size: 12, color: AppTheme.textDim),
              Text(holdLabel, style: GoogleFonts.spaceGrotesk(fontSize: 8, color: AppTheme.textDim)),
            ],
          ),
        ),
        Expanded(child: _TimelineNode(label: 'OUT', time: exitTime, premium: exitPremium, color: pnlColor, alignRight: true)),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  final String label;
  final String time;
  final String premium;
  final Color color;
  final bool alignRight;

  const _TimelineNode({
    required this.label,
    required this.time,
    required this.premium,
    required this.color,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final align = alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: color)),
          const SizedBox(height: 2),
          Text(premium, style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          Text(time, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

// ── Exit badge ────────────────────────────────────────────────────────────────

class _ExitBadge extends StatelessWidget {
  final String reason;
  const _ExitBadge({required this.reason});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (reason) {
      SpxExitReasonCodes.takeProfit => ('Take Profit', AppTheme.green),
      SpxExitReasonCodes.stopLoss => ('Stop Loss', AppTheme.red),
      SpxExitReasonCodes.expired => ('Expired', AppTheme.gold),
      SpxExitReasonCodes.manualClose => ('Manual Close', AppTheme.textMuted),
      _ => (reason, AppTheme.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Signal score ──────────────────────────────────────────────────────────────

class _SignalScore extends StatelessWidget {
  final int score;
  const _SignalScore({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 12
        ? AppTheme.green
        : score >= 8
            ? AppTheme.gold
            : AppTheme.textMuted;
    return Row(
      children: [
        Text('Signal ',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, color: AppTheme.textDim)),
        Text('$score/17',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SideBadge extends StatelessWidget {
  final bool isCall;
  final bool dimmed;
  const _SideBadge({required this.isCall, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final base = isCall ? AppTheme.green : AppTheme.red;
    final color = dimmed ? base.withValues(alpha: 0.6) : base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        isCall ? 'CALL' : 'PUT',
        style: GoogleFonts.syne(
            fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 8, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoChip({required this.label, required this.value, this.valueColor});

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
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary)),
      ],
    );
  }
}

class _SimulatorNotice extends StatelessWidget {
  const _SimulatorNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_outlined, size: 40, color: AppTheme.textDim),
          const SizedBox(height: 12),
          Text('Simulator mode active',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textDim)),
          const SizedBox(height: 6),
          Text('Switch to live data to record real trades',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded, size: 40, color: AppTheme.textDim),
          const SizedBox(height: 12),
          Text('No trade history yet',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textDim)),
          const SizedBox(height: 6),
          Text('Live trades will appear here organised by day',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
