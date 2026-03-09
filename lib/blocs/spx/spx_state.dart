part of 'spx_bloc.dart';

enum SpxDataMode { live, simulator }
enum SpxScannerStatus { active, paused }

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

  /// Most-recent GEX snapshot.
  final GexData? gexData;

  /// Activity log (newest first).
  final List<TradeLog> logs;

  /// Tradier API token (stored in-memory; persisted via flutter_secure_storage).
  final String? tradierToken;

  // ── Daily P&L ─────────────────────────────────────────────────────────────
  final double realizedPnL;
  final int totalTrades;
  final int winTrades;

  const SpxState({
    required this.chain,
    required this.positions,
    required this.expirations,
    required this.spotPrice,
    required this.logs,
    required this.scannerStatus,
    required this.dataMode,
    this.selectedExpiration,
    this.selectedSymbol,
    this.gexData,
    this.tradierToken,
    this.realizedPnL = 0,
    this.totalTrades = 0,
    this.winTrades = 0,
  });

  factory SpxState.initial() => const SpxState(
        chain: [],
        positions: [],
        expirations: [],
        spotPrice: 5750.0,
        logs: [],
        scannerStatus: SpxScannerStatus.paused,
        dataMode: SpxDataMode.simulator,
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
    GexData? gexData,
    List<TradeLog>? logs,
    String? tradierToken,
    double? realizedPnL,
    int? totalTrades,
    int? winTrades,
  }) {
    return SpxState(
      chain:               chain              ?? this.chain,
      positions:           positions          ?? this.positions,
      expirations:         expirations        ?? this.expirations,
      spotPrice:           spotPrice          ?? this.spotPrice,
      logs:                logs               ?? this.logs,
      scannerStatus:       scannerStatus      ?? this.scannerStatus,
      dataMode:            dataMode           ?? this.dataMode,
      selectedExpiration:  selectedExpiration ?? this.selectedExpiration,
      selectedSymbol:      clearSelectedSymbol ? null : (selectedSymbol ?? this.selectedSymbol),
      gexData:             gexData            ?? this.gexData,
      tradierToken:        tradierToken       ?? this.tradierToken,
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
        gexData,
        logs,
        tradierToken,
        realizedPnL,
        totalTrades,
        winTrades,
      ];
}
