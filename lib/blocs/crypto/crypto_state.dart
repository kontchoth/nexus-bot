part of 'crypto_bloc.dart';

class CryptoState extends Equatable {
  final List<CoinData> coins;
  final List<CryptoOpportunity> opportunities;
  final List<Position> positions;
  final List<TradeLog> logs;
  final DailyStats stats;
  final BotStatus botStatus;
  final Exchange selectedExchange;
  final CryptoDataProvider marketProvider;
  final Timeframe selectedTimeframe;
  final CryptoScannerViewMode scannerViewMode;
  final MarketDataMode marketDataMode;
  final bool alertsEnabled;
  final bool hapticsEnabled;
  final bool opportunitiesLoading;
  final String? selectedSymbol;
  final String? selectedOpportunityId;
  final String? opportunitiesError;
  final DateTime? opportunitiesUpdatedAt;

  const CryptoState({
    required this.coins,
    required this.opportunities,
    required this.positions,
    required this.logs,
    required this.stats,
    required this.botStatus,
    required this.selectedExchange,
    required this.marketProvider,
    required this.selectedTimeframe,
    required this.scannerViewMode,
    required this.marketDataMode,
    required this.alertsEnabled,
    required this.hapticsEnabled,
    required this.opportunitiesLoading,
    this.selectedSymbol,
    this.selectedOpportunityId,
    this.opportunitiesError,
    this.opportunitiesUpdatedAt,
  });

  factory CryptoState.initial() => const CryptoState(
        coins: [],
        opportunities: [],
        positions: [],
        logs: [],
        stats: DailyStats(),
        botStatus: BotStatus.paused,
        selectedExchange: Exchange.all,
        marketProvider: CryptoDataProvider.binance,
        selectedTimeframe: Timeframe.m15,
        scannerViewMode: CryptoScannerViewMode.scanner,
        marketDataMode: MarketDataMode.simulator,
        alertsEnabled: true,
        hapticsEnabled: true,
        opportunitiesLoading: false,
      );

  CoinData? get selectedCoin {
    if (selectedSymbol == null || coins.isEmpty) return null;
    return coins.firstWhere(
      (c) => c.symbol == selectedSymbol,
      orElse: () => coins.first,
    );
  }

  CryptoOpportunity? get selectedOpportunity {
    if (selectedOpportunityId == null || opportunities.isEmpty) {
      return opportunities.isEmpty ? null : opportunities.first;
    }
    return opportunities.firstWhere(
      (opportunity) => opportunity.id == selectedOpportunityId,
      orElse: () => opportunities.first,
    );
  }

  List<CoinData> get signalCoins =>
      coins.where((c) => c.indicators.signal != SignalType.watch).toList();

  List<CoinData> get buySignals =>
      coins.where((c) => c.indicators.signal == SignalType.buy).toList();

  List<CoinData> get sellSignals =>
      coins.where((c) => c.indicators.signal == SignalType.sell).toList();

  List<CryptoOpportunity> get actionableOpportunities => opportunities
      .where((opportunity) => opportunity.score?.isActionable ?? false)
      .toList();

  double get totalUnrealizedPnL =>
      positions.fold<double>(0.0, (s, p) => s + p.unrealizedPnL);

  CryptoState copyWith({
    List<CoinData>? coins,
    List<CryptoOpportunity>? opportunities,
    List<Position>? positions,
    List<TradeLog>? logs,
    DailyStats? stats,
    BotStatus? botStatus,
    Exchange? selectedExchange,
    CryptoDataProvider? marketProvider,
    Timeframe? selectedTimeframe,
    CryptoScannerViewMode? scannerViewMode,
    MarketDataMode? marketDataMode,
    bool? alertsEnabled,
    bool? hapticsEnabled,
    bool? opportunitiesLoading,
    String? selectedSymbol,
    String? selectedOpportunityId,
    String? opportunitiesError,
    DateTime? opportunitiesUpdatedAt,
    bool clearSelectedSymbol = false,
    bool clearSelectedOpportunityId = false,
    bool clearOpportunitiesError = false,
  }) {
    return CryptoState(
      coins: coins ?? this.coins,
      opportunities: opportunities ?? this.opportunities,
      positions: positions ?? this.positions,
      logs: logs ?? this.logs,
      stats: stats ?? this.stats,
      botStatus: botStatus ?? this.botStatus,
      selectedExchange: selectedExchange ?? this.selectedExchange,
      marketProvider: marketProvider ?? this.marketProvider,
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
      scannerViewMode: scannerViewMode ?? this.scannerViewMode,
      marketDataMode: marketDataMode ?? this.marketDataMode,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      opportunitiesLoading: opportunitiesLoading ?? this.opportunitiesLoading,
      selectedSymbol:
          clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
      selectedOpportunityId: clearSelectedOpportunityId
          ? null
          : (selectedOpportunityId ?? this.selectedOpportunityId),
      opportunitiesError: clearOpportunitiesError
          ? null
          : (opportunitiesError ?? this.opportunitiesError),
      opportunitiesUpdatedAt:
          opportunitiesUpdatedAt ?? this.opportunitiesUpdatedAt,
    );
  }

  @override
  List<Object?> get props => [
        coins,
        opportunities,
        positions,
        logs,
        stats,
        botStatus,
        selectedExchange,
        marketProvider,
        selectedTimeframe,
        scannerViewMode,
        marketDataMode,
        alertsEnabled,
        hapticsEnabled,
        opportunitiesLoading,
        selectedSymbol,
        selectedOpportunityId,
        opportunitiesError,
        opportunitiesUpdatedAt,
      ];
}
