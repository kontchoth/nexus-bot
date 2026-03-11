import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexusbot/services/spx/spx_opportunity_journal_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSpxOpportunityJournalRepository', () {
    late LocalSpxOpportunityJournalRepository repository;
    const userId = 'user-1';
    final base = DateTime(2026, 3, 10, 12);

    SpxOpportunityJournalRecord record({
      required String id,
      required String status,
      required String symbol,
      required DateTime createdAt,
      DateTime? updatedAt,
      String? missedReasonCode,
    }) {
      return SpxOpportunityJournalRecord(
        opportunityId: id,
        createdAt: createdAt,
        updatedAt: updatedAt ?? createdAt,
        status: status,
        symbol: symbol,
        side: 'call',
        strike: 5800,
        expiryIso: DateTime(2026, 3, 20).toIso8601String(),
        dte: 10,
        premiumAtFind: 12.5,
        signalScore: 4,
        signalDetails: const {'src': 'test'},
        entryReasonCode: 'auto_scanner_signal',
        entrySource: 'auto',
        executionModeAtDecision: 'manual_confirm',
        entryDelaySeconds: 30,
        validationWindowSeconds: 120,
        missedReasonCode: missedReasonCode,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = LocalSpxOpportunityJournalRepository();
      await repository.upsert(
        userId,
        record(
          id: 'opp-1',
          status: SpxOpportunityStatus.pendingUser,
          symbol: 'SPX 01C05800000',
          createdAt: base,
        ),
      );
      await repository.upsert(
        userId,
        record(
          id: 'opp-2',
          status: SpxOpportunityStatus.missed,
          symbol: 'SPX 01P05700000',
          createdAt: base.add(const Duration(minutes: 1)),
          updatedAt: base.add(const Duration(minutes: 3)),
          missedReasonCode: 'user_timeout',
        ),
      );
      await repository.upsert(
        userId,
        record(
          id: 'opp-3',
          status: SpxOpportunityStatus.executed,
          symbol: 'SPX 01C05900000',
          createdAt: base.add(const Duration(minutes: 2)),
          updatedAt: base.add(const Duration(minutes: 4)),
        ),
      );
    });

    test('filters by status', () async {
      final pending = await repository.loadAll(
        userId,
        status: SpxOpportunityStatus.pendingUser,
      );
      expect(pending, hasLength(1));
      expect(pending.first.opportunityId, 'opp-1');
    });

    test('filters by symbol case-insensitively', () async {
      final filtered = await repository.loadAll(
        userId,
        symbol: 'p057',
      );
      expect(filtered, hasLength(1));
      expect(filtered.first.opportunityId, 'opp-2');
    });

    test('filters by created date bounds', () async {
      final filtered = await repository.loadAll(
        userId,
        createdFrom: base.add(const Duration(minutes: 1)),
        createdTo: base.add(const Duration(minutes: 2)),
      );
      expect(filtered.map((r) => r.opportunityId).toSet(), {'opp-2', 'opp-3'});
    });

    test('upsert overwrites existing opportunity by id', () async {
      await repository.upsert(
        userId,
        record(
          id: 'opp-1',
          status: SpxOpportunityStatus.executed,
          symbol: 'SPX 01C05800000',
          createdAt: base,
          updatedAt: base.add(const Duration(minutes: 10)),
        ),
      );

      final all = await repository.loadAll(userId, limit: 20);
      expect(all, hasLength(3));
      final updated = all.firstWhere((r) => r.opportunityId == 'opp-1');
      expect(updated.status, SpxOpportunityStatus.executed);
      expect(updated.updatedAt.isAfter(base.add(const Duration(minutes: 9))),
          isTrue);
    });
  });

  group('SpxOpportunityStatus.normalize', () {
    test('returns known status as-is', () {
      expect(
        SpxOpportunityStatus.normalize(SpxOpportunityStatus.pendingDelay),
        SpxOpportunityStatus.pendingDelay,
      );
    });

    test('falls back to found for unknown values', () {
      expect(SpxOpportunityStatus.normalize('bad_status'),
          SpxOpportunityStatus.found);
      expect(SpxOpportunityStatus.normalize(null), SpxOpportunityStatus.found);
    });
  });
}
