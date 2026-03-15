import 'dart:math';
import '../../models/spx_models.dart';

/// Static Black-Scholes engine for SPX options pricing and greeks.
///
/// All formulas assume European-style exercise (SPX options are European).
/// Theta is expressed as daily decay (divided by 365).
/// Vega is expressed per 1% move in IV (divided by 100).
class SpxGreeksCalculator {
  static const double _riskFreeRate = 0.05; // ~5% US risk-free rate
  static const double _contractMultiplier = 100.0;
  static const double _onePercentMove = 0.01;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Compute all four greeks for a contract.
  static OptionsGreeks calcGreeks({
    required double spot, // Current SPX price, e.g. 5750.0
    required double strike, // Option strike, e.g. 5800.0
    required int daysToExpiry, // Calendar days remaining
    required double iv, // Implied volatility as decimal, e.g. 0.18
    required OptionsSide side,
  }) {
    if (daysToExpiry <= 0 || iv <= 0 || spot <= 0) {
      return const OptionsGreeks(delta: 0, gamma: 0, theta: 0, vega: 0);
    }

    final T = daysToExpiry / 365.0;
    final d1 = _d1(spot, strike, T, iv);
    final d2 = d1 - iv * sqrt(T);

    final delta = _calcDelta(d1, d2, T, side);
    final gamma = _calcGamma(spot, d1, iv, T);
    final theta = _calcTheta(spot, strike, d1, d2, iv, T, side);
    final vega = _calcVega(spot, d1, T);

    return OptionsGreeks(
      delta: delta,
      gamma: gamma,
      theta: theta,
      vega: vega,
    );
  }

  /// Fair-value price for an option using Black-Scholes.
  static double calcPrice({
    required double spot,
    required double strike,
    required int daysToExpiry,
    required double iv,
    required OptionsSide side,
  }) {
    if (daysToExpiry <= 0 || iv <= 0 || spot <= 0) return 0;
    final T = daysToExpiry / 365.0;
    final d1 = _d1(spot, strike, T, iv);
    final d2 = d1 - iv * sqrt(T);
    const r = _riskFreeRate;

    if (side == OptionsSide.call) {
      return spot * _normCdf(d1) - strike * exp(-r * T) * _normCdf(d2);
    } else {
      return strike * exp(-r * T) * _normCdf(-d2) - spot * _normCdf(-d1);
    }
  }

  /// IV rank: where the current IV falls within a historical range (0–100).
  /// ivRank = 100 means current IV is the highest it's been in the period.
  /// ivRank < 25 → cheap options (buyers' market).
  /// ivRank > 75 → expensive options (sellers' market).
  static double calcIvRank(double currentIv, List<double> yearlyIvHistory) {
    if (yearlyIvHistory.isEmpty) return 50;
    final minIv = yearlyIvHistory.reduce(min);
    final maxIv = yearlyIvHistory.reduce(max);
    if (maxIv == minIv) return 50;
    return ((currentIv - minIv) / (maxIv - minIv) * 100).clamp(0, 100);
  }

  /// Net dealer Gamma Exposure in $billions for a 1% underlying move.
  ///
  /// Convention: calls contribute positive GEX and puts contribute negative
  /// GEX as a simplified proxy for customer-long / dealer-short positioning.
  ///
  /// Gamma is re-derived at the snapshot spot, IV, and remaining time so the
  /// estimate can move intraday even when open interest is static.
  ///
  /// Strike GEX = OI × gamma × 100 × spot² × 0.01
  /// Net GEX = Σ(call GEX) − Σ(put GEX)
  ///
  /// Positive net GEX → dealers long gamma (stabilizing).
  /// Negative net GEX → dealers short gamma (volatile / trending).
  static GexData calcGex(
    List<OptionsContract> chain,
    double spot, {
    DateTime? timestamp,
  }) {
    final asOf = timestamp ?? DateTime.now();
    final byStrike = <double, double>{};

    for (final contract in chain) {
      if (contract.openInterest <= 0 ||
          contract.impliedVolatility <= 0 ||
          spot <= 0) {
        continue;
      }

      final timeToExpiryYears = _timeToExpiryYearsForGex(contract, asOf);
      if (timeToExpiryYears <= 0) continue;

      final gamma = _calcGammaAtSnapshot(
        spot: spot,
        strike: contract.strike,
        timeToExpiryYears: timeToExpiryYears,
        iv: contract.impliedVolatility,
      );
      if (gamma <= 0) continue;

      final strikeGex = contract.openInterest *
          gamma *
          _contractMultiplier *
          spot *
          spot *
          _onePercentMove;

      final contribution =
          contract.side == OptionsSide.call ? strikeGex : -strikeGex;

      byStrike.update(
        contract.strike,
        (v) => v + contribution,
        ifAbsent: () => contribution,
      );
    }

    // Scale to $billions
    final netGex = byStrike.values.fold<double>(0, (s, v) => s + v) / 1e9;
    final scaledByStrike =
        byStrike.map((k, v) => MapEntry(k, v / 1e6)); // in $millions per strike

    return GexData(
      netGex: netGex,
      spxSpotPrice: spot,
      gexByStrike: scaledByStrike,
      lastUpdated: asOf,
    );
  }

  static double _calcGammaAtSnapshot({
    required double spot,
    required double strike,
    required double timeToExpiryYears,
    required double iv,
  }) {
    if (spot <= 0 || strike <= 0 || iv <= 0 || timeToExpiryYears <= 0) {
      return 0;
    }
    final d1 = _d1(spot, strike, timeToExpiryYears, iv);
    return _calcGamma(spot, d1, iv, timeToExpiryYears);
  }

  static double _timeToExpiryYearsForGex(
    OptionsContract contract,
    DateTime asOf,
  ) {
    var expiryMoment = contract.expiry;
    final hasNoExplicitTime = contract.expiry.hour == 0 &&
        contract.expiry.minute == 0 &&
        contract.expiry.second == 0 &&
        contract.expiry.millisecond == 0 &&
        contract.expiry.microsecond == 0;

    if (hasNoExplicitTime) {
      expiryMoment = DateTime(
        contract.expiry.year,
        contract.expiry.month,
        contract.expiry.day,
        16,
      );
    }

    final remainingMs = expiryMoment.difference(asOf).inMilliseconds;
    if (remainingMs > 0) {
      return remainingMs / Duration.millisecondsPerDay / 365.0;
    }
    if (contract.daysToExpiry > 0) {
      return contract.daysToExpiry / 365.0;
    }
    return 0;
  }

  // ── Black-Scholes internals ────────────────────────────────────────────────

  static double _d1(double S, double K, double T, double sigma) {
    const r = _riskFreeRate;
    return (log(S / K) + (r + sigma * sigma / 2) * T) / (sigma * sqrt(T));
  }

  static double _calcDelta(double d1, double d2, double T, OptionsSide side) {
    return side == OptionsSide.call ? _normCdf(d1) : _normCdf(d1) - 1;
  }

  static double _calcGamma(double S, double d1, double sigma, double T) {
    return _normPdf(d1) / (S * sigma * sqrt(T));
  }

  static double _calcTheta(
    double S,
    double K,
    double d1,
    double d2,
    double sigma,
    double T,
    OptionsSide side,
  ) {
    const r = _riskFreeRate;
    final common = -S * _normPdf(d1) * sigma / (2 * sqrt(T));

    if (side == OptionsSide.call) {
      return (common - r * K * exp(-r * T) * _normCdf(d2)) / 365;
    } else {
      return (common + r * K * exp(-r * T) * _normCdf(-d2)) / 365;
    }
  }

  /// Vega per 1% move in IV (divide by 100 since 1 vega = $1 per 1% IV change).
  static double _calcVega(double S, double d1, double T) {
    return S * _normPdf(d1) * sqrt(T) / 100;
  }

  // ── Normal distribution helpers ────────────────────────────────────────────

  /// Cumulative distribution function of the standard normal.
  /// Uses the Abramowitz & Stegun rational approximation (error < 7.5e-8).
  static double _normCdf(double x) {
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    final sign = x < 0 ? -1 : 1;
    final t = 1.0 / (1.0 + p * x.abs());
    final poly = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t;
    final y = 1.0 - poly * exp(-x * x);
    return 0.5 * (1.0 + sign * y);
  }

  /// Probability density function of the standard normal.
  static double _normPdf(double x) => exp(-0.5 * x * x) / sqrt(2 * pi);
}
