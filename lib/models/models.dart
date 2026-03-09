import 'package:equatable/equatable.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SignalType { buy, sell, watch }
enum MACDTrend { bullish, bearish, neutral }
enum Exchange { all, binance, coinbase, kraken, bybit }
enum Timeframe { m1, m5, m15, h1, h4 }
enum BotStatus { active, paused, error }
enum MarketDataMode { live, simulator }

extension TimeframeExt on Timeframe {
  String get label {
    switch (this) {
      case Timeframe.m1: return '1m';
      case Timeframe.m5: return '5m';
      case Timeframe.m15: return '15m';
      case Timeframe.h1: return '1h';
      case Timeframe.h4: return '4h';
    }
  }
}

extension ExchangeExt on Exchange {
  String get label {
    switch (this) {
      case Exchange.all: return 'All Exchanges';
      case Exchange.binance: return 'Binance';
      case Exchange.coinbase: return 'Coinbase';
      case Exchange.kraken: return 'Kraken';
      case Exchange.bybit: return 'Bybit';
    }
  }
}

// ── Indicator Model ───────────────────────────────────────────────────────────

class TechnicalIndicators extends Equatable {
  final double rsi;
  final MACDTrend macd;
  final double volumeSpike;
  final bool bbSqueeze;
  final int signalStrength; // 0-4

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
  List<Object?> get props => [rsi, macd, volumeSpike, bbSqueeze, signalStrength];
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

  const Position({
    required this.id,
    required this.symbol,
    required this.entryPrice,
    required this.currentPrice,
    required this.size,
    required this.quantity,
    required this.openedAt,
    required this.exchange,
  });

  double get unrealizedPnL => (currentPrice - entryPrice) * quantity;
  double get pnlPercent => ((currentPrice - entryPrice) / entryPrice) * 100;
  bool get isProfit => unrealizedPnL >= 0;

  Position copyWith({double? currentPrice}) {
    return Position(
      id: id,
      symbol: symbol,
      entryPrice: entryPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      size: size,
      quantity: quantity,
      openedAt: openedAt,
      exchange: exchange,
    );
  }

  String get formattedPnL {
    final sign = unrealizedPnL >= 0 ? '+' : '';
    return '$sign\$${unrealizedPnL.toStringAsFixed(2)}';
  }

  @override
  List<Object?> get props => [id, symbol, currentPrice];
}

// ── Trade Log Model ───────────────────────────────────────────────────────────

enum TradeLogType { buy, sell, win, loss, warn, system, info }

class TradeLog extends Equatable {
  final String id;
  final DateTime timestamp;
  final String message;
  final TradeLogType type;

  const TradeLog({
    required this.id,
    required this.timestamp,
    required this.message,
    required this.type,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  List<Object?> get props => [id];
}

// ── Daily Stats ───────────────────────────────────────────────────────────────

class DailyStats extends Equatable {
  final double realizedPnL;
  final double unrealizedPnL;
  final int totalTrades;
  final int winTrades;
  final double dailyTarget;
  final double capital;

  const DailyStats({
    this.realizedPnL = 0,
    this.unrealizedPnL = 0,
    this.totalTrades = 0,
    this.winTrades = 0,
    this.dailyTarget = 500,
    this.capital = 15000,
  });

  double get winRate => totalTrades == 0 ? 0 : (winTrades / totalTrades) * 100;
  double get targetProgress => (realizedPnL / dailyTarget).clamp(0, 1);

  DailyStats copyWith({
    double? realizedPnL,
    double? unrealizedPnL,
    int? totalTrades,
    int? winTrades,
  }) {
    return DailyStats(
      realizedPnL: realizedPnL ?? this.realizedPnL,
      unrealizedPnL: unrealizedPnL ?? this.unrealizedPnL,
      totalTrades: totalTrades ?? this.totalTrades,
      winTrades: winTrades ?? this.winTrades,
      dailyTarget: dailyTarget,
      capital: capital,
    );
  }

  @override
  List<Object?> get props => [realizedPnL, unrealizedPnL, totalTrades, winTrades];
}
