import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexusbot/services/app_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAppSettingsRepository', () {
    const userId = 'prefs-user';
    final repo = LocalAppSettingsRepository();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and loads tradier environment', () async {
      await repo.save(
        userId,
        const AppPreferences(
          spxTradierEnvironment: SpxTradierEnvironment.sandbox,
        ),
      );

      final loaded = await repo.load(userId);

      expect(
        loaded.spxTradierEnvironment,
        SpxTradierEnvironment.sandbox,
      );
    });

    test('saves and loads spx contract targeting mode', () async {
      await repo.save(
        userId,
        const AppPreferences(
          spxContractTargetingMode: SpxContractTargetingMode.nearOtm,
        ),
      );

      final loaded = await repo.load(userId);

      expect(
        loaded.spxContractTargetingMode,
        SpxContractTargetingMode.nearOtm,
      );
    });

    test('normalizes invalid tradier environment values', () async {
      SharedPreferences.setMockInitialValues({
        '$userId-settings_spx_tradier_environment': 'staging',
      });

      final loaded = await repo.load(userId);

      expect(
        loaded.spxTradierEnvironment,
        SpxTradierEnvironment.production,
      );
    });

    test('normalizes invalid spx contract targeting values', () async {
      SharedPreferences.setMockInitialValues({
        '$userId-settings_spx_contract_targeting_mode': 'deep_itm',
      });

      final loaded = await repo.load(userId);

      expect(
        loaded.spxContractTargetingMode,
        SpxContractTargetingMode.deltaZone,
      );
    });
  });
}
