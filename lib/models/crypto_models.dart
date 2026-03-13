import 'package:equatable/equatable.dart';
export 'common_models.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SignalType { buy, sell, watch }

enum MACDTrend { bullish, bearish, neutral }

enum Exchange { all, binance, coinbase, kraken, bybit }

enum CryptoDataProvider { binance, robinhood }

enum Timeframe { m1, m5, m15, h1, h4 }

enum CryptoScannerViewMode { scanner, opportunities }

enum CryptoOpportunitySource {
  coinGecko,
  dexScreener,
  binance,
  moralis,
  coinMarketCap,
}

enum CryptoOpportunityGrade { elite, strong, watch, weak }

enum CryptoOpportunitySignalKind {
  volumeMarketCap,
  momentum24h,
  volumeSpike24h,
  lowCap,
  accumulation,
  freshDexLiquidity,
  binanceConfirmation,
  lowLiquidityRisk,
  missingMarketCapRisk,
  noCexConfirmationRisk,
}

extension TimeframeExt on Timeframe {
  String get label {
    switch (this) {
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
}

extension ExchangeExt on Exchange {
  String get label {
    switch (this) {
      case Exchange.all:
        return 'All Exchanges';
      case Exchange.binance:
        return 'Binance';
      case Exchange.coinbase:
        return 'Coinbase';
      case Exchange.kraken:
        return 'Kraken';
      case Exchange.bybit:
        return 'Bybit';
    }
  }
}

extension CryptoDataProviderExt on CryptoDataProvider {
  String get label {
    switch (this) {
      case CryptoDataProvider.binance:
        return 'Binance (Default)';
      case CryptoDataProvider.robinhood:
        return 'Robinhood Crypto';
    }
  }
}

extension CryptoScannerViewModeExt on CryptoScannerViewMode {
  String get label {
    switch (this) {
      case CryptoScannerViewMode.scanner:
        return 'Scanner';
      case CryptoScannerViewMode.opportunities:
        return 'Opportunities';
    }
  }
}

extension CryptoOpportunitySourceExt on CryptoOpportunitySource {
  String get label {
    switch (this) {
      case CryptoOpportunitySource.coinGecko:
        return 'CoinGecko';
      case CryptoOpportunitySource.dexScreener:
        return 'DEX';
      case CryptoOpportunitySource.binance:
        return 'Binance';
      case CryptoOpportunitySource.moralis:
        return 'Moralis';
      case CryptoOpportunitySource.coinMarketCap:
        return 'CMC';
    }
  }
}

extension CryptoOpportunityGradeExt on CryptoOpportunityGrade {
  String get label {
    switch (this) {
      case CryptoOpportunityGrade.elite:
        return 'Elite';
      case CryptoOpportunityGrade.strong:
        return 'Strong';
      case CryptoOpportunityGrade.watch:
        return 'Watch';
      case CryptoOpportunityGrade.weak:
        return 'Weak';
    }
  }
}

class CryptoOpportunitySignal extends Equatable {
  final CryptoOpportunitySignalKind kind;
  final String label;
  final double scoreDelta;
  final bool isRisk;

  const CryptoOpportunitySignal({
    required this.kind,
    required this.label,
    required this.scoreDelta,
    this.isRisk = false,
  });

  @override
  List<Object?> get props => [kind, label, scoreDelta, isRisk];
}

class CryptoOpportunityScore extends Equatable {
  final double value;
  final CryptoOpportunityGrade grade;
  final List<CryptoOpportunitySignal> signals;

  const CryptoOpportunityScore({
    required this.value,
    required this.grade,
    required this.signals,
  });

  List<CryptoOpportunitySignal> get positiveSignals =>
      signals.where((signal) => !signal.isRisk).toList();

  List<CryptoOpportunitySignal> get riskSignals =>
      signals.where((signal) => signal.isRisk).toList();

  bool get isActionable => value >= 30;

  @override
  List<Object?> get props => [value, grade, signals];
}

class CryptoOpportunity extends Equatable {
  final String id;
  final String symbol;
  final String name;
  final String? chain;
  final String? logoUrl;
  final double priceUsd;
  final double priceChange24h;
  final double? marketCap;
  final double? volume24h;
  final double? volumeChange24h;
  final double? liquidityUsd;
  final double? pairAgeHours;
  final bool isDex;
  final bool binanceListed;
  final double? rsi;
  final MACDTrend? macdTrend;
  final List<CryptoOpportunitySource> sources;
  final DateTime lastUpdated;
  final CryptoOpportunityScore? score;

  const CryptoOpportunity({
    required this.id,
    required this.symbol,
    required this.name,
    required this.priceUsd,
    required this.priceChange24h,
    required this.sources,
    required this.lastUpdated,
    this.chain,
    this.logoUrl,
    this.marketCap,
    this.volume24h,
    this.volumeChange24h,
    this.liquidityUsd,
    this.pairAgeHours,
    this.isDex = false,
    this.binanceListed = false,
    this.rsi,
    this.macdTrend,
    this.score,
  });

  double get volumeMarketCapRatio {
    final marketCapValue = marketCap ?? 0;
    final volumeValue = volume24h ?? 0;
    if (marketCapValue <= 0 || volumeValue <= 0) return 0;
    return volumeValue / marketCapValue;
  }

  bool hasSource(CryptoOpportunitySource source) => sources.contains(source);

  CryptoOpportunity copyWith({
    double? priceUsd,
    double? priceChange24h,
    double? marketCap,
    double? volume24h,
    double? volumeChange24h,
    double? liquidityUsd,
    double? pairAgeHours,
    bool? isDex,
    bool? binanceListed,
    double? rsi,
    MACDTrend? macdTrend,
    List<CryptoOpportunitySource>? sources,
    DateTime? lastUpdated,
    CryptoOpportunityScore? score,
  }) {
    return CryptoOpportunity(
      id: id,
      symbol: symbol,
      name: name,
      chain: chain,
      logoUrl: logoUrl,
      priceUsd: priceUsd ?? this.priceUsd,
      priceChange24h: priceChange24h ?? this.priceChange24h,
      marketCap: marketCap ?? this.marketCap,
      volume24h: volume24h ?? this.volume24h,
      volumeChange24h: volumeChange24h ?? this.volumeChange24h,
      liquidityUsd: liquidityUsd ?? this.liquidityUsd,
      pairAgeHours: pairAgeHours ?? this.pairAgeHours,
      isDex: isDex ?? this.isDex,
      binanceListed: binanceListed ?? this.binanceListed,
      rsi: rsi ?? this.rsi,
      macdTrend: macdTrend ?? this.macdTrend,
      sources: sources ?? this.sources,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      score: score ?? this.score,
    );
  }

  @override
  List<Object?> get props => [
        id,
        symbol,
        priceUsd,
        priceChange24h,
        marketCap,
        volume24h,
        volumeChange24h,
        liquidityUsd,
        pairAgeHours,
        isDex,
        binanceListed,
        rsi,
        macdTrend,
        sources,
        lastUpdated,
        score,
      ];
}

// ── Indicator Model ───────────────────────────────────────────────────────────

class TechnicalIndicators extends Equatable {
  final double rsi;
  final MACDTrend macd;
  final double volumeSpike;
  final bool bbSqueeze;
  final int signalStrength; // 0–4

  const TechnicalIndicators({
    required this.rsi,
    required this.macd,
    required this.volumeSpike,
    required this.bbSqueeze,
    required this.signalStrength,
  });

  SignalType get signal {
    if (signalStrength >= 3 && rsi < 48) return SignalType.buy;
    if (rsi > 66 || (macd == MACDTrend.bearish && volumeSpike > 1.5)) {
      return SignalType.sell;
    }
    return SignalType.watch;
  }

  String get rsiLabel {
    if (rsi < 35) return 'Oversold';
    if (rsi > 65) return 'Overbought';
    return 'Neutral';
  }

  @override
  List<Object?> get props =>
      [rsi, macd, volumeSpike, bbSqueeze, signalStrength];
}

// ── Coin Model ────────────────────────────────────────────────────────────────

class CoinData extends Equatable {
  final String symbol;
  final String name;
  final double price;
  final double basePrice;
  final double changePercent;
  final double volume;
  final double avgVolume;
  final List<double> priceHistory;
  final TechnicalIndicators indicators;
  final DateTime lastUpdated;

  const CoinData({
    required this.symbol,
    required this.name,
    required this.price,
    required this.basePrice,
    required this.changePercent,
    required this.volume,
    required this.avgVolume,
    required this.priceHistory,
    required this.indicators,
    required this.lastUpdated,
  });

  CoinData copyWith({
    double? price,
    double? changePercent,
    double? volume,
    List<double>? priceHistory,
    TechnicalIndicators? indicators,
    DateTime? lastUpdated,
  }) {
    return CoinData(
      symbol: symbol,
      name: name,
      price: price ?? this.price,
      basePrice: basePrice,
      changePercent: changePercent ?? this.changePercent,
      volume: volume ?? this.volume,
      avgVolume: avgVolume,
      priceHistory: priceHistory ?? this.priceHistory,
      indicators: indicators ?? this.indicators,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  bool get isPositive => changePercent >= 0;

  String get formattedPrice {
    if (price >= 1000) return '\$${price.toStringAsFixed(2)}';
    if (price >= 1) return '\$${price.toStringAsFixed(3)}';
    return '\$${price.toStringAsFixed(5)}';
  }

  String get formattedChange {
    final sign = changePercent >= 0 ? '+' : '';
    return '$sign${changePercent.toStringAsFixed(2)}%';
  }

  @override
  List<Object?> get props => [symbol, price, changePercent, indicators];
}

// ── Position Model ────────────────────────────────────────────────────────────

class Position extends Equatable {
  final String id;
  final String symbol;
  final double entryPrice;
  final double currentPrice;
  final double size;
  final double quantity;
  final DateTime openedAt;
  final Exchange exchange;
  final double stopLossPct; // e.g. 0.05 = close if down 5%
  final double takeProfitPct; // e.g. 0.10 = close if up 10%

  const Position({
    required this.id,
    required this.symbol,
    required this.entryPrice,
    required this.currentPrice,
    required this.size,
    required this.quantity,
    required this.openedAt,
    required this.exchange,
    this.stopLossPct = 0.05,
    this.takeProfitPct = 0.10,
  });

  double get unrealizedPnL => (currentPrice - entryPrice) * quantity;
  double get pnlPercent =>
      entryPrice > 0 ? ((currentPrice - entryPrice) / entryPrice) * 100 : 0;
  bool get isProfit => unrealizedPnL >= 0;
  bool get isStopLossHit => pnlPercent <= -(stopLossPct * 100);
  bool get isTakeProfitHit => pnlPercent >= (takeProfitPct * 100);

  Position copyWith({
    double? currentPrice,
    double? stopLossPct,
    double? takeProfitPct,
  }) {
    return Position(
      id: id,
      symbol: symbol,
      entryPrice: entryPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      size: size,
      quantity: quantity,
      openedAt: openedAt,
      exchange: exchange,
      stopLossPct: stopLossPct ?? this.stopLossPct,
      takeProfitPct: takeProfitPct ?? this.takeProfitPct,
    );
  }

  String get formattedPnL {
    final sign = unrealizedPnL >= 0 ? '+' : '';
    return '$sign\$${unrealizedPnL.toStringAsFixed(2)}';
  }

  @override
  List<Object?> get props =>
      [id, symbol, currentPrice, stopLossPct, takeProfitPct];
}
