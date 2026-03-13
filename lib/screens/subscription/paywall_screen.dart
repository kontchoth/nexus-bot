import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/subscription/subscription_cubit.dart';
import '../../widgets/subscription/paywall_gate.dart';
import '../../theme/app_theme.dart';
import '../../theme/google_fonts_stub.dart';

/// Full-screen paywall shown when a user lacks the required entitlement,
/// or as a modal when called from [TrialBanner] during an active trial.
class PaywallScreen extends StatefulWidget {
  final SubscriptionPlan plan;

  /// When true, renders as an upgrade screen (user is trialing) rather than
  /// the initial "unlock" paywall.
  final bool isUpgrade;

  const PaywallScreen({super.key, required this.plan, this.isUpgrade = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _purchasing = false;
  bool _restoring = false;

  String get _planName =>
      widget.plan == SubscriptionPlan.cryptoPro ? 'Crypto Pro' : 'SPX Pro';

  Color get _planColor =>
      widget.plan == SubscriptionPlan.cryptoPro ? AppTheme.green : AppTheme.blue;

  List<_Feature> get _features => widget.plan == SubscriptionPlan.cryptoPro
      ? _cryptoFeatures
      : _spxFeatures;

  static const _cryptoFeatures = [
    _Feature(Icons.radar_rounded, 'Live Market Scanner',
        'Real-time Binance & Robinhood signal feed'),
    _Feature(Icons.auto_awesome_rounded, 'Opportunity Engine',
        'CoinGecko + DEXScreener ranked discovery'),
    _Feature(Icons.account_balance_wallet_outlined, 'Portfolio Tracking',
        'Positions, P&L, and performance metrics'),
    _Feature(Icons.notifications_outlined, 'Smart Alerts',
        'Score threshold & watchlist notifications'),
    _Feature(Icons.receipt_long_outlined, 'Activity Log',
        'Full signal history and trade log'),
  ];

  static const _spxFeatures = [
    _Feature(Icons.show_chart_rounded, 'Live Options Chain',
        'Greeks, strike ladder, and spot GEX'),
    _Feature(Icons.account_balance_wallet_outlined, 'SPX Positions',
        'Real-time position tracking via Tradier'),
    _Feature(Icons.bar_chart_rounded, 'Dashboard Analytics',
        'P&L, win rate, and performance charts'),
    _Feature(Icons.book_outlined, 'Trade Journal',
        'Log, annotate, and export your trades'),
    _Feature(Icons.notifications_outlined, 'Opportunity Alerts',
        'Auto-detected SPX setups with deep links'),
  ];

  Future<void> _onSubscribe() async {
    setState(() => _purchasing = true);
    try {
      final cubit = context.read<SubscriptionCubit>();
      if (widget.plan == SubscriptionPlan.cryptoPro) {
        await cubit.purchaseCryptoPro();
      } else {
        await cubit.purchaseSpxPro();
      }
      if (mounted && context.read<SubscriptionCubit>().state.hasAnyPlan) {
        if (widget.isUpgrade) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _onRestore() async {
    setState(() => _restoring = true);
    try {
      await context.read<SubscriptionCubit>().restorePurchases();
      if (mounted && context.read<SubscriptionCubit>().state.hasAnyPlan) {
        if (widget.isUpgrade) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SubscriptionCubit, SubscriptionState>(
      listenWhen: (p, c) => c.errorMessage != null && p.errorMessage == null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.errorMessage!),
          backgroundColor: AppTheme.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ));
        context.read<SubscriptionCubit>().clearError();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: widget.isUpgrade
            ? AppBar(
                backgroundColor: AppTheme.bg2,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  _planName,
                  style: GoogleFonts.syne(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(planName: _planName, planColor: _planColor, isUpgrade: widget.isUpgrade),
                const SizedBox(height: 32),
                _FeatureList(features: _features, accentColor: _planColor),
                const SizedBox(height: 32),
                _SubscribeButton(
                  planName: _planName,
                  accentColor: _planColor,
                  isLoading: _purchasing,
                  onTap: _onSubscribe,
                ),
                const SizedBox(height: 16),
                _BundleUpsell(currentPlan: widget.plan),
                const SizedBox(height: 24),
                _RestoreRow(isLoading: _restoring, onRestore: _onRestore),
                const SizedBox(height: 16),
                const _LegalNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String planName;
  final Color planColor;
  final bool isUpgrade;

  const _Header({
    required this.planName,
    required this.planColor,
    required this.isUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: planColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: planColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            planName.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: planColor,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isUpgrade ? 'Keep your access' : 'Unlock $planName',
          style: GoogleFonts.syne(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isUpgrade
              ? 'Your trial is ending soon. Subscribe to keep using all features.'
              : 'Start your 7-day free trial. Cancel anytime.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String description;
  const _Feature(this.icon, this.title, this.description);
}

class _FeatureList extends StatelessWidget {
  final List<_Feature> features;
  final Color accentColor;

  const _FeatureList({required this.features, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: features.asMap().entries.map((e) {
          final isLast = e.key == features.length - 1;
          return _FeatureRow(
            feature: e.value,
            accentColor: accentColor,
            showDivider: !isLast,
          );
        }).toList(),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _Feature feature;
  final Color accentColor;
  final bool showDivider;

  const _FeatureRow({
    required this.feature,
    required this.accentColor,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(feature.icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      feature.description,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_circle_rounded, size: 16, color: accentColor),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: AppTheme.border),
      ],
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  final String planName;
  final Color accentColor;
  final bool isLoading;
  final VoidCallback onTap;

  const _SubscribeButton({
    required this.planName,
    required this.accentColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: isLoading ? 0.1 : 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accentColor.withValues(alpha: isLoading ? 0.2 : 0.5),
          ),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor,
                  ),
                ),
              )
            : Column(
                children: [
                  Text(
                    'Start 7-Day Free Trial',
                    style: GoogleFonts.syne(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '\$9.99 / month after trial · Cancel anytime',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: accentColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BundleUpsell extends StatelessWidget {
  final SubscriptionPlan currentPlan;

  const _BundleUpsell({required this.currentPlan});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionCubit, SubscriptionState>(
      builder: (context, state) {
        // Show bundle upsell only if user already has the other plan
        final showUpsell = currentPlan == SubscriptionPlan.cryptoPro
            ? state.hasSpxPro
            : state.hasCryptoPro;
        if (!showUpsell) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => context.read<SubscriptionCubit>().purchaseBundle(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bundle both plans for \$17.99/mo — save \$2',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: AppTheme.gold),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RestoreRow extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onRestore;

  const _RestoreRow({required this.isLoading, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: isLoading ? null : onRestore,
        child: Text(
          isLoading ? 'Restoring…' : 'Restore Purchases',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: AppTheme.textMuted,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _LegalNote extends StatelessWidget {
  const _LegalNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Payment is charged to your App Store / Google Play account at confirmation of purchase. '
      'Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.',
      textAlign: TextAlign.center,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 10,
        color: AppTheme.textDim,
        height: 1.5,
      ),
    );
  }
}
