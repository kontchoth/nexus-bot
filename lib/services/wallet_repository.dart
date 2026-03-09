import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletProfile {
  final String address;
  final int chainId;
  final String network;

  const WalletProfile({
    required this.address,
    this.chainId = 1,
    this.network = 'Ethereum Mainnet',
  });

  String get normalizedAddress => address.toLowerCase();

  Map<String, dynamic> toJson() => {
        'address': address,
        'chainId': chainId,
        'network': network,
      };

  factory WalletProfile.fromJson(Map<String, dynamic> json) {
    return WalletProfile(
      address: json['address'] as String,
      chainId: json['chainId'] as int? ?? 1,
      network: json['network'] as String? ?? 'Ethereum Mainnet',
    );
  }
}

abstract class WalletRepository {
  Future<List<WalletProfile>> loadAll(String userId);
  Future<void> upsert(String userId, WalletProfile profile);
  Future<void> remove(String userId, String address);
  Future<void> clearAll(String userId);
}

class LocalWalletRepository implements WalletRepository {
  static const _walletsSuffix = 'wallets_json';
  static const _addressSuffix = 'wallet_address';
  static const _chainIdSuffix = 'wallet_chain_id';
  static const _networkSuffix = 'wallet_network';

  String _walletsKey(String userId) => '$userId-$_walletsSuffix';
  String _addressKey(String userId) => '$userId-$_addressSuffix';
  String _chainIdKey(String userId) => '$userId-$_chainIdSuffix';
  String _networkKey(String userId) => '$userId-$_networkSuffix';

  @override
  Future<List<WalletProfile>> loadAll(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_walletsKey(userId)) ?? const <String>[];

    final wallets = <WalletProfile>[];
    for (final item in raw) {
      try {
        final parsed = jsonDecode(item) as Map<String, dynamic>;
        wallets.add(WalletProfile.fromJson(parsed));
      } catch (_) {}
    }

    // Backward compatibility migration from previous single-wallet keys.
    final legacyAddress = prefs.getString(_addressKey(userId));
    if (legacyAddress != null && legacyAddress.isNotEmpty) {
      wallets.add(WalletProfile(
        address: legacyAddress,
        chainId: prefs.getInt(_chainIdKey(userId)) ?? 1,
        network: prefs.getString(_networkKey(userId)) ?? 'Ethereum Mainnet',
      ));
    }

    final deduped = _dedupe(wallets);
    await _saveLocal(userId, deduped);
    return deduped;
  }

  @override
  Future<void> upsert(String userId, WalletProfile profile) async {
    final wallets = await loadAll(userId);
    final updated = wallets
        .where((w) => w.normalizedAddress != profile.normalizedAddress)
        .toList();
    updated.add(profile);
    await _saveLocal(userId, _dedupe(updated));
  }

  @override
  Future<void> remove(String userId, String address) async {
    final wallets = await loadAll(userId);
    final updated = wallets
        .where((w) => w.normalizedAddress != address.toLowerCase())
        .toList();
    await _saveLocal(userId, updated);
  }

  @override
  Future<void> clearAll(String userId) async {
    await _saveLocal(userId, const <WalletProfile>[]);
  }

  Future<void> _saveLocal(String userId, List<WalletProfile> wallets) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = wallets.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_walletsKey(userId), encoded);
    await prefs.remove(_addressKey(userId));
    await prefs.remove(_chainIdKey(userId));
    await prefs.remove(_networkKey(userId));
  }

  List<WalletProfile> _dedupe(List<WalletProfile> wallets) {
    final byAddress = <String, WalletProfile>{};
    for (final wallet in wallets) {
      byAddress[wallet.normalizedAddress] = wallet;
    }
    return byAddress.values.toList();
  }
}

class FirebaseWalletRepository extends LocalWalletRepository {
  final FirebaseFirestore _firestore;

  FirebaseWalletRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Future<List<WalletProfile>> loadAll(String userId) async {
    final local = await super.loadAll(userId);
    try {
      final snap = await _doc(userId).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final walletsData = data['wallets'] as List<dynamic>?;

      var remoteWallets = <WalletProfile>[];
      if (walletsData != null) {
        remoteWallets = walletsData
            .whereType<Map<String, dynamic>>()
            .map(WalletProfile.fromJson)
            .toList();
      } else {
        // Backward compatibility: old single wallet object.
        final walletData = data['wallet'] as Map<String, dynamic>?;
        final address = walletData?['address'] as String?;
        if (address != null && address.isNotEmpty) {
          remoteWallets = [
            WalletProfile(
              address: address,
              chainId: walletData?['chainId'] as int? ?? 1,
              network: walletData?['network'] as String? ?? 'Ethereum Mainnet',
            )
          ];
        }
      }

      final merged = _merge(local, remoteWallets);
      await _saveLocal(userId, merged);
      await _saveRemote(userId, merged);
      return merged;
    } catch (_) {
      return local;
    }
  }

  @override
  Future<void> upsert(String userId, WalletProfile profile) async {
    await super.upsert(userId, profile);
    final wallets = await super.loadAll(userId);
    await _saveRemote(userId, wallets);
  }

  @override
  Future<void> remove(String userId, String address) async {
    await super.remove(userId, address);
    final wallets = await super.loadAll(userId);
    await _saveRemote(userId, wallets);
  }

  @override
  Future<void> clearAll(String userId) async {
    await super.clearAll(userId);
    try {
      await _doc(userId).set({
        'wallet': FieldValue.delete(),
        'wallets': const <dynamic>[],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore cloud delete errors
    }
  }

  Future<void> _saveRemote(String userId, List<WalletProfile> wallets) async {
    try {
      await _saveLocal(userId, wallets);
      await _doc(userId).set({
        'wallets': wallets.map((w) => w.toJson()).toList(),
        'wallet': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // keep local if cloud write fails
    }
  }

  List<WalletProfile> _merge(
      List<WalletProfile> local, List<WalletProfile> remote) {
    final merged = <String, WalletProfile>{};
    for (final w in [...local, ...remote]) {
      merged[w.normalizedAddress] = w;
    }
    return merged.values.toList();
  }
}
