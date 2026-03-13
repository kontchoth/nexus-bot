import 'package:dio/dio.dart';

import '../../models/crypto_models.dart';

class CoinGeckoMarketService {
  CoinGeckoMarketService({
    Dio? dio,
    DateTime Function()? now,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.coingecko.com/api/v3',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            ),
        _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;

  Future<List<CryptoOpportunity>> fetchMarkets({
    int limit = 80,
  }) async {
    final response = await _dio.get<dynamic>(
      '/coins/markets',
      queryParameters: {
        'vs_currency': 'usd',
        'order': 'volume_desc',
        'per_page': limit,
        'page': 1,
        'sparkline': false,
        'price_change_percentage': '24h',
      },
    );

    final data = response.data;
    if (data is! List) {
      throw StateError('Unexpected CoinGecko response format');
    }

    final fetchedAt = _now();
    final markets = <CryptoOpportunity>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final market = _parseMarket(item, fetchedAt);
      if (market != null) {
        markets.add(market);
      }
    }

    if (markets.isEmpty) {
      throw StateError('No CoinGecko market rows returned');
    }
    return List<CryptoOpportunity>.unmodifiable(markets);
  }

  CryptoOpportunity? _parseMarket(
    Map<String, dynamic> json,
    DateTime fetchedAt,
  ) {
    final id = json['id']?.toString().trim();
    final symbol = json['symbol']?.toString().trim().toUpperCase();
    final name = json['name']?.toString().trim();
    final priceUsd = _toDouble(json['current_price']);
    if (id == null ||
        id.isEmpty ||
        symbol == null ||
        symbol.isEmpty ||
        name == null ||
        name.isEmpty ||
        priceUsd == null ||
        priceUsd <= 0) {
      return null;
    }

    return CryptoOpportunity(
      id: id,
      symbol: symbol,
      name: name,
      logoUrl: json['image']?.toString(),
      priceUsd: priceUsd,
      priceChange24h: _toDouble(json['price_change_percentage_24h']) ?? 0,
      marketCap: _toDouble(json['market_cap']),
      volume24h: _toDouble(json['total_volume']),
      sources: const [CryptoOpportunitySource.coinGecko],
      lastUpdated: fetchedAt,
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
