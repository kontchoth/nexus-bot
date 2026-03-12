import 'package:intl/intl.dart';

class NexusFormatters {
  static final Map<int, NumberFormat> _currencyFormatters =
      <int, NumberFormat>{};
  static final Map<int, NumberFormat> _numberFormatters = <int, NumberFormat>{};
  static final NumberFormat _compactNumberFormatter =
      NumberFormat.compact(locale: 'en_US');

  static String usd(
    num value, {
    int decimals = 2,
    bool signed = false,
  }) {
    final precision = decimals.clamp(0, 6);
    final formatter = _currencyFormatters.putIfAbsent(
      precision,
      () => NumberFormat.currency(
        locale: 'en_US',
        symbol: '\$',
        decimalDigits: precision,
      ),
    );
    if (!signed) return formatter.format(value);

    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${formatter.format(value.abs())}';
  }

  static String number(
    num value, {
    int decimals = 0,
    bool signed = false,
  }) {
    final precision = decimals.clamp(0, 6);
    final formatter = _numberFormatters.putIfAbsent(
      precision,
      () => NumberFormat.decimalPatternDigits(
        locale: 'en_US',
        decimalDigits: precision,
      ),
    );
    if (!signed) return formatter.format(value);

    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${formatter.format(value.abs())}';
  }

  static String points(
    num value, {
    int decimals = 1,
    bool signed = false,
  }) {
    return '${number(value, decimals: decimals, signed: signed)} pts';
  }

  static String compactNumber(num value) {
    return _compactNumberFormatter.format(value);
  }
}
