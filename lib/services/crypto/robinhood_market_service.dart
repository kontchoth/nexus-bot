import 'dart:math';
import 'package:dio/dio.dart';
import '../../models/crypto_models.dart';

class RobinhoodMarketService {
  RobinhoodMarketService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://trading.robinhood.com',
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );

  final Dio _dio;
  String? _apiToken;

  static const List<Map<String, String>> _coinDefs = [
    {'symbol': 'BTC', 'name': 'Bitcoin'},
    {'symbol': 'ETH', 'name': 'Ethereum'},
    {'symbol': 'SOL', 'name': 'Solana'},
    {'symbol': 'DOGE', 'name': 'Dogecoin'},
    {'symbol': 'XRP', 'name': 'XRP'},
    {'symbol': 'ADA', 'name': 'Cardano'},
    {'symbol': 'AVAX', 'name': 'Avalanche'},
    {'symbol': 'LINK', 'name': 'Chainlink'},
    {'symbol': 'DOT', 'name': 'Polkadot'},
    {'symbol': 'MATIC', 'name': 'Polygon'},
    {'symbol': 'UNI', 'name': 'Uniswap'},
    {'symbol': 'LTC', 'name': 'Litecoin'},
  ];

  List<String> get symbols => _coinDefs.map((e) => e['symbol']!).toList();

  void setApiToken(String? token) {
    final normalized = token?.trim() ?? '';
    _apiToken = normalized.isEmpty ? null : normalized;
  }

  Future<List<CoinData>> fetchInitialCoins(Timeframe timeframe) async {
    _ensureToken();
    final quotes = await _fetchQuotes(symbols);
    final now = DateTime.now();
    final result = <CoinData>[];
    for (final def in _coinDefs) {
      final symbol = def['symbol']!;
      final name = def['name']!;
      final quote = quotes[symbol];
      if (quote == null) continue;

      final history = await _fetchOrFallbackHistory(symbol, timeframe, quote.price);
      final indicators = _calcIndicators(history, quote.volume24h, max(quote.volume24h / 60, 1.0));
      final basePrice = quote.changePercent24h == -100
          ? quote.price
          : quote.price / (1 + (quote.changePercent24h / 100));

      result.add(
        CoinData(
          symbol: symbol,
          name: name,
          price: quote.price,
          basePrice: basePrice.isFinite ? basePrice : quote.price,
          changePercent: quote.changePercent24h,
          volume: quote.volume24h,
          avgVolume: max(quote.volume24h / 60, 1.0),
          priceHistory: history,
          indicators: indicators,
          lastUpdated: now,
        ),
      );
    }

    if (result.isEmpty) {
      throw StateError('No Robinhood quotes returned');
    }
    return result;
  }

  Future<List<CoinData>> tickCoins(List<CoinData> currentCoins) async {
    _ensureToken();
    if (currentCoins.isEmpty) return currentCoins;

    final quotes = await _fetchQuotes(currentCoins.map((c) => c.symbol).toList());
    final now = DateTime.now();
    final updated = <CoinData>[];

    for (final coin in currentCoins) {
      final quote = quotes[coin.symbol];
      if (quote == null) {
        updated.add(coin.copyWith(lastUpdated: now));
        continue;
      }

      final newHistory = [...coin.priceHistory.skip(1), quote.price];
      final indicators = _calcIndicators(
        newHistory,
        quote.volume24h,
        max(quote.volume24h / 60, 1.0),
      );

      updated.add(
        coin.copyWith(
          price: quote.price,
          changePercent: quote.changePercent24h,
          volume: quote.volume24h,
          priceHistory: newHistory,
          indicators: indicators,
          lastUpdated: now,
        ),
      );
    }

    return updated;
  }

  Future<Map<String, _RobinhoodQuote>> _fetchQuotes(List<String> assetSymbols) async {
    if (assetSymbols.isEmpty) return {};
    final pairs = assetSymbols.map(_toPairSymbol).toList();
    final response = await _dio.get(
      '/api/v1/crypto/marketdata/best_bid_ask/',
      queryParameters: {'symbols': pairs.join(',')},
      options: Options(headers: _headers),
    );

    final data = response.data;
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      rows.addAll(data.whereType<Map<String, dynamic>>());
    } else if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) {
        rows.addAll(results.whereType<Map<String, dynamic>>());
      } else {
        rows.add(data);
      }
    }

    final map = <String, _RobinhoodQuote>{};
    for (final row in rows) {
      final pair = row['symbol']?.toString() ?? row['asset_code']?.toString() ?? '';
      final base = _toBaseSymbol(pair);
      if (base.isEmpty) continue;

      final bid = _toDouble(
            row['bid_inclusive_of_sell_spread'] ??
                row['bid_price'] ??
                row['bid'],
          ) ??
          0;
      final ask = _toDouble(
            row['ask_inclusive_of_buy_spread'] ??
                row['ask_price'] ??
                row['ask'],
          ) ??
          0;
      final mark = _toDouble(row['mark_price']) ??
          _toDouble(row['price']) ??
          (bid > 0 && ask > 0 ? (bid + ask) / 2 : 0);
      if (mark <= 0) continue;

      final volume24h = _toDouble(row['volume_24h']) ??
          _toDouble(row['volume']) ??
          _toDouble(row['quote_volume']) ??
          0.0;
      final changePercent24h = _toDouble(row['price_movement_24h']) ??
          _toDouble(row['change_percent_24h']) ??
          0.0;

      map[base] = _RobinhoodQuote(
        symbol: base,
        price: mark,
        volume24h: volume24h,
        changePercent24h: changePercent24h,
      );
    }
    return map;
  }

  Future<List<double>> _fetchOrFallbackHistory(
    String symbol,
    Timeframe timeframe,
    double fallbackPrice,
  ) async {
    try {
      final response = await _dio.get(
        '/api/v1/crypto/marketdata/historicals/',
        queryParameters: {
          'symbol': _toPairSymbol(symbol),
          'interval': _intervalFor(timeframe),
          'span': _spanFor(timeframe),
          'bounds': '24_7',
        },
        options: Options(headers: _headers),
      );

      final data = response.data;
      final rows = <dynamic>[];
      if (data is Map<String, dynamic>) {
        final historicals = data['historicals'];
        if (historicals is List) rows.addAll(historicals);
      } else if (data is List) {
        rows.addAll(data);
      }

      final prices = <double>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final close = _toDouble(
          row['close_price'] ?? row['close'] ?? row['price'],
        );
        if (close != null && close > 0) prices.add(close);
      }
      if (prices.length >= 20) {
        return prices.length > 60 ? prices.sublist(prices.length - 60) : prices;
      }
    } catch (_) {
      // Fall back below.
    }
    return List<double>.filled(60, fallbackPrice);
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${_apiToken ?? ''}',
        'x-api-key': _apiToken ?? '',
      };

  void _ensureToken() {
    if ((_apiToken ?? '').isEmpty) {
      throw StateError('Robinhood token is missing');
    }
  }

  String _toPairSymbol(String symbol) => '${symbol.toUpperCase()}-USD';

  String _toBaseSymbol(String pair) {
    final upper = pair.toUpperCase();
    if (upper.endsWith('-USD')) return upper.substring(0, upper.length - 4);
    if (upper.endsWith('_USD')) return upper.substring(0, upper.length - 4);
    if (upper.endsWith('USD') && upper.length > 3) {
      return upper.substring(0, upper.length - 3);
    }
    return upper;
  }

  String _intervalFor(Timeframe timeframe) {
    switch (timeframe) {
      case Timeframe.m1:
        return '15second';
      case Timeframe.m5:
        return '5minute';
      case Timeframe.m15:
        return '15minute';
      case Timeframe.h1:
        return 'hour';
      case Timeframe.h4:
        return 'hour';
    }
  }

  String _spanFor(Timeframe timeframe) {
    switch (timeframe) {
      case Timeframe.m1:
      case Timeframe.m5:
      case Timeframe.m15:
        return 'day';
      case Timeframe.h1:
      case Timeframe.h4:
        return 'week';
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

    var signals = 0;
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
      if (diff >= 0) {
        gains += diff;
      } else {
        losses += -diff;
      }
    }
    if (losses == 0) return 100;
    final rs = gains / losses;
    return 100 - (100 / (1 + rs));
  }

  String _calcTrend(List<double> prices) {
    if (prices.length < 25) return 'neutral';
    final short = _ema(prices, 12);
    final long = _ema(prices, 26);
    if (short > long) return 'bullish';
    if (short < long) return 'bearish';
    return 'neutral';
  }

  double _ema(List<double> prices, int period) {
    if (prices.isEmpty) return 0;
    final k = 2 / (period + 1);
    double ema = prices.first;
    for (int i = 1; i < prices.length; i++) {
      ema = (prices[i] * k) + (ema * (1 - k));
    }
    return ema;
  }

  bool _calcBBSqueeze(List<double> prices, {int period = 20}) {
    if (prices.length < period) return false;
    final slice = prices.sublist(prices.length - period);
    final mean = slice.reduce((a, b) => a + b) / period;
    var variance = 0.0;
    for (final p in slice) {
      variance += (p - mean) * (p - mean);
    }
    variance /= period;
    final stdev = sqrt(variance);
    if (mean == 0) return false;
    final widthPct = (4 * stdev) / mean;
    return widthPct < 0.05;
  }
}

class _RobinhoodQuote {
  final String symbol;
  final double price;
  final double volume24h;
  final double changePercent24h;

  const _RobinhoodQuote({
    required this.symbol,
    required this.price,
    required this.volume24h,
    required this.changePercent24h,
  });
}
