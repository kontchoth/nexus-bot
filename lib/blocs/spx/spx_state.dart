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

  /// Most-recent GEX snapshot.
  final GexData? gexData;

  /// Activity log (newest first).
  final List<TradeLog> logs;

  /// Tradier API token (stored in-memory; persisted via flutter_secure_storage).
  final String? tradierToken;
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
    required this.logs,
    required this.scannerStatus,
    required this.dataMode,
    this.selectedExpiration,
    this.selectedSymbol,
    this.gexData,
    this.tradierToken,
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

  factory SpxState.initial() => const SpxState(
        chain: [],
        positions: [],
        expirations: [],
        spotPrice: 5750.0,
        isMarketOpen: false,
        logs: [],
        scannerStatus: SpxScannerStatus.paused,
        dataMode: SpxDataMode.simulator,
        termFilter: SpxTermFilter(
          mode: SpxTermMode.exact,
          exactDte: 7,
          minDte: 5,
          maxDte: 14,
        ),
      );

  // ── Computed ───────────────────────────────────────────────────────────────

  double get unrealizedPnL =>
      positions.fold(0.0, (s, p) => s + p.unrealizedPnL);

  double get winRate =>
      totalTrades == 0 ? 0 : (winTrades / totalTrades) * 100;

  /// Contracts matching the selected expiration, sorted by strike.
  List<OptionsContract> get filteredChain {
    if (selectedExpiration == null) return chain;
    return chain
        .where((c) => c.expiry.toIso8601String().startsWith(selectedExpiration!))
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
  List<OptionsContract> get buySignals => chain
      .where((c) => c.signal == SpxSignalType.buy)
      .toList()
        ..sort((a, b) => a.greeks.delta.abs().compareTo(b.greeks.delta.abs()));

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
    GexData? gexData,
    List<TradeLog>? logs,
    String? tradierToken,
    SpxStrategySnapshot? strategySnapshot,
    SpxTermFilter? termFilter,
    double? realizedPnL,
    int? totalTrades,
    int? winTrades,
  }) {
    return SpxState(
      chain:               chain              ?? this.chain,
      positions:           positions          ?? this.positions,
      expirations:         expirations        ?? this.expirations,
      spotPrice:           spotPrice          ?? this.spotPrice,
      isMarketOpen:        isMarketOpen       ?? this.isMarketOpen,
      logs:                logs               ?? this.logs,
      scannerStatus:       scannerStatus      ?? this.scannerStatus,
      dataMode:            dataMode           ?? this.dataMode,
      selectedExpiration:  selectedExpiration ?? this.selectedExpiration,
      selectedSymbol:      clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
      gexData:             gexData            ?? this.gexData,
      tradierToken:        tradierToken       ?? this.tradierToken,
      strategySnapshot:    strategySnapshot   ?? this.strategySnapshot,
      termFilter:          termFilter         ?? this.termFilter,
      realizedPnL:         realizedPnL        ?? this.realizedPnL,
      totalTrades:         totalTrades        ?? this.totalTrades,
      winTrades:           winTrades          ?? this.winTrades,
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
        gexData,
        logs,
        tradierToken,
        strategySnapshot,
        termFilter,
        realizedPnL,
        totalTrades,
        winTrades,
      ];
}
