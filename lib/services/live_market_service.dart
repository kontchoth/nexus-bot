import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/models.dart';

class LiveMarketService {
  LiveMarketService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.binance.us',
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );

  final Dio _dio;
  Set<String>? _supportedAssets;

  static const List<Map<String, String>> _coinDefs = [
    {'symbol': 'BTC', 'name': 'Bitcoin'},
    {'symbol': 'ETH', 'name': 'Ethereum'},
    {'symbol': 'SOL', 'name': 'Solana'},
    {'symbol': 'BNB', 'name': 'BNB'},
    {'symbol': 'XRP', 'name': 'XRP'},
    {'symbol': 'DOGE', 'name': 'Dogecoin'},
    {'symbol': 'ADA', 'name': 'Cardano'},
    {'symbol': 'AVAX', 'name': 'Avalanche'},
    {'symbol': 'LINK', 'name': 'Chainlink'},
    {'symbol': 'DOT', 'name': 'Polkadot'},
    {'symbol': 'MATIC', 'name': 'Polygon'},
    {'symbol': 'UNI', 'name': 'Uniswap'},
  ];

  List<String> get symbols => _coinDefs.map((e) => e['symbol']!).toList();

  Future<List<CoinData>> fetchInitialCoins(Timeframe timeframe) async {
    final supported = await _fetchSupportedAssets(symbols);
    final tickers = await _fetch24hTickers(supported);
    final interval = _intervalFor(timeframe);
    final now = DateTime.now();

    final result = <CoinData>[];
    for (final def in _coinDefs) {
      final symbol = def['symbol']!;
      final name = def['name']!;
      if (!supported.contains(symbol)) continue;
      final ticker = tickers[symbol];
      if (ticker == null) continue;

      final pair = '${symbol}USDT';
      final prices = await _fetchPriceHistory(pair, interval);
      final price = _toDouble(ticker['lastPrice']) ?? prices.last;
      final changePercent = _toDouble(ticker['priceChangePercent']) ?? 0.0;
      final volume = _toDouble(ticker['quoteVolume']) ?? 0.0;
      // Divide 24h total volume by candle count to get a per-candle baseline.
      // This ensures volumeSpike (volume / avgVolume) reflects real spikes
      // rather than always returning 1.0 when both values equal the 24h total.
      final avgVolume = max(volume / (prices.isNotEmpty ? prices.length : 60), 1.0);
      final basePrice = changePercent == -100
          ? price
          : price / (1 + (changePercent / 100));
      final indicators = _calcIndicators(prices, volume, avgVolume);

      result.add(
        CoinData(
          symbol: symbol,
          name: name,
          price: price,
          basePrice: basePrice.isFinite ? basePrice : price,
          changePercent: changePercent,
          volume: volume,
          avgVolume: avgVolume,
          priceHistory: prices,
          indicators: indicators,
          lastUpdated: now,
        ),
      );
    }

    if (result.isEmpty) {
      throw StateError('No live market data returned');
    }
    return result;
  }

  Future<List<CoinData>> tickCoins(
    List<CoinData> currentCoins,
  ) async {
    if (currentCoins.isEmpty) return currentCoins;

    final tickers =
        await _fetch24hTickers(currentCoins.map((c) => c.symbol).toList());
    final now = DateTime.now();
    final updated = <CoinData>[];

    for (final coin in currentCoins) {
      final ticker = tickers[coin.symbol];
      if (ticker == null) {
        updated.add(coin.copyWith(lastUpdated: now));
        continue;
      }

      final price = _toDouble(ticker['lastPrice']) ?? coin.price;
      final changePercent =
          _toDouble(ticker['priceChangePercent']) ?? coin.changePercent;
      final volume = _toDouble(ticker['quoteVolume']) ?? coin.volume;
      final newHistory = [...coin.priceHistory.skip(1), price];
      final indicators = _calcIndicators(newHistory, volume, coin.avgVolume);

      updated.add(
        coin.copyWith(
          price: price,
          changePercent: changePercent,
          volume: volume,
          priceHistory: newHistory,
          indicators: indicators,
          lastUpdated: now,
        ),
      );
    }

    return updated;
  }

  Future<Map<String, Map<String, dynamic>>> _fetch24hTickers(
    List<String> assetSymbols,
  ) async {
    if (assetSymbols.isEmpty) return {};
    final pairSymbols = assetSymbols.map((s) => '${s.toUpperCase()}USDT').toList();
    final symbolsParam = jsonEncode(pairSymbols);
    final response = await _dio.get(
      '/api/v3/ticker/24hr',
      queryParameters: {'symbols': symbolsParam},
    );

    final data = response.data;
    if (data is! List) {
      throw StateError('Unexpected ticker response format');
    }

    final map = <String, Map<String, dynamic>>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final symbolPair = item['symbol']?.toString() ?? '';
      final symbol = symbolPair.replaceAll('USDT', '');
      if (symbol.isNotEmpty) {
        map[symbol] = item;
      }
    }
    return map;
  }

  Future<List<String>> _fetchSupportedAssets(List<String> assets) async {
    if (_supportedAssets == null) {
      final response = await _dio.get('/api/v3/exchangeInfo');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Unexpected exchangeInfo format');
      }
      final symbolsData = data['symbols'];
      if (symbolsData is! List) {
        throw StateError('Unexpected exchangeInfo symbols format');
      }
      final supported = <String>{};
      for (final item in symbolsData) {
        if (item is! Map<String, dynamic>) continue;
        final quote = item['quoteAsset']?.toString();
        final base = item['baseAsset']?.toString();
        final status = item['status']?.toString();
        if (quote == 'USDT' && base != null && status == 'TRADING') {
          supported.add(base);
        }
      }
      _supportedAssets = supported;
    }

    return assets.where((s) => _supportedAssets!.contains(s)).toList();
  }

  Future<List<double>> _fetchPriceHistory(String pair, String interval) async {
    final response = await _dio.get(
      '/api/v3/klines',
      queryParameters: {
        'symbol': pair,
        'interval': interval,
        'limit': 60,
      },
    );
    final data = response.data;
    if (data is! List) {
      throw StateError('Unexpected klines response format');
    }

    final prices = <double>[];
    for (final kline in data) {
      if (kline is List && kline.length > 4) {
        final close = _toDouble(kline[4]);
        if (close != null && close > 0) prices.add(close);
      }
    }
    if (prices.isEmpty) {
      throw StateError('No klines returned for $pair');
    }
    return prices;
  }

  String _intervalFor(Timeframe timeframe) {
    switch (timeframe) {
      case Timeframe.m1:
        return '1m';
      case Timeframe.m5:
        return '5m';
      case Timeframe.m15:
        return '15m';
      case Timeframe.h1:
        return '1h';
      case Timeframe.h4:
        return '4h';
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  TechnicalIndicators _calcIndicators(
    List<double> prices,
    double volume,
    double avgVolume,
  ) {
    final rsi = _calcRSI(prices);
    final volSpike = avgVolume > 0 ? volume / avgVolume : 1.0;
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

  double _calcRSI(List<double> prices, {int period = 14}) {
    if (prices.length < period + 1) return 50;
    double gains = 0;
    double losses = 0;
    final start = prices.length - period;
    for (int i = start; i < prices.length; i++) {
      final diff = prices[i] - prices[i - 1];
      if (diff > 0) {
        gains += diff;
      } else {
        losses -= diff;
      }
    }
    final avgGain = gains / period;
    final avgLoss = losses / period;
    if (avgGain == 0 && avgLoss == 0) return 50;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  // Exponential Moving Average over a price series.
  double _ema(List<double> prices, int period) {
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
  String _calcTrend(List<double> prices) {
    if (prices.length < 26) {
      return prices.last > prices.first ? 'bullish' : 'bearish';
    }
    // Build MACD line: EMA(12) - EMA(26) for each point from index 25 onward.
    // Use last 35 prices to get ~10 MACD values for a stable signal line.
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
  bool _calcBBSqueeze(List<double> prices, {int period = 20, double numStd = 2.0, double threshold = 0.05}) {
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
}
