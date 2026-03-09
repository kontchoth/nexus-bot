import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/trading_bloc.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class PositionsScreen extends StatelessWidget {
  const PositionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingBloc, TradingState>(
      builder: (context, state) {
        if (state.positions.isEmpty) {
          return _EmptyPositions();
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: state.positions.length,
                itemBuilder: (context, i) =>
                    _PositionCard(pos: state.positions[i]),
              ),
            ),
            _TotalPnLBar(state: state),
          ],
        );
      },
    );
  }
}

class _EmptyPositions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: AppTheme.textDim),
          const SizedBox(height: 16),
          Text(
            'No Open Positions',
            style: GoogleFonts.syne(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the bot or manually buy\nfrom the Scanner tab.',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: AppTheme.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  final Position pos;
  const _PositionCard({required this.pos});

  @override
  Widget build(BuildContext context) {
    final isProfit = pos.isProfit;
    final pnlColor = isProfit ? AppTheme.green : AppTheme.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(
          color: isProfit
              ? AppTheme.green.withOpacity(0.2)
              : AppTheme.red.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CoinAvatar(symbol: pos.symbol, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pos.symbol,
                      style: GoogleFonts.syne(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Entry: \$${_fmtPrice(pos.entryPrice)}  ·  Size: \$${pos.size.toStringAsFixed(0)}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      'Opened: ${_fmtTime(pos.openedAt)}  ·  Qty: ${pos.quantity.toStringAsFixed(4)}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    pos.formattedPnL,
                    style: GoogleFonts.syne(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: pnlColor,
                    ),
                  ),
                  Text(
                    '${pos.pnlPercent >= 0 ? '+' : ''}${pos.pnlPercent.toStringAsFixed(2)}%',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: pnlColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: RiskBar(
                  pct: (pos.pnlPercent.abs() / 10).clamp(0, 1),
                  color: pnlColor,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () =>
                    context.read<TradingBloc>().add(SellPosition(pos.id)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.redBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppTheme.red.withOpacity(0.5)),
                  ),
                  child: Text(
                    'SELL',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double p) =>
      p >= 1000 ? p.toStringAsFixed(2) : p.toStringAsFixed(4);

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _TotalPnLBar extends StatelessWidget {
  final TradingState state;
  const _TotalPnLBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final pnl = state.totalUnrealizedPnL;
    final isPos = pnl >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total Unrealized PnL',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
          Text(
            '${isPos ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
            style: GoogleFonts.syne(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isPos ? AppTheme.green : AppTheme.red,
            ),
          ),
        ],
      ),
    );
  }
}
