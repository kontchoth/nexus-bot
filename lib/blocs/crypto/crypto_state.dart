part of 'crypto_bloc.dart';

class CryptoState extends Equatable {
  final List<CoinData> coins;
  final List<Position> positions;
  final List<TradeLog> logs;
  final DailyStats stats;
  final BotStatus botStatus;
  final Exchange selectedExchange;
  final CryptoDataProvider marketProvider;
  final Timeframe selectedTimeframe;
  final MarketDataMode marketDataMode;
  final bool alertsEnabled;
  final bool hapticsEnabled;
  final bool hasRobinhoodToken;
  final String? selectedSymbol;

  const CryptoState({
    required this.coins,
    required this.positions,
    required this.logs,
    required this.stats,
    required this.botStatus,
    required this.selectedExchange,
    required this.marketProvider,
    required this.selectedTimeframe,
    required this.marketDataMode,
    required this.alertsEnabled,
    required this.hapticsEnabled,
    this.hasRobinhoodToken = false,
    this.selectedSymbol,
  });

  factory CryptoState.initial() => const CryptoState(
        coins: [],
        positions: [],
        logs: [],
        stats: DailyStats(),
        botStatus: BotStatus.paused,
        selectedExchange: Exchange.all,
        marketProvider: CryptoDataProvider.binance,
        selectedTimeframe: Timeframe.m15,
        marketDataMode: MarketDataMode.simulator,
        alertsEnabled: true,
        hapticsEnabled: true,
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

  CryptoState copyWith({
    List<CoinData>? coins,
    List<Position>? positions,
    List<TradeLog>? logs,
    DailyStats? stats,
    BotStatus? botStatus,
    Exchange? selectedExchange,
    CryptoDataProvider? marketProvider,
    Timeframe? selectedTimeframe,
    MarketDataMode? marketDataMode,
    bool? alertsEnabled,
    bool? hapticsEnabled,
    bool? hasRobinhoodToken,
    String? selectedSymbol,
    bool clearSelectedSymbol = false,
  }) {
    return CryptoState(
      coins: coins ?? this.coins,
      positions: positions ?? this.positions,
      logs: logs ?? this.logs,
      stats: stats ?? this.stats,
      botStatus: botStatus ?? this.botStatus,
      selectedExchange: selectedExchange ?? this.selectedExchange,
      marketProvider: marketProvider ?? this.marketProvider,
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
      marketDataMode: marketDataMode ?? this.marketDataMode,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      hasRobinhoodToken: hasRobinhoodToken ?? this.hasRobinhoodToken,
      selectedSymbol:
          clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
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
        marketProvider,
        selectedTimeframe,
        marketDataMode,
        alertsEnabled,
        hapticsEnabled,
        hasRobinhoodToken,
        selectedSymbol,
      ];
}
