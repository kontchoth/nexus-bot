import 'dart:math';
import '../../models/spx_models.dart';
import 'spx_greeks_calculator.dart';

/// Offline SPX options chain simulator.
///
/// Generates a synthetic but realistic SPX options chain using Black-Scholes
/// pricing with a volatility smile/skew that mimics real SPX behaviour:
///  - OTM puts carry higher IV than OTM calls (typical negative skew)
///  - ATM IV varies each call to [refreshChain] to simulate changing vol
///  - Open interest and volume are randomised within realistic SPX ranges
///  - Contracts are scored and given buy/sell/watch signals
///
/// Use this when the Tradier API is unavailable or outside market hours.
class SpxOptionsSimulator {
  static const double _syntheticSpot = 5750.0;

  // Volatility parameters
  static const double _minAtmIv = 0.13; // 13%
  static const double _maxAtmIv = 0.22; // 22%
  static const double _putSkew   = -0.30; // down-skew for puts (realistic)
  static const double _callSkew  =  0.05; // mild up-skew for calls

  // Chain geometry
  static const double _rangePercent = 0.06; // ±6% strikes from spot
  static const double _strikeStep   = 5.0;  // 5-point increments

  // Signal thresholds (0–5 scoring system)
  static const int _signalBuyThreshold  = 3;
  static const int _signalSellThreshold = 1; // sell = 1 or lower score on re-tick

  static final _rng = Random();

  // ── State ────────────────────────────────────────────────────────────────

  double _spot = _syntheticSpot;
  double _atmIv = 0.16;
  List<OptionsContract> _chain = [];
  DateTime _lastUpdated = DateTime.now();

  // ── Public API ───────────────────────────────────────────────────────────

  double get spot => _spot;

  /// Generate a fresh chain.  Call once on startup and on expiry roll.
  List<OptionsContract> refreshChain({
    DateTime? asOf,
    List<int> dteDays = const [7, 14, 21, 45],
  }) {
    _spot = _jitterSpot(_spot);
    _atmIv = _minAtmIv + _rng.nextDouble() * (_maxAtmIv - _minAtmIv);
    _lastUpdated = asOf ?? DateTime.now();

    final contracts = <OptionsContract>[];
    final strikeLow  = (_spot * (1 - _rangePercent) / _strikeStep).floor() * _strikeStep;
    final strikeHigh = (_spot * (1 + _rangePercent) / _strikeStep).ceil()  * _strikeStep;

    for (final dte in dteDays) {
      for (double strike = strikeLow; strike <= strikeHigh; strike += _strikeStep) {
        for (final side in OptionsSide.values) {
          final iv = _ivForStrike(strike, side);
          final greeks = SpxGreeksCalculator.calcGreeks(
            spot: _spot,
            strike: strike,
            daysToExpiry: dte,
            iv: iv,
            side: side,
          );
          final price = SpxGreeksCalculator.calcPrice(
            spot: _spot,
            strike: strike,
            daysToExpiry: dte,
            iv: iv,
            side: side,
          );
          // Skip near-zero-value contracts (very deep OTM)
          if (price < 0.05) continue;

          final oi     = _syntheticOI(strike, dte, side);
          final volume = _syntheticVolume(oi);
          final ivRank = SpxGreeksCalculator.calcIvRank(_atmIv, _historicalIvSample());
          final signal = _scoreSignal(greeks, ivRank, oi, volume, price);

          contracts.add(OptionsContract(
            symbol:            _symbol(strike, dte, side),
            side:              side,
            strike:            strike,
            expiry:            _lastUpdated.add(Duration(days: dte)),
            daysToExpiry:      dte,
            bid:               _bid(price),
            ask:               _ask(price),
            lastPrice:         price,
            openInterest:      oi,
            volume:            volume,
            greeks:            greeks,
            impliedVolatility: iv,
            ivRank:            ivRank,
            signal:            signal,
            lastUpdated:       _lastUpdated,
          ));
        }
      }
    }

    _chain = contracts;
    return _chain;
  }

  /// Lightweight tick: slightly vary prices on every timer tick.
  /// Returns updated contracts without regenerating strikes/IVs.
  List<OptionsContract> tick() {
    if (_chain.isEmpty) return refreshChain();

    // Small spot drift each tick
    _spot = _jitterSpot(_spot, maxPct: 0.0008);
    final now = DateTime.now();

    _chain = _chain.map((c) {
      // Re-price using delta approximation: ΔP ≈ delta × ΔS
      final spotDelta = _spot - c.greeks.delta * c.strike; // rough re-centre
      final _ = spotDelta; // suppress lint — we use SpxGreeksCalculator below
      final newPrice = SpxGreeksCalculator.calcPrice(
        spot: _spot,
        strike: c.strike,
        daysToExpiry: c.daysToExpiry,
        iv: c.impliedVolatility,
        side: c.side,
      );
      if (newPrice < 0.01) return c;

      final newGreeks = SpxGreeksCalculator.calcGreeks(
        spot: _spot,
        strike: c.strike,
        daysToExpiry: c.daysToExpiry,
        iv: c.impliedVolatility,
        side: c.side,
      );

      return c.copyWith(
        bid:         _bid(newPrice),
        ask:         _ask(newPrice),
        lastPrice:   newPrice,
        greeks:      newGreeks,
        lastUpdated: now,
      );
    }).toList();

    return _chain;
  }

  /// Simulate a spot price tick only (for position P&L updates).
  double tickSpot() {
    _spot = _jitterSpot(_spot, maxPct: 0.0005);
    return _spot;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Volatility smile: SPX puts carry higher IV (negative skew).
  double _ivForStrike(double strike, OptionsSide side) {
    final moneyness = (strike - _spot) / _spot; // negative for OTM puts
    final skew = side == OptionsSide.put ? _putSkew : _callSkew;
    return (_atmIv - skew * moneyness).clamp(0.05, 0.80);
  }

  double _jitterSpot(double base, {double maxPct = 0.003}) {
    final drift = ((_rng.nextDouble() * 2) - 1) * base * maxPct;
    return base + drift;
  }

  /// Realistic SPX OI: highest near ATM, falls off sharply OTM/ITM.
  int _syntheticOI(double strike, int dte, OptionsSide side) {
    final distPct = ((strike - _spot) / _spot).abs();
    final base = 5000 + _rng.nextInt(15000);
    final decay = exp(-distPct * 20); // ~0 by 5% away from spot
    final dteFactor = dte <= 7 ? 1.5 : (dte <= 21 ? 1.0 : 0.6);
    return (base * decay * dteFactor).round().clamp(100, 30000);
  }

  int _syntheticVolume(int oi) {
    return (oi * (0.02 + _rng.nextDouble() * 0.15)).round();
  }

  double _bid(double mid) {
    final spread = mid * (0.01 + _rng.nextDouble() * 0.02);
    return (mid - spread / 2).clamp(0.01, double.infinity);
  }

  double _ask(double mid) {
    final spread = mid * (0.01 + _rng.nextDouble() * 0.02);
    return mid + spread / 2;
  }

  /// Pseudo-historical IV sample for IV Rank calculation.
  List<double> _historicalIvSample() {
    return List.generate(252, (i) => 0.10 + _rng.nextDouble() * 0.20);
  }

  /// Score contract for trading signal (0–5).
  SpxSignalType _scoreSignal(
    OptionsGreeks greeks,
    double ivRank,
    int oi,
    int volume,
    double price,
  ) {
    var score = 0;
    if (ivRank > 50)               score += 2; // elevated IV → sell premium
    if (greeks.delta.abs() >= 0.20 &&
        greeks.delta.abs() <= 0.45) { score += 1; } // target delta zone
    if (volume > oi * 0.05)        score += 1; // active volume
    if (price > 0.50)              score += 1; // liquid, not penny options

    if (score >= _signalBuyThreshold)  return SpxSignalType.buy;
    if (score <= _signalSellThreshold) return SpxSignalType.sell;
    return SpxSignalType.watch;
  }

  String _symbol(double strike, int dte, OptionsSide side) {
    final sideChar = side == OptionsSide.call ? 'C' : 'P';
    final strikeStr = (strike * 1000).round().toString().padLeft(8, '0');
    final dtePart = dte.toString().padLeft(2, '0');
    return 'SPX 0$dtePart$sideChar$strikeStr';
  }
}
