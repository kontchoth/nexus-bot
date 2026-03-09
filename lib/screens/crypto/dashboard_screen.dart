import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/crypto/crypto_bloc.dart';
import '../../models/crypto_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoBloc, CryptoState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _PnLSection(state: state),
            const SizedBox(height: 12),
            _StatsGrid(state: state),
            const SizedBox(height: 12),
            _SignalAlerts(state: state),
            const SizedBox(height: 12),
            _StrategyPanel(),
            const SizedBox(height: 12),
            _RiskPanel(state: state),
            const SizedBox(height: 12),
            _RiskNotice(),
          ],
        );
      },
    );
  }
}

class _PnLSection extends StatelessWidget {
  final CryptoState state;
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
          Text(
            'Daily Performance',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: AppTheme.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          PnLArc(
            value: state.stats.realizedPnL.clamp(0, double.infinity),
            target: state.stats.dailyTarget,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PnLChip(
                label: 'Realized',
                value: '\$${state.stats.realizedPnL.toStringAsFixed(2)}',
                color: state.stats.realizedPnL >= 0 ? AppTheme.green : AppTheme.red,
              ),
              const SizedBox(width: 16),
              _PnLChip(
                label: 'Unrealized',
                value: '\$${state.totalUnrealizedPnL.toStringAsFixed(2)}',
                color: state.totalUnrealizedPnL >= 0 ? AppTheme.green : AppTheme.red,
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

class _StatsGrid extends StatelessWidget {
  final CryptoState state;
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
          value: '${state.stats.totalTrades}',
          valueColor: AppTheme.blue,
        ),
        StatBox(
          label: 'Win Rate',
          value: state.stats.totalTrades == 0
              ? '—'
              : '${state.stats.winRate.toStringAsFixed(0)}%',
          valueColor: AppTheme.gold,
        ),
        StatBox(
          label: 'Capital',
          value: '\$${(state.stats.capital / 1000).toStringAsFixed(1)}k',
          valueColor: AppTheme.textPrimary,
        ),
        StatBox(
          label: 'Open Positions',
          value: '${state.positions.length}',
          valueColor: AppTheme.blue,
        ),
      ],
    );
  }
}

class _SignalAlerts extends StatelessWidget {
  final CryptoState state;
  const _SignalAlerts({required this.state});

  @override
  Widget build(BuildContext context) {
    final signals = state.signalCoins;
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
            child: Text(
              '⚡ LIVE SIGNALS',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (signals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                'Scanning for signals...',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: AppTheme.textDim),
              ),
            ),
          ...signals.map((coin) => _SignalTile(coin: coin)),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  final CoinData coin;
  const _SignalTile({required this.coin});

  @override
  Widget build(BuildContext context) {
    final isBuy = coin.indicators.signal == SignalType.buy;
    final color = isBuy ? AppTheme.green : AppTheme.red;
    final bgColor = isBuy ? AppTheme.greenBg : AppTheme.redBg;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${isBuy ? '🟢' : '🔴'} ${coin.symbol}',
                style: GoogleFonts.syne(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${isBuy ? 'BUY' : 'SELL'} · ${coin.indicators.signalStrength}/4',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'RSI ${coin.indicators.rsi.toStringAsFixed(1)} · Vol ${coin.indicators.volumeSpike.toStringAsFixed(2)}x · MACD ${coin.indicators.macd.name}',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    final bloc = context.read<CryptoBloc>();
                    if (isBuy) {
                      bloc.add(BuyCoin(coin.symbol));
                    } else {
                      final positions = bloc.state.positions
                          .where((p) => p.symbol == coin.symbol)
                          .toList();
                      if (positions.isNotEmpty) {
                        bloc.add(SellPosition(positions.first.id));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'EXECUTE ${isBuy ? 'BUY' : 'SELL'}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    context.read<CryptoBloc>().add(SelectCoin(coin.symbol)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bg3,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.border2),
                  ),
                  child: Text(
                    'CHART',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: AppTheme.textMuted,
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
}

class _StrategyPanel extends StatelessWidget {
  final strategies = const [
    ('RSI Momentum', 'Oversold/overbought detection'),
    ('MACD Trend', 'Trend direction confirmation'),
    ('Volume Spike', 'Unusual volume detection'),
    ('BB Squeeze', 'Breakout prediction'),
  ];

  const _StrategyPanel();

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              '🎯 ACTIVE STRATEGIES',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...strategies.map(
            (s) => Container(
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
                        Text(s.$1,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12, color: AppTheme.textPrimary)),
                        Text(s.$2,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.greenBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppTheme.green.withOpacity(0.4)),
                    ),
                    child: Text('ON',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.green)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskPanel extends StatelessWidget {
  final CryptoState state;
  const _RiskPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final riskPct = 5.0;
    final riskAmount = state.stats.capital * riskPct / 100;

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
          Text('RISK PER TRADE',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          RiskBar(pct: riskPct / 100, color: AppTheme.green),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${riskPct.toStringAsFixed(0)}% (\$${riskAmount.toStringAsFixed(0)})',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, color: AppTheme.textMuted)),
              Text('Max: 10%',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskNotice extends StatelessWidget {
  const _RiskNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0500),
        border: Border.all(color: AppTheme.gold.withOpacity(0.25)),
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
                Text('Risk Notice',
                    style: GoogleFonts.syne(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold)),
                const SizedBox(height: 4),
                Text(
                  'This app uses simulated market data for demonstration. Real trading involves substantial risk of loss. Always backtest strategies and paper trade before using real capital.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppTheme.gold.withOpacity(0.7),
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
