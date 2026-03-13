import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/subscription_service.dart';
import 'subscription_state.dart';

export 'subscription_state.dart';

class SubscriptionCubit extends Cubit<SubscriptionState> {
  final SubscriptionService _service;
  StreamSubscription<SubscriptionInfo>? _infoSub;

  SubscriptionCubit({SubscriptionService? service})
      : _service = service ?? SubscriptionService.instance,
        super(const SubscriptionState());

  /// Must be called once after auth, with the signed-in user id.
  Future<void> initialize(String userId) async {
    emit(const SubscriptionState(status: SubscriptionStatus.loading));
    try {
      final info = await _service.initialize(userId: userId);
      emit(state.copyWithInfo(info));

      // Stay in sync with RevenueCat updates (renewals, cancellations)
      _infoSub = _service.infoStream.listen((info) {
        if (!isClosed) emit(state.copyWithInfo(info));
      });
    } catch (e) {
      emit(state.withError(e.toString()));
    }
  }

  /// Purchase the Crypto Pro monthly plan.
  Future<void> purchaseCryptoPro() => _purchaseOffering(OfferingIds.cryptoPro);

  /// Purchase the SPX Pro monthly plan.
  Future<void> purchaseSpxPro() => _purchaseOffering(OfferingIds.spxPro);

  /// Purchase the bundle (both plans).
  Future<void> purchaseBundle() => _purchaseOffering(OfferingIds.bundle);

  Future<void> _purchaseOffering(String offeringId) async {
    try {
      if (!_service.isConfigured) {
        final reason = _service.initError;
        emit(state.withError(
          reason != null
              ? 'RevenueCat failed to initialize: $reason'
              : 'Payments are not set up yet. Add your RevenueCat API keys to enable subscriptions.',
        ));
        return;
      }
      final offering = await _service.fetchOffering(offeringId);
      if (offering == null) {
        emit(state.withError(
          'Plan not found in RevenueCat. Check that the offering "$offeringId" is configured in your RevenueCat dashboard.',
        ));
        return;
      }
      final package = offering.monthly ?? offering.availablePackages.firstOrNull;
      if (package == null) {
        emit(state.withError('No monthly package found for this plan.'));
        return;
      }
      final info = await _service.purchase(package);
      emit(state.copyWithInfo(info));
    } on PurchasesError catch (e) {
      if (e.code != PurchasesErrorCode.purchaseCancelledError) {
        emit(state.withError('Purchase failed. Please try again.'));
      }
      // Cancelled — silently ignore, user tapped back.
    } catch (e) {
      emit(state.withError('Purchase failed. Please try again.'));
    }
  }

  Future<void> restorePurchases() async {
    try {
      final info = await _service.restorePurchases();
      emit(state.copyWithInfo(info));
    } catch (e) {
      emit(state.withError('Restore failed. Please try again.'));
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      emit(SubscriptionState(
        status: state.status,
        hasCryptoPro: state.hasCryptoPro,
        hasSpxPro: state.hasSpxPro,
        isTrialing: state.isTrialing,
        isPrivileged: state.isPrivileged,
        trialEndsAt: state.trialEndsAt,
      ));
    }
  }

  @override
  Future<void> close() {
    _infoSub?.cancel();
    return super.close();
  }
}
