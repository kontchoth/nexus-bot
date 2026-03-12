part of 'spx_bloc.dart';

enum SpxDataMode { live, simulator }

enum SpxScannerStatus { active, paused }

enum SpxTermMode { exact, range }

class SpxTermFilter extends Equatable {
  final SpxTermMode mode;
  final int exactDte;
  final int minDte;
  final int maxDte;

  const SpxTermFilter({
    required this.mode,
    required this.exactDte,
    required this.minDte,
    required this.maxDte,
  });

  factory SpxTermFilter.initial() => const SpxTermFilter(
        mode: SpxTermMode.exact,
        exactDte: 7,
        minDte: 5,
        maxDte: 14,
      );

  SpxTermFilter copyWith({
    SpxTermMode? mode,
    int? exactDte,
    int? minDte,
    int? maxDte,
  }) {
    final next = SpxTermFilter(
      mode: mode ?? this.mode,
      exactDte: (exactDte ?? this.exactDte).clamp(0, 365),
      minDte: (minDte ?? this.minDte).clamp(0, 365),
      maxDte: (maxDte ?? this.maxDte).clamp(0, 365),
    );
    if (next.mode == SpxTermMode.range && next.minDte > next.maxDte) {
      return SpxTermFilter(
        mode: next.mode,
        exactDte: next.exactDte,
        minDte: next.maxDte,
        maxDte: next.maxDte,
      );
    }
    return next;
  }

  bool matchesDte(int dte) {
    if (mode == SpxTermMode.exact) return dte == exactDte;
    return dte >= minDte && dte <= maxDte;
  }

  @override
  List<Object?> get props => [mode, exactDte, minDte, maxDte];
}

class SpxState extends Equatable {
  /// Full options chain for the selected expiration.
  final List<OptionsContract> chain;

  /// Open SPX positions.
  final List<SpxPosition> positions;

  /// All available expiration dates (YYYY-MM-DD strings).
  final List<String> expirations;

  /// Currently displayed expiration.
  final String? selectedExpiration;

  /// Highlighted contract in the chain screen.
  final String? selectedSymbol;

  /// Whether auto-scanner is running.
  final SpxScannerStatus scannerStatus;

  /// Whether data is coming from Tradier (live) or the simulator.
  final SpxDataMode dataMode;

  /// Current SPX spot price.
  final double spotPrice;
  final bool isMarketOpen;
  final List<SpxSpotSample> intradaySpots;
  final List<SpxCandleSample> intradayCandles;
  final List<SpxIntradayMarker> intradayMarkers;
  final DateTime? sessionStartedAt;
  final double? sessionOpenPrice;
  final double? sessionHighPrice;
  final double? sessionLowPrice;

  /// Most-recent GEX snapshot.
  final GexData? gexData;

  /// Activity log (newest first).
  final List<TradeLog> logs;

  /// Tradier API token (stored in-memory; persisted via flutter_secure_storage).
  final String? tradierToken;
  final String tradierEnvironment;
  final String contractTargetingMode;
  final SpxTermFilter termFilter;
  final SpxStrategySnapshot? strategySnapshot;

  // ── Daily P&L ─────────────────────────────────────────────────────────────
  final double realizedPnL;
  final int totalTrades;
  final int winTrades;

  const SpxState({
    required this.chain,
    required this.positions,
    required this.expirations,
    required this.spotPrice,
    required this.isMarketOpen,
    required this.intradaySpots,
    required this.intradayCandles,
    required this.intradayMarkers,
    required this.logs,
    required this.scannerStatus,
    required this.dataMode,
    this.sessionStartedAt,
    this.sessionOpenPrice,
    this.sessionHighPrice,
    this.sessionLowPrice,
    this.selectedExpiration,
    this.selectedSymbol,
    this.gexData,
    this.tradierToken,
    this.tradierEnvironment = SpxTradierEnvironment.production,
    this.contractTargetingMode = SpxContractTargetingMode.deltaZone,
    this.strategySnapshot,
    this.termFilter = const SpxTermFilter(
      mode: SpxTermMode.exact,
      exactDte: 7,
      minDte: 5,
      maxDte: 14,
    ),
    this.realizedPnL = 0,
    this.totalTrades = 0,
    this.winTrades = 0,
  });

  factory SpxState.initial({
    String? tradierToken,
    String tradierEnvironment = SpxTradierEnvironment.production,
  }) =>
      SpxState(
        chain: const [],
        positions: const [],
        expirations: const [],
        spotPrice: 5750.0,
        isMarketOpen: false,
        intradaySpots: const [],
        intradayCandles: const [],
        intradayMarkers: const [],
        logs: const [],
        scannerStatus: SpxScannerStatus.paused,
        dataMode: SpxDataMode.simulator,
        tradierToken: tradierToken,
        tradierEnvironment: SpxTradierEnvironment.normalize(tradierEnvironment),
        contractTargetingMode: SpxContractTargetingMode.deltaZone,
        termFilter: const SpxTermFilter(
          mode: SpxTermMode.exact,
          exactDte: 7,
          minDte: 5,
          maxDte: 14,
        ),
      );

  // ── Computed ───────────────────────────────────────────────────────────────

  double get unrealizedPnL =>
      positions.fold(0.0, (s, p) => s + p.unrealizedPnL);

  double get winRate => totalTrades == 0 ? 0 : (winTrades / totalTrades) * 100;

  double? get impliedDailyExpectedMove {
    final anchor = sessionOpenPrice ?? spotPrice;
    if (anchor <= 0) return null;

    final sourceChain = filteredChain.isNotEmpty ? filteredChain : chain;
    if (sourceChain.isEmpty) return null;

    final nearestCall =
        _nearestExpectedMoveContract(sourceChain, anchor, OptionsSide.call);
    final nearestPut =
        _nearestExpectedMoveContract(sourceChain, anchor, OptionsSide.put);
    final ivs = [
      nearestCall?.impliedVolatility,
      nearestPut?.impliedVolatility,
    ].whereType<double>().where((iv) => iv > 0).toList();
    if (ivs.isEmpty) return null;

    final avgIv = ivs.reduce((a, b) => a + b) / ivs.length;
    return anchor * avgIv / math.sqrt(252);
  }

  bool get isTradierSandbox =>
      SpxTradierEnvironment.isSandbox(tradierEnvironment);

  String get tradierEnvironmentLabel =>
      SpxTradierEnvironment.label(tradierEnvironment).toLowerCase();

  /// Contracts matching the selected expiration, sorted by strike.
  List<OptionsContract> get filteredChain {
    if (selectedExpiration == null) return chain;
    return chain
        .where(
            (c) => c.expiry.toIso8601String().startsWith(selectedExpiration!))
        .toList()
      ..sort((a, b) => a.strike.compareTo(b.strike));
  }

  List<String> get termExpirations {
    final now = DateTime.now();
    final filtered = expirations.where((exp) {
      final expiry = DateTime.tryParse(exp);
      if (expiry == null) return false;
      final dte = expiry.difference(now).inDays.clamp(0, 365);
      return termFilter.matchesDte(dte);
    }).toList();
    if (filtered.isNotEmpty || expirations.isEmpty) return filtered;
    if (termFilter.mode == SpxTermMode.exact) return [];

    final target = ((termFilter.minDte + termFilter.maxDte) / 2).round();
    String? nearest;
    var nearestDistance = 9999;
    for (final exp in expirations) {
      final expiry = DateTime.tryParse(exp);
      if (expiry == null) continue;
      final dte = expiry.difference(now).inDays.clamp(0, 365);
      final distance = (dte - target).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = exp;
      }
    }
    return nearest == null ? [] : [nearest];
  }

  /// Top-scored buy signals for the scanner card.
  List<OptionsContract> get buySignals => orderSpxContractsForTargeting(
        chain.where((c) => c.signal == SpxSignalType.buy),
        spot: spotPrice,
        targetingMode: contractTargetingMode,
      );

  OptionsContract? get selectedContract {
    if (selectedSymbol == null) return null;
    try {
      return chain.firstWhere((c) => c.symbol == selectedSymbol);
    } catch (_) {
      return null;
    }
  }

  SpxState copyWith({
    List<OptionsContract>? chain,
    List<SpxPosition>? positions,
    List<String>? expirations,
    String? selectedExpiration,
    String? selectedSymbol,
    bool clearSelectedSymbol = false,
    SpxScannerStatus? scannerStatus,
    SpxDataMode? dataMode,
    double? spotPrice,
    bool? isMarketOpen,
    List<SpxSpotSample>? intradaySpots,
    List<SpxCandleSample>? intradayCandles,
    List<SpxIntradayMarker>? intradayMarkers,
    DateTime? sessionStartedAt,
    double? sessionOpenPrice,
    double? sessionHighPrice,
    double? sessionLowPrice,
    GexData? gexData,
    List<TradeLog>? logs,
    String? tradierToken,
    String? tradierEnvironment,
    String? contractTargetingMode,
    SpxStrategySnapshot? strategySnapshot,
    SpxTermFilter? termFilter,
    double? realizedPnL,
    int? totalTrades,
    int? winTrades,
  }) {
    return SpxState(
      chain: chain ?? this.chain,
      positions: positions ?? this.positions,
      expirations: expirations ?? this.expirations,
      spotPrice: spotPrice ?? this.spotPrice,
      isMarketOpen: isMarketOpen ?? this.isMarketOpen,
      intradaySpots: intradaySpots ?? this.intradaySpots,
      intradayCandles: intradayCandles ?? this.intradayCandles,
      intradayMarkers: intradayMarkers ?? this.intradayMarkers,
      logs: logs ?? this.logs,
      scannerStatus: scannerStatus ?? this.scannerStatus,
      dataMode: dataMode ?? this.dataMode,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      sessionOpenPrice: sessionOpenPrice ?? this.sessionOpenPrice,
      sessionHighPrice: sessionHighPrice ?? this.sessionHighPrice,
      sessionLowPrice: sessionLowPrice ?? this.sessionLowPrice,
      selectedExpiration: selectedExpiration ?? this.selectedExpiration,
      selectedSymbol:
          clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
      gexData: gexData ?? this.gexData,
      tradierToken: tradierToken ?? this.tradierToken,
      tradierEnvironment: SpxTradierEnvironment.normalize(
        tradierEnvironment ?? this.tradierEnvironment,
      ),
      contractTargetingMode: SpxContractTargetingMode.normalize(
        contractTargetingMode ?? this.contractTargetingMode,
      ),
      strategySnapshot: strategySnapshot ?? this.strategySnapshot,
      termFilter: termFilter ?? this.termFilter,
      realizedPnL: realizedPnL ?? this.realizedPnL,
      totalTrades: totalTrades ?? this.totalTrades,
      winTrades: winTrades ?? this.winTrades,
    );
  }

  @override
  List<Object?> get props => [
        chain,
        positions,
        expirations,
        selectedExpiration,
        selectedSymbol,
        scannerStatus,
        dataMode,
        spotPrice,
        isMarketOpen,
        intradaySpots,
        intradayCandles,
        intradayMarkers,
        sessionStartedAt,
        sessionOpenPrice,
        sessionHighPrice,
        sessionLowPrice,
        gexData,
        logs,
        tradierToken,
        tradierEnvironment,
        contractTargetingMode,
        strategySnapshot,
        termFilter,
        realizedPnL,
        totalTrades,
        winTrades,
      ];
}

OptionsContract? _nearestExpectedMoveContract(
  List<OptionsContract> contracts,
  double anchor,
  OptionsSide side,
) {
  final candidates = contracts.where((contract) {
    return contract.side == side && contract.impliedVolatility > 0;
  }).toList();
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final distanceCompare = a
        .strikeDistanceFromSpot(anchor)
        .compareTo(b.strikeDistanceFromSpot(anchor));
    if (distanceCompare != 0) return distanceCompare;

    final dteCompare = a.daysToExpiry.compareTo(b.daysToExpiry);
    if (dteCompare != 0) return dteCompare;

    return b.volume.compareTo(a.volume);
  });
  return candidates.first;
}
