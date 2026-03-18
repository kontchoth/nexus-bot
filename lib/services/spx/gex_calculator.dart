import '../../models/gex_stream_models.dart';
import '../../models/spx_models.dart';

/// Intermediate result from a single chain computation.
class GexSnapshot {
  final double netGex;
  final double netIv;
  final int callVol;
  final int putVol;
  final GexLevels levels;
  final List<GexStrikeBar> strikeBars;

  const GexSnapshot({
    required this.netGex,
    required this.netIv,
    required this.callVol,
    required this.putVol,
    required this.levels,
    required this.strikeBars,
  });
}

/// Pure, stateless GEX math.
///
/// Dollar-gamma formula per contract:
///   dollarGamma = gamma × OI × 100 × spot² × 0.01
///
/// The ×100 accounts for 100 shares per contract.
/// The ×0.01 converts from per-point to per-1%-move exposure.
/// Net GEX = Σ callDollarGamma − Σ putDollarGamma (reported in millions).
class GexCalculator {
  const GexCalculator._();

  static GexSnapshot compute(List<OptionsContract> chain, double spot) {
    if (chain.isEmpty || spot <= 0) {
      return const GexSnapshot(
        netGex: 0,
        netIv: 0,
        callVol: 0,
        putVol: 0,
        levels: GexLevels.empty,
        strikeBars: [],
      );
    }

    // Aggregate by strike for level computation
    final strikeMap = <double, _StrikeData>{};
    double totalIvWeighted = 0;
    double totalOi = 0;
    int callVol = 0;
    int putVol = 0;

    for (final c in chain) {
      final gamma = c.greeks.gamma.abs();
      final oi = c.openInterest;
      final vol = c.volume;
      final dollarGamma = gamma * oi * 100 * spot * spot * 0.01;

      final agg = strikeMap.putIfAbsent(c.strike, () => _StrikeData());

      if (c.side == OptionsSide.call) {
        agg.callGex += dollarGamma;
        agg.callOi  += oi;
        agg.callVol += vol;
        callVol += vol;
      } else {
        agg.putGex += dollarGamma;
        agg.putOi  += oi;
        agg.putVol += vol;
        putVol += vol;
      }

      if (oi > 0) {
        totalIvWeighted += c.impliedVolatility * oi;
        totalOi += oi;
      }
    }

    // Net GEX across all strikes, in millions
    double netGex = 0;
    for (final agg in strikeMap.values) {
      netGex += agg.callGex - agg.putGex;
    }
    netGex /= 1e6;

    final netIv = totalOi > 0 ? totalIvWeighted / totalOi : 0.0;
    final levels = _computeLevels(strikeMap, spot);

    // Build sorted per-strike bars with cumulative GEX for the chart.
    final sortedStrikes = strikeMap.keys.toList()..sort();
    double cumulative = 0;
    final strikeBars = <GexStrikeBar>[];
    for (final strike in sortedStrikes) {
      final d = strikeMap[strike]!;
      final net = d.callGex - d.putGex;
      cumulative += net;
      strikeBars.add(GexStrikeBar(
        strike: strike,
        netGexRaw: net,
        callGexRaw: d.callGex,
        putGexRaw: d.putGex,
        cumulativeGexB: cumulative / 1e9,
        callOi: d.callOi,
        putOi: d.putOi,
        callVol: d.callVol,
        putVol: d.putVol,
      ));
    }

    return GexSnapshot(
      netGex: netGex,
      netIv: netIv,
      callVol: callVol,
      putVol: putVol,
      levels: levels,
      strikeBars: strikeBars,
    );
  }

  static GexLevels _computeLevels(
    Map<double, _StrikeData> strikeMap,
    double spot,
  ) {
    if (strikeMap.isEmpty) return GexLevels.empty;

    final strikes = strikeMap.keys.toList()..sort();

    double maxGammaStrike = spot;
    double maxTotalGex = 0;
    double minGammaStrike = spot;
    double minNetGex = 0;
    double zeroGammaStrike = spot;
    bool foundZero = false;

    double cumulative = 0;
    double prevCumulative = 0;

    for (final strike in strikes) {
      final agg = strikeMap[strike]!;
      final net = agg.callGex - agg.putGex;
      final total = agg.callGex + agg.putGex;

      if (total > maxTotalGex) {
        maxTotalGex = total;
        maxGammaStrike = strike;
      }

      if (net < minNetGex) {
        minNetGex = net;
        minGammaStrike = strike;
      }

      prevCumulative = cumulative;
      cumulative += net;

      if (!foundZero && prevCumulative != 0 &&
          prevCumulative.sign != cumulative.sign) {
        zeroGammaStrike = strike;
        foundZero = true;
      }
    }

    return GexLevels(
      maxGamma: maxGammaStrike,
      zeroGamma: foundZero ? zeroGammaStrike : spot,
      minGamma: minGammaStrike,
    );
  }
}

class _StrikeData {
  double callGex = 0;
  double putGex  = 0;
  int    callOi  = 0;
  int    putOi   = 0;
  int    callVol = 0;
  int    putVol  = 0;
}
