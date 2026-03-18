import 'package:equatable/equatable.dart';

// ── Per-strike GEX bar ────────────────────────────────────────────────────────

/// One bar in the Gamma Exposure by Strike cross-section chart.
/// Computed fresh each options-chain poll and passed through the BLoC.
class GexStrikeBar {
  final double strike;

  /// Net GEX at this strike in raw dollars (callGex − putGex).
  /// Positive = call-gamma dominated (blue bar), negative = put-gamma (orange).
  final double netGexRaw;

  /// Raw call-gamma contribution at this strike (always >= 0).
  /// Used by the Split GEX chart mode to draw call bars above the zero line.
  final double callGexRaw;

  /// Raw put-gamma contribution at this strike (always >= 0, drawn downward).
  /// Used by the Split GEX chart mode to draw put bars below the zero line.
  final double putGexRaw;

  /// Running cumulative net GEX (low → this strike), in billions.
  /// Used for the secondary y-axis line overlay.
  final double cumulativeGexB;

  // ── Tooltip fields ─────────────────────────────────────────────────────────
  final int callOi;
  final int putOi;
  final int callVol;
  final int putVol;

  const GexStrikeBar({
    required this.strike,
    required this.netGexRaw,
    required this.callGexRaw,
    required this.putGexRaw,
    required this.cumulativeGexB,
    required this.callOi,
    required this.putOi,
    required this.callVol,
    required this.putVol,
  });
}

// ── One intraday time-series sample for the live GEX stream chart.
class GexStreamPoint extends Equatable {
  final DateTime time;

  /// SPY/SPX spot price.
  final double price;

  /// Net dollar-gamma exposure in millions.
  /// Positive = call-heavy (dealers long gamma), negative = put-heavy.
  final double netGex;

  /// Cumulative net flow: running sum of (callVol − putVol) per bar.
  final double netFlow;

  /// Open-interest-weighted average implied volatility across the chain.
  final double netIv;

  /// Raw call volume for this bar.
  final int callVol;

  /// Raw put volume for this bar.
  final int putVol;

  /// Net GEX normalised to 0..1 relative to the session high/low.
  final double gexRatio;

  /// Call-volume proportion: callVol / (callVol + putVol), 0..1.
  final double flowRatio;

  /// IV normalised to 0..1 relative to the session high/low.
  final double ivRatio;

  const GexStreamPoint({
    required this.time,
    required this.price,
    required this.netGex,
    required this.netFlow,
    required this.netIv,
    required this.callVol,
    required this.putVol,
    required this.gexRatio,
    required this.flowRatio,
    required this.ivRatio,
  });

  GexStreamPoint copyWith({
    double? gexRatio,
    double? flowRatio,
    double? ivRatio,
  }) {
    return GexStreamPoint(
      time: time,
      price: price,
      netGex: netGex,
      netFlow: netFlow,
      netIv: netIv,
      callVol: callVol,
      putVol: putVol,
      gexRatio: gexRatio ?? this.gexRatio,
      flowRatio: flowRatio ?? this.flowRatio,
      ivRatio: ivRatio ?? this.ivRatio,
    );
  }

  @override
  List<Object?> get props => [
        time,
        price,
        netGex,
        netFlow,
        netIv,
        callVol,
        putVol,
        gexRatio,
        flowRatio,
        ivRatio,
      ];
}

/// Key gamma-exposure strike price levels derived from the options chain.
class GexLevels extends Equatable {
  /// Strike with the highest total (call + put) gamma × OI notional.
  final double maxGamma;

  /// Strike where cumulative net GEX crosses zero (the "gamma flip" level).
  final double zeroGamma;

  /// Strike with the most negative net GEX.
  final double minGamma;

  const GexLevels({
    required this.maxGamma,
    required this.zeroGamma,
    required this.minGamma,
  });

  static const empty = GexLevels(maxGamma: 0, zeroGamma: 0, minGamma: 0);

  bool get isPopulated => maxGamma != 0 || zeroGamma != 0 || minGamma != 0;

  @override
  List<Object?> get props => [maxGamma, zeroGamma, minGamma];
}
