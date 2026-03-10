import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/spx_models.dart';
import '../../services/spx/spx_greeks_calculator.dart';
import '../../services/spx/spx_options_service.dart';
import '../../services/spx/spx_options_simulator.dart';
import '../../services/spx/spx_trade_journal_codes.dart';
import '../../services/spx/spx_trade_journal_repository.dart';

part 'spx_event.dart';
part 'spx_state.dart';

const _uuid = Uuid();

class SpxBloc extends Bloc<SpxEvent, SpxState> {
  static const int _maxAutoPositions = 6;
  static const double _maxAutoPerTradeNotional = 2500; // premium dollars
  static const double _maxAutoPortfolioNotional = 12000; // premium dollars
  static const int _maxAutoPerSide = 4;
  static const int _maxAutoPerDteBucket = 2;

  Timer? _tickTimer;
  int _tickCount = 0;
  bool _tickInFlight = false;
  bool _chainRefreshInFlight = false;

  SpxOptionsService _service;
  final SpxOptionsSimulator _sim = SpxOptionsSimulator();
  final SpxTradeJournalRepository _journal;
  final String _userId;

  // Alert stream (mirrors CryptoBloc pattern)
  final _alertController = StreamController<TradeAlert>.broadcast();
  Stream<TradeAlert> get alertsStream => _alertController.stream;

  SpxBloc({
    String? tradierToken,
    required String userId,
    SpxTradeJournalRepository? journalRepository,
  })
      : _service = SpxOptionsService(
          apiToken: tradierToken,
          useSandbox: false,
          enforceMarketHours: false,
        ),
        _journal = journalRepository ?? FirebaseSpxTradeJournalRepository(),
        _userId = userId,
        super(SpxState.initial()) {
    on<InitializeSpx>(_onInitialize);
    on<SpxMarketTick>(_onMarketTick);
    on<RefreshSpxChain>(_onRefreshChain);
    on<SelectExpiration>(_onSelectExpiration);
    on<SelectSpxContract>(_onSelectContract);
    on<BuySpxContract>(_onBuy);
    on<CloseSpxPosition>(_onClose);
    on<ToggleSpxScanner>(_onToggleScanner);
    on<UpdateTradierToken>(_onUpdateToken);
    on<UpdateSpxTermFilter>(_onUpdateTermFilter);
    on<ResetSpxDay>(_onResetDay);
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

    // GEX snapshot
    final gexData = SpxGreeksCalculator.calcGex(chain, spot);

    final mode = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;

    emit(state.copyWith(
      chain:              chain,
      expirations:        expirations,
      selectedExpiration: selectedExp,
      spotPrice:          spot,
      gexData:            gexData,
      dataMode:           mode,
    ));

    _addLog(
      _service.isLive
          ? '📡 Connected to Tradier live feed'
          : '📡 Running in simulation mode (set Tradier token in Settings)',
      TradeLogType.system,
    );
    _addLog(
      '🎯 GEX: ${gexData.netGex.toStringAsFixed(2)}B  '
      '| Gamma Wall: \$${gexData.gammaWall?.toStringAsFixed(0) ?? '—'}  '
      '| Put Wall: \$${gexData.putWall?.toStringAsFixed(0) ?? '—'}',
      TradeLogType.info,
    );

    _startTimer();
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

      // ── SL / TP sweep ──────────────────────────────────────────────────────
      final surviving = <SpxPosition>[];
      var realizedPnL = state.realizedPnL;
      var totalTrades = state.totalTrades;
      var winTrades   = state.winTrades;

      for (final pos in updatedPositions) {
        if (pos.isStopLossHit) {
          final pnl = pos.unrealizedPnL;
          _recordExit(
            pos,
            exitReasonCode: SpxExitReasonCodes.stopLoss,
            exitReasonText: 'Position hit stop-loss threshold.',
            pnlUsd: pnl,
          );
          _addLog(
            '🛑 STOP-LOSS ${pos.contract.symbol} — PnL: \$${pnl.toStringAsFixed(2)}',
            TradeLogType.loss,
          );
          _emitAlert(
            title:   'Stop-Loss Triggered',
            message: '${pos.contract.symbol} · ${pos.contract.daysToExpiry}DTE',
            type:    TradeLogType.loss,
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
          _addLog(
            '🎯 TAKE-PROFIT ${pos.contract.symbol} — PnL: +\$${pnl.toStringAsFixed(2)}',
            TradeLogType.win,
          );
          _emitAlert(
            title:   'Take-Profit Hit',
            message: '${pos.contract.symbol} · +${pos.pnlPercent.toStringAsFixed(1)}%',
            type:    TradeLogType.win,
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
        final (newPositions, newRealized, newTotal, newWins) =
            _runScanner(surviving, state.chain, realizedPnL, totalTrades, winTrades);
        surviving
          ..clear()
          ..addAll(newPositions);
        realizedPnL = newRealized;
        totalTrades = newTotal;
        winTrades   = newWins;
      }

      emit(state.copyWith(
        positions:   surviving,
        realizedPnL: realizedPnL,
        totalTrades: totalTrades,
        winTrades:   winTrades,
      ));
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
      final exp   = state.selectedExpiration;
      final fallbackExp = state.termExpirations.isNotEmpty ? state.termExpirations.first : null;
      final selectedExp = exp ?? fallbackExp;
      final chain = selectedExp != null
          ? await _service.fetchChain(expiration: selectedExp)
          : (state.termFilter.mode == SpxTermMode.exact
              ? <OptionsContract>[]
              : _sim.refreshChain(dteDays: _simDteDays(state.termFilter)));
      final spot   = await _service.fetchSpxSpot();
      final gex    = SpxGreeksCalculator.calcGex(chain, spot);
      final mode   = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;
      emit(state.copyWith(
        chain: chain,
        spotPrice: spot,
        gexData: gex,
        dataMode: mode,
        selectedExpiration: selectedExp,
      ));
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
    final gex   = SpxGreeksCalculator.calcGex(chain, state.spotPrice);
    emit(state.copyWith(chain: chain, gexData: gex));
    _addLog('📅 Expiration: ${event.expiration}', TradeLogType.info);
  }

  void _onSelectContract(SelectSpxContract event, Emitter<SpxState> emit) {
    emit(state.copyWith(
      selectedSymbol:      event.symbol,
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
      _addLog('⚠️ Contract ${event.symbol} not found in chain', TradeLogType.warn);
      return;
    }
    if (contract.midPrice <= 0) {
      _addLog('⚠️ Invalid price for ${event.symbol}', TradeLogType.warn);
      return;
    }

    final pos = SpxPosition(
      id:             _uuid.v4(),
      contract:       contract,
      contracts:      event.contracts,
      entryPremium:   contract.midPrice,
      currentPremium: contract.midPrice,
      openedAt:       DateTime.now(),
    );

    _addLog(
      '🟢 BUY ${event.contracts}× ${contract.symbol} @ \$${contract.midPrice.toStringAsFixed(2)}'
      ' | Δ${contract.greeks.delta.toStringAsFixed(2)} | ${contract.daysToExpiry}DTE',
      TradeLogType.buy,
    );
    _emitAlert(
      title:   'SPX Buy',
      message: '${contract.symbol} · \$${contract.midPrice.toStringAsFixed(2)}',
      type:    TradeLogType.buy,
    );
    _recordEntry(
      pos,
      entrySource: 'manual', // free-form source bucket (manual | auto)
      entryReasonCode: SpxEntryReasonCodes.manualBuy,
      entryReasonText: 'Manual buy from chain/dashboard action.',
    );

    emit(state.copyWith(positions: [...state.positions, pos]));
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
    final sign = pnl >= 0 ? '+' : '';
    _addLog(
      '🔴 CLOSE ${pos.contract.symbol} — PnL: $sign\$${pnl.toStringAsFixed(2)}',
      pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    _emitAlert(
      title:   'SPX Close',
      message: '${pos.contract.symbol} · $sign\$${pnl.toStringAsFixed(2)}',
      type:    pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    emit(state.copyWith(
      positions:   state.positions.where((p) => p.id != event.positionId).toList(),
      realizedPnL: state.realizedPnL + pnl,
      totalTrades: state.totalTrades + 1,
      winTrades:   pnl > 0 ? state.winTrades + 1 : state.winTrades,
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

  Future<void> _onUpdateToken(
    UpdateTradierToken event,
    Emitter<SpxState> emit,
  ) async {
    _service = SpxOptionsService(
      apiToken: event.token,
      useSandbox: false,
      enforceMarketHours: false,
    );
    emit(state.copyWith(tradierToken: event.token));
    _addLog('🔑 Tradier token updated — retrying live feed', TradeLogType.system);
    add(const InitializeSpx());
  }

  Future<void> _onUpdateTermFilter(
    UpdateSpxTermFilter event,
    Emitter<SpxState> emit,
  ) async {
    final filteredExp = _filterExpirationsByTerm(state.expirations, event.filter);
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
    final gex  = SpxGreeksCalculator.calcGex(chain, spot);
    final mode = _service.isLive ? SpxDataMode.live : SpxDataMode.simulator;

    emit(state.copyWith(
      chain: chain,
      spotPrice: spot,
      gexData: gex,
      dataMode: mode,
    ));

    final label = event.filter.mode == SpxTermMode.exact
        ? 'Exact ${event.filter.exactDte}DTE'
        : 'Range ${event.filter.minDte}-${event.filter.maxDte}DTE';
    _addLog('🧭 SPX terms updated — $label', TradeLogType.info);
  }

  void _onResetDay(ResetSpxDay event, Emitter<SpxState> emit) {
    emit(state.copyWith(
      logs:        [],
      realizedPnL: 0,
      totalTrades: 0,
      winTrades:   0,
    ));
    _addLog('🔄 SPX daily stats reset', TradeLogType.system);
  }

  // ── Auto-scanner ──────────────────────────────────────────────────────────

  /// Returns updated (positions, realizedPnL, totalTrades, winTrades).
  (List<SpxPosition>, double, int, int) _runScanner(
    List<SpxPosition> current,
    List<OptionsContract> chain,
    double realizedPnL,
    int totalTrades,
    int winTrades,
  ) {
    final positions = List<SpxPosition>.from(current);
    var totalNotional = positions.fold<double>(
      0,
      (sum, p) => sum + (p.currentPremium * p.contracts * 100),
    );

    for (final contract in chain) {
      if (contract.signal != SpxSignalType.buy) continue;
      if (positions.length >= _maxAutoPositions) break;
      if (positions.any((p) => p.contract.symbol == contract.symbol)) continue;
      if (contract.midPrice <= 0) continue;
      final orderNotional = contract.midPrice * 100;
      if (orderNotional > _maxAutoPerTradeNotional) continue;
      if (totalNotional + orderNotional > _maxAutoPortfolioNotional) continue;

      final sameSide = positions
          .where((p) => p.contract.side == contract.side)
          .length;
      if (sameSide >= _maxAutoPerSide) continue;

      final sameDteBucket = positions
          .where((p) => p.contract.daysToExpiry == contract.daysToExpiry)
          .length;
      if (sameDteBucket >= _maxAutoPerDteBucket) continue;

      final pos = SpxPosition(
        id:             _uuid.v4(),
        contract:       contract,
        contracts:      1,
        entryPremium:   contract.midPrice,
        currentPremium: contract.midPrice,
        openedAt:       DateTime.now(),
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
        title:   'SPX Auto Entry',
        message: '${contract.symbol} · ${contract.daysToExpiry}DTE',
        type:    TradeLogType.buy,
      );
      _recordEntry(
        pos,
        entrySource: 'auto', // free-form source bucket (manual | auto)
        entryReasonCode: SpxEntryReasonCodes.autoScannerSignal,
        entryReasonText: 'Auto scanner selected buy signal contract.',
      );
    }

    return (positions, realizedPnL, totalTrades, winTrades);
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
      id:        _uuid.v4(),
      timestamp: DateTime.now(),
      message:   message,
      type:      type,
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
  }) {
    if (_alertController.isClosed) return;
    _alertController.add(TradeAlert(title: title, message: message, type: type));
  }

  void _recordEntry(
    SpxPosition pos, {
    required String entrySource,
    required String entryReasonCode,
    required String entryReasonText,
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
      'deltaInTargetRange':
          contract.greeks.delta.abs() >= 0.20 &&
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
    };
  }

  @override
  Future<void> close() {
    _tickTimer?.cancel();
    _alertController.close();
    return super.close();
  }
}
