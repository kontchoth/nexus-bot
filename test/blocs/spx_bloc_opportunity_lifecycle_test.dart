import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexusbot/blocs/spx/spx_bloc.dart';
import 'package:nexusbot/models/spx_models.dart';
import 'package:nexusbot/services/app_settings_repository.dart';
import 'package:nexusbot/services/spx/spx_opportunity_journal_repository.dart';
import 'package:nexusbot/services/spx/spx_options_service.dart';
import 'package:nexusbot/services/spx/spx_trade_journal_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpxBloc opportunity lifecycle', () {
    const userId = 'spx-test-user';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('manual_confirm keeps pending until user approves', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.manualConfirm,
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);

      final pending = await _waitForStatus(
        opportunities: harness.opportunities,
        userId: userId,
        status: SpxOpportunityStatus.pendingUser,
      );

      harness.bloc.add(
        ApproveSpxOpportunity(
          opportunityId: pending.opportunityId,
          symbol: pending.symbol,
        ),
      );
      final executed = await _waitForOpportunity(
        opportunities: harness.opportunities,
        userId: userId,
        opportunityId: pending.opportunityId,
        expectedStatus: SpxOpportunityStatus.executed,
      );
      expect(executed.status, SpxOpportunityStatus.executed);
      expect(executed.executedTradeId?.isNotEmpty ?? false, isTrue);
      expect(harness.bloc.state.positions, hasLength(1));
    });

    test('auto_after_delay schedules then executes after delay', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.autoAfterDelay,
        entryDelaySeconds: 2,
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      final pending = await _waitForStatus(
        opportunities: harness.opportunities,
        userId: userId,
        status: SpxOpportunityStatus.pendingDelay,
      );
      expect(pending.entryDelaySeconds, 2);

      await Future<void>.delayed(const Duration(milliseconds: 2300));
      final executed = await _waitForOpportunity(
        opportunities: harness.opportunities,
        userId: userId,
        opportunityId: pending.opportunityId,
        expectedStatus: SpxOpportunityStatus.executed,
      );
      expect(executed.status, SpxOpportunityStatus.executed);
      expect(harness.bloc.state.positions, hasLength(1));
    });

    test('manual_confirm reject logs user_rejected and stays flat', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.manualConfirm,
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      final pending = await _waitForStatus(
        opportunities: harness.opportunities,
        userId: userId,
        status: SpxOpportunityStatus.pendingUser,
      );

      harness.bloc.add(
        RejectSpxOpportunity(
          opportunityId: pending.opportunityId,
          symbol: pending.symbol,
        ),
      );

      final rejected = await _waitForOpportunity(
        opportunities: harness.opportunities,
        userId: userId,
        opportunityId: pending.opportunityId,
        expectedStatus: SpxOpportunityStatus.rejected,
      );
      expect(rejected.missedReasonCode, 'user_rejected');
      expect(rejected.userAction, 'rejected');
      expect(harness.bloc.state.positions, isEmpty);
    });

    test('auto_after_delay cancel logs delay_cancelled and stays flat',
        () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.autoAfterDelay,
        entryDelaySeconds: 2,
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      final pending = await _waitForStatus(
        opportunities: harness.opportunities,
        userId: userId,
        status: SpxOpportunityStatus.pendingDelay,
      );

      harness.bloc.add(
        CancelSpxOpportunity(
          opportunityId: pending.opportunityId,
          symbol: pending.symbol,
        ),
      );

      final missed = await _waitForOpportunity(
        opportunities: harness.opportunities,
        userId: userId,
        opportunityId: pending.opportunityId,
        expectedStatus: SpxOpportunityStatus.missed,
      );
      expect(missed.missedReasonCode, 'delay_cancelled');
      expect(missed.userAction, 'cancelled');
      expect(harness.bloc.state.positions, isEmpty);
    });

    test('auto_immediate executes without pending state', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.autoImmediate,
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      await _waitForStatus(
        opportunities: harness.opportunities,
        userId: userId,
        status: SpxOpportunityStatus.executed,
      );

      final all = await harness.opportunities.loadAll(userId, limit: 20);
      expect(
        all.where((r) => r.status == SpxOpportunityStatus.pendingUser),
        isEmpty,
      );
      expect(
        all.where((r) => r.status == SpxOpportunityStatus.pendingDelay),
        isEmpty,
      );
      final executed =
          all.firstWhere((r) => r.status == SpxOpportunityStatus.executed);
      expect(executed.executionModeAtDecision,
          SpxOpportunityExecutionMode.autoImmediate);
      expect(harness.bloc.state.positions, hasLength(1));
      expect(
        harness.bloc.state.intradayMarkers
            .map((marker) => marker.type)
            .toList(),
        containsAllInOrder([
          SpxIntradayMarkerType.signal,
          SpxIntradayMarkerType.entry,
        ]),
      );
    });

    test('auto scanner honors near OTM targeting mode', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.autoImmediate,
        contractTargetingMode: SpxContractTargetingMode.nearOtm,
        service: _StaticChainSpxOptionsService(
          spot: 5750.0,
          contracts: [
            _buildTestCallContract(
              symbol: 'CALL-ITM',
              strike: 5740,
              delta: 0.55,
            ),
            _buildTestCallContract(
              symbol: 'CALL-ATM',
              strike: 5750,
              delta: 0.33,
            ),
            _buildTestCallContract(
              symbol: 'CALL-OTM',
              strike: 5760,
              delta: 0.20,
            ),
          ],
        ),
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      await _waitFor(() => harness.bloc.state.positions.isNotEmpty);

      expect(harness.bloc.state.positions.single.contract.symbol, 'CALL-OTM');
    });

    test('auto scanner honors near ITM targeting mode', () async {
      final harness = await _buildHarness(
        userId: userId,
        executionMode: SpxOpportunityExecutionMode.autoImmediate,
        contractTargetingMode: SpxContractTargetingMode.nearItm,
        service: _StaticChainSpxOptionsService(
          spot: 5750.0,
          contracts: [
            _buildTestCallContract(
              symbol: 'CALL-ITM',
              strike: 5740,
              delta: 0.55,
            ),
            _buildTestCallContract(
              symbol: 'CALL-ATM',
              strike: 5750,
              delta: 0.33,
            ),
            _buildTestCallContract(
              symbol: 'CALL-OTM',
              strike: 5760,
              delta: 0.20,
            ),
          ],
        ),
      );
      addTearDown(harness.bloc.close);

      await _runScannerWindow(harness.bloc);
      await _waitFor(() => harness.bloc.state.positions.isNotEmpty);

      expect(harness.bloc.state.positions.single.contract.symbol, 'CALL-ITM');
    });

    test('market ticks update session levels and intraday spot series',
        () async {
      final bloc = SpxBloc(
        userId: userId,
        journalRepository: LocalSpxTradeJournalRepository(),
        opportunityJournalRepository: LocalSpxOpportunityJournalRepository(),
        autoTickEnabled: false,
        optionsService: _SequenceSpotSpxOptionsService(
          spots: const [5750.0, 5756.0, 5744.0],
          contract: _buildTestCallContract(symbol: 'SPX-INTRADAY'),
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const InitializeSpx());
      await _waitFor(() => bloc.state.chain.isNotEmpty);

      expect(bloc.state.sessionOpenPrice, 5750.0);
      expect(bloc.state.sessionHighPrice, 5750.0);
      expect(bloc.state.sessionLowPrice, 5750.0);
      expect(bloc.state.intradaySpots, hasLength(1));
      expect(bloc.state.intradaySpots.single.price, 5750.0);
      expect(bloc.state.intradayCandles, hasLength(1));
      expect(bloc.state.intradayCandles.single.open, 5750.0);
      expect(bloc.state.intradayCandles.single.high, 5750.0);
      expect(bloc.state.intradayCandles.single.low, 5750.0);
      expect(bloc.state.intradayCandles.single.close, 5750.0);
      expect(bloc.state.impliedDailyExpectedMove, isNotNull);

      bloc.add(const SpxMarketTick());
      await _waitFor(() => bloc.state.spotPrice == 5756.0);

      expect(bloc.state.sessionHighPrice, 5756.0);
      expect(bloc.state.sessionLowPrice, 5750.0);
      expect(bloc.state.intradaySpots.single.price, 5756.0);
      expect(bloc.state.intradayCandles, hasLength(1));
      expect(bloc.state.intradayCandles.single.open, 5750.0);
      expect(bloc.state.intradayCandles.single.high, 5756.0);
      expect(bloc.state.intradayCandles.single.low, 5750.0);
      expect(bloc.state.intradayCandles.single.close, 5756.0);

      bloc.add(const SpxMarketTick());
      await _waitFor(() => bloc.state.spotPrice == 5744.0);

      expect(bloc.state.sessionHighPrice, 5756.0);
      expect(bloc.state.sessionLowPrice, 5744.0);
      expect(bloc.state.intradaySpots.single.price, 5744.0);
      expect(bloc.state.intradayCandles, hasLength(1));
      expect(bloc.state.intradayCandles.single.open, 5750.0);
      expect(bloc.state.intradayCandles.single.high, 5756.0);
      expect(bloc.state.intradayCandles.single.low, 5744.0);
      expect(bloc.state.intradayCandles.single.close, 5744.0);
    });

    test('tradier credentials update rebuilds the sandbox service', () async {
      final bloc = SpxBloc(
        userId: userId,
        journalRepository: LocalSpxTradeJournalRepository(),
        opportunityJournalRepository: LocalSpxOpportunityJournalRepository(),
        autoTickEnabled: false,
        optionsServiceBuilder: ({
          String? apiToken,
          required String tradierEnvironment,
        }) {
          return _InspectableSpxOptionsService(
            token: apiToken,
            environment: tradierEnvironment,
            contract: _buildTestCallContract(symbol: 'SPX-$tradierEnvironment'),
          );
        },
      );
      addTearDown(bloc.close);

      bloc.add(const UpdateTradierCredentials(
        token: 'sandbox-token',
        environment: SpxTradierEnvironment.sandbox,
      ));

      await _waitFor(
        () =>
            bloc.state.tradierEnvironment == SpxTradierEnvironment.sandbox &&
            bloc.state.dataMode == SpxDataMode.live &&
            bloc.state.chain.isNotEmpty,
      );

      expect(bloc.state.tradierToken, 'sandbox-token');
      expect(bloc.state.spotPrice, 5711.0);
      expect(bloc.state.chain.first.symbol, 'SPX-sandbox');
    });

    test('tradier credentials update rebuilds the production service',
        () async {
      final bloc = SpxBloc(
        userId: userId,
        journalRepository: LocalSpxTradeJournalRepository(),
        opportunityJournalRepository: LocalSpxOpportunityJournalRepository(),
        autoTickEnabled: false,
        optionsServiceBuilder: ({
          String? apiToken,
          required String tradierEnvironment,
        }) {
          return _InspectableSpxOptionsService(
            token: apiToken,
            environment: tradierEnvironment,
            contract: _buildTestCallContract(symbol: 'SPX-$tradierEnvironment'),
          );
        },
      );
      addTearDown(bloc.close);

      bloc.add(const UpdateTradierCredentials(
        token: 'production-token',
        environment: SpxTradierEnvironment.production,
      ));

      await _waitFor(
        () =>
            bloc.state.tradierEnvironment == SpxTradierEnvironment.production &&
            bloc.state.dataMode == SpxDataMode.live &&
            bloc.state.chain.isNotEmpty,
      );

      expect(bloc.state.tradierToken, 'production-token');
      expect(bloc.state.spotPrice, 5811.0);
      expect(bloc.state.chain.first.symbol, 'SPX-production');
    });
  });
}

Future<void> _runScannerWindow(SpxBloc bloc) async {
  for (var i = 0; i < 10; i++) {
    bloc.add(const SpxMarketTick());
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await _drain();
}

Future<void> _drain() async {
  await Future<void>.delayed(const Duration(milliseconds: 180));
}

Future<SpxOpportunityJournalRecord> _waitForStatus({
  required LocalSpxOpportunityJournalRepository opportunities,
  required String userId,
  required String status,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final started = DateTime.now();
  while (true) {
    final all = await opportunities.loadAll(userId, limit: 20);
    for (final record in all) {
      if (record.status == status) return record;
    }
    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException('Timed out waiting for status=$status');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<SpxOpportunityJournalRecord> _waitForOpportunity({
  required LocalSpxOpportunityJournalRepository opportunities,
  required String userId,
  required String opportunityId,
  required String expectedStatus,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final started = DateTime.now();
  while (true) {
    final all = await opportunities.loadAll(userId, limit: 20);
    for (final record in all) {
      if (record.opportunityId == opportunityId &&
          record.status == expectedStatus) {
        return record;
      }
    }
    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException(
        'Timed out waiting for opportunity=$opportunityId '
        'status=$expectedStatus',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<_Harness> _buildHarness({
  required String userId,
  required String executionMode,
  String contractTargetingMode = SpxContractTargetingMode.deltaZone,
  SpxOptionsService? service,
  int entryDelaySeconds = 30,
  int validationWindowSeconds = 120,
}) async {
  final opportunities = LocalSpxOpportunityJournalRepository();
  final journal = LocalSpxTradeJournalRepository();
  final contract = _buildTestCallContract(
      symbol: 'SPX TEST ${DateTime.now().microsecondsSinceEpoch}');
  final optionsService = service ?? _FakeSpxOptionsService(contract: contract);

  final bloc = SpxBloc(
    userId: userId,
    journalRepository: journal,
    opportunityJournalRepository: opportunities,
    optionsService: optionsService,
    autoTickEnabled: false,
    scannerOverrideAction: SpxStrategyActionType.goLong,
  );

  bloc.add(const InitializeSpx());
  await _waitFor(
    () => bloc.state.chain.isNotEmpty && bloc.state.selectedExpiration != null,
  );

  bloc.add(UpdateSpxContractTargeting(contractTargetingMode));
  bloc.add(
    UpdateSpxExecutionSettings(
      executionMode: executionMode,
      entryDelaySeconds: entryDelaySeconds,
      validationWindowSeconds: validationWindowSeconds,
      maxSlippagePct: 5.0,
      notificationsEnabled: true,
    ),
  );
  bloc.add(const ToggleSpxScanner());
  await _drain();

  return _Harness(
    bloc: bloc,
    opportunities: opportunities,
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final started = DateTime.now();
  while (!condition()) {
    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException('Condition not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

OptionsContract _buildTestCallContract({
  required String symbol,
  double strike = 5750,
  double delta = 0.33,
}) {
  final now = DateTime.now();
  final expiry =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 8));
  return OptionsContract(
    symbol: symbol,
    side: OptionsSide.call,
    strike: strike,
    expiry: expiry,
    daysToExpiry: 7,
    bid: 10.0,
    ask: 10.4,
    lastPrice: 10.2,
    openInterest: 12000,
    volume: 1800,
    greeks: OptionsGreeks(
      delta: delta,
      gamma: 0.015,
      theta: -0.24,
      vega: 0.12,
    ),
    impliedVolatility: 0.18,
    ivRank: 28,
    signal: SpxSignalType.buy,
    lastUpdated: now,
  );
}

class _FakeSpxOptionsService extends SpxOptionsService {
  final OptionsContract contract;

  _FakeSpxOptionsService({
    required this.contract,
  }) : super(apiToken: null);

  @override
  bool get isMarketOpenNow => true;

  @override
  bool get isLive => false;

  @override
  Future<double> fetchSpxSpot() async => 5750.0;

  @override
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    return [_formatYmd(contract.expiry)];
  }

  @override
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    return [
      contract.copyWith(lastUpdated: DateTime.now()),
    ];
  }

  @override
  Future<List<OptionsContract>> tickPositions(
      List<OptionsContract> contracts) async {
    final now = DateTime.now();
    return contracts.map((c) => c.copyWith(lastUpdated: now)).toList();
  }
}

class _InspectableSpxOptionsService extends SpxOptionsService {
  final String? token;
  final String environment;
  final OptionsContract contract;

  _InspectableSpxOptionsService({
    required this.token,
    required this.environment,
    required this.contract,
  }) : super(
          apiToken: token,
          useSandbox: SpxTradierEnvironment.isSandbox(environment),
        );

  @override
  bool get isMarketOpenNow => true;

  @override
  bool get isLive => (token ?? '').trim().isNotEmpty;

  @override
  Future<double> fetchSpxSpot() async {
    return SpxTradierEnvironment.isSandbox(environment) ? 5711.0 : 5811.0;
  }

  @override
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    return [_formatYmd(contract.expiry)];
  }

  @override
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    return [
      contract.copyWith(lastUpdated: DateTime.now()),
    ];
  }

  @override
  Future<List<OptionsContract>> tickPositions(
      List<OptionsContract> contracts) async {
    return contracts;
  }
}

class _StaticChainSpxOptionsService extends SpxOptionsService {
  final double spot;
  final List<OptionsContract> contracts;

  _StaticChainSpxOptionsService({
    required this.spot,
    required this.contracts,
  }) : super(apiToken: null);

  @override
  bool get isMarketOpenNow => true;

  @override
  bool get isLive => false;

  @override
  Future<double> fetchSpxSpot() async => spot;

  @override
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    return [_formatYmd(contracts.first.expiry)];
  }

  @override
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    final now = DateTime.now();
    return contracts.map((c) => c.copyWith(lastUpdated: now)).toList();
  }

  @override
  Future<List<OptionsContract>> tickPositions(
      List<OptionsContract> contracts) async {
    return contracts;
  }
}

class _SequenceSpotSpxOptionsService extends SpxOptionsService {
  final List<double> spots;
  final OptionsContract contract;
  var _spotIndex = 0;

  _SequenceSpotSpxOptionsService({
    required this.spots,
    required this.contract,
  }) : super(apiToken: null);

  @override
  bool get isMarketOpenNow => true;

  @override
  bool get isLive => false;

  @override
  Future<double> fetchSpxSpot() async {
    final index = _spotIndex < spots.length ? _spotIndex : spots.length - 1;
    final value = spots[index];
    if (_spotIndex < spots.length - 1) {
      _spotIndex += 1;
    }
    return value;
  }

  @override
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    return [_formatYmd(contract.expiry)];
  }

  @override
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    return [
      contract.copyWith(lastUpdated: DateTime.now()),
    ];
  }

  @override
  Future<List<OptionsContract>> tickPositions(
      List<OptionsContract> contracts) async {
    return contracts;
  }
}

String _formatYmd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class _Harness {
  final SpxBloc bloc;
  final LocalSpxOpportunityJournalRepository opportunities;

  const _Harness({
    required this.bloc,
    required this.opportunities,
  });
}
