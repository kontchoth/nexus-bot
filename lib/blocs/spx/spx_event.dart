part of 'spx_bloc.dart';

abstract class SpxEvent extends Equatable {
  const SpxEvent();
  @override
  List<Object?> get props => [];
}

/// Initialise the SPX module: load chain, spot, GEX.
class InitializeSpx extends SpxEvent {
  const InitializeSpx();
}

/// Periodic market tick — refresh spot price and re-price positions.
class SpxMarketTick extends SpxEvent {
  const SpxMarketTick();
}

/// Reload a fresh options chain for the selected expiration.
class RefreshSpxChain extends SpxEvent {
  const RefreshSpxChain();
}

/// Change the displayed expiration date.
class SelectExpiration extends SpxEvent {
  final String expiration; // YYYY-MM-DD
  const SelectExpiration(this.expiration);
  @override
  List<Object?> get props => [expiration];
}

/// Highlight a single contract in the chain screen.
class SelectSpxContract extends SpxEvent {
  final String? symbol;
  const SelectSpxContract(this.symbol);
  @override
  List<Object?> get props => [symbol];
}

/// Manually open a long options position.
class BuySpxContract extends SpxEvent {
  final String symbol;
  final int contracts;
  const BuySpxContract({required this.symbol, this.contracts = 1});
  @override
  List<Object?> get props => [symbol, contracts];
}

/// Close an open SPX position by id.
class CloseSpxPosition extends SpxEvent {
  final String positionId;
  const CloseSpxPosition(this.positionId);
  @override
  List<Object?> get props => [positionId];
}

/// Toggle the SPX auto-scanner on/off.
class ToggleSpxScanner extends SpxEvent {
  const ToggleSpxScanner();
}

/// Update the Tradier API token (triggers live-data retry).
class UpdateTradierToken extends SpxEvent {
  final String token;
  const UpdateTradierToken(this.token);
  @override
  List<Object?> get props => [token];
}

/// Reset daily P&L and log.
class ResetSpxDay extends SpxEvent {
  const ResetSpxDay();
}

// Internal event — append a log entry.
class _SpxAddLog extends SpxEvent {
  final TradeLog log;
  const _SpxAddLog(this.log);
  @override
  List<Object?> get props => [log.id];
}
