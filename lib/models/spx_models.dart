import 'dart:math' as math;

import 'package:equatable/equatable.dart';
export 'common_models.dart';

// ── Quote data ────────────────────────────────────────────────────────────────

class SpxQuoteData {
  final double spot;
  final double dayLow;
  final double dayHigh;
  final double week52Low;
  final double week52High;
  final double bid;
  final double ask;
  final double change;
  final double changePercent;
  final int volume;
  final int avgVolume;
  final double beta;
  final double marketCap;
  final double peRatio;

  const SpxQuoteData({
    required this.spot,
    required this.dayLow,
    required this.dayHigh,
    required this.week52Low,
    required this.week52High,
    this.bid = 0,
    this.ask = 0,
    this.change = 0,
    this.changePercent = 0,
    this.volume = 0,
    this.avgVolume = 0,
    this.beta = 0,
    this.marketCap = 0,
    this.peRatio = 0,
  });

  static const empty = SpxQuoteData(
    spot: 0, dayLow: 0, dayHigh: 0, week52Low: 0, week52High: 0,
  );

  double get spread => ask > 0 && bid > 0 ? ask - bid : 0;
  double get volRatio => avgVolume > 0 ? volume / avgVolume : 0;
  bool get isUp => change >= 0;
  bool get isPopulated => spot > 0 && dayHigh > dayLow;
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum OptionsSide { call, put }

enum SpxSignalType { buy, sell, watch }

enum SpxContractMoneyness { itm, atm, otm }

enum SpxIntradayMarkerType { signal, entry, exit }

// ── Greeks ────────────────────────────────────────────────────────────────────

/// The four main option sensitivities used for risk and signal scoring.
class OptionsGreeks extends Equatable {
  /// Rate of change of option price per $1 move in the underlying.
  /// Calls: 0 to +1 · Puts: -1 to 0.
  final double delta;

  /// Rate of change of delta per $1 move in the underlying.
  /// Always positive. Higher near ATM and near expiry.
  final double gamma;

  /// Daily time decay in dollars (always negative for long options).
  final double theta;

  /// Sensitivity to a 1% move in implied volatility (in dollars).
  final double vega;

  const OptionsGreeks({
    required this.delta,
    required this.gamma,
    required this.theta,
    required this.vega,
  });

  OptionsGreeks copyWith({
    double? delta,
    double? gamma,
    double? theta,
    double? vega,
  }) {
    return OptionsGreeks(
      delta: delta ?? this.delta,
      gamma: gamma ?? this.gamma,
      theta: theta ?? this.theta,
      vega: vega ?? this.vega,
    );
  }

  @override
  List<Object?> get props => [delta, gamma, theta, vega];
}

// ── Options Contract ──────────────────────────────────────────────────────────

/// A single row in the SPX options chain.
class OptionsContract extends Equatable {
  static const double atmTolerancePoints = 5.0;

  /// OCC symbol, e.g. "SPX 241220C05800000"
  final String symbol;
  final OptionsSide side;
  final double strike;
  final DateTime expiry;

  /// Calendar days remaining until expiry.
  final int daysToExpiry;

  final double bid;
  final double ask;
  final double lastPrice;
  final int openInterest;
  final int volume;
  final OptionsGreeks greeks;

  /// Raw IV as a decimal, e.g. 0.18 = 18%.
  final double impliedVolatility;

  /// IV percentile vs trailing year history (0–100).
  /// < 25 = low IV (good for buying), > 75 = high IV (good for selling).
  final double ivRank;

  final SpxSignalType signal;
  final DateTime lastUpdated;

  const OptionsContract({
    required this.symbol,
    required this.side,
    required this.strike,
    required this.expiry,
    required this.daysToExpiry,
    required this.bid,
    required this.ask,
    required this.lastPrice,
    required this.openInterest,
    required this.volume,
    required this.greeks,
    required this.impliedVolatility,
    required this.ivRank,
    required this.signal,
    required this.lastUpdated,
  });

  /// Mid-point of bid/ask spread.
  double get midPrice => (bid + ask) / 2;

  double strikeDistanceFromSpot(double spot) => (strike - spot).abs();

  double signedMoneynessDistance(double spot) {
    return side == OptionsSide.call ? spot - strike : strike - spot;
  }

  bool isAtmForSpot(
    double spot, {
    double tolerancePoints = atmTolerancePoints,
  }) {
    return strikeDistanceFromSpot(spot) <= tolerancePoints;
  }

  SpxContractMoneyness moneynessForSpot(
    double spot, {
    double tolerancePoints = atmTolerancePoints,
  }) {
    if (isAtmForSpot(spot, tolerancePoints: tolerancePoints)) {
      return SpxContractMoneyness.atm;
    }
    return signedMoneynessDistance(spot) > 0
        ? SpxContractMoneyness.itm
        : SpxContractMoneyness.otm;
  }

  bool isNearItmForSpot(
    double spot, {
    int maxSteps = 1,
    double tolerancePoints = atmTolerancePoints,
  }) {
    final steps = maxSteps.clamp(1, 10);
    final maxDistance = tolerancePoints * (steps + 1);
    return moneynessForSpot(spot, tolerancePoints: tolerancePoints) ==
            SpxContractMoneyness.itm &&
        strikeDistanceFromSpot(spot) <= maxDistance;
  }

  bool isNearOtmForSpot(
    double spot, {
    int maxSteps = 1,
    double tolerancePoints = atmTolerancePoints,
  }) {
    final steps = maxSteps.clamp(1, 10);
    final maxDistance = tolerancePoints * (steps + 1);
    return moneynessForSpot(spot, tolerancePoints: tolerancePoints) ==
            SpxContractMoneyness.otm &&
        strikeDistanceFromSpot(spot) <= maxDistance;
  }

  double intrinsicValueAtSpot(double underlyingSpot) {
    final rawIntrinsic = side == OptionsSide.call
        ? underlyingSpot - strike
        : strike - underlyingSpot;
    return rawIntrinsic > 0 ? rawIntrinsic : 0.0;
  }

  double breakEvenSpot({
    double? premium,
  }) {
    final debit = premium ?? midPrice;
    return side == OptionsSide.call ? strike + debit : strike - debit;
  }

  double payoffAtExpiry(
    double underlyingSpot, {
    double? premium,
    int contracts = 1,
  }) {
    final debit = premium ?? midPrice;
    final pnlPerShare = intrinsicValueAtSpot(underlyingSpot) - debit;
    return pnlPerShare * contracts * 100;
  }

  /// Whether this contract is in the liquid, tradeable delta zone (0.20–0.45).
  bool get isTargetDelta =>
      greeks.delta.abs() >= 0.20 && greeks.delta.abs() <= 0.45;

  /// Flag contracts approaching expiry where risk spikes.
  bool get isDteWarning => daysToExpiry <= 7;

  OptionsContract copyWith({
    double? bid,
    double? ask,
    double? lastPrice,
    int? openInterest,
    int? volume,
    OptionsGreeks? greeks,
    double? impliedVolatility,
    double? ivRank,
    SpxSignalType? signal,
    int? daysToExpiry,
    DateTime? lastUpdated,
  }) {
    return OptionsContract(
      symbol: symbol,
      side: side,
      strike: strike,
      expiry: expiry,
      daysToExpiry: daysToExpiry ?? this.daysToExpiry,
      bid: bid ?? this.bid,
      ask: ask ?? this.ask,
      lastPrice: lastPrice ?? this.lastPrice,
      openInterest: openInterest ?? this.openInterest,
      volume: volume ?? this.volume,
      greeks: greeks ?? this.greeks,
      impliedVolatility: impliedVolatility ?? this.impliedVolatility,
      ivRank: ivRank ?? this.ivRank,
      signal: signal ?? this.signal,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  List<Object?> get props =>
      [symbol, bid, ask, greeks, impliedVolatility, daysToExpiry];
}

// ── SPX Position ──────────────────────────────────────────────────────────────

/// An open options position. Each contract controls 100 shares of the underlying.
class SpxPosition extends Equatable {
  final String id;
  final OptionsContract contract;

  /// Number of option contracts held (each = 100 underlying shares).
  final int contracts;

  /// Premium paid per contract at entry, in dollars (e.g. 12.40 = $1,240 per contract).
  final double entryPremium;

  /// Current market premium per contract (mid of bid/ask).
  final double currentPremium;

  final DateTime openedAt;

  /// Close if position loses more than this fraction of entry cost.
  final double stopLossPct;

  /// Close when position reaches this fraction of max profit.
  final double takeProfitPct;

  const SpxPosition({
    required this.id,
    required this.contract,
    required this.contracts,
    required this.entryPremium,
    required this.currentPremium,
    required this.openedAt,
    this.stopLossPct = 1.0, // 100% of premium (max loss for long options)
    this.takeProfitPct = 0.50, // Close at 50% of max profit (standard rule)
  });

  // ── P&L ───────────────────────────────────────────────────────────────────

  /// Total cost paid to enter (max loss for a long option).
  double get totalCost => entryPremium * contracts * 100;

  /// Current unrealized P&L in dollars.
  double get unrealizedPnL => (currentPremium - entryPremium) * contracts * 100;

  /// P&L as a percentage of entry cost.
  double get pnlPercent => entryPremium > 0
      ? ((currentPremium - entryPremium) / entryPremium) * 100
      : 0;

  bool get isProfit => unrealizedPnL >= 0;

  /// True when the position has hit its 50% profit target.
  bool get isTakeProfitHit => pnlPercent >= (takeProfitPct * 100);

  /// True when the position has lost the configured stop-loss fraction.
  bool get isStopLossHit => pnlPercent <= -(stopLossPct * 100);

  /// True when the underlying contract has expired.
  bool get isExpired => contract.daysToExpiry <= 0;

  /// DTE warning — should be closed before gamma risk spikes near expiry.
  bool get isDteWarning => contract.daysToExpiry <= 5;

  String get formattedPnL {
    final sign = unrealizedPnL >= 0 ? '+' : '';
    return '$sign\$${unrealizedPnL.toStringAsFixed(2)}';
  }

  SpxPosition copyWith({
    double? currentPremium,
    OptionsContract? contract,
    double? stopLossPct,
    double? takeProfitPct,
  }) {
    return SpxPosition(
      id: id,
      contract: contract ?? this.contract,
      contracts: contracts,
      entryPremium: entryPremium,
      currentPremium: currentPremium ?? this.currentPremium,
      openedAt: openedAt,
      stopLossPct: stopLossPct ?? this.stopLossPct,
      takeProfitPct: takeProfitPct ?? this.takeProfitPct,
    );
  }

  @override
  List<Object?> get props => [id, contract.symbol, currentPremium];
}

// ── GEX Data ──────────────────────────────────────────────────────────────────

/// Aggregate dealer gamma exposure snapshot.
///
/// Positive net GEX = dealers are net long gamma → they sell into rallies and
/// buy dips, suppressing volatility and pinning price near the gamma wall.
///
/// Negative net GEX = dealers are net short gamma → they chase moves,
/// amplifying directional trends and increasing volatility.
class GexData extends Equatable {
  /// Aggregate net GEX in $billions.
  final double netGex;

  /// Current SPX spot price at the time this snapshot was taken.
  final double spxSpotPrice;

  /// Per-strike GEX contribution in $millions.
  /// Positive = call-heavy (stabilizing), negative = put-heavy (destabilizing).
  final Map<double, double> gexByStrike;

  final DateTime lastUpdated;

  const GexData({
    required this.netGex,
    required this.spxSpotPrice,
    required this.gexByStrike,
    required this.lastUpdated,
  });

  /// The strike with the largest positive GEX — acts as a price magnet.
  double? get gammaWall {
    if (gexByStrike.isEmpty) return null;
    return gexByStrike.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// The strike below spot where dealer put-selling creates a support floor.
  double? get putWall {
    if (gexByStrike.isEmpty) return null;
    final belowSpot =
        gexByStrike.entries.where((e) => e.key < spxSpotPrice).toList();
    if (belowSpot.isEmpty) return null;
    return belowSpot.reduce((a, b) => a.value < b.value ? a : b).key;
  }

  /// Whether the market is in a stabilizing (positive) GEX regime.
  bool get isPositiveGex => netGex >= 0;

  @override
  List<Object?> get props => [netGex, spxSpotPrice, lastUpdated];
}

// ── SPX Signal ────────────────────────────────────────────────────────────────

/// A scored signal for a specific options contract.
class SpxSignal extends Equatable {
  final OptionsContract contract;

  /// Human-readable explanation of why this contract scored well.
  /// e.g. "High IV Rank (72) · Delta 0.32 · DTE 21 · Active volume"
  final String rationale;

  /// Confidence score 0–100. Signals with score ≥ 60 are shown in the scanner.
  final double confidenceScore;

  const SpxSignal({
    required this.contract,
    required this.rationale,
    required this.confidenceScore,
  });

  @override
  List<Object?> get props => [contract.symbol, confidenceScore];
}

class SpxSpotSample extends Equatable {
  final DateTime recordedAt;
  final double price;

  const SpxSpotSample({
    required this.recordedAt,
    required this.price,
  });

  @override
  List<Object?> get props => [recordedAt, price];
}

class SpxCandleSample extends Equatable {
  final DateTime bucketStart;
  final double open;
  final double high;
  final double low;
  final double close;
  final int sampleCount;

  const SpxCandleSample({
    required this.bucketStart,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.sampleCount = 1,
  });

  SpxCandleSample update(double price) {
    return SpxCandleSample(
      bucketStart: bucketStart,
      open: open,
      high: math.max(high, price),
      low: math.min(low, price),
      close: price,
      sampleCount: sampleCount + 1,
    );
  }

  @override
  List<Object?> get props => [bucketStart, open, high, low, close, sampleCount];
}

class SpxIntradayMarker extends Equatable {
  final DateTime timestamp;
  final double spotPrice;
  final SpxIntradayMarkerType type;
  final String label;
  final String symbol;
  final OptionsSide? side;

  const SpxIntradayMarker({
    required this.timestamp,
    required this.spotPrice,
    required this.type,
    required this.label,
    required this.symbol,
    this.side,
  });

  @override
  List<Object?> get props => [timestamp, spotPrice, type, label, symbol, side];
}

// ── Intraday Strategy Models ─────────────────────────────────────────────────

enum SpxDirection { up, down, neutral }

enum SpxStrategyActionType { goLong, goShort, wait }

extension SpxDirectionExt on SpxDirection {
  String get label {
    switch (this) {
      case SpxDirection.up:
        return 'Up';
      case SpxDirection.down:
        return 'Down';
      case SpxDirection.neutral:
        return 'Neutral';
    }
  }
}

extension SpxStrategyActionTypeExt on SpxStrategyActionType {
  String get label {
    switch (this) {
      case SpxStrategyActionType.goLong:
        return 'GO LONG';
      case SpxStrategyActionType.goShort:
        return 'GO SHORT';
      case SpxStrategyActionType.wait:
        return 'WAIT / REASSESS';
    }
  }
}

class SpxStrategySignal extends Equatable {
  final String key;
  final String label;
  final SpxDirection direction;
  final String detail;

  const SpxStrategySignal({
    required this.key,
    required this.label,
    required this.direction,
    required this.detail,
  });

  @override
  List<Object?> get props => [key, label, direction, detail];
}

class SpxStrategySnapshot extends Equatable {
  final SpxStrategyActionType action;
  final String reason;
  final bool significantGap;
  final double gapPercent;
  final int minutesFromSessionStart;
  final double? minute14High;
  final double? minute14Low;
  final SpxDirection dominantDirection;
  final SpxDirection dplDirection;
  final List<SpxStrategySignal> signals;
  final DateTime updatedAt;

  const SpxStrategySnapshot({
    required this.action,
    required this.reason,
    required this.significantGap,
    required this.gapPercent,
    required this.minutesFromSessionStart,
    required this.minute14High,
    required this.minute14Low,
    required this.dominantDirection,
    required this.dplDirection,
    required this.signals,
    required this.updatedAt,
  });

  int get upSignals =>
      signals.where((s) => s.direction == SpxDirection.up).length;

  int get downSignals =>
      signals.where((s) => s.direction == SpxDirection.down).length;

  int get neutralSignals =>
      signals.where((s) => s.direction == SpxDirection.neutral).length;

  bool get allSignalsAligned =>
      (upSignals == signals.length) || (downSignals == signals.length);

  double? get longOtmStrike {
    if (minute14Low == null) return null;
    return minute14Low! + 50;
  }

  double? get shortOtmStrike {
    if (minute14High == null) return null;
    return minute14High! - 50;
  }

  @override
  List<Object?> get props => [
        action,
        reason,
        significantGap,
        gapPercent,
        minutesFromSessionStart,
        minute14High,
        minute14Low,
        dominantDirection,
        dplDirection,
        signals,
        updatedAt,
      ];
}
