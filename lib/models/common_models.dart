import 'package:equatable/equatable.dart';

// ── Shared Enums ──────────────────────────────────────────────────────────────

enum BotStatus { active, paused, error }

enum MarketDataMode { live, simulator }

enum TradeLogType { buy, sell, win, loss, warn, system, info }

// ── Trade Log ─────────────────────────────────────────────────────────────────

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
    double? capital,
    double? dailyTarget,
  }) {
    return DailyStats(
      realizedPnL: realizedPnL ?? this.realizedPnL,
      unrealizedPnL: unrealizedPnL ?? this.unrealizedPnL,
      totalTrades: totalTrades ?? this.totalTrades,
      winTrades: winTrades ?? this.winTrades,
      capital: capital ?? this.capital,
      dailyTarget: dailyTarget ?? this.dailyTarget,
    );
  }

  @override
  List<Object?> get props => [
        realizedPnL,
        unrealizedPnL,
        totalTrades,
        winTrades,
        capital,
        dailyTarget
      ];
}

// ── Trade Alert ───────────────────────────────────────────────────────────────

class TradeAlert {
  final String title;
  final String message;
  final TradeLogType type;
  final String? payload;

  const TradeAlert({
    required this.title,
    required this.message,
    required this.type,
    this.payload,
  });
}

class TradeAlertPayloads {
  static const spxOpportunities = 'spx_opportunities';
  static const _spxOpportunityPrefix = 'spx_opportunity:';

  static String forSpxOpportunity(String opportunityId) =>
      '$_spxOpportunityPrefix$opportunityId';

  static bool isSpxOpportunity(String payload) =>
      payload.startsWith(_spxOpportunityPrefix);

  static String? spxOpportunityIdFrom(String payload) {
    if (!isSpxOpportunity(payload)) return null;
    final raw = payload.substring(_spxOpportunityPrefix.length).trim();
    return raw.isEmpty ? null : raw;
  }
}
