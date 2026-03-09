import 'dart:math';
import '../models/models.dart';

class MarketSimulator {
  static final Random _rng = Random();

  static final List<Map<String, dynamic>> _coinDefs = [
    {'symbol': 'BTC', 'name': 'Bitcoin', 'base': 67000.0, 'vol': 0.008},
    {'symbol': 'ETH', 'name': 'Ethereum', 'base': 3450.0, 'vol': 0.012},
    {'symbol': 'SOL', 'name': 'Solana', 'base': 178.0, 'vol': 0.022},
    {'symbol': 'BNB', 'name': 'BNB', 'base': 598.0, 'vol': 0.015},
    {'symbol': 'XRP', 'name': 'XRP', 'base': 0.62, 'vol': 0.025},
    {'symbol': 'DOGE', 'name': 'Dogecoin', 'base': 0.172, 'vol': 0.035},
    {'symbol': 'ADA', 'name': 'Cardano', 'base': 0.48, 'vol': 0.028},
    {'symbol': 'AVAX', 'name': 'Avalanche', 'base': 39.5, 'vol': 0.030},
    {'symbol': 'LINK', 'name': 'Chainlink', 'base': 18.2, 'vol': 0.028},
    {'symbol': 'DOT', 'name': 'Polkadot', 'base': 8.9, 'vol': 0.032},
    {'symbol': 'MATIC', 'name': 'Polygon', 'base': 0.89, 'vol': 0.040},
    {'symbol': 'UNI', 'name': 'Uniswap', 'base': 11.4, 'vol': 0.035},
  ];

  /// Generates initial coin data
  static List<CoinData> generateInitialCoins() {
    return _coinDefs.map((def) {
      final prices = _genPriceHistory(def['base'] as double, def['vol'] as double);
      final price = prices.last;
      final avgVol = _rand(1e6, 1e8);
      final volume = avgVol * _rand(0.6, 3.0);
      final indicators = _calcIndicators(prices, volume, avgVol);

      return CoinData(
        symbol: def['symbol'] as String,
        name: def['name'] as String,
        price: price,
        basePrice: def['base'] as double,
        changePercent: ((price - (def['base'] as double)) / (def['base'] as double)) * 100,
        volume: volume,
        avgVolume: avgVol,
        priceHistory: prices,
        indicators: indicators,
        lastUpdated: DateTime.now(),
      );
    }).toList();
  }

  /// Ticks market prices
  static CoinData tick(CoinData coin, Map<String, dynamic> def) {
    final volatility = def['vol'] as double;
    final newPrice = coin.price * (1 + (_rng.nextDouble() - 0.495) * volatility * 0.4);
    final newPrices = [...coin.priceHistory.skip(1), newPrice];
    final volume = coin.avgVolume * _rand(0.5, 2.5);
    final indicators = _calcIndicators(newPrices, volume, coin.avgVolume);

    return coin.copyWith(
      price: newPrice,
      changePercent: ((newPrice - coin.basePrice) / coin.basePrice) * 100,
      volume: volume,
      priceHistory: newPrices,
      indicators: indicators,
      lastUpdated: DateTime.now(),
    );
  }

  static Map<String, dynamic> getDefFor(String symbol) =>
      _coinDefs.firstWhere((d) => d['symbol'] == symbol,
          orElse: () => {'symbol': symbol, 'vol': 0.02, 'base': 1.0});

  // ── Private helpers ─────────────────────────────────────────────────────────

  static List<double> _genPriceHistory(double base, double volatility,
      {int points = 60}) {
    final prices = <double>[base];
    for (int i = 1; i < points; i++) {
      final change = (_rng.nextDouble() - 0.48) * volatility * prices[i - 1];
      prices.add(max(prices[i - 1] + change, 0.001));
    }
    return prices;
  }

  static TechnicalIndicators _calcIndicators(
      List<double> prices, double volume, double avgVolume) {
    final rsi = _calcRSI(prices);
    final volSpike = volume / avgVolume;
    final trend = _calcTrend(prices);
    final macd = trend == 'bullish' ? MACDTrend.bullish : MACDTrend.bearish;
    final bbSqueeze = _calcBBSqueeze(prices);

    int signals = 0;
    if (volSpike > 1.5) signals++;
    if (rsi > 28 && rsi < 42) signals++;
    if (macd == MACDTrend.bullish) signals++;
    if (bbSqueeze) signals++;

    return TechnicalIndicators(
      rsi: rsi,
      macd: macd,
      volumeSpike: volSpike,
      bbSqueeze: bbSqueeze,
      signalStrength: signals,
    );
  }

  static double _calcRSI(List<double> prices, {int period = 14}) {
    if (prices.length < period + 1) return 50;
    double gains = 0, losses = 0;
    final start = prices.length - period;
    for (int i = start; i < prices.length; i++) {
      final diff = prices[i] - prices[i - 1];
      if (diff > 0) gains += diff;
      else losses -= diff;
    }
    final avgGain = gains / period;
    final avgLoss = losses / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  static String _calcTrend(List<double> prices) {
    final recent = prices.sublist(max(0, prices.length - 10));
    return recent.last > recent.first ? 'bullish' : 'bearish';
  }

  static bool _calcBBSqueeze(List<double> prices) {
    final recent = prices.sublist(max(0, prices.length - 10));
    final upper = recent.reduce(max);
    final lower = recent.reduce(min);
    return lower > 0 ? (upper - lower) / lower < 0.02 : false;
  }

  static double _rand(double min, double max) =>
      _rng.nextDouble() * (max - min) + min;
}
