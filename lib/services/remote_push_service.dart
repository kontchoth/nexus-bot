import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/common_models.dart';

class RemotePushMessage {
  final String title;
  final String body;
  final String? payload;

  const RemotePushMessage({
    required this.title,
    required this.body,
    this.payload,
  });
}

class RemotePushService {
  RemotePushService._();

  static final RemotePushService instance = RemotePushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final StreamController<String> _openedPayloadController =
      StreamController<String>.broadcast();
  final StreamController<RemotePushMessage> _foregroundController =
      StreamController<RemotePushMessage>.broadcast();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  String? _currentUserId;
  bool _configured = false;

  Stream<String> get openedPayloadStream => _openedPayloadController.stream;
  Stream<RemotePushMessage> get foregroundMessageStream =>
      _foregroundController.stream;

  Future<void> configure({
    required String userId,
    required bool alertsEnabled,
  }) async {
    if (Firebase.apps.isEmpty) return;

    _currentUserId = userId;
    if (!_configured) {
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );
      _foregroundSub = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) {
        unawaited(_upsertToken(token, alertsEnabled: alertsEnabled));
      });

      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _handleOpenedMessage(initial);
      }
      _configured = true;
    }

    await _messaging.setAutoInitEnabled(alertsEnabled);
    await _messaging.requestPermission(
      alert: alertsEnabled,
      badge: alertsEnabled,
      sound: alertsEnabled,
      provisional: false,
    );

    final token = await _messaging.getToken();
    if (token != null && token.trim().isNotEmpty) {
      await _upsertToken(token, alertsEnabled: alertsEnabled);
    }
  }

  Future<void> updateAlertsPreference({
    required bool alertsEnabled,
  }) async {
    if (Firebase.apps.isEmpty || _currentUserId == null) return;
    await _messaging.setAutoInitEnabled(alertsEnabled);

    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _upsertToken(token, alertsEnabled: alertsEnabled);
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final payload = _extractPayload(message);
    if (payload == null || _openedPayloadController.isClosed) return;
    _openedPayloadController.add(payload);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (_foregroundController.isClosed) return;

    final notification = message.notification;
    final title = (notification?.title ??
            message.data['title']?.toString() ??
            'SPX Opportunity')
        .trim();
    final body = (notification?.body ??
            message.data['body']?.toString() ??
            'Opportunity update')
        .trim();

    _foregroundController.add(
      RemotePushMessage(
        title: title.isEmpty ? 'SPX Opportunity' : title,
        body: body.isEmpty ? 'Opportunity update' : body,
        payload: _extractPayload(message),
      ),
    );
  }

  String? _extractPayload(RemoteMessage message) {
    final direct = message.data['payload']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final opportunityId = message.data['opportunityId']?.toString().trim();
    if (opportunityId != null && opportunityId.isNotEmpty) {
      return TradeAlertPayloads.forSpxOpportunity(opportunityId);
    }

    final target = message.data['target']?.toString().trim().toLowerCase();
    if (target == 'spx_opportunities') {
      return TradeAlertPayloads.spxOpportunities;
    }
    return null;
  }

  Future<void> _upsertToken(
    String token, {
    required bool alertsEnabled,
  }) async {
    final userId = _currentUserId;
    if (userId == null || userId.trim().isEmpty) return;

    final doc = _firestore
        .collection('users')
        .doc(userId)
        .collection('push_tokens')
        .doc(token);

    await doc.set({
      'token': token,
      'alertsEnabled': alertsEnabled,
      'platform': _platformLabel(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
    _tokenRefreshSub = null;
    _openedSub = null;
    _foregroundSub = null;
    _configured = false;
  }
}
