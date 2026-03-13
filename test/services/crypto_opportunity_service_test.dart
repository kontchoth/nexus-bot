import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/models/crypto_models.dart';
import 'package:nexusbot/services/crypto/coingecko_market_service.dart';
import 'package:nexusbot/services/crypto/crypto_opportunity_service.dart';

void main() {
  group('CryptoOpportunityService', () {
    test('scores, sorts, and caches CoinGecko opportunities', () async {
      final marketService = _FakeCoinGeckoMarketService([
        _opportunity(
          id: 'alpha',
          symbol: 'ALPHA',
          priceChange24h: 14,
          marketCap: 42000000,
          volume24h: 18000000,
        ),
        _opportunity(
          id: 'beta',
          symbol: 'BETA',
          priceChange24h: 4,
          marketCap: 900000000,
          volume24h: 90000000,
        ),
      ]);
      final service = CryptoOpportunityService(
        coinGeckoMarketService: marketService,
        cacheDuration: const Duration(minutes: 10),
      );

      final firstLoad = await service.loadOpportunities();
      final secondLoad = await service.loadOpportunities();

      expect(marketService.callCount, 1);
      expect(firstLoad.first.id, 'alpha');
      expect(firstLoad.first.score, isNotNull);
      expect(firstLoad.first.score!.grade, CryptoOpportunityGrade.strong);
      expect(secondLoad.map((item) => item.id), ['alpha', 'beta']);
    });

    test('applies scanner confirmation when matching live coins exist',
        () async {
      final marketService = _FakeCoinGeckoMarketService([
        _opportunity(
          id: 'solana',
          symbol: 'SOL',
          priceChange24h: 12,
          marketCap: 40000000,
          volume24h: 16000000,
        ),
      ]);
      final service = CryptoOpportunityService(
        coinGeckoMarketService: marketService,
      );

      final opportunities = await service.loadOpportunities(
        scannerCoins: [
          CoinData(
            symbol: 'SOL',
            name: 'Solana',
            price: 180,
            basePrice: 176,
            changePercent: 2.1,
            volume: 24000000,
            avgVolume: 18000000,
            priceHistory: const [170, 172, 175, 178, 180],
            indicators: const TechnicalIndicators(
              rsi: 51,
              macd: MACDTrend.bullish,
              volumeSpike: 1.8,
              bbSqueeze: false,
              signalStrength: 3,
            ),
            lastUpdated: DateTime(2026, 3, 12, 10),
          ),
        ],
        useScannerConfirmation: true,
      );

      final opportunity = opportunities.single;
      expect(opportunity.binanceListed, isTrue);
      expect(opportunity.sources, contains(CryptoOpportunitySource.binance));
      expect(
        opportunity.score!.positiveSignals.map((signal) => signal.kind),
        contains(CryptoOpportunitySignalKind.binanceConfirmation),
      );
    });
  });
}

class _FakeCoinGeckoMarketService extends CoinGeckoMarketService {
  _FakeCoinGeckoMarketService(this._markets);

  final List<CryptoOpportunity> _markets;
  int callCount = 0;

  @override
  Future<List<CryptoOpportunity>> fetchMarkets({int limit = 80}) async {
    callCount++;
    return List<CryptoOpportunity>.unmodifiable(_markets.take(limit));
  }
}

CryptoOpportunity _opportunity({
  required String id,
  required String symbol,
  required double priceChange24h,
  required double marketCap,
  required double volume24h,
}) {
  return CryptoOpportunity(
    id: id,
    symbol: symbol,
    name: symbol,
    priceUsd: 1.25,
    priceChange24h: priceChange24h,
    marketCap: marketCap,
    volume24h: volume24h,
    sources: const [CryptoOpportunitySource.coinGecko],
    lastUpdated: DateTime(2026, 3, 12, 10),
  );
}
