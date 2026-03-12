import '../../models/spx_models.dart';
import 'spx_trade_journal_repository.dart';

class SpxTradeHeatmapCell {
  final String bucketKey;
  final String bucketLabel;
  final String moneynessKey;
  final int tradeCount;
  final int winCount;
  final double totalPnlUsd;
  final double avgPnlUsd;
  final double avgWinUsd;
  final double avgLossUsd;

  const SpxTradeHeatmapCell({
    required this.bucketKey,
    required this.bucketLabel,
    required this.moneynessKey,
    required this.tradeCount,
    required this.winCount,
    required this.totalPnlUsd,
    required this.avgPnlUsd,
    required this.avgWinUsd,
    required this.avgLossUsd,
  });

  double get winRate => tradeCount == 0 ? 0 : (winCount / tradeCount) * 100;
}

class SpxTradeHeatmap {
  final List<String> bucketKeys;
  final Map<String, String> bucketLabels;
  final Map<String, Map<String, SpxTradeHeatmapCell>> cellsByMoneyness;
  final int totalClosedTrades;

  const SpxTradeHeatmap({
    required this.bucketKeys,
    required this.bucketLabels,
    required this.cellsByMoneyness,
    required this.totalClosedTrades,
  });
}

String classifyTradeMoneyness(
  SpxTradeJournalRecord record, {
  double tolerancePoints = OptionsContract.atmTolerancePoints,
}) {
  final strikeDistance = (record.strike - record.spotEntry).abs();
  if (strikeDistance <= tolerancePoints) {
    return SpxContractMoneyness.atm.name;
  }

  final side = record.side.trim().toLowerCase();
  final isCall = side == 'call';
  final isItm = isCall
      ? record.spotEntry > record.strike
      : record.strike > record.spotEntry;
  return isItm ? SpxContractMoneyness.itm.name : SpxContractMoneyness.otm.name;
}

SpxTradeHeatmap buildSpxTradeHeatmap(
  List<SpxTradeJournalRecord> records, {
  int bucketMinutes = 30,
}) {
  final normalizedBucketMinutes = bucketMinutes.clamp(5, 120);
  final closed = records.where((record) => record.pnlUsd != null).toList()
    ..sort((a, b) => a.enteredAt.compareTo(b.enteredAt));

  if (closed.isEmpty) {
    return const SpxTradeHeatmap(
      bucketKeys: <String>[],
      bucketLabels: <String, String>{},
      cellsByMoneyness: <String, Map<String, SpxTradeHeatmapCell>>{},
      totalClosedTrades: 0,
    );
  }

  final rows = <String, Map<String, List<SpxTradeJournalRecord>>>{
    SpxContractMoneyness.itm.name: <String, List<SpxTradeJournalRecord>>{},
    SpxContractMoneyness.atm.name: <String, List<SpxTradeJournalRecord>>{},
    SpxContractMoneyness.otm.name: <String, List<SpxTradeJournalRecord>>{},
  };
  final bucketLabels = <String, String>{};
  final orderedBucketKeys = <String>[];

  for (final record in closed) {
    final localEnteredAt = record.enteredAt.toLocal();
    final bucketStartMinutes = _bucketStartMinutes(
      localEnteredAt,
      bucketMinutes: normalizedBucketMinutes,
    );
    final bucketKey = bucketStartMinutes.toString();
    bucketLabels[bucketKey] = _formatBucketLabel(bucketStartMinutes);
    if (!orderedBucketKeys.contains(bucketKey)) {
      orderedBucketKeys.add(bucketKey);
    }

    final moneyness = classifyTradeMoneyness(record);
    rows[moneyness]!.putIfAbsent(bucketKey, () => <SpxTradeJournalRecord>[]);
    rows[moneyness]![bucketKey]!.add(record);
  }

  final cellsByMoneyness = <String, Map<String, SpxTradeHeatmapCell>>{};
  for (final entry in rows.entries) {
    final bucketMap = <String, SpxTradeHeatmapCell>{};
    for (final bucketKey in orderedBucketKeys) {
      final bucketRecords =
          entry.value[bucketKey] ?? const <SpxTradeJournalRecord>[];
      if (bucketRecords.isEmpty) continue;

      final pnls = bucketRecords.map((record) => record.pnlUsd!).toList();
      final wins = pnls.where((pnl) => pnl > 0).toList();
      final losses = pnls.where((pnl) => pnl < 0).toList();
      final totalPnl = pnls.fold<double>(0.0, (sum, pnl) => sum + pnl);

      bucketMap[bucketKey] = SpxTradeHeatmapCell(
        bucketKey: bucketKey,
        bucketLabel: bucketLabels[bucketKey] ?? bucketKey,
        moneynessKey: entry.key,
        tradeCount: pnls.length,
        winCount: wins.length,
        totalPnlUsd: totalPnl,
        avgPnlUsd: totalPnl / pnls.length,
        avgWinUsd: wins.isEmpty
            ? 0
            : wins.fold<double>(0.0, (sum, pnl) => sum + pnl) / wins.length,
        avgLossUsd: losses.isEmpty
            ? 0
            : losses.fold<double>(0.0, (sum, pnl) => sum + pnl) / losses.length,
      );
    }
    cellsByMoneyness[entry.key] = bucketMap;
  }

  orderedBucketKeys.sort((a, b) => int.parse(a).compareTo(int.parse(b)));

  return SpxTradeHeatmap(
    bucketKeys: orderedBucketKeys,
    bucketLabels: bucketLabels,
    cellsByMoneyness: cellsByMoneyness,
    totalClosedTrades: closed.length,
  );
}

int _bucketStartMinutes(
  DateTime dateTime, {
  required int bucketMinutes,
}) {
  final totalMinutes = dateTime.hour * 60 + dateTime.minute;
  return totalMinutes - (totalMinutes % bucketMinutes);
}

String _formatBucketLabel(int minutesSinceMidnight) {
  final hour24 = minutesSinceMidnight ~/ 60;
  final minute = minutesSinceMidnight % 60;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
  final minuteLabel = minute.toString().padLeft(2, '0');
  return '$hour12:$minuteLabel $suffix';
}
