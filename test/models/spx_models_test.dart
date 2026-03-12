import 'package:flutter_test/flutter_test.dart';

import 'package:nexusbot/models/spx_models.dart';

void main() {
  group('OptionsContract moneyness helpers', () {
    const spot = 5750.0;

    test('classifies calls as ITM ATM and OTM', () {
      final itm = _buildContract(
        symbol: 'CALL-ITM',
        side: OptionsSide.call,
        strike: 5740,
      );
      final atm = _buildContract(
        symbol: 'CALL-ATM',
        side: OptionsSide.call,
        strike: 5750,
      );
      final otm = _buildContract(
        symbol: 'CALL-OTM',
        side: OptionsSide.call,
        strike: 5760,
      );

      expect(itm.moneynessForSpot(spot), SpxContractMoneyness.itm);
      expect(atm.moneynessForSpot(spot), SpxContractMoneyness.atm);
      expect(otm.moneynessForSpot(spot), SpxContractMoneyness.otm);
    });

    test('classifies puts as ITM ATM and OTM', () {
      final itm = _buildContract(
        symbol: 'PUT-ITM',
        side: OptionsSide.put,
        strike: 5760,
      );
      final atm = _buildContract(
        symbol: 'PUT-ATM',
        side: OptionsSide.put,
        strike: 5750,
      );
      final otm = _buildContract(
        symbol: 'PUT-OTM',
        side: OptionsSide.put,
        strike: 5740,
      );

      expect(itm.moneynessForSpot(spot), SpxContractMoneyness.itm);
      expect(atm.moneynessForSpot(spot), SpxContractMoneyness.atm);
      expect(otm.moneynessForSpot(spot), SpxContractMoneyness.otm);
    });

    test('detects shallow ITM and OTM contracts', () {
      final nearItm = _buildContract(
        symbol: 'CALL-NEAR-ITM',
        side: OptionsSide.call,
        strike: 5740,
      );
      final farItm = _buildContract(
        symbol: 'CALL-FAR-ITM',
        side: OptionsSide.call,
        strike: 5720,
      );
      final nearOtm = _buildContract(
        symbol: 'CALL-NEAR-OTM',
        side: OptionsSide.call,
        strike: 5760,
      );
      final farOtm = _buildContract(
        symbol: 'CALL-FAR-OTM',
        side: OptionsSide.call,
        strike: 5780,
      );

      expect(nearItm.isNearItmForSpot(spot), isTrue);
      expect(farItm.isNearItmForSpot(spot), isFalse);
      expect(nearOtm.isNearOtmForSpot(spot), isTrue);
      expect(farOtm.isNearOtmForSpot(spot), isFalse);
    });
  });

  group('OptionsContract payoff helpers', () {
    test('computes call break-even and expiry payoff', () {
      final contract = _buildContract(
        symbol: 'CALL-PAYOFF',
        side: OptionsSide.call,
        strike: 5750,
      );

      expect(contract.breakEvenSpot(premium: 10), 5760);
      expect(contract.payoffAtExpiry(5740, premium: 10), -1000);
      expect(contract.payoffAtExpiry(5775, premium: 10), 1500);
    });

    test('computes put break-even and expiry payoff', () {
      final contract = _buildContract(
        symbol: 'PUT-PAYOFF',
        side: OptionsSide.put,
        strike: 5750,
      );

      expect(contract.breakEvenSpot(premium: 12), 5738);
      expect(contract.payoffAtExpiry(5765, premium: 12), -1200);
      expect(contract.payoffAtExpiry(5710, premium: 12), 2800);
    });
  });
}

OptionsContract _buildContract({
  required String symbol,
  required OptionsSide side,
  required double strike,
}) {
  final now = DateTime(2026, 3, 12);
  return OptionsContract(
    symbol: symbol,
    side: side,
    strike: strike,
    expiry: now.add(const Duration(days: 7)),
    daysToExpiry: 7,
    bid: 10.0,
    ask: 10.4,
    lastPrice: 10.2,
    openInterest: 1000,
    volume: 250,
    greeks: const OptionsGreeks(
      delta: 0.33,
      gamma: 0.015,
      theta: -0.24,
      vega: 0.12,
    ),
    impliedVolatility: 0.18,
    ivRank: 28,
    signal: SpxSignalType.buy,
    lastUpdated: now,
  );
}
