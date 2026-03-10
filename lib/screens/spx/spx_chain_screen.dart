import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../models/spx_models.dart';
import '../../theme/app_theme.dart';
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
            Expanded(
              child: state.filteredChain.isEmpty
                  ? const _EmptyChain()
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
            value: state.spotPrice.toStringAsFixed(2),
            color: AppTheme.textPrimary,
          ),
          const SizedBox(width: 16),
          if (gex != null) ...[
            _InfoChip(
              label: 'Net GEX',
              value: '${gex.netGex >= 0 ? '+' : ''}${gex.netGex.toStringAsFixed(2)}B',
              color: gex.isPositiveGex ? AppTheme.green : AppTheme.red,
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'γ Wall',
              value: '\$${gex.gammaWall?.toStringAsFixed(0) ?? '—'}',
              color: AppTheme.gold,
            ),
            const SizedBox(width: 16),
            _InfoChip(
              label: 'Put Wall',
              value: '\$${gex.putWall?.toStringAsFixed(0) ?? '—'}',
              color: AppTheme.red,
            ),
          ],
          const Spacer(),
          _ModeChip(mode: state.dataMode),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoChip({required this.label, required this.value, required this.color});

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
  const _ModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final isLive = mode == SpxDataMode.live;
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
        isLive ? 'LIVE' : 'SIM',
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
    final isAtm  = (contract.strike - spot).abs() <= 5;
    final signalColor = switch (contract.signal) {
      SpxSignalType.buy   => AppTheme.green,
      SpxSignalType.sell  => AppTheme.red,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    contract.strike.toStringAsFixed(0),
                    style: GoogleFonts.syne(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isAtm ? AppTheme.gold : AppTheme.textPrimary,
                    ),
                  ),
                  if (isAtm)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('ATM',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 8,
                              color: AppTheme.gold,
                              fontWeight: FontWeight.w700)),
                    ),
                  const Spacer(),
                  // Mid price
                  Text(
                    '\$${contract.midPrice.toStringAsFixed(2)}',
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
                    color: contract.isTargetDelta ? AppTheme.blue : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  // DTE
                  _MetaTag(
                    label: 'DTE',
                    value: '${contract.daysToExpiry}',
                    color: contract.isDteWarning ? AppTheme.red : AppTheme.textMuted,
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

class _MetaTag extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetaTag({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, color: AppTheme.textDim)),
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
        _BidAskCell(label: 'Bid', value: contract.bid.toStringAsFixed(2)),
        const SizedBox(width: 8),
        _BidAskCell(label: 'Ask', value: contract.ask.toStringAsFixed(2)),
        const SizedBox(width: 8),
        _BidAskCell(label: 'OI', value: _fmtInt(contract.openInterest)),
        const SizedBox(width: 8),
        _BidAskCell(label: 'Vol', value: _fmtInt(contract.volume)),
      ],
    );
  }

  String _fmtInt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
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
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, color: AppTheme.textDim)),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: AppTheme.textPrimary)),
      ],
    );
  }
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
          'BUY 1 CONTRACT  ·  \$${(contract.midPrice * 100).toStringAsFixed(0)} debit',
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
  const _EmptyChain();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.show_chart, size: 40, color: AppTheme.textDim),
          const SizedBox(height: 12),
          Text('Loading options chain…',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
