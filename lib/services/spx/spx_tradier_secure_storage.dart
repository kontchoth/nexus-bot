import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_settings_repository.dart';

const tradierLegacyTokenStorageKey = 'tradier_api_token';

String tradierTokenStorageKey(String environment) {
  final normalized = SpxTradierEnvironment.normalize(environment);
  return 'tradier_api_token_$normalized';
}

Future<String> readTradierTokenForEnvironment(
  FlutterSecureStorage storage, {
  required String environment,
}) async {
  final envToken = (await storage.read(
            key: tradierTokenStorageKey(environment),
          ) ??
          '')
      .trim();
  if (envToken.isNotEmpty) return envToken;
  return (await storage.read(key: tradierLegacyTokenStorageKey) ?? '').trim();
}

Future<void> writeTradierTokenForEnvironment(
  FlutterSecureStorage storage, {
  required String environment,
  required String token,
}) async {
  final key = tradierTokenStorageKey(environment);
  final normalized = token.trim();
  if (normalized.isEmpty) {
    await storage.delete(key: key);
  } else {
    await storage.write(key: key, value: normalized);
  }
  await storage.delete(key: tradierLegacyTokenStorageKey);
}
