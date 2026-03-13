import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RevenueCat API keys
// TODO: Replace with your real RevenueCat API keys from app.revenuecat.com
// ─────────────────────────────────────────────────────────────────────────────
// Single SDK API key — used for both iOS and Android in newer RevenueCat projects.
const _rcSdkApiKey = 'test_GOfvlUdUxxYMTjLXWYeoqboqRNU';

// ─────────────────────────────────────────────────────────────────────────────
// Firestore collection for privileged users.
// Add a document with the user's Firebase UID as the document ID.
// The document can contain any fields (e.g. note, grantedAt) — only its
// existence matters. Remove the document to revoke access.
//
// Firebase console path: Firestore → privileged_users → {uid}
// ─────────────────────────────────────────────────────────────────────────────
const _privilegedCollection = 'privileged_users';

// ─────────────────────────────────────────────────────────────────────────────
// Entitlement identifiers — must match what you set in RevenueCat dashboard
// ─────────────────────────────────────────────────────────────────────────────
class Entitlements {
  static const cryptoPro = 'crypto_pro';
  static const spxPro = 'spx_pro';
}

// ─────────────────────────────────────────────────────────────────────────────
// Product identifiers — must match App Store Connect / Google Play Console
// ─────────────────────────────────────────────────────────────────────────────
class ProductIds {
  static const cryptoProMonthly = 'com.hintekk.nexusbot.crypto_monthly';
  static const spxProMonthly = 'com.hintekk.nexusbot.spxpro.monthly';
  static const bundleMonthly = 'com.hintekk.nexusbot.bundle.monthly';
}

// ─────────────────────────────────────────────────────────────────────────────
// Offering identifiers — configure these in RevenueCat dashboard
// ─────────────────────────────────────────────────────────────────────────────
class OfferingIds {
  static const cryptoPro = 'crypto_pro';
  static const spxPro = 'spx_pro';
  static const bundle = 'bundle';
}

class SubscriptionInfo {
  final bool hasCryptoPro;
  final bool hasSpxPro;
  final bool isTrialing;
  final bool isPrivileged;
  final DateTime? trialEndsAt;

  const SubscriptionInfo({
    this.hasCryptoPro = false,
    this.hasSpxPro = false,
    this.isTrialing = false,
    this.isPrivileged = false,
    this.trialEndsAt,
  });

  bool get hasAnyPlan => hasCryptoPro || hasSpxPro;

  SubscriptionInfo copyWith({
    bool? hasCryptoPro,
    bool? hasSpxPro,
    bool? isTrialing,
    bool? isPrivileged,
    DateTime? trialEndsAt,
  }) =>
      SubscriptionInfo(
        hasCryptoPro: hasCryptoPro ?? this.hasCryptoPro,
        hasSpxPro: hasSpxPro ?? this.hasSpxPro,
        isTrialing: isTrialing ?? this.isTrialing,
        isPrivileged: isPrivileged ?? this.isPrivileged,
        trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      );
}

const _fullAccess = SubscriptionInfo(
  hasCryptoPro: true,
  hasSpxPro: true,
  isPrivileged: true,
);

class SubscriptionService {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  bool _initialized = false;
  bool _configuredSuccessfully = false;
  String? _currentUserId;
  String? _initError;

  bool get isConfigured => _configuredSuccessfully;
  String? get initError => _initError;

  // Cached privilege check — avoids repeated Firestore reads within a session.
  bool? _isPrivilegedCache;

  final _infoController = StreamController<SubscriptionInfo>.broadcast();
  Stream<SubscriptionInfo> get infoStream => _infoController.stream;

  /// Call once after Firebase/auth is ready, passing the signed-in user id.
  Future<SubscriptionInfo> initialize({required String userId}) async {
    _currentUserId = userId;
    _isPrivilegedCache = null; // Reset on each new auth session.

    // Check Firestore privilege first — short-circuit before RevenueCat.
    if (await _checkPrivileged(userId)) return _fullAccess;

    if (_initialized) return _fetchCurrentInfo();
    _initialized = true;

    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.error,
      );
      final config = PurchasesConfiguration(_rcSdkApiKey)
        ..appUserID = userId;
      await Purchases.configure(config);
      _configuredSuccessfully = true;

      // Listen for customer info updates (renewals, cancellations, etc.)
      Purchases.addCustomerInfoUpdateListener((info) {
        final parsed = _parseInfo(info);
        _infoController.add(parsed);
      });
    } catch (e, st) {
      _initError = e.toString();
      debugPrint('[Subscription] RevenueCat init failed: $e');
      debugPrint('[Subscription] $st');
    }

    return _fetchCurrentInfo();
  }

  /// Returns true if the user has a document in the privileged_users collection.
  Future<bool> _checkPrivileged(String userId) async {
    if (_isPrivilegedCache != null) return _isPrivilegedCache!;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_privilegedCollection)
          .doc(userId)
          .get();
      _isPrivilegedCache = doc.exists;
      return _isPrivilegedCache!;
    } catch (e) {
      debugPrint('[Subscription] Privilege check failed: $e');
      _isPrivilegedCache = false;
      return false;
    }
  }

  Future<SubscriptionInfo> _fetchCurrentInfo() async {
    if (_currentUserId != null && (_isPrivilegedCache ?? false)) {
      return _fullAccess;
    }
    if (!_configuredSuccessfully) return const SubscriptionInfo();
    try {
      final info = await Purchases.getCustomerInfo();
      return _parseInfo(info);
    } catch (e) {
      debugPrint('[Subscription] Failed to fetch customer info: $e');
      return const SubscriptionInfo();
    }
  }

  SubscriptionInfo _parseInfo(CustomerInfo info) {
    final entitlements = info.entitlements.active;
    final hasCrypto = entitlements.containsKey(Entitlements.cryptoPro);
    final hasSpx = entitlements.containsKey(Entitlements.spxPro);

    bool isTrialing = false;
    DateTime? trialEndsAt;
    for (final key in [Entitlements.cryptoPro, Entitlements.spxPro]) {
      final e = entitlements[key];
      if (e != null && e.periodType == PeriodType.trial) {
        isTrialing = true;
        final expiry = e.expirationDate;
        if (expiry != null) {
          final parsed = DateTime.tryParse(expiry);
          if (parsed != null &&
              (trialEndsAt == null || parsed.isAfter(trialEndsAt))) {
            trialEndsAt = parsed;
          }
        }
      }
    }

    return SubscriptionInfo(
      hasCryptoPro: hasCrypto,
      hasSpxPro: hasSpx,
      isTrialing: isTrialing,
      trialEndsAt: trialEndsAt,
    );
  }

  /// Fetch the Offering for a given offering ID (contains Package + pricing).
  Future<Offering?> fetchOffering(String offeringId) async {
    if (!_configuredSuccessfully) return null;
    try {
      final offerings = await Purchases.getOfferings();
      debugPrint('[Subscription] Available offerings: ${offerings.all.keys.toList()}');
      debugPrint('[Subscription] Current offering: ${offerings.current?.identifier}');
      return offerings.all[offeringId];
    } catch (e) {
      debugPrint('[Subscription] fetchOffering($offeringId) failed: $e');
      return null;
    }
  }

  /// Purchase a package (e.g. the monthly package inside an Offering).
  Future<SubscriptionInfo> purchase(Package package) async {
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      return _parseInfo(customerInfo);
    } on PurchasesError catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('[Subscription] Purchase cancelled by user.');
      } else {
        debugPrint('[Subscription] Purchase error: ${e.code}');
      }
      rethrow;
    }
  }

  /// Restore purchases after reinstall or device change.
  Future<SubscriptionInfo> restorePurchases() async {
    if (!_configuredSuccessfully) return const SubscriptionInfo();
    try {
      final info = await Purchases.restorePurchases();
      return _parseInfo(info);
    } catch (e) {
      debugPrint('[Subscription] Restore failed: $e');
      rethrow;
    }
  }

  void dispose() {
    _infoController.close();
  }
}
