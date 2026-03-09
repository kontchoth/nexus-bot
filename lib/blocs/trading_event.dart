part of 'trading_bloc.dart';

abstract class TradingEvent extends Equatable {
  const TradingEvent();
  @override
  List<Object?> get props => [];
}

class InitializeMarket extends TradingEvent {}

class MarketTick extends TradingEvent {}

class ToggleBot extends TradingEvent {}

class ResetDay extends TradingEvent {}

class BuyCoin extends TradingEvent {
  final String symbol;
  const BuyCoin(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class SellPosition extends TradingEvent {
  final String positionId;
  const SellPosition(this.positionId);
  @override
  List<Object?> get props => [positionId];
}

class SelectCoin extends TradingEvent {
  final String? symbol;
  const SelectCoin(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class ChangeExchange extends TradingEvent {
  final Exchange exchange;
  const ChangeExchange(this.exchange);
  @override
  List<Object?> get props => [exchange];
}

class ChangeTimeframe extends TradingEvent {
  final Timeframe timeframe;
  const ChangeTimeframe(this.timeframe);
  @override
  List<Object?> get props => [timeframe];
}

class ChangeTab extends TradingEvent {
  final int tab;
  const ChangeTab(this.tab);
  @override
  List<Object?> get props => [tab];
}

class UpdateCapital extends TradingEvent {
  final double capital;
  const UpdateCapital(this.capital);
  @override
  List<Object?> get props => [capital];
}

class UpdateAlertPreferences extends TradingEvent {
  final bool alertsEnabled;
  final bool hapticsEnabled;
  const UpdateAlertPreferences({
    required this.alertsEnabled,
    required this.hapticsEnabled,
  });

  @override
  List<Object?> get props => [alertsEnabled, hapticsEnabled];
}
