import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../services/app_settings_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';
import 'spx_greeks_panel.dart';

class SpxChainScreen extends StatelessWidget {
  const SpxChainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      builder: (context, state) {
        return Column(
          children: [
            _ExpirationBar(state: state),
            _SpotGexBar(state: state),
            if (state.filteredChain.isNotEmpty)
              _StrikeLadderPanel(state: state),
            Expanded(
              child: state.filteredChain.isEmpty
                  ? _EmptyChain(state: state)
                  : _ChainList(state: state),
            ),
          ],
        );
      },
    );
  }
}

// ── Expiration selector ───────────────────────────────────────────────────────

class _ExpirationBar extends StatelessWidget {
  final SpxState state;
  const _ExpirationBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final expirations = state.termExpirations;
    if (expirations.isEmpty) return const SizedBox.shrink();
    final selected = expirations.contains(state.selectedExpiration)
        ? state.selectedExpiration
        : expirations.first;
    final termLabel = state.termFilter.mode == SpxTermMode.exact
        ? '${state.termFilter.exactDte}DTE'
        : '${state.termFilter.minDte}-${state.termFilter.maxDte}DTE';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: AppTheme.bg2,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.blue.withValues(alpha: 0.4)),
            ),
            child: Text(
              termLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.blue,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  dropdownColor: AppTheme.bg2,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textMuted,
                  ),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  items: expirations.map((exp) {
                    final expiry = DateTime.tryParse(exp);
                    final dte =
                        expiry?.difference(DateTime.now()).inDays.clamp(0, 365);
                    final label = dte == null ? exp : '$exp  ·  ${dte}DTE';
                    return DropdownMenuItem<String>(
                      value: exp,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<SpxBloc>().add(SelectExpiration(value));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Spot + GEX summary bar ────────────────────────────────────────────────────

class _SpotGexBar extends StatelessWidget {
  final SpxState state;
  const _SpotGexBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final gex = state.gexData;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          _InfoChip(
            label: 'SPX',
            value: NexusFormatters.number(state.spotPrice, decimals: 2),
            color: AppTheme.textPrimary,
          ),
          const SizedBox(width: 16),
          if (gex != null) ...[
            _InfoChip(
              label: 'Net GEX',
              value:
                  '${gex.netGex >= 0 ? '+' : ''}${gex.netGex.toStringAsFixed(2)}B',
              color: gex.isPositiveGex ? AppTheme.green : AppTheme.red,
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'γ Wall',
              value: gex.gammaWall == null
                  ? '—'
                  : NexusFormatters.usd(gex.gammaWall!, decimals: 0),
              color: AppTheme.gold,
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'Put Wall',
              value: gex.putWall == null
                  ? '—'
                  : NexusFormatters.usd(gex.putWall!, decimals: 0),
              color: AppTheme.red,
            ),
          ],
          const Spacer(),
          _MarketChip(isOpen: state.isMarketOpen),
          const SizedBox(width: 6),
          _ModeChip(
            mode: state.dataMode,
            tradierEnvironment: state.tradierEnvironment,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, color: AppTheme.textMuted, letterSpacing: 0.8)),
        Text(value,
            style: GoogleFonts.syne(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  final SpxDataMode mode;
  final String tradierEnvironment;

  const _ModeChip({
    required this.mode,
    required this.tradierEnvironment,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = mode == SpxDataMode.live;
    final label = !isLive
        ? 'SIM'
        : (SpxTradierEnvironment.isSandbox(tradierEnvironment)
            ? 'SBX'
            : 'LIVE');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isLive ? AppTheme.greenBg : AppTheme.bg3,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isLive
              ? AppTheme.green.withValues(alpha: 0.45)
              : AppTheme.border2,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isLive ? AppTheme.green : AppTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MarketChip extends StatelessWidget {
  final bool isOpen;
  const _MarketChip({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen ? AppTheme.greenBg : AppTheme.redBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOpen
              ? AppTheme.green.withValues(alpha: 0.45)
              : AppTheme.red.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        isOpen ? 'MKT OPEN' : 'MKT CLOSED',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isOpen ? AppTheme.green : AppTheme.red,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Strike ladder ────────────────────────────────────────────────────────────

class _StrikeLadderPanel extends StatelessWidget {
  final SpxState state;

  const _StrikeLadderPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final rows = _buildStrikeLadderRows(state.filteredChain, state.spotPrice);
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxBodyHeight = math.min(
      280.0,
      MediaQuery.sizeOf(context).height * 0.34,
    );

    final selectedContract = state.selectedContract;
    final selectedStrike = selectedContract?.strike;
    final nearestStrike = _nearestStrike(rows, state.spotPrice);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'STRIKE LADDER',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bg4,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.border2),
                ),
                child: Text(
                  'Spot ${NexusFormatters.number(state.spotPrice, decimals: 1)}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxBodyHeight),
            child: Scrollbar(
              thumbVisibility: rows.length > 4,
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  children: rows.map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _StrikeLadderRow(
                        row: row,
                        spot: state.spotPrice,
                        isNearestSpot: row.strike == nearestStrike,
                        isSelectedStrike: selectedStrike != null &&
                            row.strike == selectedStrike,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrikeLadderRow extends StatelessWidget {
  final _StrikeLadderRowData row;
  final double spot;
  final bool isNearestSpot;
  final bool isSelectedStrike;

  const _StrikeLadderRow({
    required this.row,
    required this.spot,
    required this.isNearestSpot,
    required this.isSelectedStrike,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelectedStrike
        ? AppTheme.blue.withValues(alpha: 0.55)
        : (isNearestSpot
            ? AppTheme.gold.withValues(alpha: 0.38)
            : AppTheme.border);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LadderSideCell(
              label: 'CALL',
              contract: row.call,
              spot: spot,
              alignEnd: true,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 88,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: isNearestSpot
                  ? AppTheme.gold.withValues(alpha: 0.1)
                  : AppTheme.bg4,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isNearestSpot
                    ? AppTheme.gold.withValues(alpha: 0.36)
                    : AppTheme.border2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  NexusFormatters.number(row.strike, decimals: 0),
                  style: GoogleFonts.syne(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isNearestSpot ? AppTheme.gold : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSelectedStrike
                      ? 'SELECTED'
                      : (isNearestSpot ? 'SPOT ROW' : 'STRIKE'),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    color: isSelectedStrike
                        ? AppTheme.blue
                        : (isNearestSpot ? AppTheme.gold : AppTheme.textMuted),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LadderSideCell(
              label: 'PUT',
              contract: row.put,
              spot: spot,
              alignEnd: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _LadderSideCell extends StatelessWidget {
  final String label;
  final OptionsContract? contract;
  final double spot;
  final bool alignEnd;

  const _LadderSideCell({
    required this.label,
    required this.contract,
    required this.spot,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final alignment =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    if (contract == null) {
      return Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: AppTheme.textDim,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '—',
            style: GoogleFonts.syne(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDim,
            ),
          ),
        ],
      );
    }

    final moneyness = contract!.moneynessForSpot(spot);
    final color = switch (moneyness) {
      SpxContractMoneyness.itm => AppTheme.blue,
      SpxContractMoneyness.atm => AppTheme.gold,
      SpxContractMoneyness.otm => AppTheme.textMuted,
    };

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: AppTheme.textDim,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          NexusFormatters.usd(contract!.midPrice),
          style: GoogleFonts.syne(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_moneynessLabel(moneyness)}  Δ${contract!.greeks.delta.abs().toStringAsFixed(2)}',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

String _moneynessLabel(SpxContractMoneyness value) {
  return switch (value) {
    SpxContractMoneyness.itm => 'ITM',
    SpxContractMoneyness.atm => 'ATM',
    SpxContractMoneyness.otm => 'OTM',
  };
}

double? _nearestStrike(List<_StrikeLadderRowData> rows, double spot) {
  if (rows.isEmpty) return null;
  final sorted = [
    ...rows
  ]..sort((a, b) => (a.strike - spot).abs().compareTo((b.strike - spot).abs()));
  return sorted.first.strike;
}

List<_StrikeLadderRowData> _buildStrikeLadderRows(
  List<OptionsContract> chain,
  double spot, {
  int maxRows = 7,
}) {
  if (chain.isEmpty) return const <_StrikeLadderRowData>[];

  final callByStrike = <double, OptionsContract>{};
  final putByStrike = <double, OptionsContract>{};
  for (final contract in chain) {
    if (contract.side == OptionsSide.call) {
      callByStrike[contract.strike] = contract;
    } else {
      putByStrike[contract.strike] = contract;
    }
  }

  final strikes = {
    ...callByStrike.keys,
    ...putByStrike.keys,
  }.toList()
    ..sort();
  if (strikes.isEmpty) return const <_StrikeLadderRowData>[];

  final focusStrike = strikes.reduce((a, b) {
    return (a - spot).abs() <= (b - spot).abs() ? a : b;
  });
  final focusIndex = strikes.indexOf(focusStrike);
  final halfWindow = maxRows ~/ 2;
  var start = math.max(0, focusIndex - halfWindow);
  var end = math.min(strikes.length, start + maxRows);
  start = math.max(0, end - maxRows);

  final window = strikes.sublist(start, end);
  return window.reversed
      .map((strike) => _StrikeLadderRowData(
            strike: strike,
            call: callByStrike[strike],
            put: putByStrike[strike],
          ))
      .toList();
}

class _StrikeLadderRowData {
  final double strike;
  final OptionsContract? call;
  final OptionsContract? put;

  const _StrikeLadderRowData({
    required this.strike,
    required this.call,
    required this.put,
  });
}

// ── Chain list ────────────────────────────────────────────────────────────────

class _ChainList extends StatelessWidget {
  final SpxState state;
  const _ChainList({required this.state});

  @override
  Widget build(BuildContext context) {
    final chain = state.filteredChain;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: chain.length,
      itemBuilder: (context, i) {
        final contract = chain[i];
        final isSelected = contract.symbol == state.selectedSymbol;
        return _ContractTile(
          contract: contract,
          spot: state.spotPrice,
          isSelected: isSelected,
        );
      },
    );
  }
}

class _ContractTile extends StatelessWidget {
  final OptionsContract contract;
  final double spot;
  final bool isSelected;
  const _ContractTile({
    required this.contract,
    required this.spot,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isCall = contract.side == OptionsSide.call;
    final moneyness = contract.moneynessForSpot(spot);
    final isAtm = moneyness == SpxContractMoneyness.atm;
    final signalColor = switch (contract.signal) {
      SpxSignalType.buy => AppTheme.green,
      SpxSignalType.sell => AppTheme.red,
      SpxSignalType.watch => AppTheme.textMuted,
    };

    return GestureDetector(
      onTap: () => context.read<SpxBloc>().add(
            SelectSpxContract(
              isSelected ? null : contract.symbol,
            ),
          ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.blue.withValues(alpha: 0.08)
              : isAtm
                  ? AppTheme.bg3
                  : AppTheme.bg2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppTheme.blue.withValues(alpha: 0.5)
                : isAtm
                    ? AppTheme.border2
                    : AppTheme.border,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Side badge
                  Container(
                    width: 32,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: (isCall ? AppTheme.green : AppTheme.red)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isCall ? 'C' : 'P',
                      style: GoogleFonts.syne(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isCall ? AppTheme.green : AppTheme.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Strike
                  Text(
                    NexusFormatters.number(contract.strike, decimals: 0),
                    style: GoogleFonts.syne(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isAtm ? AppTheme.gold : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _MoneynessBadge(moneyness: moneyness),
                  const Spacer(),
                  // Mid price
                  Text(
                    NexusFormatters.usd(contract.midPrice),
                    style: GoogleFonts.syne(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  // Delta
                  _MetaTag(
                    label: 'Δ',
                    value: contract.greeks.delta.toStringAsFixed(2),
                    color: contract.isTargetDelta
                        ? AppTheme.blue
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  // DTE
                  _MetaTag(
                    label: 'DTE',
                    value: '${contract.daysToExpiry}',
                    color: contract.isDteWarning
                        ? AppTheme.red
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  // Signal dot
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: signalColor),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const Divider(height: 1, color: AppTheme.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SpxGreeksPanel(
                      greeks: contract.greeks,
                      impliedVolatility: contract.impliedVolatility,
                      ivRank: contract.ivRank,
                    ),
                    const SizedBox(height: 8),
                    _BidAskRow(contract: contract),
                    const SizedBox(height: 10),
                    _ExpiryPayoffPanel(
                      contract: contract,
                      currentSpot: spot,
                    ),
                    const SizedBox(height: 8),
                    _BuyButton(contract: contract),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoneynessBadge extends StatelessWidget {
  final SpxContractMoneyness moneyness;

  const _MoneynessBadge({required this.moneyness});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (moneyness) {
      SpxContractMoneyness.itm => ('ITM', AppTheme.blue),
      SpxContractMoneyness.atm => ('ATM', AppTheme.gold),
      SpxContractMoneyness.otm => ('OTM', AppTheme.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetaTag(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style:
                GoogleFonts.spaceGrotesk(fontSize: 9, color: AppTheme.textDim)),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _BidAskRow extends StatelessWidget {
  final OptionsContract contract;
  const _BidAskRow({required this.contract});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BidAskCell(
          label: 'Bid',
          value: NexusFormatters.number(contract.bid, decimals: 2),
        ),
        const SizedBox(width: 8),
        _BidAskCell(
          label: 'Ask',
          value: NexusFormatters.number(contract.ask, decimals: 2),
        ),
        const SizedBox(width: 8),
        _BidAskCell(label: 'OI', value: _fmtInt(contract.openInterest)),
        const SizedBox(width: 8),
        _BidAskCell(label: 'Vol', value: _fmtInt(contract.volume)),
      ],
    );
  }

  String _fmtInt(int n) =>
      n >= 1000 ? NexusFormatters.compactNumber(n).toLowerCase() : '$n';
}

class _BidAskCell extends StatelessWidget {
  final String label;
  final String value;
  const _BidAskCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                GoogleFonts.spaceGrotesk(fontSize: 8, color: AppTheme.textDim)),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: AppTheme.textPrimary)),
      ],
    );
  }
}

class _ExpiryPayoffPanel extends StatelessWidget {
  final OptionsContract contract;
  final double currentSpot;

  const _ExpiryPayoffPanel({
    required this.contract,
    required this.currentSpot,
  });

  @override
  Widget build(BuildContext context) {
    final premium = contract.midPrice;
    final breakEven = contract.breakEvenSpot(premium: premium);
    final currentExpiryPnl = contract.payoffAtExpiry(
      currentSpot,
      premium: premium,
    );
    final maxLoss = -(premium * 100);
    final lineColor =
        contract.side == OptionsSide.call ? AppTheme.green : AppTheme.red;

    final baseLow = math.min(
      math.min(contract.strike, currentSpot),
      breakEven,
    );
    final baseHigh = math.max(
      math.max(contract.strike, currentSpot),
      breakEven,
    );
    final xPadding = math.max(75.0, (baseHigh - baseLow) * 0.8);
    final minSpot = math.max(0.0, baseLow - xPadding);
    final maxSpot = baseHigh + xPadding;

    final xValues = <double>{
      for (var i = 0; i <= 24; i += 1) minSpot + ((maxSpot - minSpot) / 24) * i,
      currentSpot,
      contract.strike,
      breakEven,
    }.toList()
      ..sort();

    final points = xValues
        .map(
          (spot) => FlSpot(
            spot,
            contract.payoffAtExpiry(spot, premium: premium),
          ),
        )
        .toList();

    final yValues = [
      ...points.map((point) => point.y),
      0.0,
    ];
    final minY = yValues.reduce(math.min);
    final maxY = yValues.reduce(math.max);
    final yPadding = math.max(100.0, (maxY - minY) * 0.18);
    final bottomY = minY - yPadding;
    final topY = maxY + yPadding;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EXPIRY PAYOFF',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: lineColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: lineColor.withValues(alpha: 0.28)),
                ),
                child: Text(
                  contract.side == OptionsSide.call ? 'CALL' : 'PUT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    color: lineColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _PayoffStatChip(
                label: 'Strike',
                value: NexusFormatters.number(contract.strike, decimals: 0),
                color: AppTheme.textPrimary,
              ),
              _PayoffStatChip(
                label: 'B/E',
                value: NexusFormatters.number(breakEven, decimals: 1),
                color: AppTheme.gold,
              ),
              _PayoffStatChip(
                label: 'At Spot',
                value: NexusFormatters.usd(currentExpiryPnl, signed: true),
                color: currentExpiryPnl >= 0 ? AppTheme.green : AppTheme.red,
              ),
              _PayoffStatChip(
                label: 'Max Loss',
                value: NexusFormatters.usd(maxLoss),
                color: AppTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: minSpot,
                maxX: maxSpot,
                minY: bottomY,
                maxY: topY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _nicePayoffYAxisInterval(topY - bottomY),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: value == 0
                        ? AppTheme.textPrimary.withValues(alpha: 0.28)
                        : AppTheme.border.withValues(alpha: 0.35),
                    strokeWidth: value == 0 ? 1.4 : 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 54,
                      interval: _nicePayoffYAxisInterval(topY - bottomY),
                      getTitlesWidget: (value, meta) {
                        return Text(
                          NexusFormatters.usd(value, decimals: 0),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            color: AppTheme.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (maxSpot - minSpot) / 2,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          NexusFormatters.number(value, decimals: 0),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            color: AppTheme.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: AppTheme.textPrimary.withValues(alpha: 0.28),
                      strokeWidth: 1.4,
                    ),
                  ],
                  verticalLines: [
                    VerticalLine(
                      x: currentSpot,
                      color: AppTheme.blue.withValues(alpha: 0.5),
                      strokeWidth: 1.2,
                      dashArray: const [4, 4],
                    ),
                    VerticalLine(
                      x: breakEven,
                      color: AppTheme.gold.withValues(alpha: 0.55),
                      strokeWidth: 1.2,
                      dashArray: const [4, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${NexusFormatters.number(spot.x, decimals: 1)}\n${NexusFormatters.usd(spot.y, signed: true)}',
                          GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: false,
                    color: lineColor,
                    barWidth: 2.2,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, barData) {
                        return (spot.x - currentSpot).abs() < 0.001 ||
                            (spot.x - breakEven).abs() < 0.001;
                      },
                      getDotPainter: (spot, percent, barData, index) {
                        final isBreakEven = (spot.x - breakEven).abs() < 0.001;
                        return FlDotCirclePainter(
                          radius: 3.8,
                          color: isBreakEven ? AppTheme.gold : AppTheme.blue,
                          strokeWidth: 1.8,
                          strokeColor: AppTheme.bg2,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 150),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoffStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PayoffStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bg4,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

double _nicePayoffYAxisInterval(double span) {
  if (span <= 400) return 100;
  if (span <= 1200) return 250;
  if (span <= 2400) return 500;
  return 1000;
}

class _BuyButton extends StatelessWidget {
  final OptionsContract contract;
  const _BuyButton({required this.contract});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          context.read<SpxBloc>().add(BuySpxContract(symbol: contract.symbol)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.greenBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          'BUY 1 CONTRACT  ·  ${NexusFormatters.usd(contract.midPrice * 100, decimals: 0)} debit',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.green,
          ),
        ),
      ),
    );
  }
}

class _EmptyChain extends StatelessWidget {
  final SpxState state;
  const _EmptyChain({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasTermMatches = state.termExpirations.isNotEmpty;
    final message = !hasTermMatches
        ? (state.termFilter.mode == SpxTermMode.exact
            ? 'No contracts for ${state.termFilter.exactDte}DTE right now'
            : 'No contracts in ${state.termFilter.minDte}-${state.termFilter.maxDte}DTE')
        : 'Loading options chain…';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.show_chart, size: 40, color: AppTheme.textDim),
          const SizedBox(height: 12),
          Text(message,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
