import 'package:equatable/equatable.dart';
import '../../services/subscription_service.dart';

enum SubscriptionStatus { loading, active, trialing, free, error }

class SubscriptionState extends Equatable {
  final SubscriptionStatus status;
  final bool hasCryptoPro;
  final bool hasSpxPro;
  final bool isTrialing;
  final bool isPrivileged;
  final DateTime? trialEndsAt;
  final String? errorMessage;

  const SubscriptionState({
    this.status = SubscriptionStatus.loading,
    this.hasCryptoPro = false,
    this.hasSpxPro = false,
    this.isTrialing = false,
    this.isPrivileged = false,
    this.trialEndsAt,
    this.errorMessage,
  });

  bool get hasAnyPlan => hasCryptoPro || hasSpxPro;
  bool get isLoading => status == SubscriptionStatus.loading;

  /// Days remaining in trial, or null if not trialing.
  int? get trialDaysRemaining {
    if (!isTrialing || trialEndsAt == null) return null;
    final diff = trialEndsAt!.difference(DateTime.now()).inDays;
    return diff.clamp(0, 7);
  }

  SubscriptionState copyWithInfo(SubscriptionInfo info) => SubscriptionState(
        status: _resolveStatus(info),
        hasCryptoPro: info.hasCryptoPro,
        hasSpxPro: info.hasSpxPro,
        isTrialing: info.isTrialing,
        isPrivileged: info.isPrivileged,
        trialEndsAt: info.trialEndsAt,
      );

  SubscriptionState withError(String message) => SubscriptionState(
        status: SubscriptionStatus.error,
        hasCryptoPro: hasCryptoPro,
        hasSpxPro: hasSpxPro,
        isTrialing: isTrialing,
        isPrivileged: isPrivileged,
        trialEndsAt: trialEndsAt,
        errorMessage: message,
      );

  static SubscriptionStatus _resolveStatus(SubscriptionInfo info) {
    if (info.isTrialing) return SubscriptionStatus.trialing;
    if (info.hasCryptoPro || info.hasSpxPro) return SubscriptionStatus.active;
    return SubscriptionStatus.free;
  }

  @override
  List<Object?> get props => [
        status,
        hasCryptoPro,
        hasSpxPro,
        isTrialing,
        isPrivileged,
        trialEndsAt,
        errorMessage,
      ];
}
