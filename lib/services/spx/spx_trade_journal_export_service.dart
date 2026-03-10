import 'dart:convert';

import 'spx_trade_journal_repository.dart';

class SpxTradeJournalExportService {
  final SpxTradeJournalRepository _repository;

  const SpxTradeJournalExportService({
    required SpxTradeJournalRepository repository,
  }) : _repository = repository;

  Future<String> exportCsv(
    String userId, {
    int limit = 2000,
    bool closedOnly = false,
    bool openOnly = false,
    DateTime? enteredFrom,
    DateTime? enteredTo,
  }) async {
    final records = await _repository.loadAll(
      userId,
      limit: limit,
      closedOnly: closedOnly,
      openOnly: openOnly,
      enteredFrom: enteredFrom,
      enteredTo: enteredTo,
    );

    const headers = <String>[
      'tradeId',
      'positionId',
      'symbol',
      'side',
      'strike',
      'expiryIso',
      'enteredAt',
      'exitedAt',
      'dteEntry',
      'dteExit',
      'entrySource',
      'entryReasonCode',
      'entryReasonText',
      'signalScore',
      'signalDetails',
      'contracts',
      'entryPremium',
      'exitPremium',
      'pnlUsd',
      'pnlPct',
      'exitReasonCode',
      'exitReasonText',
      'reviewVerdict',
      'reviewNotes',
      'reviewedAt',
      'spotEntry',
      'spotExit',
      'ivRankEntry',
      'ivRankExit',
      'dataMode',
      'termMode',
      'termExactDte',
      'termMinDte',
      'termMaxDte',
      'updatedAt',
      'durationMinutes',
    ];

    final out = StringBuffer();
    out.writeln(headers.join(','));
    for (final r in records) {
      final durationMinutes = r.exitedAt?.difference(r.enteredAt).inMinutes;
      final row = <dynamic>[
        r.tradeId,
        r.positionId,
        r.symbol,
        r.side,
        r.strike,
        r.expiryIso,
        r.enteredAt.toIso8601String(),
        r.exitedAt?.toIso8601String(),
        r.dteEntry,
        r.dteExit,
        r.entrySource,
        r.entryReasonCode,
        r.entryReasonText,
        r.signalScore,
        jsonEncode(r.signalDetails),
        r.contracts,
        r.entryPremium,
        r.exitPremium,
        r.pnlUsd,
        r.pnlPct,
        r.exitReasonCode,
        r.exitReasonText,
        r.reviewVerdict,
        r.reviewNotes,
        r.reviewedAt?.toIso8601String(),
        r.spotEntry,
        r.spotExit,
        r.ivRankEntry,
        r.ivRankExit,
        r.dataMode,
        r.termMode,
        r.termExactDte,
        r.termMinDte,
        r.termMaxDte,
        r.updatedAt.toIso8601String(),
        durationMinutes,
      ];
      out.writeln(row.map(_csvCell).join(','));
    }
    return out.toString();
  }

  Future<String> exportFeatureCsv(
    String userId, {
    int limit = 2000,
    DateTime? enteredFrom,
    DateTime? enteredTo,
  }) async {
    final records = await _repository.loadAll(
      userId,
      limit: limit,
      closedOnly: true,
      enteredFrom: enteredFrom,
      enteredTo: enteredTo,
    );

    const headers = <String>[
      'tradeId',
      'enteredAt',
      'exitedAt',
      'holdMinutes',
      'symbol',
      'side',
      'dteEntry',
      'dteExit',
      'entrySource',
      'entryReasonCode',
      'exitReasonCode',
      'signalScore',
      'delta',
      'iv',
      'ivRankEntry',
      'volumeVsOiRatio',
      'midPrice',
      'termMode',
      'termExactDte',
      'termMinDte',
      'termMaxDte',
      'pnlUsd',
      'pnlPct',
      'winFlag',
      'dataMode',
      'reviewVerdict',
      'reviewNotes',
    ];

    final out = StringBuffer();
    out.writeln(headers.join(','));
    for (final r in records) {
      final signal = r.signalDetails;
      final delta = _asDouble(signal['delta']);
      final iv = _asDouble(signal['iv']);
      final volumeVsOiRatio = _asDouble(signal['volumeVsOiRatio']);
      final midPrice = _asDouble(signal['midPrice']);
      final rawHoldMinutes = r.exitedAt?.difference(r.enteredAt).inMinutes;
      final holdMinutes = rawHoldMinutes?.clamp(0, 525600);
      final pnlUsd = r.pnlUsd ?? 0;

      final row = <dynamic>[
        r.tradeId,
        r.enteredAt.toIso8601String(),
        r.exitedAt?.toIso8601String(),
        holdMinutes,
        r.symbol,
        r.side,
        r.dteEntry,
        r.dteExit,
        r.entrySource,
        r.entryReasonCode,
        r.exitReasonCode,
        r.signalScore,
        delta,
        iv,
        r.ivRankEntry,
        volumeVsOiRatio,
        midPrice,
        r.termMode,
        r.termExactDte,
        r.termMinDte,
        r.termMaxDte,
        pnlUsd,
        r.pnlPct ?? 0,
        pnlUsd > 0 ? 1 : 0,
        r.dataMode,
        r.reviewVerdict,
        r.reviewNotes,
      ];
      out.writeln(row.map(_csvCell).join(','));
    }

    return out.toString();
  }

  Future<String> exportJsonLines(
    String userId, {
    int limit = 2000,
    bool closedOnly = false,
    bool openOnly = false,
    DateTime? enteredFrom,
    DateTime? enteredTo,
  }) async {
    final records = await _repository.loadAll(
      userId,
      limit: limit,
      closedOnly: closedOnly,
      openOnly: openOnly,
      enteredFrom: enteredFrom,
      enteredTo: enteredTo,
    );

    final out = StringBuffer();
    for (final record in records) {
      out.writeln(jsonEncode(record.toJson()));
    }
    return out.toString();
  }

  String _csvCell(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('\r') ||
        escaped.contains('"')) {
      return '"$escaped"';
    }
    return escaped;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
