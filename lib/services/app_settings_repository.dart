import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  final bool alertsEnabled;
  final bool hapticsEnabled;

  const AppPreferences({
    this.alertsEnabled = true,
    this.hapticsEnabled = true,
  });

  AppPreferences copyWith({
    bool? alertsEnabled,
    bool? hapticsEnabled,
  }) {
    return AppPreferences(
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
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

  String _alertsKey(String userId) => '$userId-$_alertsSuffix';
  String _hapticsKey(String userId) => '$userId-$_hapticsSuffix';

  @override
  Future<AppPreferences> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      alertsEnabled: prefs.getBool(_alertsKey(userId)) ?? true,
      hapticsEnabled: prefs.getBool(_hapticsKey(userId)) ?? true,
    );
  }

  @override
  Future<void> save(String userId, AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertsKey(userId), preferences.alertsEnabled);
    await prefs.setBool(_hapticsKey(userId), preferences.hapticsEnabled);
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
      final merged = AppPreferences(
        alertsEnabled:
            prefsMap['alertsEnabled'] as bool? ?? local.alertsEnabled,
        hapticsEnabled:
            prefsMap['hapticsEnabled'] as bool? ?? local.hapticsEnabled,
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
