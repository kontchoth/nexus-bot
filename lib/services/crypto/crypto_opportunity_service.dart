import '../../models/crypto_models.dart';
import 'coingecko_market_service.dart';
import 'crypto_opportunity_signal_engine.dart';

class CryptoOpportunityService {
  CryptoOpportunityService({
    CoinGeckoMarketService? coinGeckoMarketService,
    CryptoOpportunitySignalEngine? signalEngine,
    Duration cacheDuration = const Duration(minutes: 4),
  })  : _coinGeckoMarketService =
            coinGeckoMarketService ?? CoinGeckoMarketService(),
        _signalEngine = signalEngine ?? const CryptoOpportunitySignalEngine(),
        _cacheDuration = cacheDuration;

  final CoinGeckoMarketService _coinGeckoMarketService;
  final CryptoOpportunitySignalEngine _signalEngine;
  final Duration _cacheDuration;

  List<CryptoOpportunity>? _cachedMarkets;
  DateTime? _cachedAt;

  Future<List<CryptoOpportunity>> loadOpportunities({
    bool forceRefresh = false,
    Iterable<CoinData> scannerCoins = const <CoinData>[],
    bool useScannerConfirmation = false,
  }) async {
    final markets = await _loadMarkets(forceRefresh: forceRefresh);
    final scannerBySymbol = <String, CoinData>{
      for (final coin in scannerCoins) coin.symbol.toUpperCase(): coin,
    };

    final scored = markets.map((market) {
      var enriched = market;
      if (useScannerConfirmation) {
        final scannerCoin = scannerBySymbol[market.symbol.toUpperCase()];
        if (scannerCoin != null) {
          enriched = market.copyWith(
            binanceListed: true,
            rsi: scannerCoin.indicators.rsi,
            macdTrend: scannerCoin.indicators.macd,
            sources: _mergeSources(
              market.sources,
              CryptoOpportunitySource.binance,
            ),
          );
        }
      }
      return _signalEngine.score(enriched);
    }).toList()
      ..sort(_compareByScore);

    return List<CryptoOpportunity>.unmodifiable(scored);
  }

  Future<List<CryptoOpportunity>> _loadMarkets({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh &&
        _cachedMarkets != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cachedMarkets!;
    }

    final markets = await _coinGeckoMarketService.fetchMarkets();
    _cachedMarkets = List<CryptoOpportunity>.unmodifiable(markets);
    _cachedAt = DateTime.now();
    return _cachedMarkets!;
  }

  List<CryptoOpportunitySource> _mergeSources(
    List<CryptoOpportunitySource> sources,
    CryptoOpportunitySource source,
  ) {
    if (sources.contains(source)) return sources;
    return List<CryptoOpportunitySource>.unmodifiable([...sources, source]);
  }

  int _compareByScore(CryptoOpportunity a, CryptoOpportunity b) {
    final scoreDiff = (b.score?.value ?? 0).compareTo(a.score?.value ?? 0);
    if (scoreDiff != 0) return scoreDiff;

    final changeDiff = b.priceChange24h.compareTo(a.priceChange24h);
    if (changeDiff != 0) return changeDiff;

    final volumeDiff = (b.volume24h ?? 0).compareTo(a.volume24h ?? 0);
    if (volumeDiff != 0) return volumeDiff;

    return a.symbol.compareTo(b.symbol);
  }
}
