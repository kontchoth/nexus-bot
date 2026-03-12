import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/utils/number_formatters.dart';

void main() {
  group('NexusFormatters', () {
    test('formats signed usd values with grouping', () {
      expect(
        NexusFormatters.usd(5750.25),
        '\$5,750.25',
      );
      expect(
        NexusFormatters.usd(1250.5, signed: true),
        '+\$1,250.50',
      );
      expect(
        NexusFormatters.usd(-1250.5, signed: true),
        '-\$1,250.50',
      );
    });

    test('formats grouped index prices and points', () {
      expect(
        NexusFormatters.number(5750.4, decimals: 1),
        '5,750.4',
      );
      expect(
        NexusFormatters.points(12.3, signed: true),
        '+12.3 pts',
      );
    });
  });
}
