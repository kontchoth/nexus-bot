import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/models/crypto_models.dart';

void main() {
  group('CryptoOpportunity', () {
    test('computes volume to market cap ratio safely', () {
      final opportunity = CryptoOpportunity(
        id: 'sol-opportunity',
        symbol: 'SOL',
        name: 'Solana',
        priceUsd: 180,
        priceChange24h: 12,
        marketCap: 40000000,
        volume24h: 16000000,
        sources: const [CryptoOpportunitySource.coinGecko],
        lastUpdated: DateTime(2026, 3, 12, 9, 30),
      );

      expect(opportunity.volumeMarketCapRatio, 0.4);
      expect(opportunity.hasSource(CryptoOpportunitySource.coinGecko), isTrue);
      expect(
          opportunity.hasSource(CryptoOpportunitySource.dexScreener), isFalse);
    });

    test('returns zero ratio when market cap is missing', () {
      final opportunity = CryptoOpportunity(
        id: 'new-pair',
        symbol: 'NEWT',
        name: 'New Token',
        priceUsd: 0.02,
        priceChange24h: 40,
        volume24h: 250000,
        sources: const [CryptoOpportunitySource.dexScreener],
        lastUpdated: DateTime(2026, 3, 12, 9, 30),
      );

      expect(opportunity.volumeMarketCapRatio, 0);
    });
  });

  group('CryptoOpportunityScore', () {
    test('separates positive and risk signals', () {
      const score = CryptoOpportunityScore(
        value: 42,
        grade: CryptoOpportunityGrade.watch,
        signals: [
          CryptoOpportunitySignal(
            kind: CryptoOpportunitySignalKind.momentum24h,
            label: 'Momentum',
            scoreDelta: 20,
          ),
          CryptoOpportunitySignal(
            kind: CryptoOpportunitySignalKind.lowLiquidityRisk,
            label: 'Low liquidity',
            scoreDelta: -20,
            isRisk: true,
          ),
        ],
      );

      expect(score.isActionable, isTrue);
      expect(score.positiveSignals, hasLength(1));
      expect(score.riskSignals, hasLength(1));
    });
  });
}
