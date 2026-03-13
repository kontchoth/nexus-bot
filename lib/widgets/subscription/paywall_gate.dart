import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/subscription/subscription_cubit.dart';
import '../../screens/subscription/paywall_screen.dart';

enum SubscriptionPlan { cryptoPro, spxPro }

/// Wraps a screen and shows [PaywallScreen] instead when the user
/// does not have the required entitlement.
///
/// Usage:
/// ```dart
/// PaywallGate(plan: SubscriptionPlan.cryptoPro, child: ScannerScreen())
/// ```
class PaywallGate extends StatelessWidget {
  final SubscriptionPlan plan;
  final Widget child;

  const PaywallGate({
    super.key,
    required this.plan,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionCubit, SubscriptionState>(
      buildWhen: (p, c) =>
          p.isLoading != c.isLoading ||
          p.hasCryptoPro != c.hasCryptoPro ||
          p.hasSpxPro != c.hasSpxPro ||
          p.isTrialing != c.isTrialing,
      builder: (context, state) {
        if (state.isLoading) {
          return const _LoadingGate();
        }
        final hasAccess = switch (plan) {
          SubscriptionPlan.cryptoPro =>
            state.hasCryptoPro || state.isTrialing,
          SubscriptionPlan.spxPro =>
            state.hasSpxPro || state.isTrialing,
        };
        if (hasAccess) return child;
        return PaywallScreen(plan: plan);
      },
    );
  }
}

class _LoadingGate extends StatelessWidget {
  const _LoadingGate();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
