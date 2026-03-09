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
    if (avgGain == 0 && avgLoss == 0) return 50;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  // Exponential Moving Average over a price series.
  static double _ema(List<double> prices, int period) {
    if (prices.isEmpty) return 0;
    final k = 2.0 / (period + 1);
    double ema = prices.first;
    for (int i = 1; i < prices.length; i++) {
      ema = prices[i] * k + ema * (1 - k);
    }
    return ema;
  }

  // Returns 'bullish' when MACD line > signal line, 'bearish' otherwise.
  // Falls back to simple first-vs-last comparison if fewer than 26 candles.
  static String _calcTrend(List<double> prices) {
    if (prices.length < 26) {
      return prices.last > prices.first ? 'bullish' : 'bearish';
    }
    final window = prices.sublist(max(0, prices.length - 35));
    final macdLine = <double>[];
    for (int i = 25; i < window.length; i++) {
      final slice = window.sublist(0, i + 1);
      macdLine.add(_ema(slice, 12) - _ema(slice, 26));
    }
    if (macdLine.length < 2) {
      return macdLine.isNotEmpty && macdLine.last > 0 ? 'bullish' : 'bearish';
    }
    final signalLine = _ema(macdLine, min(9, macdLine.length));
    return macdLine.last > signalLine ? 'bullish' : 'bearish';
  }

  // Squeeze = BB bandwidth (upper - lower) / middle < threshold.
  // Standard params: 20-period SMA, 2 standard deviations, 5% bandwidth threshold.
  static bool _calcBBSqueeze(List<double> prices, {int period = 20, double numStd = 2.0, double threshold = 0.05}) {
    if (prices.length < period) return false;
    final recent = prices.sublist(prices.length - period);
    final mean = recent.reduce((a, b) => a + b) / period;
    final variance = recent.map((p) => (p - mean) * (p - mean)).reduce((a, b) => a + b) / period;
    final std = sqrt(variance);
    final upper = mean + numStd * std;
    final lower = mean - numStd * std;
    if (mean == 0) return false;
    return (upper - lower) / mean < threshold;
  }

  static double _rand(double min, double max) =>
      _rng.nextDouble() * (max - min) + min;
}
