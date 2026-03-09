import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/trading_bloc.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingBloc, TradingState>(
      builder: (context, state) {
        return Column(
          children: [
            _SignalSummary(state: state),
            if (state.selectedCoin != null) _CoinDetailCard(coin: state.selectedCoin!),
            Expanded(child: _CoinList(state: state)),
          ],
        );
      },
    );
  }
}

class _SignalSummary extends StatelessWidget {
  final TradingState state;
  const _SignalSummary({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppTheme.border)),
              ),
              child: StatBox(
                label: 'Buy Signals',
                value: '${state.buySignals.length}',
                valueColor: AppTheme.green,
              ),
            ),
          ),
          Expanded(
            child: StatBox(
              label: 'Sell Signals',
              value: '${state.sellSignals.length}',
              valueColor: AppTheme.red,
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppTheme.border)),
              ),
              child: StatBox(
                label: 'Positions',
                value: '${state.positions.length}',
                valueColor: AppTheme.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinDetailCard extends StatelessWidget {
  final CoinData coin;
  const _CoinDetailCard({required this.coin});

  @override
  Widget build(BuildContext context) {
    final ind = coin.indicators;
    final rsiColor = ind.rsi < 40
        ? AppTheme.green
        : ind.rsi > 65
            ? AppTheme.red
            : AppTheme.blue;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CoinAvatar(symbol: coin.symbol, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            coin.formattedPrice,
                            style: GoogleFonts.syne(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            coin.formattedChange,
                            style: GoogleFonts.syne(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: coin.isPositive ? AppTheme.green : AppTheme.red,
                            ),
                          ),
                          SignalBadge(signal: coin.indicators.signal),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${coin.name} · Vol ${_fmtBig(coin.volume)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                NexusButton(
                  label: 'BUY ${coin.symbol}',
                  borderColor: AppTheme.green,
                  textColor: AppTheme.green,
                  onTap: () => context.read<TradingBloc>().add(BuyCoin(coin.symbol)),
                ),
              ],
            ),
          ),
          // Chart
          SizedBox(
            height: 140,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: PriceChart(
                prices: coin.priceHistory,
                isPositive: coin.isPositive,
              ),
            ),
          ),
          // Indicators
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: IndicatorTile(
                    label: 'RSI',
                    value: ind.rsi.toStringAsFixed(1),
                    note: ind.rsiLabel,
                    color: rsiColor,
                  ),
                ),
                _vertDiv(),
                Expanded(
                  child: IndicatorTile(
                    label: 'MACD',
                    value: ind.macd == MACDTrend.bullish ? 'Bullish' : 'Bearish',
                    note: ind.macd == MACDTrend.bullish ? '↗ Uptrend' : '↘ Downtrend',
                    color: ind.macd == MACDTrend.bullish ? AppTheme.green : AppTheme.red,
                  ),
                ),
                _vertDiv(),
                Expanded(
                  child: IndicatorTile(
                    label: 'Vol Spike',
                    value: '${ind.volumeSpike.toStringAsFixed(2)}x',
                    note: ind.volumeSpike > 1.5 ? 'Unusual' : 'Normal',
                    color: ind.volumeSpike > 1.5 ? AppTheme.gold : AppTheme.blue,
                  ),
                ),
                _vertDiv(),
                Expanded(
                  child: IndicatorTile(
                    label: 'BB Squeeze',
                    value: ind.bbSqueeze ? 'YES' : 'NO',
                    note: ind.bbSqueeze ? 'Breakout soon' : 'Normal range',
                    color: ind.bbSqueeze ? AppTheme.gold : AppTheme.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vertDiv() => Container(
        width: 1,
        color: AppTheme.border,
      );

  String _fmtBig(double n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _CoinList extends StatelessWidget {
  final TradingState state;
  const _CoinList({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: state.coins.length,
      itemBuilder: (context, i) {
        final coin = state.coins[i];
        final isSelected = state.selectedSymbol == coin.symbol;
        final sig = coin.indicators.signal;
        return GestureDetector(
          onTap: () => context.read<TradingBloc>().add(SelectCoin(coin.symbol)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.bg3
                  : sig == SignalType.buy
                      ? const Color(0xFF001508)
                      : AppTheme.bg2,
              border: const Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CoinAvatar(symbol: coin.symbol, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            coin.symbol,
                            style: GoogleFonts.syne(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            coin.name,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            coin.formattedPrice,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            coin.formattedChange,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: coin.isPositive ? AppTheme.green : AppTheme.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SignalBadge(signal: sig),
                    const SizedBox(height: 6),
                    MiniSparkline(prices: coin.priceHistory, signal: sig),
                  ],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.read<TradingBloc>().add(BuyCoin(coin.symbol)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.green.withOpacity(0.5)),
                    ),
                    child: Text(
                      'BUY',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
