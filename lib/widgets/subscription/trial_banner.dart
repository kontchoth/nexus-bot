import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/subscription/subscription_cubit.dart';
import '../../screens/subscription/paywall_screen.dart';
import '../../widgets/subscription/paywall_gate.dart';
import '../../theme/app_theme.dart';
import '../../theme/google_fonts_stub.dart';

/// Shows a persistent banner at the top of a screen during the free trial,
/// reminding the user how many days remain and offering a subscribe CTA.
///
/// Renders nothing when not trialing or after the user dismisses for the session.
class TrialBanner extends StatefulWidget {
  final SubscriptionPlan plan;
  final Widget child;

  const TrialBanner({super.key, required this.plan, required this.child});

  @override
  State<TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends State<TrialBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionCubit, SubscriptionState>(
      buildWhen: (p, c) => p.isTrialing != c.isTrialing || p.trialEndsAt != c.trialEndsAt,
      builder: (context, state) {
        final show = state.isTrialing && !_dismissed;
        return Column(
          children: [
            if (show) _Banner(
              daysLeft: state.trialDaysRemaining ?? 7,
              plan: widget.plan,
              onDismiss: () => setState(() => _dismissed = true),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final int daysLeft;
  final SubscriptionPlan plan;
  final VoidCallback onDismiss;

  const _Banner({
    required this.daysLeft,
    required this.plan,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final label = daysLeft == 1 ? '1 day' : '$daysLeft days';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.08),
        border: const Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppTheme.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label left in your free trial — subscribe to keep access.',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PaywallScreen(plan: plan, isUpgrade: true),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
              ),
              child: Text(
                'SUBSCRIBE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 14, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
