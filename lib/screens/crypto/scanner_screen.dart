import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';

import '../../blocs/crypto/crypto_bloc.dart';
import '../../models/crypto_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/shared_widgets.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoBloc, CryptoState>(
      builder: (context, state) {
        return Column(
          children: [
            _ScannerModePicker(state: state),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: state.scannerViewMode == CryptoScannerViewMode.scanner
                    ? _MarketScannerPane(
                        key: const ValueKey('market-scanner-pane'),
                        state: state,
                      )
                    : _OpportunitiesPane(
                        key: const ValueKey('opportunities-pane'),
                        state: state,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerModePicker extends StatelessWidget {
  final CryptoState state;

  const _ScannerModePicker({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SegmentedButton<CryptoScannerViewMode>(
        segments: const [
          ButtonSegment<CryptoScannerViewMode>(
            value: CryptoScannerViewMode.scanner,
            label: Text('Scanner'),
            icon: Icon(Icons.show_chart_rounded),
          ),
          ButtonSegment<CryptoScannerViewMode>(
            value: CryptoScannerViewMode.opportunities,
            label: Text('Opportunities'),
            icon: Icon(Icons.bolt_rounded),
          ),
        ],
        selected: {state.scannerViewMode},
        onSelectionChanged: (selection) {
          if (selection.isEmpty) return;
          context.read<CryptoBloc>().add(
                ChangeCryptoScannerView(selection.first),
              );
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTheme.bg4;
            }
            return AppTheme.bg3;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppTheme.textMuted;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppTheme.border),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketScannerPane extends StatelessWidget {
  final CryptoState state;

  const _MarketScannerPane({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SignalSummary(state: state),
        if (state.selectedCoin != null)
          _CoinDetailCard(coin: state.selectedCoin!),
        Expanded(child: _CoinList(state: state)),
      ],
    );
  }
}

class _OpportunitiesPane extends StatelessWidget {
  final CryptoState state;

  const _OpportunitiesPane({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OpportunitySummary(state: state),
        if (state.opportunitiesLoading && state.opportunities.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        if (state.selectedOpportunity != null)
          _OpportunityDetailCard(
            opportunity: state.selectedOpportunity!,
            scannerHasSymbol: state.coins.any(
                (coin) => coin.symbol == state.selectedOpportunity!.symbol),
          ),
        Expanded(child: _OpportunityList(state: state)),
      ],
    );
  }
}

class _SignalSummary extends StatelessWidget {
  final CryptoState state;
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

class _OpportunitySummary extends StatelessWidget {
  final CryptoState state;

  const _OpportunitySummary({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Ranked',
                  value: '${state.opportunities.length}',
                  color: AppTheme.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: 'Actionable',
                  value: '${state.actionableOpportunities.length}',
                  color: AppTheme.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  label: 'Updated',
                  value:
                      _formatUpdatedAt(context, state.opportunitiesUpdatedAt),
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh opportunities',
                onPressed: state.opportunitiesLoading
                    ? null
                    : () => context
                        .read<CryptoBloc>()
                        .add(RefreshCryptoOpportunities()),
                icon: Icon(
                  Icons.refresh_rounded,
                  color: state.opportunitiesLoading
                      ? AppTheme.textDim
                      : AppTheme.blue,
                ),
              ),
            ],
          ),
          if (state.opportunitiesError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.redBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.red.withValues(alpha: 0.25)),
              ),
              child: Text(
                state.opportunitiesError!,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: AppTheme.red,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatUpdatedAt(BuildContext context, DateTime? updatedAt) {
    if (updatedAt == null) return 'Never';
    return TimeOfDay.fromDateTime(updatedAt).format(context);
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
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
                              color: coin.isPositive
                                  ? AppTheme.green
                                  : AppTheme.red,
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
                  onTap: () =>
                      context.read<CryptoBloc>().add(BuyCoin(coin.symbol)),
                ),
              ],
            ),
          ),
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
                    value:
                        ind.macd == MACDTrend.bullish ? 'Bullish' : 'Bearish',
                    note: ind.macd == MACDTrend.bullish
                        ? '↗ Uptrend'
                        : '↘ Downtrend',
                    color: ind.macd == MACDTrend.bullish
                        ? AppTheme.green
                        : AppTheme.red,
                  ),
                ),
                _vertDiv(),
                Expanded(
                  child: IndicatorTile(
                    label: 'Vol Spike',
                    value: '${ind.volumeSpike.toStringAsFixed(2)}x',
                    note: ind.volumeSpike > 1.5 ? 'Unusual' : 'Normal',
                    color:
                        ind.volumeSpike > 1.5 ? AppTheme.gold : AppTheme.blue,
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

class _OpportunityDetailCard extends StatelessWidget {
  final CryptoOpportunity opportunity;
  final bool scannerHasSymbol;

  const _OpportunityDetailCard({
    required this.opportunity,
    required this.scannerHasSymbol,
  });

  @override
  Widget build(BuildContext context) {
    final score = opportunity.score;
    final positiveSignals = score?.positiveSignals.take(5).toList() ?? const [];
    final riskSignals = score?.riskSignals.take(3).toList() ?? const [];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoinAvatar(symbol: opportunity.symbol, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${opportunity.symbol} · ${opportunity.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.syne(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OpportunityScoreBadge(score: score),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          _formatOpportunityPrice(opportunity.priceUsd),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _formatPct(opportunity.priceChange24h),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: opportunity.priceChange24h >= 0
                                ? AppTheme.green
                                : AppTheme.red,
                          ),
                        ),
                        ...opportunity.sources.map(
                          (source) => _OpportunityTag(
                            label: source.label,
                            color: AppTheme.blue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (scannerHasSymbol)
                NexusButton(
                  label: 'OPEN IN SCANNER',
                  small: true,
                  borderColor: AppTheme.blue,
                  textColor: AppTheme.blue,
                  onTap: () {
                    final bloc = context.read<CryptoBloc>();
                    bloc.add(const ChangeCryptoScannerView(
                      CryptoScannerViewMode.scanner,
                    ));
                    bloc.add(SelectCoin(opportunity.symbol));
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OpportunityMetric(
                label: 'Market Cap',
                value: _formatCompactUsd(opportunity.marketCap),
              ),
              _OpportunityMetric(
                label: '24h Volume',
                value: _formatCompactUsd(opportunity.volume24h),
              ),
              _OpportunityMetric(
                label: 'Liquidity',
                value: _formatCompactUsd(opportunity.liquidityUsd),
              ),
              _OpportunityMetric(
                label: 'Vol/MCap',
                value:
                    '${NexusFormatters.number(opportunity.volumeMarketCapRatio * 100, decimals: 1)}%',
              ),
            ],
          ),
          if (positiveSignals.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Signals',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ...positiveSignals.map(
              (signal) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${signal.label}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
          if (riskSignals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: riskSignals
                  .map(
                    (signal) => _OpportunityTag(
                      label: signal.label,
                      color: AppTheme.red,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpportunityMetric extends StatelessWidget {
  final String label;
  final String value;

  const _OpportunityMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.syne(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunityTag extends StatelessWidget {
  final String label;
  final Color color;

  const _OpportunityTag({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _OpportunityScoreBadge extends StatelessWidget {
  final CryptoOpportunityScore? score;

  const _OpportunityScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final grade = score?.grade ?? CryptoOpportunityGrade.weak;
    final color = switch (grade) {
      CryptoOpportunityGrade.elite => AppTheme.green,
      CryptoOpportunityGrade.strong => AppTheme.gold,
      CryptoOpportunityGrade.watch => AppTheme.blue,
      CryptoOpportunityGrade.weak => AppTheme.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Score ${score?.value.toStringAsFixed(0) ?? '0'}',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _OpportunityList extends StatelessWidget {
  final CryptoState state;

  const _OpportunityList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.opportunities.isEmpty) {
      if (state.opportunitiesLoading) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }

      return _OpportunityEmptyState(
        icon: state.opportunitiesError == null
            ? Icons.search_off_rounded
            : Icons.error_outline_rounded,
        message: state.opportunitiesError == null
            ? 'No opportunities ranked yet.'
            : 'Unable to load opportunities right now.',
      );
    }

    return ListView.builder(
      itemCount: state.opportunities.length,
      itemBuilder: (context, index) {
        final opportunity = state.opportunities[index];
        final isSelected = state.selectedOpportunity?.id == opportunity.id;
        final leadSignals =
            opportunity.score?.positiveSignals.take(2).toList() ?? const [];

        return GestureDetector(
          onTap: () => context
              .read<CryptoBloc>()
              .add(SelectCryptoOpportunity(opportunity.id)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.bg3 : AppTheme.bg2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.blue : AppTheme.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoinAvatar(symbol: opportunity.symbol, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${opportunity.symbol} · ${opportunity.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.syne(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _OpportunityScoreBadge(score: opportunity.score),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            _formatOpportunityPrice(opportunity.priceUsd),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            _formatPct(opportunity.priceChange24h),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: opportunity.priceChange24h >= 0
                                  ? AppTheme.green
                                  : AppTheme.red,
                            ),
                          ),
                          Text(
                            'MCap ${_formatCompactUsd(opportunity.marketCap)}',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (leadSignals.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...leadSignals.map(
                          (signal) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              signal.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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

class _OpportunityEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _OpportunityEmptyState({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: AppTheme.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinList extends StatelessWidget {
  final CryptoState state;
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
          onTap: () => context.read<CryptoBloc>().add(SelectCoin(coin.symbol)),
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
                              color: coin.isPositive
                                  ? AppTheme.green
                                  : AppTheme.red,
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
                  onTap: () =>
                      context.read<CryptoBloc>().add(BuyCoin(coin.symbol)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppTheme.green.withValues(alpha: 0.5)),
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

String _formatOpportunityPrice(double price) {
  if (price >= 1000) return NexusFormatters.usd(price, decimals: 2);
  if (price >= 1) return NexusFormatters.usd(price, decimals: 3);
  if (price >= 0.1) return NexusFormatters.usd(price, decimals: 4);
  return NexusFormatters.usd(price, decimals: 6);
}

String _formatPct(double value) {
  return '${NexusFormatters.number(value, decimals: 1, signed: true)}%';
}

String _formatCompactUsd(double? value) {
  if (value == null || value <= 0) return '—';
  return '\$${NexusFormatters.compactNumber(value)}';
}
