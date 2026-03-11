import 'package:flutter_test/flutter_test.dart';

import 'package:nexusbot/services/app_settings_repository.dart';

void main() {
  test('SpxOpportunityExecutionMode falls back to manual confirm', () {
    expect(
      SpxOpportunityExecutionMode.normalize('invalid'),
      SpxOpportunityExecutionMode.manualConfirm,
    );
  });
}
