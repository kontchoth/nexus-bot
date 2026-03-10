import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  final bool alertsEnabled;
  final bool hapticsEnabled;
  final String spxTermMode;
  final int spxExactDte;
  final int spxMinDte;
  final int spxMaxDte;

  const AppPreferences({
    this.alertsEnabled = true,
    this.hapticsEnabled = true,
    this.spxTermMode = 'exact',
    this.spxExactDte = 7,
    this.spxMinDte = 5,
    this.spxMaxDte = 14,
  });

  AppPreferences copyWith({
    bool? alertsEnabled,
    bool? hapticsEnabled,
    String? spxTermMode,
    int? spxExactDte,
    int? spxMinDte,
    int? spxMaxDte,
  }) {
    return AppPreferences(
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      spxTermMode: spxTermMode ?? this.spxTermMode,
      spxExactDte: spxExactDte ?? this.spxExactDte,
      spxMinDte: spxMinDte ?? this.spxMinDte,
      spxMaxDte: spxMaxDte ?? this.spxMaxDte,
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
  static const _spxExactDteSuffix = 'settings_spx_exact_dte';
  static const _spxMinDteSuffix = 'settings_spx_min_dte';
  static const _spxMaxDteSuffix = 'settings_spx_max_dte';

  String _alertsKey(String userId) => '$userId-$_alertsSuffix';
  String _hapticsKey(String userId) => '$userId-$_hapticsSuffix';
  String _spxTermModeKey(String userId) => '$userId-$_spxTermModeSuffix';
  String _spxExactDteKey(String userId) => '$userId-$_spxExactDteSuffix';
  String _spxMinDteKey(String userId) => '$userId-$_spxMinDteSuffix';
  String _spxMaxDteKey(String userId) => '$userId-$_spxMaxDteSuffix';

  @override
  Future<AppPreferences> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final minDte = prefs.getInt(_spxMinDteKey(userId)) ?? 5;
    final maxDte = prefs.getInt(_spxMaxDteKey(userId)) ?? 14;
    return AppPreferences(
      alertsEnabled: prefs.getBool(_alertsKey(userId)) ?? true,
      hapticsEnabled: prefs.getBool(_hapticsKey(userId)) ?? true,
      spxTermMode: prefs.getString(_spxTermModeKey(userId)) ?? 'exact',
      spxExactDte: prefs.getInt(_spxExactDteKey(userId)) ?? 7,
      spxMinDte: minDte,
      spxMaxDte: maxDte < minDte ? minDte : maxDte,
    );
  }

  @override
  Future<void> save(String userId, AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertsKey(userId), preferences.alertsEnabled);
    await prefs.setBool(_hapticsKey(userId), preferences.hapticsEnabled);
    await prefs.setString(_spxTermModeKey(userId), preferences.spxTermMode);
    await prefs.setInt(_spxExactDteKey(userId), preferences.spxExactDte);
    await prefs.setInt(_spxMinDteKey(userId), preferences.spxMinDte);
    await prefs.setInt(_spxMaxDteKey(userId), preferences.spxMaxDte);
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
      final merged = AppPreferences(
        alertsEnabled:
            prefsMap['alertsEnabled'] as bool? ?? local.alertsEnabled,
        hapticsEnabled:
            prefsMap['hapticsEnabled'] as bool? ?? local.hapticsEnabled,
        spxTermMode: prefsMap['spxTermMode'] as String? ?? local.spxTermMode,
        spxExactDte: spxExact ?? local.spxExactDte,
        spxMinDte: spxMin ?? local.spxMinDte,
        spxMaxDte: spxMax ?? local.spxMaxDte,
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
          'spxExactDte': preferences.spxExactDte,
          'spxMinDte': preferences.spxMinDte,
          'spxMaxDte': preferences.spxMaxDte,
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
