part of 'trading_bloc.dart';

class TradingState extends Equatable {
  final List<CoinData> coins;
  final List<Position> positions;
  final List<TradeLog> logs;
  final DailyStats stats;
  final BotStatus botStatus;
  final Exchange selectedExchange;
  final Timeframe selectedTimeframe;
  final MarketDataMode marketDataMode;
  final bool alertsEnabled;
  final bool hapticsEnabled;
  final String? selectedSymbol;
  final int activeTab;

  const TradingState({
    required this.coins,
    required this.positions,
    required this.logs,
    required this.stats,
    required this.botStatus,
    required this.selectedExchange,
    required this.selectedTimeframe,
    required this.marketDataMode,
    required this.alertsEnabled,
    required this.hapticsEnabled,
    this.selectedSymbol,
    required this.activeTab,
  });

  factory TradingState.initial() => const TradingState(
        coins: [],
        positions: [],
        logs: [],
        stats: DailyStats(),
        botStatus: BotStatus.paused,
        selectedExchange: Exchange.all,
        selectedTimeframe: Timeframe.m15,
        marketDataMode: MarketDataMode.simulator,
        alertsEnabled: true,
        hapticsEnabled: true,
        activeTab: 0,
      );

  CoinData? get selectedCoin {
    if (selectedSymbol == null || coins.isEmpty) return null;
    return coins.firstWhere(
      (c) => c.symbol == selectedSymbol,
      orElse: () => coins.first,
    );
  }

  List<CoinData> get signalCoins =>
      coins.where((c) => c.indicators.signal != SignalType.watch).toList();

  List<CoinData> get buySignals =>
      coins.where((c) => c.indicators.signal == SignalType.buy).toList();

  List<CoinData> get sellSignals =>
      coins.where((c) => c.indicators.signal == SignalType.sell).toList();

  double get totalUnrealizedPnL =>
      positions.fold<double>(0.0, (s, p) => s + p.unrealizedPnL);

  TradingState copyWith({
    List<CoinData>? coins,
    List<Position>? positions,
    List<TradeLog>? logs,
    DailyStats? stats,
    BotStatus? botStatus,
    Exchange? selectedExchange,
    Timeframe? selectedTimeframe,
    MarketDataMode? marketDataMode,
    bool? alertsEnabled,
    bool? hapticsEnabled,
    String? selectedSymbol,
    bool clearSelectedSymbol = false,
    int? activeTab,
  }) {
    return TradingState(
      coins: coins ?? this.coins,
      positions: positions ?? this.positions,
      logs: logs ?? this.logs,
      stats: stats ?? this.stats,
      botStatus: botStatus ?? this.botStatus,
      selectedExchange: selectedExchange ?? this.selectedExchange,
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
      marketDataMode: marketDataMode ?? this.marketDataMode,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      selectedSymbol:
          clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
      activeTab: activeTab ?? this.activeTab,
    );
  }

  @override
  List<Object?> get props => [
        coins,
        positions,
        logs,
        stats,
        botStatus,
        selectedExchange,
        selectedTimeframe,
        marketDataMode,
        alertsEnabled,
        hapticsEnabled,
        selectedSymbol,
        activeTab,
      ];
}
