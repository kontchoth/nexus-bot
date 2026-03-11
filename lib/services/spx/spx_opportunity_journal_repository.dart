import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _opportunityLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[SPX-OPPORTUNITY] $message');
}

class SpxOpportunityStatus {
  static const found = 'found';
  static const alerted = 'alerted';
  static const pendingUser = 'pending_user';
  static const pendingDelay = 'pending_delay';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const executed = 'executed';
  static const missed = 'missed';

  static const values = <String>{
    found,
    alerted,
    pendingUser,
    pendingDelay,
    approved,
    rejected,
    executed,
    missed,
  };

  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    return values.contains(value) ? value : found;
  }
}

class SpxOpportunityJournalRecord {
  final String opportunityId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;

  final String symbol;
  final String side;
  final double strike;
  final String expiryIso;
  final int dte;
  final double premiumAtFind;

  final int signalScore;
  final Map<String, dynamic> signalDetails;
  final String entryReasonCode;
  final String entrySource;

  final String executionModeAtDecision;
  final int entryDelaySeconds;
  final int validationWindowSeconds;

  final DateTime? notificationSentAt;
  final String? userAction;
  final DateTime? userActionAt;

  final String? executedTradeId;
  final String? missedReasonCode;

  const SpxOpportunityJournalRecord({
    required this.opportunityId,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.symbol,
    required this.side,
    required this.strike,
    required this.expiryIso,
    required this.dte,
    required this.premiumAtFind,
    required this.signalScore,
    required this.signalDetails,
    required this.entryReasonCode,
    required this.entrySource,
    required this.executionModeAtDecision,
    required this.entryDelaySeconds,
    required this.validationWindowSeconds,
    this.notificationSentAt,
    this.userAction,
    this.userActionAt,
    this.executedTradeId,
    this.missedReasonCode,
  });

  SpxOpportunityJournalRecord copyWith({
    DateTime? updatedAt,
    String? status,
    DateTime? notificationSentAt,
    String? userAction,
    DateTime? userActionAt,
    String? executedTradeId,
    String? missedReasonCode,
  }) {
    return SpxOpportunityJournalRecord(
      opportunityId: opportunityId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      symbol: symbol,
      side: side,
      strike: strike,
      expiryIso: expiryIso,
      dte: dte,
      premiumAtFind: premiumAtFind,
      signalScore: signalScore,
      signalDetails: signalDetails,
      entryReasonCode: entryReasonCode,
      entrySource: entrySource,
      executionModeAtDecision: executionModeAtDecision,
      entryDelaySeconds: entryDelaySeconds,
      validationWindowSeconds: validationWindowSeconds,
      notificationSentAt: notificationSentAt ?? this.notificationSentAt,
      userAction: userAction ?? this.userAction,
      userActionAt: userActionAt ?? this.userActionAt,
      executedTradeId: executedTradeId ?? this.executedTradeId,
      missedReasonCode: missedReasonCode ?? this.missedReasonCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'opportunityId': opportunityId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status,
      'symbol': symbol,
      'side': side,
      'strike': strike,
      'expiryIso': expiryIso,
      'dte': dte,
      'premiumAtFind': premiumAtFind,
      'signalScore': signalScore,
      'signalDetails': signalDetails,
      'entryReasonCode': entryReasonCode,
      'entrySource': entrySource,
      'executionModeAtDecision': executionModeAtDecision,
      'entryDelaySeconds': entryDelaySeconds,
      'validationWindowSeconds': validationWindowSeconds,
      'notificationSentAt': notificationSentAt?.toIso8601String(),
      'userAction': userAction,
      'userActionAt': userActionAt?.toIso8601String(),
      'executedTradeId': executedTradeId,
      'missedReasonCode': missedReasonCode,
    };
  }

  factory SpxOpportunityJournalRecord.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, [int fallback = 0]) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    double asDouble(dynamic v, [double fallback = 0]) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    DateTime? asDateTime(dynamic v, {DateTime? fallback}) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? fallback;
      return fallback;
    }

    final rawSignalDetails = json['signalDetails'];
    Map<String, dynamic> signalDetails = const <String, dynamic>{};
    if (rawSignalDetails is Map<String, dynamic>) {
      signalDetails = rawSignalDetails;
    } else if (rawSignalDetails is Map) {
      signalDetails = rawSignalDetails.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return SpxOpportunityJournalRecord(
      opportunityId: (json['opportunityId'] as String?) ?? '',
      createdAt: asDateTime(json['createdAt'], fallback: DateTime.now())!,
      updatedAt: asDateTime(json['updatedAt'], fallback: DateTime.now())!,
      status: SpxOpportunityStatus.normalize(json['status'] as String?),
      symbol: (json['symbol'] as String?) ?? '',
      side: (json['side'] as String?) ?? '',
      strike: asDouble(json['strike']),
      expiryIso: (json['expiryIso'] as String?) ?? '',
      dte: asInt(json['dte']),
      premiumAtFind: asDouble(json['premiumAtFind']),
      signalScore: asInt(json['signalScore']),
      signalDetails: signalDetails,
      entryReasonCode: (json['entryReasonCode'] as String?) ?? 'unknown',
      entrySource: (json['entrySource'] as String?) ?? 'unknown',
      executionModeAtDecision:
          (json['executionModeAtDecision'] as String?) ?? 'manual_confirm',
      entryDelaySeconds: asInt(json['entryDelaySeconds']),
      validationWindowSeconds: asInt(json['validationWindowSeconds'], 120),
      notificationSentAt: asDateTime(json['notificationSentAt']),
      userAction: (json['userAction'] as String?)?.trim(),
      userActionAt: asDateTime(json['userActionAt']),
      executedTradeId: (json['executedTradeId'] as String?)?.trim(),
      missedReasonCode: (json['missedReasonCode'] as String?)?.trim(),
    );
  }
}

abstract class SpxOpportunityJournalRepository {
  Future<void> upsert(String userId, SpxOpportunityJournalRecord record);
  Future<List<SpxOpportunityJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    String? status,
    String? symbol,
    DateTime? createdFrom,
    DateTime? createdTo,
  });
}

class LocalSpxOpportunityJournalRepository
    implements SpxOpportunityJournalRepository {
  static const _suffix = 'spx_opportunity_journal_v1';
  static const _maxLocalRecords = 2500;

  String _key(String userId) => '$userId-$_suffix';

  @override
  Future<void> upsert(String userId, SpxOpportunityJournalRecord record) async {
    final records = await loadAll(userId, limit: _maxLocalRecords);
    final merged = <String, SpxOpportunityJournalRecord>{
      for (final item in records) item.opportunityId: item,
      record.opportunityId: record.copyWith(
        status: SpxOpportunityStatus.normalize(record.status),
        updatedAt: DateTime.now(),
      ),
    }.values.toList();

    await _saveLocal(userId, merged);
    _opportunityLog(
      'Local upsert user=$userId opportunity=${record.opportunityId} total=${merged.length}',
    );
  }

  @override
  Future<List<SpxOpportunityJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    String? status,
    String? symbol,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? const <String>[];

    final records = <SpxOpportunityJournalRecord>[];
    for (final item in raw) {
      try {
        final parsed = jsonDecode(item) as Map<String, dynamic>;
        final record = SpxOpportunityJournalRecord.fromJson(parsed);
        if (record.opportunityId.isNotEmpty) records.add(record);
      } catch (_) {}
    }

    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = _filterRecords(
      records,
      status: status,
      symbol: symbol,
      createdFrom: createdFrom,
      createdTo: createdTo,
    );
    return filtered.take(limit).toList();
  }

  Future<void> _saveLocal(
    String userId,
    List<SpxOpportunityJournalRecord> records,
  ) async {
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final trimmed = records.take(_maxLocalRecords).toList();
    final payload = trimmed.map((r) => jsonEncode(r.toJson())).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), payload);
    _opportunityLog('Local save complete user=$userId count=${trimmed.length}');
  }

  List<SpxOpportunityJournalRecord> _filterRecords(
    List<SpxOpportunityJournalRecord> source, {
    String? status,
    String? symbol,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) {
    final normalizedStatus = status?.trim();
    final normalizedSymbol = symbol?.trim().toUpperCase();

    return source.where((record) {
      if (normalizedStatus != null &&
          normalizedStatus.isNotEmpty &&
          record.status != normalizedStatus) {
        return false;
      }
      if (normalizedSymbol != null &&
          normalizedSymbol.isNotEmpty &&
          !record.symbol.toUpperCase().contains(normalizedSymbol)) {
        return false;
      }
      if (createdFrom != null && record.createdAt.isBefore(createdFrom)) {
        return false;
      }
      if (createdTo != null && record.createdAt.isAfter(createdTo)) {
        return false;
      }
      return true;
    }).toList();
  }
}

class FirebaseSpxOpportunityJournalRepository
    extends LocalSpxOpportunityJournalRepository {
  final FirebaseFirestore _firestore;

  FirebaseSpxOpportunityJournalRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('spx_opportunity_journal');

  @override
  Future<void> upsert(String userId, SpxOpportunityJournalRecord record) async {
    await super.upsert(userId, record);
    try {
      await _col(userId).doc(record.opportunityId).set({
        ...record.toJson(),
        'status': SpxOpportunityStatus.normalize(record.status),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _opportunityLog(
        'Firestore upsert ok user=$userId opportunity=${record.opportunityId}',
      );
    } catch (e) {
      _opportunityLog(
        'Firestore upsert failed user=$userId opportunity=${record.opportunityId} error=$e',
      );
      // Keep local data when cloud write fails.
    }
  }

  @override
  Future<List<SpxOpportunityJournalRecord>> loadAll(
    String userId, {
    int limit = 500,
    String? status,
    String? symbol,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) async {
    final local = await super.loadAll(
      userId,
      limit: limit,
      status: status,
      symbol: symbol,
      createdFrom: createdFrom,
      createdTo: createdTo,
    );
    try {
      final remoteLimit = limit < 400 ? 400 : limit.clamp(400, 2500);
      final snap = await _col(userId)
          .orderBy('createdAt', descending: true)
          .limit(remoteLimit)
          .get();
      final remote = snap.docs
          .map((doc) => SpxOpportunityJournalRecord.fromJson(doc.data()))
          .where((record) => record.opportunityId.isNotEmpty)
          .toList();

      if (remote.isNotEmpty) {
        final merged = <String, SpxOpportunityJournalRecord>{
          for (final record in local) record.opportunityId: record,
          for (final record in remote) record.opportunityId: record,
        }.values.toList();
        await _saveLocal(userId, merged);
        final filtered = _filterRecords(
          merged,
          status: status,
          symbol: symbol,
          createdFrom: createdFrom,
          createdTo: createdTo,
        )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _opportunityLog(
          'Firestore load merged user=$userId remote=${remote.length} local=${local.length} filtered=${filtered.length}',
        );
        return filtered.take(limit).toList();
      }
      _opportunityLog(
          'Firestore load no-remote user=$userId local=${local.length}');
      return local;
    } catch (e) {
      _opportunityLog('Firestore load fallback user=$userId error=$e');
      return local;
    }
  }
}
