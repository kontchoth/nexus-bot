import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/models/crypto_models.dart';
import 'package:nexusbot/services/crypto/crypto_opportunity_signal_engine.dart';

void main() {
  group('CryptoOpportunitySignalEngine', () {
    const engine = CryptoOpportunitySignalEngine();

    test('scores a strong high-momentum low-cap opportunity', () {
      final opportunity = CryptoOpportunity(
        id: 'arb-1',
        symbol: 'ARB',
        name: 'Arbitrum',
        priceUsd: 1.24,
        priceChange24h: 18.4,
        marketCap: 42000000,
        volume24h: 18000000,
        volumeChange24h: 145,
        liquidityUsd: 210000,
        pairAgeHours: 18,
        isDex: true,
        binanceListed: true,
        rsi: 53,
        macdTrend: MACDTrend.bullish,
        sources: const [
          CryptoOpportunitySource.coinGecko,
          CryptoOpportunitySource.dexScreener,
          CryptoOpportunitySource.binance,
        ],
        lastUpdated: DateTime(2026, 3, 12, 10, 0),
      );

      final score = engine.analyze(opportunity);

      expect(score.value, 100);
      expect(score.grade, CryptoOpportunityGrade.elite);
      expect(
          score.positiveSignals.map((s) => s.kind),
          containsAll([
            CryptoOpportunitySignalKind.volumeMarketCap,
            CryptoOpportunitySignalKind.momentum24h,
            CryptoOpportunitySignalKind.volumeSpike24h,
            CryptoOpportunitySignalKind.lowCap,
            CryptoOpportunitySignalKind.freshDexLiquidity,
            CryptoOpportunitySignalKind.binanceConfirmation,
          ]));
      expect(score.riskSignals, isEmpty);
    });

    test('detects accumulation but penalizes thin unconfirmed setups', () {
      final opportunity = CryptoOpportunity(
        id: 'thin-1',
        symbol: 'THIN',
        name: 'Thin Token',
        priceUsd: 0.04,
        priceChange24h: -8,
        volume24h: 120000,
        volumeChange24h: 80,
        liquidityUsd: 12000,
        isDex: true,
        binanceListed: false,
        sources: const [CryptoOpportunitySource.dexScreener],
        lastUpdated: DateTime(2026, 3, 12, 10, 0),
      );

      final score = engine.analyze(opportunity);

      expect(score.value, 0);
      expect(score.grade, CryptoOpportunityGrade.weak);
      expect(score.positiveSignals.map((s) => s.kind),
          contains(CryptoOpportunitySignalKind.accumulation));
      expect(
          score.riskSignals.map((s) => s.kind),
          containsAll([
            CryptoOpportunitySignalKind.lowLiquidityRisk,
            CryptoOpportunitySignalKind.missingMarketCapRisk,
            CryptoOpportunitySignalKind.noCexConfirmationRisk,
          ]));
    });

    test('attaches score to an opportunity via score()', () {
      final opportunity = CryptoOpportunity(
        id: 'link-1',
        symbol: 'LINK',
        name: 'Chainlink',
        priceUsd: 22,
        priceChange24h: 11,
        marketCap: 9000000000,
        volume24h: 1800000000,
        volumeChange24h: 110,
        liquidityUsd: 500000,
        binanceListed: true,
        rsi: 49,
        macdTrend: MACDTrend.bullish,
        sources: const [
          CryptoOpportunitySource.coinGecko,
          CryptoOpportunitySource.binance,
        ],
        lastUpdated: DateTime(2026, 3, 12, 10, 0),
      );

      final scored = engine.score(opportunity);

      expect(scored.score, isNotNull);
      expect(scored.score!.isActionable, isTrue);
      expect(scored.score!.grade, CryptoOpportunityGrade.strong);
    });
  });
}
