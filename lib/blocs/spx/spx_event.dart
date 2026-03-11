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

class ApproveSpxOpportunity extends SpxEvent {
  final String opportunityId;
  final String symbol;
  const ApproveSpxOpportunity({
    required this.opportunityId,
    required this.symbol,
  });

  @override
  List<Object?> get props => [opportunityId, symbol];
}

class RejectSpxOpportunity extends SpxEvent {
  final String opportunityId;
  final String symbol;
  const RejectSpxOpportunity({
    required this.opportunityId,
    required this.symbol,
  });

  @override
  List<Object?> get props => [opportunityId, symbol];
}

class CancelSpxOpportunity extends SpxEvent {
  final String opportunityId;
  final String symbol;
  const CancelSpxOpportunity({
    required this.opportunityId,
    required this.symbol,
  });

  @override
  List<Object?> get props => [opportunityId, symbol];
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

class UpdateSpxExecutionSettings extends SpxEvent {
  final String executionMode;
  final int entryDelaySeconds;
  final int validationWindowSeconds;
  final double maxSlippagePct;
  final bool notificationsEnabled;

  const UpdateSpxExecutionSettings({
    required this.executionMode,
    required this.entryDelaySeconds,
    required this.validationWindowSeconds,
    required this.maxSlippagePct,
    required this.notificationsEnabled,
  });

  @override
  List<Object?> get props => [
        executionMode,
        entryDelaySeconds,
        validationWindowSeconds,
        maxSlippagePct,
        notificationsEnabled,
      ];
}

class UpdateSpxTermFilter extends SpxEvent {
  final SpxTermFilter filter;
  const UpdateSpxTermFilter(this.filter);
  @override
  List<Object?> get props => [filter];
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

class _ExecutePendingOpportunity extends SpxEvent {
  final String opportunityId;
  final String symbol;
  const _ExecutePendingOpportunity({
    required this.opportunityId,
    required this.symbol,
  });

  @override
  List<Object?> get props => [opportunityId, symbol];
}

class _ExpirePendingOpportunity extends SpxEvent {
  final String opportunityId;
  final String symbol;
  final String reasonCode;
  final String reasonText;

  const _ExpirePendingOpportunity({
    required this.opportunityId,
    required this.symbol,
    required this.reasonCode,
    required this.reasonText,
  });

  @override
  List<Object?> get props => [opportunityId, symbol, reasonCode, reasonText];
}
