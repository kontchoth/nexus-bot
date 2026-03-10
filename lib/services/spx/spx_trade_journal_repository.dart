import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'spx_trade_journal_codes.dart';

void _journalLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[SPX-JOURNAL] $message');
}

/// Single SPX trade lifecycle record used for analytics and model training.
class SpxTradeJournalRecord {
  final String tradeId;
  final String positionId;
  final String symbol;
  final String side;
  final double strike;
  final String expiryIso;

  final DateTime enteredAt;
  final DateTime? exitedAt;

  final int dteEntry;
  final int? dteExit;

  final String entrySource; // manual | auto
  final String entryReasonCode;
  final String entryReasonText;
  final int signalScore;
  final Map<String, dynamic> signalDetails;

  final int contracts;
  final double entryPremium;
  final double? exitPremium;
  final double? pnlUsd;
  final double? pnlPct;

  final String? exitReasonCode;
  final String? exitReasonText;

  final String? reviewVerdict;
  final String? reviewNotes;
  final DateTime? reviewedAt;

  final double spotEntry;
  final double? spotExit;
  final double ivRankEntry;
  final double? ivRankExit;

  final String dataMode; // live | simulator

  final String termMode; // exact | range
  final int termExactDte;
  final int termMinDte;
  final int termMaxDte;

  final DateTime updatedAt;

  const SpxTradeJournalRecord({
    required this.tradeId,
    required this.positionId,
    required this.symbol,
    required this.side,
    required this.strike,
    required this.expiryIso,
    required this.enteredAt,
    this.exitedAt,
    required this.dteEntry,
    this.dteExit,
    required this.entrySource,
    required this.entryReasonCode,
    required this.entryReasonText,
    required this.signalScore,
    required this.signalDetails,
    required this.contracts,
    required this.entryPremium,
    this.exitPremium,
    this.pnlUsd,
    this.pnlPct,
    this.exitReasonCode,
    this.exitReasonText,
    this.reviewVerdict,
    this.reviewNotes,
    this.reviewedAt,
    required this.spotEntry,
    this.spotExit,
    required this.ivRankEntry,
    this.ivRankExit,
    required this.dataMode,
    required this.termMode,
    required this.termExactDte,
    required this.termMinDte,
    required this.termMaxDte,
    required this.updatedAt,
  });

  SpxTradeJournalRecord copyWith({
    DateTime? exitedAt,
    int? dteExit,
    double? exitPremium,
    double? pnlUsd,
    double? pnlPct,
    String? exitReasonCode,
    String? exitReasonText,
    String? reviewVerdict,
    String? reviewNotes,
    DateTime? reviewedAt,
    double? spotExit,
    double? ivRankExit,
    DateTime? updatedAt,
  }) {
    return SpxTradeJournalRecord(
      tradeId: tradeId,
      positionId: positionId,
      symbol: symbol,
      side: side,
      strike: strike,
      expiryIso: expiryIso,
      enteredAt: enteredAt,
      exitedAt: exitedAt ?? this.exitedAt,
      dteEntry: dteEntry,
      dteExit: dteExit ?? this.dteExit,
      entrySource: entrySource,
      entryReasonCode: entryReasonCode,
      entryReasonText: entryReasonText,
      signalScore: signalScore,
      signalDetails: signalDetails,
      contracts: contracts,
      entryPremium: entryPremium,
      exitPremium: exitPremium ?? this.exitPremium,
      pnlUsd: pnlUsd ?? this.pnlUsd,
      pnlPct: pnlPct ?? this.pnlPct,
      exitReasonCode: exitReasonCode ?? this.exitReasonCode,
      exitReasonText: exitReasonText ?? this.exitReasonText,
      reviewVerdict: reviewVerdict ?? this.reviewVerdict,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      spotEntry: spotEntry,
      spotExit: spotExit ?? this.spotExit,
      ivRankEntry: ivRankEntry,
      ivRankExit: ivRankExit ?? this.ivRankExit,
      dataMode: dataMode,
      termMode: termMode,
      termExactDte: termExactDte,
      termMinDte: termMinDte,
      termMaxDte: termMaxDte,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tradeId': tradeId,
      'positionId': positionId,
      'symbol': symbol,
      'side': side,
      'strike': strike,
      'expiryIso': expiryIso,
      'enteredAt': enteredAt.toIso8601String(),
      'exitedAt': exitedAt?.toIso8601String(),
      'dteEntry': dteEntry,
      'dteExit': dteExit,
      'entrySource': entrySource,
      'entryReasonCode': entryReasonCode,
      'entryReasonText': entryReasonText,
      'signalScore': signalScore,
      'signalDetails': signalDetails,
      'contracts': contracts,
      'entryPremium': entryPremium,
      'exitPremium': exitPremium,
      'pnlUsd': pnlUsd,
      'pnlPct': pnlPct,
      'exitReasonCode': exitReasonCode,
      'exitReasonText': exitReasonText,
      'reviewVerdict': reviewVerdict,
      'reviewNotes': reviewNotes,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'spotEntry': spotEntry,
      'spotExit': spotExit,
      'ivRankEntry': ivRankEntry,
      'ivRankExit': ivRankExit,
      'dataMode': dataMode,
      'termMode': termMode,
      'termExactDte': termExactDte,
      'termMinDte': termMinDte,
      'termMaxDte': termMaxDte,
      'updatedAt': updatedAt.toIso8601String(),
      if (exitedAt != null)
        'durationMinutes':
            exitedAt!.difference(enteredAt).inMinutes.clamp(0, 525600),
    };
  }

  factory SpxTradeJournalRecord.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v, [double fallback = 0]) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int asInt(dynamic v, [int fallback = 0]) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    DateTime? asDateTime(dynamic v, {DateTime? fallback}) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? fallback;
      return fallback;
    }

    final rawSignalDetails = json['signalDetails'];
    Map<String, dynamic> signalDetails = <String, dynamic>{};
    if (rawSignalDetails is Map<String, dynamic>) {
      signalDetails = rawSignalDetails;
    } else if (rawSignalDetails is Map) {
      signalDetails = rawSignalDetails.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    final parsedEntryReasonCode =
        (json['entryReasonCode'] as String?)?.trim() ?? 'unknown';
    final normalizedEntryReasonCode =
        SpxEntryReasonCodes.values.contains(parsedEntryReasonCode)
            ? parsedEntryReasonCode
            : (parsedEntryReasonCode.isEmpty ? 'unknown' : parsedEntryReasonCode);

    final parsedExitReasonCode = (json['exitReasonCode'] as String?)?.trim();
    final normalizedExitReasonCode = parsedExitReasonCode == null
        ? null
        : (SpxExitReasonCodes.values.contains(parsedExitReasonCode)
            ? parsedExitReasonCode
            : (parsedExitReasonCode.isEmpty ? null : parsedExitReasonCode));
    final parsedReviewVerdict = (json['reviewVerdict'] as String?)?.trim();
    final normalizedReviewVerdict = parsedReviewVerdict == null
        ? null
        : (SpxReviewVerdictCodes.values.contains(parsedReviewVerdict)
            ? parsedReviewVerdict
            : (parsedReviewVerdict.isEmpty ? null : parsedReviewVerdict));

    return SpxTradeJournalRecord(
      tradeId: (json['tradeId'] as String?) ?? '',
      positionId: (json['positionId'] as String?) ?? '',
      symbol: (json['symbol'] as String?) ?? '',
      side: (json['side'] as String?) ?? '',
      strike: asDouble(json['strike']),
      expiryIso: (json['expiryIso'] as String?) ?? '',
      enteredAt: asDateTime(json['enteredAt'], fallback: DateTime.now())!,
      exitedAt: asDateTime(json['exitedAt']),
      dteEntry: asInt(json['dteEntry']),
      dteExit: json['dteExit'] == null ? null : asInt(json['dteExit']),
      entrySource: (json['entrySource'] as String?) ?? 'unknown',
      entryReasonCode: normalizedEntryReasonCode,
      entryReasonText: (json['entryReasonText'] as String?) ?? '',
      signalScore: asInt(json['signalScore']),
      signalDetails: signalDetails,
      contracts: asInt(json['contracts'], 1),
      entryPremium: asDouble(json['entryPremium']),
      exitPremium: json['exitPremium'] == null
          ? null
          : asDouble(json['exitPremium']),
      pnlUsd: json['pnlUsd'] == null ? null : asDouble(json['pnlUsd']),
      pnlPct: json['pnlPct'] == null ? null : asDouble(json['pnlPct']),
      exitReasonCode: normalizedExitReasonCode,
      exitReasonText: json['exitReasonText'] as String?,
      reviewVerdict: normalizedReviewVerdict,
      reviewNotes: (json['reviewNotes'] as String?)?.trim(),
      reviewedAt: asDateTime(json['reviewedAt']),
      spotEntry: asDouble(json['spotEntry']),
      spotExit: json['spotExit'] == null ? null : asDouble(json['spotExit']),
      ivRankEntry: asDouble(json['ivRankEntry']),
      ivRankExit:
          json['ivRankExit'] == null ? null : asDouble(json['ivRankExit']),
      dataMode: (json['dataMode'] as String?) ?? 'simulator',
      termMode: (json['termMode'] as String?) ?? 'exact',
      termExactDte: asInt(json['termExactDte'], 7),
      termMinDte: asInt(json['termMinDte'], 5),
      termMaxDte: asInt(json['termMaxDte'], 14),
      updatedAt: asDateTime(json['updatedAt'], fallback: DateTime.now())!,
    );
  }
}

abstract class SpxTradeJournalRepository {
  Future<void> recordEntry(String userId, SpxTradeJournalRecord record);
  Future<void> recordExit(
    String userId, {
    required String tradeId,
    required DateTime exitedAt,
    required int dteExit,
    required double exitPremium,
    required double pnlUsd,
    required double pnlPct,
    required String exitReasonCode,
    required String exitReasonText,
    required double spotExit,
    required double ivRankExit,
  });
  Future<void> upsertReview(
    String userId, {
    required String tradeId,
    String? reviewVerdict,
    String? reviewNotes,
    DateTime? reviewedAt,
  });
  Future<List<SpxTradeJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    bool closedOnly = false,
    bool openOnly = false,
    DateTime? enteredFrom,
    DateTime? enteredTo,
    String? symbol,
    String? side,
    String? entrySource,
    String? exitReasonCode,
    String? reviewVerdict,
  });
}

class LocalSpxTradeJournalRepository implements SpxTradeJournalRepository {
  static const _suffix = 'spx_trade_journal_v1';
  static const _maxLocalRecords = 2000;

  String _key(String userId) => '$userId-$_suffix';

  @override
  Future<void> recordEntry(String userId, SpxTradeJournalRecord record) async {
    final records = await loadAll(userId, limit: _maxLocalRecords);
    final map = <String, SpxTradeJournalRecord>{
      for (final r in records) r.tradeId: r,
      record.tradeId: record.copyWith(updatedAt: DateTime.now()),
    };
    await _saveLocal(userId, map.values.toList());
    _journalLog(
      'Local entry upsert user=$userId trade=${record.tradeId} total=${map.length}',
    );
  }

  @override
  Future<void> recordExit(
    String userId, {
    required String tradeId,
    required DateTime exitedAt,
    required int dteExit,
    required double exitPremium,
    required double pnlUsd,
    required double pnlPct,
    required String exitReasonCode,
    required String exitReasonText,
    required double spotExit,
    required double ivRankExit,
  }) async {
    final records = await loadAll(userId, limit: _maxLocalRecords);
    var matched = false;
    final updated = records.map((r) {
      if (r.tradeId != tradeId) return r;
      matched = true;
      return r.copyWith(
        exitedAt: exitedAt,
        dteExit: dteExit,
        exitPremium: exitPremium,
        pnlUsd: pnlUsd,
        pnlPct: pnlPct,
        exitReasonCode: exitReasonCode,
        exitReasonText: exitReasonText,
        spotExit: spotExit,
        ivRankExit: ivRankExit,
        updatedAt: DateTime.now(),
      );
    }).toList();
    await _saveLocal(userId, updated);
    _journalLog(
      matched
          ? 'Local exit upsert user=$userId trade=$tradeId'
          : 'Local exit upsert missed user=$userId trade=$tradeId (not found)',
    );
  }

  @override
  Future<void> upsertReview(
    String userId, {
    required String tradeId,
    String? reviewVerdict,
    String? reviewNotes,
    DateTime? reviewedAt,
  }) async {
    final records = await loadAll(userId, limit: _maxLocalRecords);
    final cleanVerdict = reviewVerdict?.trim();
    final verdict = (cleanVerdict == null || cleanVerdict.isEmpty)
        ? null
        : cleanVerdict;
    final cleanNotes = reviewNotes?.trim();
    final notes = (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes;
    final nextReviewedAt =
        (verdict != null || notes != null) ? (reviewedAt ?? DateTime.now()) : null;

    var matched = false;
    final updated = records.map((r) {
      if (r.tradeId != tradeId) return r;
      matched = true;
      return r.copyWith(
        reviewVerdict: verdict,
        reviewNotes: notes,
        reviewedAt: nextReviewedAt,
        updatedAt: DateTime.now(),
      );
    }).toList();
    await _saveLocal(userId, updated);
    _journalLog(
      matched
          ? 'Local review upsert user=$userId trade=$tradeId verdict=${verdict ?? 'none'}'
          : 'Local review upsert missed user=$userId trade=$tradeId (not found)',
    );
  }

  @override
  Future<List<SpxTradeJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    bool closedOnly = false,
    bool openOnly = false,
    DateTime? enteredFrom,
    DateTime? enteredTo,
    String? symbol,
    String? side,
    String? entrySource,
    String? exitReasonCode,
    String? reviewVerdict,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? const <String>[];

    final records = <SpxTradeJournalRecord>[];
    for (final item in raw) {
      try {
        final parsed = jsonDecode(item) as Map<String, dynamic>;
        final record = SpxTradeJournalRecord.fromJson(parsed);
        if (record.tradeId.isNotEmpty) records.add(record);
      } catch (_) {}
    }
    records.sort((a, b) => b.enteredAt.compareTo(a.enteredAt));
    final filtered = _filterRecords(
      records,
      closedOnly: closedOnly,
      openOnly: openOnly,
      enteredFrom: enteredFrom,
      enteredTo: enteredTo,
      symbol: symbol,
      side: side,
      entrySource: entrySource,
      exitReasonCode: exitReasonCode,
      reviewVerdict: reviewVerdict,
    );
    return filtered.take(limit).toList();
  }

  Future<void> _saveLocal(
    String userId,
    List<SpxTradeJournalRecord> records,
  ) async {
    records.sort((a, b) => b.enteredAt.compareTo(a.enteredAt));
    final trimmed = records.take(_maxLocalRecords).toList();
    final payload = trimmed.map((r) => jsonEncode(r.toJson())).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), payload);
    _journalLog('Local save complete user=$userId count=${trimmed.length}');
  }

  List<SpxTradeJournalRecord> _filterRecords(
    List<SpxTradeJournalRecord> source, {
    required bool closedOnly,
    required bool openOnly,
    DateTime? enteredFrom,
    DateTime? enteredTo,
    String? symbol,
    String? side,
    String? entrySource,
    String? exitReasonCode,
    String? reviewVerdict,
  }) {
    final normalizedSymbol = symbol?.trim().toUpperCase();
    final normalizedSide = side?.trim().toLowerCase();
    final normalizedEntrySource = entrySource?.trim().toLowerCase();
    final normalizedExitReason = exitReasonCode?.trim();
    final normalizedReviewVerdict = reviewVerdict?.trim();

    return source.where((record) {
      if (closedOnly && record.exitedAt == null) return false;
      if (openOnly && record.exitedAt != null) return false;
      if (enteredFrom != null && record.enteredAt.isBefore(enteredFrom)) {
        return false;
      }
      if (enteredTo != null && record.enteredAt.isAfter(enteredTo)) {
        return false;
      }
      if (normalizedSymbol != null &&
          normalizedSymbol.isNotEmpty &&
          !record.symbol.toUpperCase().contains(normalizedSymbol)) {
        return false;
      }
      if (normalizedSide != null &&
          normalizedSide.isNotEmpty &&
          record.side.toLowerCase() != normalizedSide) {
        return false;
      }
      if (normalizedEntrySource != null &&
          normalizedEntrySource.isNotEmpty &&
          record.entrySource.toLowerCase() != normalizedEntrySource) {
        return false;
      }
      if (normalizedExitReason != null &&
          normalizedExitReason.isNotEmpty &&
          record.exitReasonCode != normalizedExitReason) {
        return false;
      }
      if (normalizedReviewVerdict != null &&
          normalizedReviewVerdict.isNotEmpty &&
          record.reviewVerdict != normalizedReviewVerdict) {
        return false;
      }
      return true;
    }).toList();
  }
}

class FirebaseSpxTradeJournalRepository extends LocalSpxTradeJournalRepository {
  final FirebaseFirestore _firestore;

  FirebaseSpxTradeJournalRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _firestore.collection('users').doc(userId).collection('spx_trade_journal');

  @override
  Future<void> recordEntry(String userId, SpxTradeJournalRecord record) async {
    await super.recordEntry(userId, record);
    try {
      await _col(userId).doc(record.tradeId).set({
        ...record.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _journalLog('Firestore entry sync ok user=$userId trade=${record.tradeId}');
    } catch (e) {
      _journalLog(
        'Firestore entry sync failed user=$userId trade=${record.tradeId} error=$e',
      );
      // keep local data if cloud write fails
    }
  }

  @override
  Future<void> recordExit(
    String userId, {
    required String tradeId,
    required DateTime exitedAt,
    required int dteExit,
    required double exitPremium,
    required double pnlUsd,
    required double pnlPct,
    required String exitReasonCode,
    required String exitReasonText,
    required double spotExit,
    required double ivRankExit,
  }) async {
    await super.recordExit(
      userId,
      tradeId: tradeId,
      exitedAt: exitedAt,
      dteExit: dteExit,
      exitPremium: exitPremium,
      pnlUsd: pnlUsd,
      pnlPct: pnlPct,
      exitReasonCode: exitReasonCode,
      exitReasonText: exitReasonText,
      spotExit: spotExit,
      ivRankExit: ivRankExit,
    );

    try {
      await _col(userId).doc(tradeId).set({
        'tradeId': tradeId,
        'exitedAt': exitedAt.toIso8601String(),
        'dteExit': dteExit,
        'exitPremium': exitPremium,
        'pnlUsd': pnlUsd,
        'pnlPct': pnlPct,
        'exitReasonCode': exitReasonCode,
        'exitReasonText': exitReasonText,
        'spotExit': spotExit,
        'ivRankExit': ivRankExit,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _journalLog('Firestore exit sync ok user=$userId trade=$tradeId');
    } catch (e) {
      _journalLog(
        'Firestore exit sync failed user=$userId trade=$tradeId error=$e',
      );
      // keep local data if cloud write fails
    }
  }

  @override
  Future<void> upsertReview(
    String userId, {
    required String tradeId,
    String? reviewVerdict,
    String? reviewNotes,
    DateTime? reviewedAt,
  }) async {
    await super.upsertReview(
      userId,
      tradeId: tradeId,
      reviewVerdict: reviewVerdict,
      reviewNotes: reviewNotes,
      reviewedAt: reviewedAt,
    );
    try {
      final cleanVerdict = reviewVerdict?.trim();
      final verdict = (cleanVerdict == null || cleanVerdict.isEmpty)
          ? null
          : cleanVerdict;
      final cleanNotes = reviewNotes?.trim();
      final notes = (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes;
      final serverPayload = <String, dynamic>{
        'reviewVerdict': verdict,
        'reviewNotes': notes,
        'reviewedAt': (verdict != null || notes != null)
            ? (reviewedAt ?? DateTime.now()).toIso8601String()
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _col(userId).doc(tradeId).set(serverPayload, SetOptions(merge: true));
      _journalLog(
        'Firestore review sync ok user=$userId trade=$tradeId verdict=${verdict ?? 'none'}',
      );
    } catch (e) {
      _journalLog(
        'Firestore review sync failed user=$userId trade=$tradeId error=$e',
      );
      // keep local data if cloud write fails
    }
  }

  @override
  Future<List<SpxTradeJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    bool closedOnly = false,
    bool openOnly = false,
    DateTime? enteredFrom,
    DateTime? enteredTo,
    String? symbol,
    String? side,
    String? entrySource,
    String? exitReasonCode,
    String? reviewVerdict,
  }) async {
    final local = await super.loadAll(
      userId,
      limit: limit,
      closedOnly: closedOnly,
      openOnly: openOnly,
      enteredFrom: enteredFrom,
      enteredTo: enteredTo,
      symbol: symbol,
      side: side,
      entrySource: entrySource,
      exitReasonCode: exitReasonCode,
      reviewVerdict: reviewVerdict,
    );
    try {
      final remoteLimit = limit < 400 ? 400 : limit.clamp(400, 2000);
      final snap = await _col(userId)
          .orderBy('enteredAt', descending: true)
          .limit(remoteLimit)
          .get();
      final remote = snap.docs
          .map((doc) => SpxTradeJournalRecord.fromJson(doc.data()))
          .where((r) => r.tradeId.isNotEmpty)
          .toList();
      if (remote.isNotEmpty) {
        final merged = <String, SpxTradeJournalRecord>{
          for (final r in local) r.tradeId: r,
          for (final r in remote) r.tradeId: r,
        }.values.toList();
        final filtered = _filterRecords(
          merged,
          closedOnly: closedOnly,
          openOnly: openOnly,
          enteredFrom: enteredFrom,
          enteredTo: enteredTo,
          symbol: symbol,
          side: side,
          entrySource: entrySource,
          exitReasonCode: exitReasonCode,
          reviewVerdict: reviewVerdict,
        )..sort((a, b) => b.enteredAt.compareTo(a.enteredAt));
        await _saveLocal(userId, merged);
        _journalLog(
          'Firestore load merged user=$userId remote=${remote.length} local=${local.length} filtered=${filtered.length}',
        );
        return filtered.take(limit).toList();
      }
      _journalLog('Firestore load no-remote user=$userId local=${local.length}');
      return local;
    } catch (e) {
      _journalLog('Firestore load fallback user=$userId error=$e');
      return local;
    }
  }
}
