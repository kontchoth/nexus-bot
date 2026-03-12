import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/services/spx/spx_trade_journal_analytics.dart';
import 'package:nexusbot/services/spx/spx_trade_journal_repository.dart';

void main() {
  group('Spx trade journal analytics', () {
    test('classifies trade moneyness from spot entry', () {
      expect(
        classifyTradeMoneyness(_buildRecord(
          side: 'call',
          strike: 5740,
          spotEntry: 5750,
        )),
        'itm',
      );
      expect(
        classifyTradeMoneyness(_buildRecord(
          side: 'call',
          strike: 5752,
          spotEntry: 5750,
        )),
        'atm',
      );
      expect(
        classifyTradeMoneyness(_buildRecord(
          side: 'put',
          strike: 5740,
          spotEntry: 5750,
        )),
        'otm',
      );
    });

    test('builds heatmap buckets and aggregates trade stats', () {
      final heatmap = buildSpxTradeHeatmap([
        _buildRecord(
          side: 'call',
          strike: 5740,
          spotEntry: 5750,
          pnlUsd: 200,
          enteredAt: DateTime(2026, 3, 12, 9, 35),
        ),
        _buildRecord(
          side: 'call',
          strike: 5740,
          spotEntry: 5750,
          pnlUsd: -100,
          enteredAt: DateTime(2026, 3, 12, 9, 50),
        ),
        _buildRecord(
          side: 'call',
          strike: 5750,
          spotEntry: 5750,
          pnlUsd: 150,
          enteredAt: DateTime(2026, 3, 12, 10, 5),
        ),
      ]);

      expect(heatmap.totalClosedTrades, 3);
      expect(heatmap.bucketKeys, ['570', '600']);
      expect(heatmap.bucketLabels['570'], '9:30 AM');
      expect(heatmap.bucketLabels['600'], '10:00 AM');

      final itmCell = heatmap.cellsByMoneyness['itm']?['570'];
      expect(itmCell, isNotNull);
      expect(itmCell!.tradeCount, 2);
      expect(itmCell.winCount, 1);
      expect(itmCell.winRate, 50);
      expect(itmCell.avgPnlUsd, 50);

      final atmCell = heatmap.cellsByMoneyness['atm']?['600'];
      expect(atmCell, isNotNull);
      expect(atmCell!.tradeCount, 1);
      expect(atmCell.winRate, 100);
      expect(atmCell.avgPnlUsd, 150);
    });
  });
}

SpxTradeJournalRecord _buildRecord({
  required String side,
  required double strike,
  required double spotEntry,
  double pnlUsd = 100,
  DateTime? enteredAt,
}) {
  final entryTime = enteredAt ?? DateTime(2026, 3, 12, 9, 35);
  return SpxTradeJournalRecord(
    tradeId: 'trade-${entryTime.microsecondsSinceEpoch}',
    positionId: 'position-${entryTime.microsecondsSinceEpoch}',
    symbol: 'SPX TEST',
    side: side,
    strike: strike,
    expiryIso: '2026-03-19',
    enteredAt: entryTime,
    exitedAt: entryTime.add(const Duration(minutes: 15)),
    dteEntry: 7,
    dteExit: 7,
    entrySource: 'manual',
    entryReasonCode: 'manual_buy',
    entryReasonText: 'Test trade',
    signalScore: 70,
    signalDetails: const <String, dynamic>{},
    contracts: 1,
    entryPremium: 10,
    exitPremium: 11,
    pnlUsd: pnlUsd,
    pnlPct: 10,
    exitReasonCode: 'manual_close',
    exitReasonText: 'Closed',
    spotEntry: spotEntry,
    spotExit: spotEntry + 5,
    ivRankEntry: 25,
    ivRankExit: 30,
    dataMode: 'simulator',
    termMode: 'exact',
    termExactDte: 7,
    termMinDte: 5,
    termMaxDte: 14,
    updatedAt: entryTime.add(const Duration(minutes: 15)),
  );
}
