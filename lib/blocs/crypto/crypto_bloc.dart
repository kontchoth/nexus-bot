import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/crypto_models.dart';
import '../../services/crypto/live_market_service.dart';
import '../../services/crypto/market_simulator.dart';

part 'crypto_event.dart';
part 'crypto_state.dart';

const _uuid = Uuid();

class CryptoBloc extends Bloc<CryptoEvent, CryptoState> {
  Timer? _marketTimer;
  int _tickCount = 0;
  final LiveMarketService _liveMarketService = LiveMarketService();
  final _alertController = StreamController<TradeAlert>.broadcast();
  bool _useLiveData = true;
  bool _tickInFlight = false;
  bool _liveErrorLogged = false;

  Stream<TradeAlert> get alertsStream => _alertController.stream;

  CryptoBloc() : super(CryptoState.initial()) {
    on<InitializeMarket>(_onInitialize);
    on<MarketTick>(_onMarketTick);
    on<ToggleBot>(_onToggleBot);
    on<BuyCoin>(_onBuyCoin);
    on<SellPosition>(_onSellPosition);
    on<SelectCoin>(_onSelectCoin);
    on<ChangeExchange>(_onChangeExchange);
    on<ChangeTimeframe>(_onChangeTimeframe);
    on<UpdateCapital>(_onUpdateCapital);
    on<UpdateAlertPreferences>(_onUpdateAlertPreferences);
    on<ResetDay>(_onResetDay);
    on<_AddLog>((event, emit) {
      final newLogs = [event.log, ...state.logs].take(80).toList();
      emit(state.copyWith(logs: newLogs));
    });
  }

  // ── Handlers ────────────────────────────────────────────────────────────────

  Future<void> _onInitialize(
      InitializeMarket event, Emitter<CryptoState> emit) async {
    List<CoinData> coins;
    try {
      coins =
          await _liveMarketService.fetchInitialCoins(state.selectedTimeframe);
      _useLiveData = true;
      _addLog('🟢 Live market mode enabled (Binance.US public feed)',
          TradeLogType.system);
    } catch (_) {
      coins = MarketSimulator.generateInitialCoins();
      _useLiveData = false;
      _addLog(
          '🟡 Live feed unavailable — using simulator data', TradeLogType.warn);
    }

    emit(state.copyWith(
      coins: coins,
      marketDataMode:
          _useLiveData ? MarketDataMode.live : MarketDataMode.simulator,
    ));

    _addLog('⚡ NexusBot initialized — Triple Confluence strategy loaded',
        TradeLogType.system);
    _addLog(
        _useLiveData
            ? '📡 Connected to Binance.US live market feed'
            : '📡 Running in simulation mode',
        TradeLogType.system);
    _addLog(
        '🎯 Daily target: \$500 | Capital: \$${state.stats.capital.toStringAsFixed(0)}',
        TradeLogType.system);

    _startMarketTimer();
  }

  Future<void> _onMarketTick(
      MarketTick event, Emitter<CryptoState> emit) async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      _tickCount++;

      List<CoinData> updatedCoins;
      var tickMode = state.marketDataMode;
      try {
        if (_useLiveData) {
          updatedCoins = await _liveMarketService.tickCoins(state.coins);
          _liveErrorLogged = false;
          tickMode = MarketDataMode.live;
        } else {
          updatedCoins = state.coins.map((coin) {
            final def = MarketSimulator.getDefFor(coin.symbol);
            return MarketSimulator.tick(coin, def);
          }).toList();
          tickMode = MarketDataMode.simulator;
        }
      } catch (_) {
        updatedCoins = state.coins.map((coin) {
          final def = MarketSimulator.getDefFor(coin.symbol);
          return MarketSimulator.tick(coin, def);
        }).toList();
        tickMode = MarketDataMode.simulator;
        if (!_liveErrorLogged) {
          _addLog('⚠️ Live feed error — temporary simulator fallback',
              TradeLogType.warn);
          _liveErrorLogged = true;
        }
      }

      // Retry live feed every 100 ticks while in simulator fallback
      if (!_useLiveData && _tickCount % 100 == 0) {
        try {
          final retryCoins = await _liveMarketService.tickCoins(state.coins);
          updatedCoins = retryCoins;
          _useLiveData = true;
          _liveErrorLogged = false;
          tickMode = MarketDataMode.live;
          _addLog('🟢 Live market feed restored', TradeLogType.system);
        } catch (_) {
          // Still unavailable — stay in simulator
        }
      }

      // Update open positions with new prices
      final updatedPositions = updatedCoins.isEmpty
          ? state.positions
          : state.positions.map((pos) {
              final coin = updatedCoins.firstWhere(
                (c) => c.symbol == pos.symbol,
                orElse: () => updatedCoins.first,
              );
              return pos.copyWith(currentPrice: coin.price);
            }).toList();

      var newStats = state.stats;

      // ── Stop-loss / take-profit sweep (runs every tick, bot on or off) ───────
      var newPositions = <Position>[];
      for (final pos in updatedPositions) {
        if (pos.isStopLossHit) {
          final pnl = pos.unrealizedPnL;
          _addLog(
            '🛑 STOP-LOSS ${pos.symbol} @ ${_fmtPrice(pos.currentPrice)} — PnL: \$${pnl.toStringAsFixed(2)} (${pos.pnlPercent.toStringAsFixed(2)}%)',
            TradeLogType.loss,
          );
          _emitTradeAlert(
            title: 'Stop-Loss Triggered',
            message: '${pos.symbol} · ${pos.pnlPercent.toStringAsFixed(2)}%',
            type: TradeLogType.loss,
          );
          newStats = newStats.copyWith(
            realizedPnL: newStats.realizedPnL + pnl,
            totalTrades: newStats.totalTrades + 1,
          );
        } else if (pos.isTakeProfitHit) {
          final pnl = pos.unrealizedPnL;
          _addLog(
            '🎯 TAKE-PROFIT ${pos.symbol} @ ${_fmtPrice(pos.currentPrice)} — PnL: +\$${pnl.toStringAsFixed(2)} (${pos.pnlPercent.toStringAsFixed(2)}%)',
            TradeLogType.win,
          );
          _emitTradeAlert(
            title: 'Take-Profit Hit',
            message: '${pos.symbol} · +${pos.pnlPercent.toStringAsFixed(2)}%',
            type: TradeLogType.win,
          );
          newStats = newStats.copyWith(
            realizedPnL: newStats.realizedPnL + pnl,
            totalTrades: newStats.totalTrades + 1,
            winTrades: newStats.winTrades + 1,
          );
        } else {
          newPositions.add(pos);
        }
      }

      // Recalculate unrealized PnL from surviving positions only
      newStats = newStats.copyWith(
        unrealizedPnL:
            newPositions.fold<double>(0.0, (s, p) => s + p.unrealizedPnL),
      );

      if (state.botStatus == BotStatus.active && _tickCount % 8 == 0) {
        for (final coin in updatedCoins) {
          final sig = coin.indicators.signal;

          // Auto BUY
          if (sig == SignalType.buy &&
              coin.indicators.signalStrength >= 3 &&
              coin.price > 0 &&
              !newPositions.any((p) => p.symbol == coin.symbol) &&
              newPositions.length < 8) {
            final size = state.stats.capital * 0.05;
            final pos = Position(
              id: _uuid.v4(),
              symbol: coin.symbol,
              entryPrice: coin.price,
              currentPrice: coin.price,
              size: size,
              quantity: size / coin.price,
              openedAt: DateTime.now(),
              exchange: state.selectedExchange,
              stopLossPct: 0.05,
              takeProfitPct: 0.10,
            );
            newPositions.add(pos);
            _addLog(
              '🟢 AUTO BUY ${coin.symbol} @ ${coin.formattedPrice} — Size: \$${size.toStringAsFixed(0)}',
              TradeLogType.buy,
            );
            _emitTradeAlert(
              title: 'Auto Buy',
              message: '${coin.symbol} at ${coin.formattedPrice}',
              type: TradeLogType.buy,
            );
          }

          // Auto SELL
          if (sig == SignalType.sell) {
            final posIdx =
                newPositions.indexWhere((p) => p.symbol == coin.symbol);
            if (posIdx != -1) {
              final pos = newPositions[posIdx];
              final pnl = pos.unrealizedPnL;
              final sign = pnl >= 0 ? '+' : '';
              _addLog(
                '🔴 AUTO SELL ${coin.symbol} @ ${coin.formattedPrice} — PnL: $sign\$${pnl.toStringAsFixed(2)}',
                pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
              );
              _emitTradeAlert(
                title: 'Auto Sell',
                message:
                    '${coin.symbol} · PnL $sign\$${pnl.toStringAsFixed(2)}',
                type: pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
              );
              newPositions.removeAt(posIdx);
              newStats = newStats.copyWith(
                realizedPnL: newStats.realizedPnL + pnl,
                totalTrades: newStats.totalTrades + 1,
                winTrades:
                    pnl > 0 ? newStats.winTrades + 1 : newStats.winTrades,
              );
            }
          }
        }
      }

      emit(state.copyWith(
        coins: updatedCoins,
        positions: newPositions,
        stats: newStats,
        marketDataMode: tickMode,
      ));
    } finally {
      _tickInFlight = false;
    }
  }

  void _onToggleBot(ToggleBot event, Emitter<CryptoState> emit) {
    final newStatus = state.botStatus == BotStatus.active
        ? BotStatus.paused
        : BotStatus.active;
    emit(state.copyWith(botStatus: newStatus));
    _addLog(
      newStatus == BotStatus.active
          ? '▶ Bot activated — scanning markets'
          : '⏸ Bot paused by user',
      newStatus == BotStatus.active ? TradeLogType.system : TradeLogType.warn,
    );
  }

  void _onBuyCoin(BuyCoin event, Emitter<CryptoState> emit) {
    if (state.positions.any((p) => p.symbol == event.symbol)) {
      _addLog('⚠️ Already holding ${event.symbol}', TradeLogType.warn);
      return;
    }
    final coinIdx = state.coins.indexWhere((c) => c.symbol == event.symbol);
    if (coinIdx == -1) {
      _addLog('⚠️ Coin ${event.symbol} not found', TradeLogType.warn);
      return;
    }
    final coin = state.coins[coinIdx];
    if (coin.price <= 0) {
      _addLog('⚠️ Invalid price for ${event.symbol}', TradeLogType.warn);
      return;
    }
    final size = state.stats.capital * 0.05;
    final pos = Position(
      id: _uuid.v4(),
      symbol: coin.symbol,
      entryPrice: coin.price,
      currentPrice: coin.price,
      size: size,
      quantity: size / coin.price,
      openedAt: DateTime.now(),
      exchange: state.selectedExchange,
      stopLossPct: 0.05,
      takeProfitPct: 0.10,
    );
    _addLog(
      '🟢 MANUAL BUY ${coin.symbol} @ ${coin.formattedPrice} — Size: \$${size.toStringAsFixed(0)}',
      TradeLogType.buy,
    );
    _emitTradeAlert(
      title: 'Manual Buy',
      message: '${coin.symbol} at ${coin.formattedPrice}',
      type: TradeLogType.buy,
    );
    emit(state.copyWith(
      positions: [...state.positions, pos],
    ));
  }

  void _onSellPosition(SellPosition event, Emitter<CryptoState> emit) {
    final posIdx = state.positions.indexWhere((p) => p.id == event.positionId);
    if (posIdx == -1) return;
    final pos = state.positions[posIdx];
    final pnl = pos.unrealizedPnL;
    final sign = pnl >= 0 ? '+' : '';
    _addLog(
      '🔴 MANUAL SELL ${pos.symbol} — PnL: $sign\$${pnl.toStringAsFixed(2)}',
      pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    _emitTradeAlert(
      title: 'Manual Sell',
      message: '${pos.symbol} · PnL $sign\$${pnl.toStringAsFixed(2)}',
      type: pnl >= 0 ? TradeLogType.win : TradeLogType.loss,
    );
    emit(state.copyWith(
      positions:
          state.positions.where((p) => p.id != event.positionId).toList(),
      stats: state.stats.copyWith(
        realizedPnL: state.stats.realizedPnL + pnl,
        unrealizedPnL: state.stats.unrealizedPnL - pnl,
        totalTrades: state.stats.totalTrades + 1,
        winTrades: pnl > 0 ? state.stats.winTrades + 1 : state.stats.winTrades,
      ),
    ));
  }

  void _onSelectCoin(SelectCoin event, Emitter<CryptoState> emit) {
    emit(state.copyWith(
      selectedSymbol:
          event.symbol == state.selectedSymbol ? null : event.symbol,
    ));
  }

  void _onChangeExchange(ChangeExchange event, Emitter<CryptoState> emit) {
    emit(state.copyWith(selectedExchange: event.exchange));
    _addLog('🔄 Switched to ${event.exchange.label}', TradeLogType.info);
  }

  void _onChangeTimeframe(ChangeTimeframe event, Emitter<CryptoState> emit) {
    emit(state.copyWith(selectedTimeframe: event.timeframe));
  }

  void _onUpdateCapital(UpdateCapital event, Emitter<CryptoState> emit) {
    if (event.capital <= 0) return;
    emit(state.copyWith(
      stats: state.stats.copyWith(capital: event.capital),
    ));
  }

  void _onUpdateAlertPreferences(
    UpdateAlertPreferences event,
    Emitter<CryptoState> emit,
  ) {
    emit(state.copyWith(
      alertsEnabled: event.alertsEnabled,
      hapticsEnabled: event.hapticsEnabled,
    ));
  }

  void _onResetDay(ResetDay event, Emitter<CryptoState> emit) {
    emit(state.copyWith(
      stats: DailyStats(capital: state.stats.capital),
      logs: [],
    ));
    _addLog('🔄 Daily stats reset', TradeLogType.system);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _startMarketTimer() {
    _marketTimer?.cancel();
    _marketTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      add(MarketTick());
    });
  }

  void _addLog(String message, TradeLogType type) {
    final log = TradeLog(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      message: message,
      type: type,
    );
    add(_AddLog(log));
  }

  String _fmtPrice(double p) =>
      p >= 1000 ? p.toStringAsFixed(2) : p.toStringAsFixed(4);

  void _emitTradeAlert({
    required String title,
    required String message,
    required TradeLogType type,
  }) {
    if (!state.alertsEnabled) return;
    if (_alertController.isClosed) return;
    _alertController.add(TradeAlert(
      title: title,
      message: message,
      type: type,
    ));
  }

  @override
  Future<void> close() {
    _marketTimer?.cancel();
    _alertController.close();
    return super.close();
  }
}

// Internal event for adding logs
class _AddLog extends CryptoEvent {
  final TradeLog log;
  const _AddLog(this.log);
  @override
  List<Object?> get props => [log.id];
}
