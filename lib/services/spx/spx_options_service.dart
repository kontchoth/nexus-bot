import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/spx_models.dart';
import 'spx_greeks_calculator.dart';
import 'spx_options_simulator.dart';

/// Live SPX options data via the Tradier API with simulator fallback.
///
/// Market hours guard: Tradier only has live quotes Mon–Fri 09:30–16:00 ET
/// (UTC 13:30–20:00 EST / 14:30–21:00 EDT).  Outside those hours the service
/// transparently falls back to [SpxOptionsSimulator].
///
/// Usage:
/// ```dart
/// final svc = SpxOptionsService(apiToken: 'your-tradier-token');
/// final spot = await svc.fetchSpxSpot();
/// final expirations = await svc.fetchExpirations();
/// final chain = await svc.fetchChain(expiration: expirations.first);
/// ```
class SpxOptionsService {
  // ── Tradier endpoints ────────────────────────────────────────────────────

  /// Use sandbox for development; swap to production when live.
  static const _sandboxBase    = 'https://sandbox.tradier.com/v1';
  static const _productionBase = 'https://api.tradier.com/v1';

  final String? _apiToken;
  final bool _useSandbox;
  final SpxOptionsSimulator _sim = SpxOptionsSimulator();

  bool _useLiveData = false;
  bool _liveErrorLogged = false;

  SpxOptionsService({String? apiToken, bool useSandbox = true})
      : _apiToken = apiToken,
        _useSandbox = useSandbox {
    _useLiveData = apiToken != null && apiToken.isNotEmpty;
  }

  String get _baseUrl => _useSandbox ? _sandboxBase : _productionBase;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiToken',
    'Accept':        'application/json',
  };

  // ── Public API ───────────────────────────────────────────────────────────

  bool get isLive => _useLiveData;

  /// SPX spot price.  Returns simulator value on failure.
  Future<double> fetchSpxSpot() async {
    if (!_useLiveData || !_isMarketHours()) return _sim.spot;
    try {
      final uri = Uri.parse('$_baseUrl/markets/quotes?symbols=SPX&greeks=false');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final last = data['quotes']['quote']['last'] as num?;
      if (last == null || last <= 0) throw Exception('Invalid quote');
      _liveErrorLogged = false;
      return last.toDouble();
    } catch (_) {
      _handleLiveError();
      return _sim.spot;
    }
  }

  /// Available expiration dates for SPX options (nearest 4 by default).
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    if (!_useLiveData || !_isMarketHours()) {
      return _simulatedExpirations();
    }
    try {
      final uri = Uri.parse(
        '$_baseUrl/markets/options/expirations?symbol=SPX&includeAllRoots=true&strikes=false',
      );
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final dates = (data['expirations']['date'] as List).cast<String>();
      _liveErrorLogged = false;
      return dates.take(limit).toList();
    } catch (_) {
      _handleLiveError();
      return _simulatedExpirations();
    }
  }

  /// Full options chain for a given expiration (YYYY-MM-DD).
  /// Returns greeks-enriched [OptionsContract] list, falling back to simulator.
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    if (!_useLiveData || !_isMarketHours()) {
      return _sim.refreshChain();
    }
    try {
      final uri = Uri.parse(
        '$_baseUrl/markets/options/chains?symbol=SPX&expiration=$expiration&greeks=true',
      );
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final options = data['options']['option'] as List?;
      if (options == null || options.isEmpty) throw Exception('Empty chain');

      final spot = await fetchSpxSpot();
      final contracts = _parseChain(options, spot, expiration);
      _liveErrorLogged = false;
      return contracts;
    } catch (_) {
      _handleLiveError();
      return _sim.refreshChain();
    }
  }

  /// Lightweight tick: update premiums for open positions.
  /// Returns [OptionsContract] list with refreshed prices.
  Future<List<OptionsContract>> tickPositions(List<OptionsContract> contracts) async {
    if (!_useLiveData || !_isMarketHours()) {
      return _sim.tick();
    }
    // For a live tick we re-fetch the spot and re-price using BS greeks
    // (a full chain re-fetch every second would hit rate limits)
    try {
      final spot = await fetchSpxSpot();
      final now  = DateTime.now();
      final updated = contracts.map((c) {
        final newGreeks = SpxGreeksCalculator.calcGreeks(
          spot: spot,
          strike: c.strike,
          daysToExpiry: c.daysToExpiry,
          iv: c.impliedVolatility,
          side: c.side,
        );
        final newPrice = SpxGreeksCalculator.calcPrice(
          spot: spot,
          strike: c.strike,
          daysToExpiry: c.daysToExpiry,
          iv: c.impliedVolatility,
          side: c.side,
        );
        return c.copyWith(
          bid:         (newPrice * 0.99).clamp(0.01, double.infinity),
          ask:         newPrice * 1.01,
          lastPrice:   newPrice,
          greeks:      newGreeks,
          lastUpdated: now,
        );
      }).toList();
      _liveErrorLogged = false;
      return updated;
    } catch (_) {
      _handleLiveError();
      return _sim.tick();
    }
  }

  // ── Tradier JSON parsing ─────────────────────────────────────────────────

  List<OptionsContract> _parseChain(
    List<dynamic> options,
    double spot,
    String expiration,
  ) {
    final expiryDate = DateTime.parse(expiration);
    final now        = DateTime.now();
    final dte        = expiryDate.difference(now).inDays.clamp(0, 365);
    final contracts  = <OptionsContract>[];

    for (final opt in options) {
      try {
        final side   = (opt['option_type'] as String) == 'call'
            ? OptionsSide.call
            : OptionsSide.put;
        final strike = (opt['strike'] as num).toDouble();
        final bid    = (opt['bid']    as num?)?.toDouble() ?? 0;
        final ask    = (opt['ask']    as num?)?.toDouble() ?? 0;
        final last   = (opt['last']   as num?)?.toDouble() ?? (bid + ask) / 2;
        final oi     = (opt['open_interest'] as num?)?.toInt() ?? 0;
        final vol    = (opt['volume']         as num?)?.toInt() ?? 0;
        final iv     = (opt['greeks']?['mid_iv'] as num?)?.toDouble() ?? 0.15;

        if (iv <= 0 || strike <= 0) continue;

        final greeks = SpxGreeksCalculator.calcGreeks(
          spot: spot, strike: strike, daysToExpiry: dte, iv: iv, side: side,
        );
        final ivRank = SpxGreeksCalculator.calcIvRank(iv, _ivHistoryPlaceholder());
        final signal = _scoreSignal(greeks, ivRank, oi, vol, (bid + ask) / 2);

        contracts.add(OptionsContract(
          symbol:            opt['symbol'] as String? ?? '',
          side:              side,
          strike:            strike,
          expiry:            expiryDate,
          daysToExpiry:      dte,
          bid:               bid,
          ask:               ask,
          lastPrice:         last,
          openInterest:      oi,
          volume:            vol,
          greeks:            greeks,
          impliedVolatility: iv,
          ivRank:            ivRank,
          signal:            signal,
          lastUpdated:       now,
        ));
      } catch (_) {
        continue; // skip malformed rows
      }
    }
    return contracts;
  }

  // ── Signal scoring (mirrors simulator logic) ─────────────────────────────

  SpxSignalType _scoreSignal(
    OptionsGreeks greeks,
    double ivRank,
    int oi,
    int volume,
    double midPrice,
  ) {
    var score = 0;
    if (ivRank > 50) { score += 2; }
    if (greeks.delta.abs() >= 0.20 && greeks.delta.abs() <= 0.45) { score += 1; }
    if (volume > oi * 0.05) { score += 1; }
    if (midPrice > 0.50)    { score += 1; }

    if (score >= 3) return SpxSignalType.buy;
    if (score <= 1) return SpxSignalType.sell;
    return SpxSignalType.watch;
  }

  // ── Market hours guard ───────────────────────────────────────────────────

  /// Returns true during US equities/options market hours (Mon–Fri).
  /// Uses a conservative UTC window that covers both EST and EDT:
  ///   EST: 09:30–16:00 ET = 14:30–21:00 UTC
  ///   EDT: 09:30–16:00 ET = 13:30–20:00 UTC
  /// We open the window at 13:30 UTC and close at 21:00 UTC to be safe.
  static bool _isMarketHours([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    if (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) {
      return false;
    }
    final minutesUtc = t.hour * 60 + t.minute;
    return minutesUtc >= (13 * 60 + 30) && minutesUtc < (21 * 60);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _handleLiveError() {
    if (!_liveErrorLogged) {
      _liveErrorLogged = true;
    }
    _useLiveData = false;
  }

  List<String> _simulatedExpirations() {
    final now  = DateTime.now();
    // Next 4 Friday dates
    final dates = <String>[];
    var d = now;
    while (dates.length < 4) {
      d = d.add(const Duration(days: 1));
      if (d.weekday == DateTime.friday) {
        dates.add('${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}');
      }
    }
    return dates;
  }

  /// Placeholder IV history (252 points ~14–34%).
  /// Replace with persistent storage once historical data is available.
  List<double> _ivHistoryPlaceholder() =>
      List.generate(252, (i) => 0.14 + (i % 20) * 0.001);
}
