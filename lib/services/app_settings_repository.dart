import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpxTradierEnvironment {
  static const sandbox = 'sandbox';
  static const production = 'production';

  static const values = <String>{
    sandbox,
    production,
  };

  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return values.contains(value) ? value : production;
  }

  static bool isSandbox(String? raw) => normalize(raw) == sandbox;

  static String label(String? raw) => isSandbox(raw) ? 'Sandbox' : 'Production';
}

class SpxOpportunityExecutionMode {
  static const manualConfirm = 'manual_confirm';
  static const autoAfterDelay = 'auto_after_delay';
  static const autoImmediate = 'auto_immediate';

  static const values = <String>{
    manualConfirm,
    autoAfterDelay,
    autoImmediate,
  };

  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    return values.contains(value) ? value : manualConfirm;
  }
}

class SpxContractTargetingMode {
  static const deltaZone = 'delta_zone';
  static const atm = 'atm';
  static const nearItm = 'near_itm';
  static const nearOtm = 'near_otm';
  static const atmOrNearItm = 'atm_or_near_itm';

  static const values = <String>{
    deltaZone,
    atm,
    nearItm,
    nearOtm,
    atmOrNearItm,
  };

  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    return values.contains(value) ? value : deltaZone;
  }

  static String label(String? raw) {
    return switch (normalize(raw)) {
      atm => 'ATM',
      nearItm => 'Near ITM',
      nearOtm => 'Near OTM',
      atmOrNearItm => 'ATM / Near ITM',
      _ => 'Delta Zone',
    };
  }
}

class AppPreferences {
  final bool alertsEnabled;
  final bool hapticsEnabled;
  final String spxTermMode;
  final String spxTradierEnvironment;
  final String spxContractTargetingMode;
  final int spxExactDte;
  final int spxMinDte;
  final int spxMaxDte;
  final String spxOpportunityExecutionMode;
  final int spxEntryDelaySeconds;
  final int spxValidationWindowSeconds;
  final double spxMaxSlippagePct;

  const AppPreferences({
    this.alertsEnabled = true,
    this.hapticsEnabled = true,
    this.spxTermMode = 'exact',
    this.spxTradierEnvironment = SpxTradierEnvironment.production,
    this.spxContractTargetingMode = SpxContractTargetingMode.deltaZone,
    this.spxExactDte = 7,
    this.spxMinDte = 5,
    this.spxMaxDte = 14,
    this.spxOpportunityExecutionMode =
        SpxOpportunityExecutionMode.manualConfirm,
    this.spxEntryDelaySeconds = 30,
    this.spxValidationWindowSeconds = 120,
    this.spxMaxSlippagePct = 5.0,
  });

  AppPreferences copyWith({
    bool? alertsEnabled,
    bool? hapticsEnabled,
    String? spxTermMode,
    String? spxTradierEnvironment,
    String? spxContractTargetingMode,
    int? spxExactDte,
    int? spxMinDte,
    int? spxMaxDte,
    String? spxOpportunityExecutionMode,
    int? spxEntryDelaySeconds,
    int? spxValidationWindowSeconds,
    double? spxMaxSlippagePct,
  }) {
    return AppPreferences(
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      spxTermMode: spxTermMode ?? this.spxTermMode,
      spxTradierEnvironment: SpxTradierEnvironment.normalize(
        spxTradierEnvironment ?? this.spxTradierEnvironment,
      ),
      spxContractTargetingMode: SpxContractTargetingMode.normalize(
        spxContractTargetingMode ?? this.spxContractTargetingMode,
      ),
      spxExactDte: spxExactDte ?? this.spxExactDte,
      spxMinDte: spxMinDte ?? this.spxMinDte,
      spxMaxDte: spxMaxDte ?? this.spxMaxDte,
      spxOpportunityExecutionMode:
          spxOpportunityExecutionMode ?? this.spxOpportunityExecutionMode,
      spxEntryDelaySeconds: spxEntryDelaySeconds ?? this.spxEntryDelaySeconds,
      spxValidationWindowSeconds:
          spxValidationWindowSeconds ?? this.spxValidationWindowSeconds,
      spxMaxSlippagePct: spxMaxSlippagePct ?? this.spxMaxSlippagePct,
    );
  }
}

abstract class AppSettingsRepository {
  Future<AppPreferences> load(String userId);
  Future<void> save(String userId, AppPreferences preferences);
}

class LocalAppSettingsRepository implements AppSettingsRepository {
  static const _alertsSuffix = 'settings_alerts_enabled';
  static const _hapticsSuffix = 'settings_haptics_enabled';
  static const _spxTermModeSuffix = 'settings_spx_term_mode';
  static const _spxTradierEnvironmentSuffix =
      'settings_spx_tradier_environment';
  static const _spxContractTargetingModeSuffix =
      'settings_spx_contract_targeting_mode';
  static const _spxExactDteSuffix = 'settings_spx_exact_dte';
  static const _spxMinDteSuffix = 'settings_spx_min_dte';
  static const _spxMaxDteSuffix = 'settings_spx_max_dte';
  static const _spxExecutionModeSuffix = 'settings_spx_execution_mode';
  static const _spxEntryDelaySecondsSuffix = 'settings_spx_entry_delay_seconds';
  static const _spxValidationWindowSecondsSuffix =
      'settings_spx_validation_window_seconds';
  static const _spxMaxSlippagePctSuffix = 'settings_spx_max_slippage_pct';

  String _alertsKey(String userId) => '$userId-$_alertsSuffix';
  String _hapticsKey(String userId) => '$userId-$_hapticsSuffix';
  String _spxTermModeKey(String userId) => '$userId-$_spxTermModeSuffix';
  String _spxTradierEnvironmentKey(String userId) =>
      '$userId-$_spxTradierEnvironmentSuffix';
  String _spxContractTargetingModeKey(String userId) =>
      '$userId-$_spxContractTargetingModeSuffix';
  String _spxExactDteKey(String userId) => '$userId-$_spxExactDteSuffix';
  String _spxMinDteKey(String userId) => '$userId-$_spxMinDteSuffix';
  String _spxMaxDteKey(String userId) => '$userId-$_spxMaxDteSuffix';
  String _spxExecutionModeKey(String userId) =>
      '$userId-$_spxExecutionModeSuffix';
  String _spxEntryDelaySecondsKey(String userId) =>
      '$userId-$_spxEntryDelaySecondsSuffix';
  String _spxValidationWindowSecondsKey(String userId) =>
      '$userId-$_spxValidationWindowSecondsSuffix';
  String _spxMaxSlippagePctKey(String userId) =>
      '$userId-$_spxMaxSlippagePctSuffix';

  @override
  Future<AppPreferences> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final minDte = prefs.getInt(_spxMinDteKey(userId)) ?? 5;
    final maxDte = prefs.getInt(_spxMaxDteKey(userId)) ?? 14;
    final executionMode = SpxOpportunityExecutionMode.normalize(
      prefs.getString(_spxExecutionModeKey(userId)),
    );
    final entryDelay = (prefs.getInt(_spxEntryDelaySecondsKey(userId)) ?? 30)
        .clamp(0, 3600)
        .toInt();
    final validationWindow =
        (prefs.getInt(_spxValidationWindowSecondsKey(userId)) ?? 120)
            .clamp(15, 3600)
            .toInt();
    final slippage = (prefs.getDouble(_spxMaxSlippagePctKey(userId)) ?? 5.0)
        .clamp(0.1, 100.0)
        .toDouble();
    return AppPreferences(
      alertsEnabled: prefs.getBool(_alertsKey(userId)) ?? true,
      hapticsEnabled: prefs.getBool(_hapticsKey(userId)) ?? true,
      spxTermMode: prefs.getString(_spxTermModeKey(userId)) ?? 'exact',
      spxTradierEnvironment: SpxTradierEnvironment.normalize(
        prefs.getString(_spxTradierEnvironmentKey(userId)),
      ),
      spxContractTargetingMode: SpxContractTargetingMode.normalize(
        prefs.getString(_spxContractTargetingModeKey(userId)),
      ),
      spxExactDte: prefs.getInt(_spxExactDteKey(userId)) ?? 7,
      spxMinDte: minDte,
      spxMaxDte: maxDte < minDte ? minDte : maxDte,
      spxOpportunityExecutionMode: executionMode,
      spxEntryDelaySeconds: entryDelay,
      spxValidationWindowSeconds: validationWindow,
      spxMaxSlippagePct: slippage,
    );
  }

  @override
  Future<void> save(String userId, AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertsKey(userId), preferences.alertsEnabled);
    await prefs.setBool(_hapticsKey(userId), preferences.hapticsEnabled);
    await prefs.setString(_spxTermModeKey(userId), preferences.spxTermMode);
    await prefs.setString(
      _spxTradierEnvironmentKey(userId),
      SpxTradierEnvironment.normalize(preferences.spxTradierEnvironment),
    );
    await prefs.setString(
      _spxContractTargetingModeKey(userId),
      SpxContractTargetingMode.normalize(
        preferences.spxContractTargetingMode,
      ),
    );
    await prefs.setInt(_spxExactDteKey(userId), preferences.spxExactDte);
    await prefs.setInt(_spxMinDteKey(userId), preferences.spxMinDte);
    await prefs.setInt(_spxMaxDteKey(userId), preferences.spxMaxDte);
    await prefs.setString(
      _spxExecutionModeKey(userId),
      SpxOpportunityExecutionMode.normalize(
        preferences.spxOpportunityExecutionMode,
      ),
    );
    await prefs.setInt(
      _spxEntryDelaySecondsKey(userId),
      preferences.spxEntryDelaySeconds.clamp(0, 3600).toInt(),
    );
    await prefs.setInt(
      _spxValidationWindowSecondsKey(userId),
      preferences.spxValidationWindowSeconds.clamp(15, 3600).toInt(),
    );
    await prefs.setDouble(
      _spxMaxSlippagePctKey(userId),
      preferences.spxMaxSlippagePct.clamp(0.1, 100.0).toDouble(),
    );
  }
}

class FirebaseAppSettingsRepository extends LocalAppSettingsRepository {
  final FirebaseFirestore _firestore;

  FirebaseAppSettingsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection('users').doc(userId);

  DocumentReference<Map<String, dynamic>> _legacyDoc(String userId) =>
      _firestore.collection('users').doc(userId).collection('meta').doc(
            'settings',
          );

  @override
  Future<AppPreferences> load(String userId) async {
    final local = await super.load(userId);
    try {
      final userSnap = await _userDoc(userId).get();
      Map<String, dynamic> data = const <String, dynamic>{};
      if (userSnap.exists) {
        data = userSnap.data() ?? const <String, dynamic>{};
      } else {
        final legacySnap = await _legacyDoc(userId).get();
        if (legacySnap.exists) {
          data = legacySnap.data() ?? const <String, dynamic>{};
        }
      }

      final prefsMap = (data['preferences'] as Map<String, dynamic>?) ?? data;
      final spxExact = (prefsMap['spxExactDte'] as num?)?.toInt();
      final spxMin = (prefsMap['spxMinDte'] as num?)?.toInt();
      final spxMax = (prefsMap['spxMaxDte'] as num?)?.toInt();
      final spxTradierEnvironment =
          prefsMap['spxTradierEnvironment'] as String?;
      final spxContractTargetingMode =
          prefsMap['spxContractTargetingMode'] as String?;
      final spxExecutionMode =
          prefsMap['spxOpportunityExecutionMode'] as String?;
      final spxEntryDelay = (prefsMap['spxEntryDelaySeconds'] as num?)?.toInt();
      final spxValidationWindow =
          (prefsMap['spxValidationWindowSeconds'] as num?)?.toInt();
      final spxMaxSlippage =
          (prefsMap['spxMaxSlippagePct'] as num?)?.toDouble();
      final merged = AppPreferences(
        alertsEnabled:
            prefsMap['alertsEnabled'] as bool? ?? local.alertsEnabled,
        hapticsEnabled:
            prefsMap['hapticsEnabled'] as bool? ?? local.hapticsEnabled,
        spxTermMode: prefsMap['spxTermMode'] as String? ?? local.spxTermMode,
        spxTradierEnvironment: spxTradierEnvironment == null
            ? local.spxTradierEnvironment
            : SpxTradierEnvironment.normalize(spxTradierEnvironment),
        spxContractTargetingMode: spxContractTargetingMode == null
            ? local.spxContractTargetingMode
            : SpxContractTargetingMode.normalize(spxContractTargetingMode),
        spxExactDte: spxExact ?? local.spxExactDte,
        spxMinDte: spxMin ?? local.spxMinDte,
        spxMaxDte: spxMax ?? local.spxMaxDte,
        spxOpportunityExecutionMode: spxExecutionMode == null
            ? local.spxOpportunityExecutionMode
            : SpxOpportunityExecutionMode.normalize(spxExecutionMode),
        spxEntryDelaySeconds: (spxEntryDelay ?? local.spxEntryDelaySeconds)
            .clamp(0, 3600)
            .toInt(),
        spxValidationWindowSeconds:
            (spxValidationWindow ?? local.spxValidationWindowSeconds)
                .clamp(15, 3600)
                .toInt(),
        spxMaxSlippagePct: (spxMaxSlippage ?? local.spxMaxSlippagePct)
            .clamp(0.1, 100.0)
            .toDouble(),
      );
      await super.save(userId, merged);
      return merged;
    } catch (e, st) {
      debugPrint('Firestore settings load failed for $userId: $e');
      debugPrint('$st');
      return local;
    }
  }

  @override
  Future<void> save(String userId, AppPreferences preferences) async {
    await super.save(userId, preferences);
    try {
      await _userDoc(userId).set({
        'preferences': {
          'alertsEnabled': preferences.alertsEnabled,
          'hapticsEnabled': preferences.hapticsEnabled,
          'spxTermMode': preferences.spxTermMode,
          'spxTradierEnvironment': SpxTradierEnvironment.normalize(
            preferences.spxTradierEnvironment,
          ),
          'spxContractTargetingMode': SpxContractTargetingMode.normalize(
            preferences.spxContractTargetingMode,
          ),
          'spxExactDte': preferences.spxExactDte,
          'spxMinDte': preferences.spxMinDte,
          'spxMaxDte': preferences.spxMaxDte,
          'spxOpportunityExecutionMode': SpxOpportunityExecutionMode.normalize(
            preferences.spxOpportunityExecutionMode,
          ),
          'spxEntryDelaySeconds':
              preferences.spxEntryDelaySeconds.clamp(0, 3600).toInt(),
          'spxValidationWindowSeconds':
              preferences.spxValidationWindowSeconds.clamp(15, 3600).toInt(),
          'spxMaxSlippagePct':
              preferences.spxMaxSlippagePct.clamp(0.1, 100.0).toDouble(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('Firestore settings save failed for $userId: $e');
      debugPrint('$st');
      // Keep local values even if cloud sync fails.
    }
  }
}
