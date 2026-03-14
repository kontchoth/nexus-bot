import 'package:flutter_test/flutter_test.dart';

import 'package:nexusbot/models/spx_models.dart';
import 'package:nexusbot/services/spx/spx_greeks_calculator.dart';

void main() {
  group('SpxGreeksCalculator.calcGex', () {
    test('offsets equal call and put exposure at the same strike', () {
      final asOf = DateTime(2026, 3, 14, 10);
      final strike = 5750.0;
      final chain = [
        _buildContract(
          symbol: 'CALL-ATM',
          side: OptionsSide.call,
          strike: strike,
          openInterest: 1500,
          expiry: DateTime(2026, 3, 21, 16),
        ),
        _buildContract(
          symbol: 'PUT-ATM',
          side: OptionsSide.put,
          strike: strike,
          openInterest: 1500,
          expiry: DateTime(2026, 3, 21, 16),
        ),
      ];

      final gex = SpxGreeksCalculator.calcGex(
        chain,
        5750.0,
        timestamp: asOf,
      );

      expect(gex.netGex.abs(), lessThan(1e-9));
      expect((gex.gexByStrike[strike] ?? 0).abs(), lessThan(1e-6));
    });

    test(
        'recomputes gamma from snapshot inputs instead of stale contract greek',
        () {
      final gex = SpxGreeksCalculator.calcGex(
        [
          _buildContract(
            symbol: 'CALL-LIVE-GAMMA',
            side: OptionsSide.call,
            strike: 5750,
            openInterest: 2000,
            expiry: DateTime(2026, 3, 21, 16),
            gamma: 0,
          ),
        ],
        5750.0,
        timestamp: DateTime(2026, 3, 14, 10),
      );

      expect(gex.netGex, greaterThan(0));
      expect(gex.gexByStrike[5750], isNotNull);
      expect(gex.gexByStrike[5750]!, greaterThan(0));
    });

    test('same ATM contract carries more GEX closer to expiry', () {
      final contract = _buildContract(
        symbol: 'CALL-ATM-TIME',
        side: OptionsSide.call,
        strike: 5750,
        openInterest: 3000,
        expiry: DateTime(2026, 3, 21, 16),
      );

      final far = SpxGreeksCalculator.calcGex(
        [contract],
        5750.0,
        timestamp: DateTime(2026, 3, 14, 10),
      );
      final near = SpxGreeksCalculator.calcGex(
        [contract],
        5750.0,
        timestamp: DateTime(2026, 3, 20, 15),
      );

      expect(near.netGex, greaterThan(far.netGex));
    });
  });
}

OptionsContract _buildContract({
  required String symbol,
  required OptionsSide side,
  required double strike,
  required int openInterest,
  required DateTime expiry,
  double gamma = 0.015,
}) {
  final lastUpdated = DateTime(2026, 3, 14, 9, 30);
  return OptionsContract(
    symbol: symbol,
    side: side,
    strike: strike,
    expiry: expiry,
    daysToExpiry: expiry.difference(lastUpdated).inDays,
    bid: 10.0,
    ask: 10.4,
    lastPrice: 10.2,
    openInterest: openInterest,
    volume: 250,
    greeks: OptionsGreeks(
      delta: side == OptionsSide.call ? 0.50 : -0.50,
      gamma: gamma,
      theta: -0.24,
      vega: 0.12,
    ),
    impliedVolatility: 0.18,
    ivRank: 28,
    signal: SpxSignalType.buy,
    lastUpdated: lastUpdated,
  );
}
