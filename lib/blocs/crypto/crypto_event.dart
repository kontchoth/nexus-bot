part of 'crypto_bloc.dart';

abstract class CryptoEvent extends Equatable {
  const CryptoEvent();
  @override
  List<Object?> get props => [];
}

class InitializeMarket extends CryptoEvent {}

class MarketTick extends CryptoEvent {}

class LoadCryptoOpportunities extends CryptoEvent {}

class RefreshCryptoOpportunities extends CryptoEvent {}

class ToggleBot extends CryptoEvent {}

class ResetDay extends CryptoEvent {}

class BuyCoin extends CryptoEvent {
  final String symbol;
  const BuyCoin(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class SellPosition extends CryptoEvent {
  final String positionId;
  const SellPosition(this.positionId);
  @override
  List<Object?> get props => [positionId];
}

class SelectCoin extends CryptoEvent {
  final String? symbol;
  const SelectCoin(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

class SelectCryptoOpportunity extends CryptoEvent {
  final String? opportunityId;
  const SelectCryptoOpportunity(this.opportunityId);

  @override
  List<Object?> get props => [opportunityId];
}

class ChangeExchange extends CryptoEvent {
  final Exchange exchange;
  const ChangeExchange(this.exchange);
  @override
  List<Object?> get props => [exchange];
}

class ChangeCryptoScannerView extends CryptoEvent {
  final CryptoScannerViewMode viewMode;
  const ChangeCryptoScannerView(this.viewMode);

  @override
  List<Object?> get props => [viewMode];
}

class ChangeTimeframe extends CryptoEvent {
  final Timeframe timeframe;
  const ChangeTimeframe(this.timeframe);
  @override
  List<Object?> get props => [timeframe];
}

class UpdateCapital extends CryptoEvent {
  final double capital;
  const UpdateCapital(this.capital);
  @override
  List<Object?> get props => [capital];
}

class UpdateAlertPreferences extends CryptoEvent {
  final bool alertsEnabled;
  final bool hapticsEnabled;
  const UpdateAlertPreferences({
    required this.alertsEnabled,
    required this.hapticsEnabled,
  });
  @override
  List<Object?> get props => [alertsEnabled, hapticsEnabled];
}

class UpdateCryptoDataProvider extends CryptoEvent {
  final CryptoDataProvider provider;
  const UpdateCryptoDataProvider(this.provider);

  @override
  List<Object?> get props => [provider];
}

class UpdateRobinhoodToken extends CryptoEvent {
  final String token;
  const UpdateRobinhoodToken(this.token);

  @override
  List<Object?> get props => [token];
}
