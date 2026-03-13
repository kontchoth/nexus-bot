import 'package:equatable/equatable.dart';

// ── Shared Enums ──────────────────────────────────────────────────────────────

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
