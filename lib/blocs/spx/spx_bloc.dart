import 'dart:async';
import 'dart:math' as math;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/spx_models.dart';
import '../../services/app_settings_repository.dart';
import '../../services/spx/spx_greeks_calculator.dart';
import '../../services/spx/spx_options_service.dart';
import '../../services/spx/spx_options_simulator.dart';
import '../../services/spx/spx_opportunity_journal_repository.dart';
import '../../services/spx/spx_trade_journal_codes.dart';
import '../../services/spx/spx_trade_journal_repository.dart';

part 'spx_event.dart';
part 'spx_state.dart';

const _uuid = Uuid();

typedef SpxOptionsServiceBuilder = SpxOptionsService Function({
  String? apiToken,
  required String tradierEnvironment,
});

SpxOptionsService _buildSpxOptionsService({
  String? apiToken,
  required String tradierEnvironment,
}) {
  return SpxOptionsService(
    apiToken: apiToken,
    useSandbox: SpxTradierEnvironment.isSandbox(tradierEnvironment),
    enforceMarketHours: false,
  );
}

List<OptionsContract> orderSpxContractsForTargeting(
  Iterable<OptionsContract> contracts, {
  required double spot,
  required String targetingMode,
}) {
  final normalizedMode = SpxContractTargetingMode.normalize(targetingMode);
  final sorted = contracts.toList()
    ..sort((a, b) {
      final rankCompare = _targetingRank(a, spot, normalizedMode)
          .compareTo(_targetingRank(b, spot, normalizedMode));
      if (rankCompare != 0) return rankCompare;

      final distanceCompare = a
          .strikeDistanceFromSpot(spot)
          .compareTo(b.strikeDistanceFromSpot(spot));
      if (distanceCompare != 0) return distanceCompare;

      final deltaCompare =
          _deltaDistanceFromTarget(a).compareTo(_deltaDistanceFromTarget(b));
      if (deltaCompare != 0) return deltaCompare;

      final volumeCompare = b.volume.compareTo(a.volume);
      if (volumeCompare != 0) return volumeCompare;

      final oiCompare = b.openInterest.compareTo(a.openInterest);
      if (oiCompare != 0) return oiCompare;

      return a.symbol.compareTo(b.symbol);
    });
  return sorted;
}

List<OptionsContract> matchingSpxContractsForTargeting(
  Iterable<OptionsContract> contracts, {
  required double spot,
  required String targetingMode,
}) {
  final normalizedMode = SpxContractTargetingMode.normalize(targetingMode);
  return contracts
      .where(
          (contract) => _matchesTargetingMode(contract, spot, normalizedMode))
      .toList();
}

bool _matchesTargetingMode(
  OptionsContract contract,
  double spot,
  String targetingMode,
) {
  final moneyness = contract.moneynessForSpot(spot);
  return switch (SpxContractTargetingMode.normalize(targetingMode)) {
    SpxContractTargetingMode.atm => moneyness == SpxContractMoneyness.atm,
    SpxContractTargetingMode.nearItm => contract.isNearItmForSpot(spot),
    SpxContractTargetingMode.nearOtm => contract.isNearOtmForSpot(spot),
    SpxContractTargetingMode.atmOrNearItm =>
      moneyness == SpxContractMoneyness.atm || contract.isNearItmForSpot(spot),
    _ => contract.isTargetDelta,
  };
}

int _targetingRank(
  OptionsContract contract,
  double spot,
  String targetingMode,
) {
  final moneyness = contract.moneynessForSpot(spot);
  return switch (SpxContractTargetingMode.normalize(targetingMode)) {
    SpxContractTargetingMode.atm =>
      moneyness == SpxContractMoneyness.atm ? 0 : 1,
    SpxContractTargetingMode.nearItm => contract.isNearItmForSpot(spot)
        ? 0
        : (moneyness == SpxContractMoneyness.atm ? 1 : 2),
    SpxContractTargetingMode.nearOtm => contract.isNearOtmForSpot(spot)
        ? 0
        : (moneyness == SpxContractMoneyness.atm ? 1 : 2),
    SpxContractTargetingMode.atmOrNearItm =>
      moneyness == SpxContractMoneyness.atm
          ? 0
          : (contract.isNearItmForSpot(spot) ? 1 : 2),
    _ => contract.isTargetDelta ? 0 : 1,
  };
}

double _deltaDistanceFromTarget(OptionsContract contract) {
  return (contract.greeks.delta.abs() - 0.33).abs();
}

class SpxBloc extends Bloc<SpxEvent, SpxState> {
  static const int _maxAutoPositions = 6;
  static const double _maxAutoPerTradeNotional = 2500; // premium dollars
  static const double _maxAutoPortfolioNotional = 12000; // premium dollars
  static const int _maxAutoPerSide = 4;
  static const int _maxAutoPerDteBucket = 2;
  static const Duration _maxExecutionQuoteAge = Duration(seconds: 90);
  static const int _maxIntradaySpotSamples = 390;
  static const int _maxIntradayMarkers = 24;

  Timer? _tickTimer;
  int _tickCount = 0;
  bool _tickInFlight = false;
  bool _chainRefreshInFlight = false;
  DateTime? _sessionStartAt;
  double? _sessionOpenPrice;
  double? _sessionReferencePrice;
  double? _sessionHighPrice;
  double? _sessionLowPrice;
  double? _minute14High;
  double? _minute14Low;
  final List<double> _spotTape = <double>[];
  final List<SpxSpotSample> _intradaySpots = <SpxSpotSample>[];
  final List<SpxCandleSample> _intradayCandles = <SpxCandleSample>[];
  final List<SpxIntradayMarker> _intradayMarkers = <SpxIntradayMarker>[];
  SpxStrategyActionType? _lastStrategyAction;
  String _executionMode = SpxOpportunityExecutionMode.manualConfirm;
  int _entryDelaySeconds = 30;
  int _validationWindowSeconds = 120;
  double _maxSlippagePct = 5.0;
  bool _notificationsEnabled = true;
  final Map<String, String> _pendingOpportunityBySymbol = <String, String>{};
  final Map<String, Timer> _pendingOpportunityTimers = <String, Timer>{};
  final Map<String, OptionsContract> _pendingOpportunityContracts =
      <String, OptionsContract>{};
  final Map<String, String> _pendingOpportunityStatusById = <String, String>{};
  final Map<String, DateTime> _opportunityCreatedAtById = <String, DateTime>{};
  final Map<String, Future<void>> _opportunityPersistQueue =
      <String, Future<void>>{};
  final bool _autoTickEnabled;
  final SpxStrategyActionType? _scannerOverrideAction;
  final SpxOptionsServiceBuilder _optionsServiceBuilder;

  SpxOptionsService _service;
  final SpxOptionsSimulator _sim = SpxOptionsSimulator();
  final SpxTradeJournalRepository _journal;
  final SpxOpportunityJournalRepository _opportunities;
  final String _userId;

  // Alert stream (mirrors CryptoBloc pattern)
  final _alertController = StreamController<TradeAlert>.broadcast();
  Stream<TradeAlert> get alertsStream => _alertController.stream;

  SpxBloc({
    String? tradierToken,
    String tradierEnvironment = SpxTradierEnvironment.production,
    required String userId,
    SpxTradeJournalRepository? journalRepository,
    SpxOpportunityJournalRepository? opportunityJournalRepository,
    SpxOptionsService? optionsService,
    SpxOptionsServiceBuilder? optionsServiceBuilder,
    bool autoTickEnabled = true,
    SpxStrategyActionType? scannerOverrideAction,
  })  : _optionsServiceBuilder =
            optionsServiceBuilder ?? _buildSpxOptionsService,
        _service = optionsService ??
            (optionsServiceBuilder ?? _buildSpxOptionsService)(
              apiToken: tradierToken,
              tradierEnvironment: tradierEnvironment,
            ),
        _journal = journalRepository ?? FirebaseSpxTradeJournalRepository(),
        _opportunities = opportunityJournalRepository ??
            FirebaseSpxOpportunityJournalRepository(),
        _userId = userId,
        _autoTickEnabled = autoTickEnabled,
        _scannerOverrideAction = scannerOverrideAction,
        super(SpxState.initial(
          tradierToken: tradierToken,
          tradierEnvironment: tradierEnvironment,
        )) {
    on<InitializeSpx>(_onInitialize);
    on<SpxMarketTick>(_onMarketTick);
    on<RefreshSpxChain>(_onRefreshChain);
    on<SelectExpiration>(_onSelectExpiration);
    on<SelectSpxContract>(_onSelectContract);
    on<BuySpxContract>(_onBuy);
    on<ApproveSpxOpportunity>(_onApproveOpportunity);
    on<RejectSpxOpportunity>(_onRejectOpportunity);
    on<CancelSpxOpportunity>(_onCancelOpportunity);
    on<CloseSpxPosition>(_onClose);
    on<ToggleSpxScanner>(_onToggleScanner);
    on<UpdateTradierCredentials>(_onUpdateTradierCredentials);
    on<UpdateSpxExecutionSettings>(_onUpdateExecutionSettings);
    on<UpdateSpxContractTargeting>(_onUpdateContractTargeting);
    on<UpdateSpxTermFilter>(_onUpdateTermFilter);
    on<ResetSpxDay>(_onResetDay);
    on<_ExecutePendingOpportunity>(_onExecutePendingOpportunity);
    on<_ExpirePendingOpportunity>(_onExpirePendingOpportunity);
    on<_SpxAddLog>((event, emit) {
      final newLogs = [event.log, ...state.logs].take(80).toList();
      emit(state.copyWith(logs: newLogs));
    });
  }

  // ── Handlers ────────────────────────────────────────────────────────────────

  Future<void> _onInitialize(
    InitializeSpx event,
    Emitter<SpxState> emit,
  ) async {
    _addLog('⚡ SPX Options module initializing…', TradeLogType.system);

    // Load expirations
    final expirations = await _service.fetchExpirations();
    final filteredExp = _filterExpirationsByTerm(expirations, state.termFilter);
    final selectedExp = filteredExp.isNotEmpty ? filteredExp.first : null;
    if (selectedExp == null && state.termFilter.mode == SpxTermMode.exact) {
      _addLog(
        '⚠️ No expiration available for ${state.termFilter.exactDte}DTE',
        TradeLogType.warn,
      );
    }

    // Load chain for first expiration
    final chain = selectedExp != null
        ? await _service.fetchChain(expiration: selectedExp)
        : (state.termFilter.mode == SpxTermMode.exact
            ? <OptionsContract>[]
            : _sim.refreshChain(dteDays: _simDteDays(state.termFilter)));

    final spot = await _service.fetchSpxSpot();
    _resetSessionTracking(spot);

    // GEX snapshot
    final gexData = SpxGreeksCalculator.calcGex(chain, spot);
    final strategySnapshot = _buildStrategySnapshot(
      spot: spot,
      chain: chain,
      gexData: gexData,
    );

    final mode = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;
    final marketOpenNow = _service.isMarketOpenNow;

    emit(state.copyWith(
      chain: chain,
      expirations: expirations,
      selectedExpiration: selectedExp,
      spotPrice: spot,
      isMarketOpen: marketOpenNow,
      intradaySpots: List<SpxSpotSample>.from(_intradaySpots),
      intradayCandles: List<SpxCandleSample>.from(_intradayCandles),
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
      sessionStartedAt: _sessionStartAt,
      sessionOpenPrice: _sessionOpenPrice,
      sessionHighPrice: _sessionHighPrice,
      sessionLowPrice: _sessionLowPrice,
      gexData: gexData,
      strategySnapshot: strategySnapshot,
      dataMode: mode,
    ));
    _logStrategyActionChange(strategySnapshot);

    _addLog(
      _service.isLive
          ? '📡 Connected to Tradier ${state.tradierEnvironmentLabel} feed'
          : '📡 Running in simulation mode '
              '(set Tradier ${state.tradierEnvironmentLabel} token in Settings)',
      TradeLogType.system,
    );
    _addLog(
      '🎯 GEX: ${gexData.netGex.toStringAsFixed(2)}B  '
      '| Gamma Wall: \$${gexData.gammaWall?.toStringAsFixed(0) ?? '—'}  '
      '| Put Wall: \$${gexData.putWall?.toStringAsFixed(0) ?? '—'}',
      TradeLogType.info,
    );

    if (_autoTickEnabled) {
      _startTimer();
    }
  }

  Future<void> _onMarketTick(
    SpxMarketTick event,
    Emitter<SpxState> emit,
  ) async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      _tickCount++;

      // Refresh chain every 50 ticks (~1 min at 1.2 s/tick)
      if (_tickCount % 50 == 0 && !_chainRefreshInFlight) {
        add(const RefreshSpxChain());
      }

      // Tick open positions
      final updatedContracts = await _service.tickPositions(
        state.positions.map((p) => p.contract).toList(),
      );

      final updatedPositions = state.positions.map((pos) {
        try {
          final updated = updatedContracts
              .firstWhere((c) => c.symbol == pos.contract.symbol);
          return pos.copyWith(
            currentPremium: updated.midPrice,
            contract: updated,
          );
        } catch (_) {
          return pos;
        }
      }).toList();
      final spot = await _service.fetchSpxSpot();
      final gexData = SpxGreeksCalculator.calcGex(state.chain, spot);
      final strategySnapshot = _buildStrategySnapshot(
        spot: spot,
        chain: state.chain,
        gexData: gexData,
      );
      final marketOpenNow = _service.isMarketOpenNow;

      // ── SL / TP sweep ──────────────────────────────────────────────────────
      final surviving = <SpxPosition>[];
      var realizedPnL = state.realizedPnL;
      var totalTrades = state.totalTrades;
      var winTrades = state.winTrades;

      for (final pos in updatedPositions) {
        if (pos.isStopLossHit) {
          final pnl = pos.unrealizedPnL;
          _recordExit(
            pos,
            exitReasonCode: SpxExitReasonCodes.stopLoss,
            exitReasonText: 'Position hit stop-loss threshold.',
            pnlUsd: pnl,
          );
          _recordIntradayMarker(
            timestamp: DateTime.now(),
            spot: spot,
            type: SpxIntradayMarkerType.exit,
            label: 'OUT',
            symbol: pos.contract.symbol,
            side: pos.contract.side,
          );
          _addLog(
            '🛑 STOP-LOSS ${pos.contract.symbol} — PnL: \$${pnl.toStringAsFixed(2)}',
            TradeLogType.loss,
          );
          _emitAlert(
            title: 'Stop-Loss Triggered',
            message: '${pos.contract.symbol} · ${pos.contract.daysToExpiry}DTE',
            type: TradeLogType.loss,
          );
          realizedPnL += pnl;
          totalTrades++;
        } else if (pos.isTakeProfitHit) {
          final pnl = pos.unrealizedPnL;
          _recordExit(
            pos,
            exitReasonCode: SpxExitReasonCodes.takeProfit,
            exitReasonText: 'Position hit take-profit threshold.',
            pnlUsd: pnl,
          );
          _recordIntradayMarker(
            timestamp: DateTime.now(),
            spot: spot,
            type: SpxIntradayMarkerType.exit,
            label: 'OUT',
            symbol: pos.contract.symbol,
            side: pos.contract.side,
          );
          _addLog(
            '🎯 TAKE-PROFIT ${pos.contract.symbol} — PnL: +\$${pnl.toStringAsFixed(2)}',
            TradeLogType.win,
          );
          _emitAlert(
            title: 'Take-Profit Hit',
            message:
                '${pos.contract.symbol} · +${pos.pnlPercent.toStringAsFixed(1)}%',
            type: TradeLogType.win,
          );
          realizedPnL += pnl;
          totalTrades++;
          winTrades++;
        } else if (pos.isExpired) {
          _recordExit(
            pos,
            exitReasonCode: SpxExitReasonCodes.expired,
            exitReasonText: 'Contract reached expiry.',
            pnlUsd: pos.unrealizedPnL,
          );
          _recordIntradayMarker(
            timestamp: DateTime.now(),
            spot: spot,
            type: SpxIntradayMarkerType.exit,
            label: 'OUT',
            symbol: pos.contract.symbol,
            side: pos.contract.side,
          );
          _addLog(
            '⏱ EXPIRED ${pos.contract.symbol} — position closed at expiry',
            TradeLogType.warn,
          );
          realizedPnL += pos.unrealizedPnL;
          totalTrades++;
        } else {
          surviving.add(pos);
        }
      }

      // DTE warning
      for (final pos in surviving) {
        if (pos.isDteWarning && _tickCount % 50 == 1) {
          _addLog(
            '⚠️ DTE WARNING ${pos.contract.symbol} — ${pos.contract.daysToExpiry} days left',
            TradeLogType.warn,
          );
        }
      }

      // Auto-scanner: open new positions when scanner is active
      if (state.scannerStatus == SpxScannerStatus.active &&
          _tickCount % 10 == 0) {
        final (newPositions, newRealized, newTotal, newWins) = _runScanner(
          surviving,
          state.chain,
          spot,
          realizedPnL,
          totalTrades,
          winTrades,
          strategySnapshot,
        );
        surviving
          ..clear()
          ..addAll(newPositions);
        realizedPnL = newRealized;
        totalTrades = newTotal;
        winTrades = newWins;
      }

      emit(state.copyWith(
        positions: surviving,
        spotPrice: spot,
        isMarketOpen: marketOpenNow,
        intradaySpots: List<SpxSpotSample>.from(_intradaySpots),
        intradayCandles: List<SpxCandleSample>.from(_intradayCandles),
        intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
        sessionStartedAt: _sessionStartAt,
        sessionOpenPrice: _sessionOpenPrice,
        sessionHighPrice: _sessionHighPrice,
        sessionLowPrice: _sessionLowPrice,
        gexData: gexData,
        strategySnapshot: strategySnapshot,
        realizedPnL: realizedPnL,
        totalTrades: totalTrades,
        winTrades: winTrades,
      ));
      _logStrategyActionChange(strategySnapshot);
    } finally {
      _tickInFlight = false;
    }
  }

  Future<void> _onRefreshChain(
    RefreshSpxChain event,
    Emitter<SpxState> emit,
  ) async {
    if (_chainRefreshInFlight) return;
    _chainRefreshInFlight = true;
    try {
      final exp = state.selectedExpiration;
      final fallbackExp =
          state.termExpirations.isNotEmpty ? state.termExpirations.first : null;
      final selectedExp = exp ?? fallbackExp;
      final chain = selectedExp != null
          ? await _service.fetchChain(expiration: selectedExp)
          : (state.termFilter.mode == SpxTermMode.exact
              ? <OptionsContract>[]
              : _sim.refreshChain(dteDays: _simDteDays(state.termFilter)));
      final spot = await _service.fetchSpxSpot();
      final gex = SpxGreeksCalculator.calcGex(chain, spot);
      final strategySnapshot = _buildStrategySnapshot(
        spot: spot,
        chain: chain,
        gexData: gex,
      );
      final mode = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;
      final marketOpenNow = _service.isMarketOpenNow;
      emit(state.copyWith(
        chain: chain,
        spotPrice: spot,
        isMarketOpen: marketOpenNow,
        intradaySpots: List<SpxSpotSample>.from(_intradaySpots),
        intradayCandles: List<SpxCandleSample>.from(_intradayCandles),
        intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
        sessionStartedAt: _sessionStartAt,
        sessionOpenPrice: _sessionOpenPrice,
        sessionHighPrice: _sessionHighPrice,
        sessionLowPrice: _sessionLowPrice,
        gexData: gex,
        strategySnapshot: strategySnapshot,
        dataMode: mode,
        selectedExpiration: selectedExp,
      ));
      _logStrategyActionChange(strategySnapshot);
    } finally {
      _chainRefreshInFlight = false;
    }
  }

  Future<void> _onSelectExpiration(
    SelectExpiration event,
    Emitter<SpxState> emit,
  ) async {
    emit(state.copyWith(selectedExpiration: event.expiration));
    final chain = await _service.fetchChain(expiration: event.expiration);
    final spot = await _service.fetchSpxSpot();
    final gex = SpxGreeksCalculator.calcGex(chain, spot);
    final strategySnapshot = _buildStrategySnapshot(
      spot: spot,
      chain: chain,
      gexData: gex,
    );
    final marketOpenNow = _service.isMarketOpenNow;
    emit(state.copyWith(
      chain: chain,
      spotPrice: spot,
      isMarketOpen: marketOpenNow,
      intradaySpots: List<SpxSpotSample>.from(_intradaySpots),
      intradayCandles: List<SpxCandleSample>.from(_intradayCandles),
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
      sessionStartedAt: _sessionStartAt,
      sessionOpenPrice: _sessionOpenPrice,
      sessionHighPrice: _sessionHighPrice,
      sessionLowPrice: _sessionLowPrice,
      gexData: gex,
      strategySnapshot: strategySnapshot,
    ));
    _logStrategyActionChange(strategySnapshot);
    _addLog('📅 Expiration: ${event.expiration}', TradeLogType.info);
  }

  void _onSelectContract(SelectSpxContract event, Emitter<SpxState> emit) {
    emit(state.copyWith(
      selectedSymbol: event.symbol,
      clearSelectedSymbol: event.symbol == null,
    ));
  }

  void _onBuy(BuySpxContract event, Emitter<SpxState> emit) {
    if (state.positions.any((p) => p.contract.symbol == event.symbol)) {
      _addLog('⚠️ Already holding ${event.symbol}', TradeLogType.warn);
      return;
    }
    final contract = state.chain
        .cast<OptionsContract?>()
        .firstWhere((c) => c!.symbol == event.symbol, orElse: () => null);
    if (contract == null) {
      _addLog(
          '⚠️ Contract ${event.symbol} not found in chain', TradeLogType.warn);
      return;
    }
    if (contract.midPrice <= 0) {
      _addLog('⚠️ Invalid price for ${event.symbol}', TradeLogType.warn);
      return;
    }

    final pos = SpxPosition(
      id: _uuid.v4(),
      contract: contract,
      contracts: event.contracts,
      entryPremium: contract.midPrice,
      currentPremium: contract.midPrice,
      openedAt: DateTime.now(),
    );
    _recordIntradayMarker(
      timestamp: pos.openedAt,
      spot: state.spotPrice,
      type: SpxIntradayMarkerType.entry,
      label: 'BUY',
      symbol: contract.symbol,
      side: contract.side,
    );

    _addLog(
      '🟢 BUY ${event.contracts}× ${contract.symbol} @ \$${contract.midPrice.toStringAsFixed(2)}'
      ' | Δ${contract.greeks.delta.toStringAsFixed(2)} | ${contract.daysToExpiry}DTE',
      TradeLogType.buy,
    );
    _emitAlert(
      title: 'SPX Buy',
      message: '${contract.symbol} · \$${contract.midPrice.toStringAsFixed(2)}',
      type: TradeLogType.buy,
    );
    final pendingOpportunityId = _pendingOpportunityBySymbol[contract.symbol];
    if (pendingOpportunityId != null) {
      _recordOpportunityLifecycle(
        opportunityId: pendingOpportunityId,
        contract: contract,
        status: SpxOpportunityStatus.approved,
        entrySource: 'manual',
        entryReasonCode: SpxEntryReasonCodes.manualBuy,
        userAction: 'approved',
        userActionAt: DateTime.now(),
      );
    }
    _recordEntry(
      pos,
      entrySource: 'manual', // free-form source bucket (manual | auto)
      entryReasonCode: SpxEntryReasonCodes.manualBuy,
      entryReasonText: 'Manual buy from chain/dashboard action.',
      opportunityId: pendingOpportunityId,
      executionModeAtDecision: pendingOpportunityId == null
          ? SpxOpportunityExecutionMode.manualConfirm
          : _executionMode,
    );

    emit(state.copyWith(
      positions: [...state.positions, pos],
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
    ));
  }

  void _onApproveOpportunity(
    ApproveSpxOpportunity event,
    Emitter<SpxState> emit,
  ) {
    final mappedId = _pendingOpportunityBySymbol[event.symbol];
    if (mappedId != event.opportunityId) {
      _addLog(
        '⚠️ Approval ignored — pending opportunity not found for ${event.symbol}',
        TradeLogType.warn,
      );
      return;
    }

    final pendingContract = _pendingOpportunityContracts[event.opportunityId];
    _clearPendingOpportunity(
      event.opportunityId,
      symbol: event.symbol,
      keepCreatedAt: true,
    );
    final contract = state.chain
            .cast<OptionsContract?>()
            .firstWhere((c) => c?.symbol == event.symbol, orElse: () => null) ??
        pendingContract;
    if (contract == null || contract.midPrice <= 0) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: 'quote_stale',
        reasonText: 'Approval failed because quote was unavailable.',
        contract: pendingContract,
      );
      return;
    }
    if (state.positions.any((p) => p.contract.symbol == contract.symbol)) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: 'already_open',
        reasonText: 'Approval ignored because position is already open.',
        contract: contract,
      );
      return;
    }
    final totalNotional = state.positions.fold<double>(
      0,
      (sum, p) => sum + (p.currentPremium * p.contracts * 100),
    );
    final failureCode = _autoExecutionFailureCode(
      contract,
      state.positions,
      totalNotional: totalNotional,
    );
    if (failureCode != null) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: failureCode,
        reasonText: _executionFailureReasonText(failureCode),
        contract: contract,
      );
      return;
    }

    _recordOpportunityLifecycle(
      opportunityId: event.opportunityId,
      contract: contract,
      status: SpxOpportunityStatus.approved,
      entrySource: 'manual',
      entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
      userAction: 'approved',
      userActionAt: DateTime.now(),
    );

    final pos = SpxPosition(
      id: _uuid.v4(),
      contract: contract,
      contracts: 1,
      entryPremium: contract.midPrice,
      currentPremium: contract.midPrice,
      openedAt: DateTime.now(),
    );
    _recordIntradayMarker(
      timestamp: pos.openedAt,
      spot: state.spotPrice,
      type: SpxIntradayMarkerType.entry,
      label: 'BUY',
      symbol: contract.symbol,
      side: contract.side,
    );
    _addLog(
      '✅ APPROVED ${contract.symbol} @ \$${contract.midPrice.toStringAsFixed(2)}',
      TradeLogType.buy,
    );
    _emitAlert(
      title: 'SPX Opportunity Approved',
      message: '${contract.symbol} · ${contract.daysToExpiry}DTE',
      type: TradeLogType.buy,
    );
    _recordEntry(
      pos,
      entrySource: 'manual',
      entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
      entryReasonText: 'User approved pending opportunity.',
      opportunityId: event.opportunityId,
      executionModeAtDecision: SpxOpportunityExecutionMode.manualConfirm,
    );
    emit(state.copyWith(
      positions: [...state.positions, pos],
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
    ));
  }

  void _onRejectOpportunity(
    RejectSpxOpportunity event,
    Emitter<SpxState> emit,
  ) {
    final mappedId = _pendingOpportunityBySymbol[event.symbol];
    if (mappedId != event.opportunityId) {
      _addLog(
        '⚠️ Reject ignored — pending opportunity not found for ${event.symbol}',
        TradeLogType.warn,
      );
      return;
    }
    final pendingStatus = _pendingOpportunityStatusById[event.opportunityId];
    if (pendingStatus == SpxOpportunityStatus.pendingDelay) {
      _onCancelOpportunity(
        CancelSpxOpportunity(
          opportunityId: event.opportunityId,
          symbol: event.symbol,
        ),
        emit,
      );
      return;
    }

    final pendingContract = _pendingOpportunityContracts[event.opportunityId];
    _clearPendingOpportunity(
      event.opportunityId,
      symbol: event.symbol,
      keepCreatedAt: true,
    );
    if (pendingContract != null) {
      _recordOpportunityLifecycle(
        opportunityId: event.opportunityId,
        contract: pendingContract,
        status: SpxOpportunityStatus.rejected,
        entrySource: 'manual',
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        userAction: 'rejected',
        userActionAt: DateTime.now(),
        missedReasonCode: 'user_rejected',
      );
    } else {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: 'user_rejected',
        reasonText: 'Opportunity rejected by user.',
      );
    }
    _addLog('🛑 REJECTED OPPORTUNITY ${event.symbol}', TradeLogType.warn);
    _emitAlert(
      title: 'SPX Opportunity Rejected',
      message: event.symbol,
      type: TradeLogType.warn,
    );
  }

  void _onCancelOpportunity(
    CancelSpxOpportunity event,
    Emitter<SpxState> emit,
  ) {
    final mappedId = _pendingOpportunityBySymbol[event.symbol];
    if (mappedId != event.opportunityId) {
      _addLog(
        '⚠️ Cancel ignored — pending opportunity not found for ${event.symbol}',
        TradeLogType.warn,
      );
      return;
    }

    final pendingStatus = _pendingOpportunityStatusById[event.opportunityId];
    final reasonCode = pendingStatus == SpxOpportunityStatus.pendingDelay
        ? 'delay_cancelled'
        : 'user_rejected';
    final reasonText = pendingStatus == SpxOpportunityStatus.pendingDelay
        ? 'Auto-delay opportunity cancelled by user.'
        : 'Opportunity rejected by user.';
    final pendingContract = _pendingOpportunityContracts[event.opportunityId];
    _clearPendingOpportunity(
      event.opportunityId,
      symbol: event.symbol,
      keepCreatedAt: true,
    );
    if (pendingContract != null) {
      _recordOpportunityLifecycle(
        opportunityId: event.opportunityId,
        contract: pendingContract,
        status: SpxOpportunityStatus.missed,
        entrySource: 'manual',
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        userAction: 'cancelled',
        userActionAt: DateTime.now(),
        missedReasonCode: reasonCode,
      );
    } else {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: reasonCode,
        reasonText: reasonText,
      );
    }
    _addLog('🛑 CANCELLED OPPORTUNITY ${event.symbol}', TradeLogType.warn);
    _emitAlert(
      title: 'SPX Opportunity Cancelled',
      message: event.symbol,
      type: TradeLogType.warn,
    );
  }

  void _onClose(CloseSpxPosition event, Emitter<SpxState> emit) {
    final idx = state.positions.indexWhere((p) => p.id == event.positionId);
    if (idx == -1) return;
    final pos = state.positions[idx];
    final pnl = pos.unrealizedPnL;
    _recordExit(
      pos,
      exitReasonCode: SpxExitReasonCodes.manualClose,
      exitReasonText: 'Manual close from positions screen.',
      pnlUsd: pnl,
    );
    _recordIntradayMarker(
      timestamp: DateTime.now(),
      spot: state.spotPrice,
      type: SpxIntradayMarkerType.exit,
      label: 'OUT',
      symbol: pos.contract.symbol,
      side: pos.contract.side,
    );
    final sign = pnl >= 0 ? '+' : '';
    _addLog(
      '🔴 CLOSE ${pos.contract.symbol} — PnL: $sign\$${pnl.toStringAsFixed(2)}',
      pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    _emitAlert(
      title: 'SPX Close',
      message: '${pos.contract.symbol} · $sign\$${pnl.toStringAsFixed(2)}',
      type: pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    emit(state.copyWith(
      positions:
          state.positions.where((p) => p.id != event.positionId).toList(),
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
      realizedPnL: state.realizedPnL + pnl,
      totalTrades: state.totalTrades + 1,
      winTrades: pnl > 0 ? state.winTrades + 1 : state.winTrades,
    ));
  }

  void _onToggleScanner(ToggleSpxScanner event, Emitter<SpxState> emit) {
    final next = state.scannerStatus == SpxScannerStatus.active
        ? SpxScannerStatus.paused
        : SpxScannerStatus.active;
    emit(state.copyWith(scannerStatus: next));
    _addLog(
      next == SpxScannerStatus.active
          ? '▶ SPX scanner activated'
          : '⏸ SPX scanner paused',
      next == SpxScannerStatus.active ? TradeLogType.system : TradeLogType.warn,
    );
  }

  void _onUpdateContractTargeting(
    UpdateSpxContractTargeting event,
    Emitter<SpxState> emit,
  ) {
    final nextMode = SpxContractTargetingMode.normalize(event.mode);
    if (nextMode == state.contractTargetingMode) return;
    emit(state.copyWith(contractTargetingMode: nextMode));
    _addLog(
      '🎯 SPX contract targeting updated: '
      '${SpxContractTargetingMode.label(nextMode)}',
      TradeLogType.info,
    );
  }

  Future<void> _onUpdateTradierCredentials(
    UpdateTradierCredentials event,
    Emitter<SpxState> emit,
  ) async {
    final environment = SpxTradierEnvironment.normalize(event.environment);
    final token = event.token.trim();
    _service = _optionsServiceBuilder(
      apiToken: token,
      tradierEnvironment: environment,
    );
    emit(state.copyWith(
      tradierToken: token,
      tradierEnvironment: environment,
    ));
    _addLog(
      token.isEmpty
          ? '🔑 Tradier ${SpxTradierEnvironment.label(environment).toLowerCase()} token cleared — using simulator'
          : '🔑 Tradier ${SpxTradierEnvironment.label(environment).toLowerCase()} token updated — retrying live feed',
      TradeLogType.system,
    );
    add(const InitializeSpx());
  }

  void _onUpdateExecutionSettings(
    UpdateSpxExecutionSettings event,
    Emitter<SpxState> emit,
  ) {
    final nextMode = SpxOpportunityExecutionMode.normalize(event.executionMode);
    final nextDelay = event.entryDelaySeconds.clamp(0, 3600).toInt();
    final nextValidation =
        event.validationWindowSeconds.clamp(15, 3600).toInt();
    final nextSlippage = event.maxSlippagePct.clamp(0.1, 100.0).toDouble();
    final changed = nextMode != _executionMode ||
        nextDelay != _entryDelaySeconds ||
        nextValidation != _validationWindowSeconds ||
        nextSlippage != _maxSlippagePct ||
        event.notificationsEnabled != _notificationsEnabled;

    _executionMode = nextMode;
    _entryDelaySeconds = nextDelay;
    _validationWindowSeconds = nextValidation;
    _maxSlippagePct = nextSlippage;
    _notificationsEnabled = event.notificationsEnabled;

    if (!changed) return;
    final modeLabel = switch (_executionMode) {
      SpxOpportunityExecutionMode.manualConfirm => 'manual_confirm',
      SpxOpportunityExecutionMode.autoAfterDelay => 'auto_after_delay',
      _ => 'auto_immediate',
    };
    _addLog(
      '⚙️ SPX execution settings updated: mode=$modeLabel '
      'delay=${_entryDelaySeconds}s validate=${_validationWindowSeconds}s '
      'slippage=${_maxSlippagePct.toStringAsFixed(1)}% '
      'alerts=${_notificationsEnabled ? 'on' : 'off'}',
      TradeLogType.info,
    );
  }

  Future<void> _onUpdateTermFilter(
    UpdateSpxTermFilter event,
    Emitter<SpxState> emit,
  ) async {
    final filteredExp =
        _filterExpirationsByTerm(state.expirations, event.filter);
    final selectedExp = filteredExp.contains(state.selectedExpiration)
        ? state.selectedExpiration
        : (filteredExp.isNotEmpty ? filteredExp.first : null);
    if (selectedExp == null && event.filter.mode == SpxTermMode.exact) {
      _addLog(
        '⚠️ No expiration available for ${event.filter.exactDte}DTE',
        TradeLogType.warn,
      );
    }

    emit(state.copyWith(
      termFilter: event.filter,
      selectedExpiration: selectedExp,
    ));

    final chain = selectedExp != null
        ? await _service.fetchChain(expiration: selectedExp)
        : (event.filter.mode == SpxTermMode.exact
            ? <OptionsContract>[]
            : _sim.refreshChain(dteDays: _simDteDays(event.filter)));
    final spot = await _service.fetchSpxSpot();
    final gex = SpxGreeksCalculator.calcGex(chain, spot);
    final strategySnapshot = _buildStrategySnapshot(
      spot: spot,
      chain: chain,
      gexData: gex,
    );
    final mode = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;
    final marketOpenNow = _service.isMarketOpenNow;

    emit(state.copyWith(
      chain: chain,
      spotPrice: spot,
      isMarketOpen: marketOpenNow,
      intradaySpots: List<SpxSpotSample>.from(_intradaySpots),
      intradayCandles: List<SpxCandleSample>.from(_intradayCandles),
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
      sessionStartedAt: _sessionStartAt,
      sessionOpenPrice: _sessionOpenPrice,
      sessionHighPrice: _sessionHighPrice,
      sessionLowPrice: _sessionLowPrice,
      gexData: gex,
      strategySnapshot: strategySnapshot,
      dataMode: mode,
    ));
    _logStrategyActionChange(strategySnapshot);

    final label = event.filter.mode == SpxTermMode.exact
        ? 'Exact ${event.filter.exactDte}DTE'
        : 'Range ${event.filter.minDte}-${event.filter.maxDte}DTE';
    _addLog('🧭 SPX terms updated — $label', TradeLogType.info);
  }

  void _onResetDay(ResetSpxDay event, Emitter<SpxState> emit) {
    emit(state.copyWith(
      logs: [],
      realizedPnL: 0,
      totalTrades: 0,
      winTrades: 0,
    ));
    _addLog('🔄 SPX daily stats reset', TradeLogType.system);
  }

  void _onExecutePendingOpportunity(
    _ExecutePendingOpportunity event,
    Emitter<SpxState> emit,
  ) {
    final mappedId = _pendingOpportunityBySymbol[event.symbol];
    if (mappedId != event.opportunityId) return;

    final pendingContract = _pendingOpportunityContracts[event.opportunityId];
    _clearPendingOpportunity(
      event.opportunityId,
      symbol: event.symbol,
      keepCreatedAt: true,
    );
    final contract = state.chain
            .cast<OptionsContract?>()
            .firstWhere((c) => c?.symbol == event.symbol, orElse: () => null) ??
        pendingContract;
    if (contract == null || contract.midPrice <= 0) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: 'quote_stale',
        reasonText: 'Delayed execution skipped because quote was unavailable.',
        contract: pendingContract,
      );
      return;
    }
    if (state.positions.any((p) => p.contract.symbol == contract.symbol)) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: 'already_open',
        reasonText:
            'Delayed execution skipped because position is already open.',
        contract: contract,
      );
      return;
    }
    final totalNotional = state.positions.fold<double>(
      0,
      (sum, p) => sum + (p.currentPremium * p.contracts * 100),
    );
    final failureCode = _autoExecutionFailureCode(
      contract,
      state.positions,
      totalNotional: totalNotional,
    );
    if (failureCode != null) {
      _markOpportunityMissed(
        event.opportunityId,
        reasonCode: failureCode,
        reasonText: _executionFailureReasonText(failureCode),
        contract: contract,
      );
      return;
    }

    final pos = SpxPosition(
      id: _uuid.v4(),
      contract: contract,
      contracts: 1,
      entryPremium: contract.midPrice,
      currentPremium: contract.midPrice,
      openedAt: DateTime.now(),
    );
    _recordIntradayMarker(
      timestamp: pos.openedAt,
      spot: state.spotPrice,
      type: SpxIntradayMarkerType.entry,
      label: 'BUY',
      symbol: contract.symbol,
      side: contract.side,
    );
    _addLog(
      '⏳ AUTO DELAY EXECUTED ${contract.symbol} '
      '@ \$${contract.midPrice.toStringAsFixed(2)}',
      TradeLogType.buy,
    );
    _emitAlert(
      title: 'SPX Delayed Entry Executed',
      message: '${contract.symbol} · ${contract.daysToExpiry}DTE',
      type: TradeLogType.buy,
    );
    _recordEntry(
      pos,
      entrySource: 'auto',
      entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
      entryReasonText: 'Delayed auto scanner execution.',
      opportunityId: event.opportunityId,
      executionModeAtDecision: SpxOpportunityExecutionMode.autoAfterDelay,
    );
    emit(state.copyWith(
      positions: [...state.positions, pos],
      intradayMarkers: List<SpxIntradayMarker>.from(_intradayMarkers),
    ));
  }

  void _onExpirePendingOpportunity(
    _ExpirePendingOpportunity event,
    Emitter<SpxState> emit,
  ) {
    final mappedId = _pendingOpportunityBySymbol[event.symbol];
    if (mappedId != event.opportunityId) return;

    final pendingContract = _pendingOpportunityContracts[event.opportunityId];
    _clearPendingOpportunity(
      event.opportunityId,
      symbol: event.symbol,
      keepCreatedAt: true,
    );
    _markOpportunityMissed(
      event.opportunityId,
      reasonCode: event.reasonCode,
      reasonText: event.reasonText,
      contract: pendingContract,
    );
  }

  // ── Auto-scanner ──────────────────────────────────────────────────────────

  /// Returns updated (positions, realizedPnL, totalTrades, winTrades).
  (List<SpxPosition>, double, int, int) _runScanner(
    List<SpxPosition> current,
    List<OptionsContract> chain,
    double spot,
    double realizedPnL,
    int totalTrades,
    int winTrades,
    SpxStrategySnapshot? strategy,
  ) {
    final positions = List<SpxPosition>.from(current);
    final action = _scannerOverrideAction ??
        strategy?.action ??
        SpxStrategyActionType.wait;
    if (action == SpxStrategyActionType.wait) {
      return (positions, realizedPnL, totalTrades, winTrades);
    }
    final requiredSide = action == SpxStrategyActionType.goLong
        ? OptionsSide.call
        : OptionsSide.put;
    final eligibleContracts = chain
        .where((contract) =>
            contract.signal == SpxSignalType.buy &&
            contract.side == requiredSide)
        .toList();
    final targetedContracts = matchingSpxContractsForTargeting(
      eligibleContracts,
      spot: spot,
      targetingMode: state.contractTargetingMode,
    );
    final orderedContracts = orderSpxContractsForTargeting(
      targetedContracts.isNotEmpty ? targetedContracts : eligibleContracts,
      spot: spot,
      targetingMode: targetedContracts.isNotEmpty
          ? state.contractTargetingMode
          : SpxContractTargetingMode.deltaZone,
    );
    var totalNotional = positions.fold<double>(
      0,
      (sum, p) => sum + (p.currentPremium * p.contracts * 100),
    );

    for (final contract in orderedContracts) {
      final activeOpportunitySlots =
          positions.length + _pendingOpportunityBySymbol.length;
      if (activeOpportunitySlots >= _maxAutoPositions) break;
      if (positions.any((p) => p.contract.symbol == contract.symbol)) continue;
      if (_pendingOpportunityBySymbol.containsKey(contract.symbol)) continue;
      if (contract.midPrice <= 0) continue;
      final orderNotional = contract.midPrice * 100;
      final failureCode = _autoExecutionFailureCode(
        contract,
        positions,
        totalNotional: totalNotional,
      );
      if (failureCode != null) {
        continue;
      }

      final markerTime = DateTime.now();
      final opportunityId = _uuid.v4();
      _recordIntradayMarker(
        timestamp: markerTime,
        spot: spot,
        type: SpxIntradayMarkerType.signal,
        label: 'SIG',
        symbol: contract.symbol,
        side: contract.side,
      );
      _recordOpportunityLifecycle(
        opportunityId: opportunityId,
        contract: contract,
        status: SpxOpportunityStatus.found,
        entrySource: 'auto',
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
      );
      _recordOpportunityLifecycle(
        opportunityId: opportunityId,
        contract: contract,
        status: SpxOpportunityStatus.alerted,
        entrySource: 'auto',
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        notificationSentAt: _notificationsEnabled ? DateTime.now() : null,
      );
      _emitAlert(
        title: 'SPX Opportunity Found',
        message: '${contract.symbol} · ${contract.daysToExpiry}DTE',
        type: TradeLogType.info,
        payload: TradeAlertPayloads.forSpxOpportunity(opportunityId),
      );

      if (_executionMode == SpxOpportunityExecutionMode.manualConfirm) {
        _recordOpportunityLifecycle(
          opportunityId: opportunityId,
          contract: contract,
          status: SpxOpportunityStatus.pendingUser,
          entrySource: 'auto',
          entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        );
        _pendingOpportunityBySymbol[contract.symbol] = opportunityId;
        _pendingOpportunityContracts[opportunityId] = contract;
        _pendingOpportunityStatusById[opportunityId] =
            SpxOpportunityStatus.pendingUser;
        _scheduleOpportunityTimeout(
          opportunityId: opportunityId,
          symbol: contract.symbol,
          duration: Duration(seconds: _validationWindowSeconds),
          onTimeout: _ExpirePendingOpportunity(
            opportunityId: opportunityId,
            symbol: contract.symbol,
            reasonCode: 'user_timeout',
            reasonText: 'Opportunity expired waiting for user confirmation.',
          ),
        );
        _addLog(
          '👀 PENDING APPROVAL ${contract.symbol} '
          '(${_validationWindowSeconds}s window)',
          TradeLogType.info,
        );
        continue;
      }

      if (_executionMode == SpxOpportunityExecutionMode.autoAfterDelay) {
        _recordOpportunityLifecycle(
          opportunityId: opportunityId,
          contract: contract,
          status: SpxOpportunityStatus.pendingDelay,
          entrySource: 'auto',
          entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        );
        _pendingOpportunityBySymbol[contract.symbol] = opportunityId;
        _pendingOpportunityContracts[opportunityId] = contract;
        _pendingOpportunityStatusById[opportunityId] =
            SpxOpportunityStatus.pendingDelay;
        _scheduleOpportunityTimeout(
          opportunityId: opportunityId,
          symbol: contract.symbol,
          duration: Duration(seconds: _entryDelaySeconds),
          onTimeout: _ExecutePendingOpportunity(
            opportunityId: opportunityId,
            symbol: contract.symbol,
          ),
        );
        _addLog(
          '⏳ AUTO DELAY QUEUED ${contract.symbol} '
          '(${_entryDelaySeconds}s delay)',
          TradeLogType.info,
        );
        continue;
      }

      final pos = SpxPosition(
        id: _uuid.v4(),
        contract: contract,
        contracts: 1,
        entryPremium: contract.midPrice,
        currentPremium: contract.midPrice,
        openedAt: DateTime.now(),
      );
      _recordIntradayMarker(
        timestamp: pos.openedAt,
        spot: spot,
        type: SpxIntradayMarkerType.entry,
        label: 'BUY',
        symbol: contract.symbol,
        side: contract.side,
      );
      positions.add(pos);
      totalNotional += orderNotional;
      _addLog(
        '🤖 AUTO ${contract.side.name.toUpperCase()} '
        '${contract.symbol} @ \$${contract.midPrice.toStringAsFixed(2)}'
        ' | Δ${contract.greeks.delta.toStringAsFixed(2)} | ${contract.daysToExpiry}DTE',
        TradeLogType.buy,
      );
      _emitAlert(
        title: 'SPX Auto Entry',
        message: '${contract.symbol} · ${contract.daysToExpiry}DTE',
        type: TradeLogType.buy,
      );
      _recordEntry(
        pos,
        entrySource: 'auto', // free-form source bucket (manual | auto)
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        entryReasonText: 'Auto scanner selected buy signal contract.',
        opportunityId: opportunityId,
        executionModeAtDecision: _executionMode,
      );
    }

    return (positions, realizedPnL, totalTrades, winTrades);
  }

  String? _autoExecutionFailureCode(
    OptionsContract contract,
    List<SpxPosition> positions, {
    required double totalNotional,
  }) {
    if (!_service.isMarketOpenNow) return 'market_closed';
    if (contract.midPrice <= 0 || contract.ask <= 0 || contract.bid <= 0) {
      return 'quote_stale';
    }
    final quoteAge = DateTime.now().difference(contract.lastUpdated);
    if (quoteAge > _maxExecutionQuoteAge) {
      return 'quote_stale';
    }

    final spreadPct =
        ((contract.ask - contract.bid).abs() / contract.midPrice) * 100;
    if (spreadPct > _maxSlippagePct) return 'price_moved_slippage';

    final orderNotional = contract.midPrice * 100;
    if (orderNotional > _maxAutoPerTradeNotional) return 'risk_guard_failed';
    if (totalNotional + orderNotional > _maxAutoPortfolioNotional) {
      return 'risk_guard_failed';
    }

    final sameSide =
        positions.where((p) => p.contract.side == contract.side).length;
    if (sameSide >= _maxAutoPerSide) return 'risk_guard_failed';

    final sameDteBucket = positions
        .where((p) => p.contract.daysToExpiry == contract.daysToExpiry)
        .length;
    if (sameDteBucket >= _maxAutoPerDteBucket) return 'risk_guard_failed';
    return null;
  }

  String _executionFailureReasonText(String code) {
    return switch (code) {
      'market_closed' => 'Execution blocked because market is closed.',
      'quote_stale' => 'Execution blocked because quote was unavailable.',
      'price_moved_slippage' =>
        'Execution blocked because spread exceeded max slippage.',
      _ => 'Execution blocked by SPX auto risk limits.',
    };
  }

  void _recordOpportunityLifecycle({
    required String opportunityId,
    required OptionsContract contract,
    required String status,
    required String entrySource,
    required String entryReasonCode,
    DateTime? notificationSentAt,
    String? userAction,
    DateTime? userActionAt,
    String? executedTradeId,
    String? missedReasonCode,
  }) {
    final createdAt =
        _opportunityCreatedAtById.putIfAbsent(opportunityId, DateTime.now);
    final record = SpxOpportunityJournalRecord(
      opportunityId: opportunityId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: status,
      symbol: contract.symbol,
      side: contract.side.name,
      strike: contract.strike,
      expiryIso: contract.expiry.toIso8601String(),
      dte: contract.daysToExpiry,
      premiumAtFind: contract.midPrice,
      signalScore: _signalScore(contract),
      signalDetails: _signalDetails(contract),
      entryReasonCode: entryReasonCode,
      entrySource: entrySource,
      executionModeAtDecision: _executionMode,
      entryDelaySeconds: _entryDelaySeconds,
      validationWindowSeconds: _validationWindowSeconds,
      notificationSentAt: notificationSentAt,
      userAction: userAction,
      userActionAt: userActionAt,
      executedTradeId: executedTradeId,
      missedReasonCode: missedReasonCode,
    );
    _enqueueOpportunityPersist(record);
    final isTerminal = status == SpxOpportunityStatus.executed ||
        status == SpxOpportunityStatus.missed ||
        status == SpxOpportunityStatus.rejected;
    if (isTerminal) {
      _clearPendingOpportunity(opportunityId);
    }
  }

  void _scheduleOpportunityTimeout({
    required String opportunityId,
    required String symbol,
    required Duration duration,
    required SpxEvent onTimeout,
  }) {
    _pendingOpportunityTimers.remove(opportunityId)?.cancel();
    final timer = Timer(duration, () {
      if (isClosed) return;
      add(onTimeout);
    });
    _pendingOpportunityTimers[opportunityId] = timer;
    _pendingOpportunityBySymbol[symbol] = opportunityId;
  }

  void _clearPendingOpportunity(
    String opportunityId, {
    String? symbol,
    bool keepCreatedAt = false,
  }) {
    _pendingOpportunityTimers.remove(opportunityId)?.cancel();
    _pendingOpportunityContracts.remove(opportunityId);
    _pendingOpportunityStatusById.remove(opportunityId);
    if (!keepCreatedAt) {
      _opportunityCreatedAtById.remove(opportunityId);
    }
    if (symbol != null) {
      if (_pendingOpportunityBySymbol[symbol] == opportunityId) {
        _pendingOpportunityBySymbol.remove(symbol);
      }
      return;
    }
    _pendingOpportunityBySymbol
        .removeWhere((_, value) => value == opportunityId);
  }

  void _markOpportunityMissed(
    String opportunityId, {
    required String reasonCode,
    required String reasonText,
    OptionsContract? contract,
  }) {
    _addLog(
        '⏭ MISSED OPPORTUNITY $opportunityId — $reasonCode', TradeLogType.warn);
    final fallbackContract = _pendingOpportunityContracts[opportunityId];
    final createdAt =
        _opportunityCreatedAtById[opportunityId] ?? DateTime.now();
    final snapshot = contract ?? fallbackContract;
    final record = SpxOpportunityJournalRecord(
      opportunityId: opportunityId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: SpxOpportunityStatus.missed,
      symbol: snapshot?.symbol ?? '',
      side: snapshot?.side.name ?? '',
      strike: snapshot?.strike ?? 0,
      expiryIso: snapshot?.expiry.toIso8601String() ?? '',
      dte: snapshot?.daysToExpiry ?? 0,
      premiumAtFind: snapshot?.midPrice ?? 0,
      signalScore: snapshot == null ? 0 : _signalScore(snapshot),
      signalDetails: {
        if (snapshot != null) ..._signalDetails(snapshot),
        'reasonText': reasonText,
      },
      entryReasonCode: 'opportunity_missed',
      entrySource: 'auto',
      executionModeAtDecision: _executionMode,
      entryDelaySeconds: _entryDelaySeconds,
      validationWindowSeconds: _validationWindowSeconds,
      missedReasonCode: reasonCode,
      userAction: 'missed',
      userActionAt: DateTime.now(),
    );
    _enqueueOpportunityPersist(record);
    _clearPendingOpportunity(opportunityId);
  }

  // ── Strategy engine ───────────────────────────────────────────────────────

  void _resetSessionTracking(double spot) {
    final now = DateTime.now();
    _sessionStartAt = now;
    _sessionOpenPrice = spot;
    _sessionReferencePrice = spot;
    _sessionHighPrice = spot;
    _sessionLowPrice = spot;
    _minute14High = spot;
    _minute14Low = spot;
    _spotTape
      ..clear()
      ..add(spot);
    _intradaySpots
      ..clear()
      ..add(SpxSpotSample(recordedAt: now, price: spot));
    _intradayCandles
      ..clear()
      ..add(
        SpxCandleSample(
          bucketStart:
              DateTime(now.year, now.month, now.day, now.hour, now.minute),
          open: spot,
          high: spot,
          low: spot,
          close: spot,
        ),
      );
    _intradayMarkers.clear();
    _lastStrategyAction = null;
  }

  void _updateSessionTracking(double spot) {
    final now = DateTime.now();
    if (_sessionStartAt != null && !_isSameCalendarDay(_sessionStartAt!, now)) {
      _resetSessionTracking(spot);
      return;
    }

    _sessionStartAt ??= now;
    _sessionOpenPrice ??= spot;
    _sessionReferencePrice ??= _sessionOpenPrice;
    _sessionHighPrice =
        _sessionHighPrice == null ? spot : math.max(_sessionHighPrice!, spot);
    _sessionLowPrice =
        _sessionLowPrice == null ? spot : math.min(_sessionLowPrice!, spot);
    _spotTape.add(spot);
    if (_spotTape.length > 240) {
      _spotTape.removeRange(0, _spotTape.length - 240);
    }
    _recordIntradaySpot(now, spot);
    _recordIntradayCandle(now, spot);

    final minutesFromStart =
        now.difference(_sessionStartAt!).inMinutes.clamp(0, 390);
    if (minutesFromStart <= 14) {
      _minute14High =
          _minute14High == null ? spot : math.max(_minute14High!, spot);
      _minute14Low =
          _minute14Low == null ? spot : math.min(_minute14Low!, spot);
    } else {
      // Keep levels adaptive if fresh extremes appear later in the session.
      _minute14High =
          _minute14High == null ? spot : math.max(_minute14High!, spot);
      _minute14Low =
          _minute14Low == null ? spot : math.min(_minute14Low!, spot);
    }
  }

  void _recordIntradaySpot(DateTime now, double spot) {
    final sample = SpxSpotSample(recordedAt: now, price: spot);
    if (_intradaySpots.isEmpty) {
      _intradaySpots.add(sample);
      return;
    }

    final last = _intradaySpots.last.recordedAt;
    final sameMinuteBucket = _isSameMinute(last, now);
    if (sameMinuteBucket) {
      _intradaySpots[_intradaySpots.length - 1] = sample;
      return;
    }

    _intradaySpots.add(sample);
    if (_intradaySpots.length > _maxIntradaySpotSamples) {
      _intradaySpots.removeRange(
        0,
        _intradaySpots.length - _maxIntradaySpotSamples,
      );
    }
  }

  void _recordIntradayCandle(DateTime now, double spot) {
    final bucketStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    if (_intradayCandles.isEmpty) {
      _intradayCandles.add(
        SpxCandleSample(
          bucketStart: bucketStart,
          open: spot,
          high: spot,
          low: spot,
          close: spot,
        ),
      );
      return;
    }

    final last = _intradayCandles.last;
    if (_isSameMinute(last.bucketStart, bucketStart)) {
      _intradayCandles[_intradayCandles.length - 1] = last.update(spot);
      return;
    }

    _intradayCandles.add(
      SpxCandleSample(
        bucketStart: bucketStart,
        open: spot,
        high: spot,
        low: spot,
        close: spot,
      ),
    );
    if (_intradayCandles.length > _maxIntradaySpotSamples) {
      _intradayCandles.removeRange(
        0,
        _intradayCandles.length - _maxIntradaySpotSamples,
      );
    }
  }

  void _recordIntradayMarker({
    required DateTime timestamp,
    required double spot,
    required SpxIntradayMarkerType type,
    required String label,
    required String symbol,
    OptionsSide? side,
  }) {
    _intradayMarkers.add(
      SpxIntradayMarker(
        timestamp: timestamp,
        spotPrice: spot,
        type: type,
        label: label,
        symbol: symbol,
        side: side,
      ),
    );
    if (_intradayMarkers.length > _maxIntradayMarkers) {
      _intradayMarkers.removeRange(
        0,
        _intradayMarkers.length - _maxIntradayMarkers,
      );
    }
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMinute(DateTime a, DateTime b) {
    return _isSameCalendarDay(a, b) && a.hour == b.hour && a.minute == b.minute;
  }

  SpxStrategySnapshot _buildStrategySnapshot({
    required double spot,
    required List<OptionsContract> chain,
    required GexData? gexData,
  }) {
    _updateSessionTracking(spot);
    final now = DateTime.now();
    final minutesFromStart = _sessionStartAt == null
        ? 0
        : now.difference(_sessionStartAt!).inMinutes.clamp(0, 390);

    final open = _sessionOpenPrice ?? spot;
    final reference = _sessionReferencePrice ?? open;
    final gapPercent =
        reference == 0 ? 0.0 : ((open - reference) / reference) * 100.0;
    final openingMovePercent = open == 0 ? 0.0 : ((spot - open) / open) * 100.0;
    final significantGap = gapPercent.abs() >= 0.35 ||
        (minutesFromStart <= 5 && openingMovePercent.abs() >= 0.45);

    final itodMove =
        _spotTape.length < 6 ? 0.0 : spot - _spotTape[_spotTape.length - 6];
    final itodDirection = _directionFromValue(itodMove, deadband: 0.6);

    final emaFast = _ema(_spotTape, 5);
    final emaSlow = _ema(_spotTape, 13);
    final optTodDiff = emaFast - emaSlow;
    final optimizedTodDirection =
        _directionFromValue(optTodDiff, deadband: 0.4);

    final gapSignalDirection = significantGap
        ? _directionFromValue(
            gapPercent.abs() > 0.01 ? gapPercent : openingMovePercent,
            deadband: 0.12,
          )
        : _combineDirections(itodDirection, optimizedTodDirection);

    final dplDirection = _deriveDplDirection(
      spot: spot,
      itodDirection: itodDirection,
      gapDirection: gapSignalDirection,
      gexData: gexData,
    );

    final callVolume = chain
        .where((c) => c.side == OptionsSide.call)
        .fold<double>(0.0, (sum, c) => sum + c.volume);
    final putVolume = chain
        .where((c) => c.side == OptionsSide.put)
        .fold<double>(0.0, (sum, c) => sum + c.volume);
    final adRatio = (callVolume + 1) / (putVolume + 1);
    final adDirection = adRatio > 1.07
        ? SpxDirection.up
        : (adRatio < 0.93 ? SpxDirection.down : SpxDirection.neutral);

    final upsideOi = chain
        .where((c) => c.side == OptionsSide.call && c.strike >= spot)
        .fold<double>(0.0, (sum, c) => sum + c.openInterest);
    final downsideOi = chain
        .where((c) => c.side == OptionsSide.put && c.strike <= spot)
        .fold<double>(0.0, (sum, c) => sum + c.openInterest);
    final domRatio = (upsideOi + 1) / (downsideOi + 1);
    final domDirection = domRatio > 1.10
        ? SpxDirection.up
        : (domRatio < 0.90 ? SpxDirection.down : SpxDirection.neutral);

    final premarketDirection =
        _directionFromValue(openingMovePercent, deadband: 0.15);

    final signals = <SpxStrategySignal>[
      SpxStrategySignal(
        key: 'premarket',
        label: 'Premarket',
        direction: premarketDirection,
        detail: 'Open drift ${openingMovePercent.toStringAsFixed(2)}%',
      ),
      SpxStrategySignal(
        key: 'itod',
        label: 'iToD',
        direction: itodDirection,
        detail: 'Last 5-tick move ${itodMove.toStringAsFixed(2)} pts',
      ),
      SpxStrategySignal(
        key: 'optimized_tod',
        label: 'Optimized ToD',
        direction: optimizedTodDirection,
        detail: 'EMA5-EMA13 ${optTodDiff.toStringAsFixed(2)}',
      ),
      SpxStrategySignal(
        key: 'tod_gap',
        label: 'ToD / Gap',
        direction: gapSignalDirection,
        detail: significantGap ? 'Gap context active' : 'Trend+gap blend',
      ),
      SpxStrategySignal(
        key: 'dpl',
        label: 'DPL',
        direction: dplDirection,
        detail: gexData == null
            ? 'Fallback trend proxy'
            : (gexData.isPositiveGex
                ? 'Positive GEX mean-reversion bias'
                : 'Short gamma momentum bias'),
      ),
      SpxStrategySignal(
        key: 'ad65',
        label: 'A/D 6.5',
        direction: adDirection,
        detail: 'Call/Put volume ${adRatio.toStringAsFixed(2)}x',
      ),
      SpxStrategySignal(
        key: 'dom_gap',
        label: 'DOM / Gap',
        direction: domDirection,
        detail: 'Upside/Downside OI ${domRatio.toStringAsFixed(2)}x',
      ),
    ];

    final upCount = signals.where((s) => s.direction == SpxDirection.up).length;
    final downCount =
        signals.where((s) => s.direction == SpxDirection.down).length;
    final dominantDirection = upCount >= 6
        ? SpxDirection.up
        : (downCount >= 6 ? SpxDirection.down : SpxDirection.neutral);

    SpxStrategyActionType action;
    String reason;
    if (significantGap && minutesFromStart < 15) {
      action = SpxStrategyActionType.wait;
      reason = 'Significant gap context. Wait for DPL separation (15+ min).';
    } else if (dominantDirection == SpxDirection.up) {
      action = SpxStrategyActionType.goLong;
      reason =
          'All 7 signals aligned up. Enter near minute-14 low on confirmation.';
    } else if (dominantDirection == SpxDirection.down) {
      action = SpxStrategyActionType.goShort;
      reason =
          'All 7 signals aligned down. Enter near minute-14 high on confirmation.';
    } else if (minutesFromStart < 35) {
      action = SpxStrategyActionType.wait;
      reason = 'Signals are discordant before S35 window. Wait/reassess.';
    } else if (dplDirection == SpxDirection.up) {
      action = SpxStrategyActionType.goLong;
      reason = 'Discordant set resolved via DPL tiebreaker (up).';
    } else if (dplDirection == SpxDirection.down) {
      action = SpxStrategyActionType.goShort;
      reason = 'Discordant set resolved via DPL tiebreaker (down).';
    } else {
      action = SpxStrategyActionType.wait;
      reason = 'Signals mixed and DPL neutral. Stay flat.';
    }

    return SpxStrategySnapshot(
      action: action,
      reason: reason,
      significantGap: significantGap,
      gapPercent: gapPercent,
      minutesFromSessionStart: minutesFromStart,
      minute14High: _minute14High,
      minute14Low: _minute14Low,
      dominantDirection: dominantDirection,
      dplDirection: dplDirection,
      signals: signals,
      updatedAt: now,
    );
  }

  SpxDirection _deriveDplDirection({
    required double spot,
    required SpxDirection itodDirection,
    required SpxDirection gapDirection,
    required GexData? gexData,
  }) {
    if (gexData == null) {
      return _combineDirections(gapDirection, itodDirection);
    }
    if (!gexData.isPositiveGex) {
      // Short-gamma regime tends to amplify directional continuation.
      return _combineDirections(gapDirection, itodDirection);
    }
    final gammaWall = gexData.gammaWall;
    if (gammaWall == null) return itodDirection;
    if (spot < gammaWall - 2) return SpxDirection.up;
    if (spot > gammaWall + 2) return SpxDirection.down;
    return SpxDirection.neutral;
  }

  SpxDirection _combineDirections(SpxDirection a, SpxDirection b) {
    if (a == SpxDirection.neutral) return b;
    if (b == SpxDirection.neutral) return a;
    if (a == b) return a;
    return SpxDirection.neutral;
  }

  SpxDirection _directionFromValue(double value, {double deadband = 0}) {
    if (value > deadband) return SpxDirection.up;
    if (value < -deadband) return SpxDirection.down;
    return SpxDirection.neutral;
  }

  double _ema(List<double> values, int period) {
    if (values.isEmpty) return 0;
    final k = 2 / (period + 1);
    var ema = values.first;
    for (int i = 1; i < values.length; i++) {
      ema = values[i] * k + ema * (1 - k);
    }
    return ema;
  }

  void _logStrategyActionChange(SpxStrategySnapshot snapshot) {
    if (_lastStrategyAction == snapshot.action) return;
    _lastStrategyAction = snapshot.action;
    final message = '🧭 Strategy ${snapshot.action.label}: ${snapshot.reason}';
    _addLog(
      message,
      snapshot.action == SpxStrategyActionType.wait
          ? TradeLogType.warn
          : TradeLogType.info,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _startTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      add(const SpxMarketTick());
    });
  }

  void _addLog(String message, TradeLogType type) {
    add(_SpxAddLog(TradeLog(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      message: message,
      type: type,
    )));
  }

  List<String> _filterExpirationsByTerm(
    List<String> expirations,
    SpxTermFilter filter,
  ) {
    final now = DateTime.now();
    final filtered = expirations.where((exp) {
      final expiry = DateTime.tryParse(exp);
      if (expiry == null) return false;
      final dte = expiry.difference(now).inDays.clamp(0, 365);
      return filter.matchesDte(dte);
    }).toList();
    if (filtered.isNotEmpty || expirations.isEmpty) return filtered;
    if (filter.mode == SpxTermMode.exact) return [];

    final target = ((filter.minDte + filter.maxDte) / 2).round();
    String? nearest;
    var nearestDistance = 9999;
    for (final exp in expirations) {
      final expiry = DateTime.tryParse(exp);
      if (expiry == null) continue;
      final dte = expiry.difference(now).inDays.clamp(0, 365);
      final distance = (dte - target).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = exp;
      }
    }
    return nearest == null ? [] : [nearest];
  }

  List<int> _simDteDays(SpxTermFilter filter) {
    int normalize(int dte) => dte < 1 ? 1 : dte;
    if (filter.mode == SpxTermMode.exact) {
      return [normalize(filter.exactDte)];
    }
    return {
      normalize(filter.minDte),
      normalize(((filter.minDte + filter.maxDte) / 2).round()),
      normalize(filter.maxDte),
    }.toList()
      ..sort();
  }

  void _emitAlert({
    required String title,
    required String message,
    required TradeLogType type,
    String? payload,
  }) {
    if (!_notificationsEnabled) return;
    if (_alertController.isClosed) return;
    _alertController.add(
      TradeAlert(
        title: title,
        message: message,
        type: type,
        payload: payload,
      ),
    );
  }

  void _recordEntry(
    SpxPosition pos, {
    required String entrySource,
    required String entryReasonCode,
    required String entryReasonText,
    String? opportunityId,
    String? executionModeAtDecision,
  }) {
    final contract = pos.contract;
    final record = SpxTradeJournalRecord(
      tradeId: pos.id,
      positionId: pos.id,
      symbol: contract.symbol,
      side: contract.side.name,
      strike: contract.strike,
      expiryIso: contract.expiry.toIso8601String(),
      enteredAt: pos.openedAt,
      dteEntry: contract.daysToExpiry,
      entrySource: entrySource,
      entryReasonCode: entryReasonCode,
      entryReasonText: entryReasonText,
      signalScore: _signalScore(contract),
      signalDetails: _signalDetails(contract),
      contracts: pos.contracts,
      entryPremium: pos.entryPremium,
      spotEntry: state.spotPrice,
      ivRankEntry: contract.ivRank,
      dataMode: state.dataMode.name,
      termMode: state.termFilter.mode.name,
      termExactDte: state.termFilter.exactDte,
      termMinDte: state.termFilter.minDte,
      termMaxDte: state.termFilter.maxDte,
      updatedAt: DateTime.now(),
    );
    unawaited(_journal.recordEntry(_userId, record));

    final id = opportunityId ?? pos.id;
    final createdAt = _opportunityCreatedAtById[id] ?? pos.openedAt;
    final opportunityRecord = SpxOpportunityJournalRecord(
      opportunityId: id,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: SpxOpportunityStatus.executed,
      symbol: contract.symbol,
      side: contract.side.name,
      strike: contract.strike,
      expiryIso: contract.expiry.toIso8601String(),
      dte: contract.daysToExpiry,
      premiumAtFind: contract.midPrice,
      signalScore: _signalScore(contract),
      signalDetails: _signalDetails(contract),
      entryReasonCode: entryReasonCode,
      entrySource: entrySource,
      executionModeAtDecision: executionModeAtDecision ??
          (entrySource == 'auto'
              ? SpxOpportunityExecutionMode.autoImmediate
              : SpxOpportunityExecutionMode.manualConfirm),
      entryDelaySeconds: _entryDelaySeconds,
      validationWindowSeconds: _validationWindowSeconds,
      executedTradeId: pos.id,
    );
    _enqueueOpportunityPersist(opportunityRecord);
    _clearPendingOpportunity(id, symbol: contract.symbol);
  }

  void _enqueueOpportunityPersist(SpxOpportunityJournalRecord record) {
    final key = record.opportunityId;
    final previous = _opportunityPersistQueue[key] ?? Future<void>.value();
    final next = previous
        .catchError((_) {})
        .then((_) => _opportunities.upsert(_userId, record));
    _opportunityPersistQueue[key] = next;
    unawaited(next.catchError((_) {}).whenComplete(() {
      if (identical(_opportunityPersistQueue[key], next)) {
        _opportunityPersistQueue.remove(key);
      }
    }));
  }

  void _recordExit(
    SpxPosition pos, {
    required String exitReasonCode,
    required String exitReasonText,
    required double pnlUsd,
  }) {
    unawaited(_journal.recordExit(
      _userId,
      tradeId: pos.id,
      exitedAt: DateTime.now(),
      dteExit: pos.contract.daysToExpiry,
      exitPremium: pos.currentPremium,
      pnlUsd: pnlUsd,
      pnlPct: pos.pnlPercent,
      exitReasonCode: exitReasonCode,
      exitReasonText: exitReasonText,
      spotExit: state.spotPrice,
      ivRankExit: pos.contract.ivRank,
    ));
  }

  int _signalScore(OptionsContract contract) {
    var score = 0;
    if (contract.ivRank < 35) {
      score += 2;
    } else if (contract.ivRank > 75) {
      score -= 1;
    }
    if (contract.greeks.delta.abs() >= 0.20 &&
        contract.greeks.delta.abs() <= 0.45) {
      score += 1;
    }
    if (contract.volume > contract.openInterest * 0.05) score += 1;
    if (contract.midPrice > 0.50) score += 1;
    return score;
  }

  Map<String, dynamic> _signalDetails(OptionsContract contract) {
    return {
      'ivRank': contract.ivRank,
      'ivRankLowFavorsLong': contract.ivRank < 35,
      'delta': contract.greeks.delta,
      'deltaInTargetRange': contract.greeks.delta.abs() >= 0.20 &&
          contract.greeks.delta.abs() <= 0.45,
      'volume': contract.volume,
      'openInterest': contract.openInterest,
      'volumeVsOiRatio': contract.openInterest <= 0
          ? null
          : contract.volume / contract.openInterest,
      'midPrice': contract.midPrice,
      'dte': contract.daysToExpiry,
      'iv': contract.impliedVolatility,
      'signalType': contract.signal.name,
      'termMode': state.termFilter.mode.name,
      'termExactDte': state.termFilter.exactDte,
      'termMinDte': state.termFilter.minDte,
      'termMaxDte': state.termFilter.maxDte,
      'strategyAction': state.strategySnapshot?.action.name,
      'strategyReason': state.strategySnapshot?.reason,
    };
  }

  @override
  Future<void> close() {
    _tickTimer?.cancel();
    for (final timer in _pendingOpportunityTimers.values) {
      timer.cancel();
    }
    _pendingOpportunityTimers.clear();
    _pendingOpportunityBySymbol.clear();
    _pendingOpportunityContracts.clear();
    _pendingOpportunityStatusById.clear();
    _opportunityCreatedAtById.clear();
    _opportunityPersistQueue.clear();
    _alertController.close();
    return super.close();
  }
}
