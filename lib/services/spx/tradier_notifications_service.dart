import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TradierNotification {
  final String id;
  final String title;
  final String text;
  final String status;

  const TradierNotification({
    required this.id,
    required this.title,
    required this.text,
    required this.status,
  });
}

/// Fetches account-level notifications from Tradier (e.g. dividend warnings,
/// margin calls, expiration alerts).
///
/// Flow:
///   1. GET /v1/user/profile           → extract account number(s)
///   2. GET /v1/accounts/{id}/notifications → return parsed list
class TradierNotificationsService {
  static const _sandboxBase    = 'https://sandbox.tradier.com/v1';
  static const _productionBase = 'https://api.tradier.com/v1';

  final String _apiToken;
  final bool _useSandbox;

  TradierNotificationsService({
    required String apiToken,
    required bool useSandbox,
  })  : _apiToken = apiToken,
        _useSandbox = useSandbox;

  String get _base => _useSandbox ? _sandboxBase : _productionBase;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiToken',
    'Accept': 'application/json',
  };

  /// Returns all active notifications across all accounts on this token.
  /// Returns [] on any error (non-throwing).
  Future<List<TradierNotification>> fetchNotifications() async {
    try {
      final accountIds = await _fetchAccountIds();
      if (accountIds.isEmpty) return [];

      final results = <TradierNotification>[];
      for (final id in accountIds) {
        results.addAll(await _fetchForAccount(id));
      }
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('[TRADIER-NOTIF] error: $e');
      return [];
    }
  }

  Future<List<String>> _fetchAccountIds() async {
    final res = await http
        .get(Uri.parse('$_base/user/profile'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final profile = data['profile'];
    if (profile == null) return [];

    // `account` can be a single object or a list
    final raw = profile['account'];
    if (raw == null) return [];

    final accounts = raw is List ? raw : [raw];
    return accounts
        .map((a) => a['account_number']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<List<TradierNotification>> _fetchForAccount(String accountId) async {
    final res = await http
        .get(
          Uri.parse('$_base/accounts/$accountId/notifications'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 5));

    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final raw = data['notifications']?['notification'];
    if (raw == null) return [];

    final list = raw is List ? raw : [raw];
    return list.map<TradierNotification>((n) {
      return TradierNotification(
        id:     '${accountId}_${n['id'] ?? n.hashCode}',
        title:  n['title']?.toString() ?? 'Tradier Notice',
        text:   n['text']?.toString() ?? '',
        status: n['status']?.toString() ?? 'active',
      );
    }).toList();
  }
}
