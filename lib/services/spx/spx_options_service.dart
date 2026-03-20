import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final bool _enforceMarketHours;
  final SpxOptionsSimulator _sim = SpxOptionsSimulator();

  bool _useLiveData = false;
  DateTime? _liveRetryAt;
  int _liveFailureCount = 0;

  SpxOptionsService({
    String? apiToken,
    bool useSandbox = false,
    bool enforceMarketHours = false,
  })
      : _apiToken = apiToken,
        _useSandbox = useSandbox,
        _enforceMarketHours = enforceMarketHours {
    _useLiveData = apiToken != null && apiToken.isNotEmpty;
    _liveLog(
      'init token=${_useLiveData ? 'present' : 'missing'} '
      'endpoint=${_useSandbox ? 'sandbox' : 'production'} '
      'marketHoursGuard=$_enforceMarketHours',
    );
  }

  String get _baseUrl => _useSandbox ? _sandboxBase : _productionBase;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiToken',
    'Accept':        'application/json',
  };

  // ── Public API ───────────────────────────────────────────────────────────

  bool get isLive => _canAttemptLive() && (!_enforceMarketHours || _isMarketHours());
  bool get isMarketOpenNow => _isMarketHours();

  /// SPX spot price.  Returns simulator value on failure.
  Future<double> fetchSpxSpot() async => (await fetchSpxQuote()).spot;

  /// SPX quote with today's range + 52-week range. Returns simulator fallback.
  Future<SpxQuoteData> fetchSpxQuote() async {
    if (!_shouldAttemptLive()) {
      _liveLog('quote -> simulator (${_liveSkipReason()})');
      final s = _sim.spot;
      return SpxQuoteData(
        spot: s, dayLow: s * 0.995, dayHigh: s * 1.005,
        week52Low: s * 0.85, week52High: s * 1.15,
      );
    }
    try {
      final uri = Uri.parse('$_baseUrl/markets/quotes?symbols=SPX&greeks=false');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final q = jsonDecode(res.body)['quotes']['quote'];
      final last    = (q['last']              as num?)?.toDouble() ?? 0;
      if (last <= 0) throw Exception('Invalid quote');
      final low     = (q['low']               as num?)?.toDouble() ?? last * 0.995;
      final high    = (q['high']              as num?)?.toDouble() ?? last * 1.005;
      final w52l    = (q['week_52_low']       as num?)?.toDouble() ?? last * 0.85;
      final w52h    = (q['week_52_high']      as num?)?.toDouble() ?? last * 1.15;
      final bid       = (q['bid']               as num?)?.toDouble() ?? 0;
      final ask       = (q['ask']               as num?)?.toDouble() ?? 0;
      final change    = (q['change']            as num?)?.toDouble() ?? 0;
      final changePct = (q['change_percentage'] as num?)?.toDouble() ?? 0;
      final volume    = (q['volume']            as num?)?.toInt() ?? 0;
      final avgVol    = (q['average_volume']    as num?)?.toInt() ?? 0;
      final beta      = (q['beta']              as num?)?.toDouble() ?? 0;
      final mktCap    = (q['market_cap']        as num?)?.toDouble() ?? 0;
      final pe        = (q['pe_ratio']          as num?)?.toDouble() ?? 0;
      _markLiveSuccess();
      return SpxQuoteData(
        spot: last, dayLow: low, dayHigh: high, week52Low: w52l, week52High: w52h,
        bid: bid, ask: ask, change: change, changePercent: changePct,
        volume: volume, avgVolume: avgVol, beta: beta, marketCap: mktCap, peRatio: pe,
      );
    } catch (e) {
      _liveLog('quote live request failed: $e');
      _handleLiveError(error: e);
      final s = _sim.spot;
      return SpxQuoteData(
        spot: s, dayLow: s * 0.995, dayHigh: s * 1.005,
        week52Low: s * 0.85, week52High: s * 1.15,
      );
    }
  }

  /// Available expiration dates for SPX options (nearest 4 by default).
  Future<List<String>> fetchExpirations({int limit = 4}) async {
    if (!_shouldAttemptLive()) {
      _liveLog('expirations -> simulator (${_liveSkipReason()})');
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
      _markLiveSuccess();
      return dates.take(limit).toList();
    } catch (e) {
      _liveLog('expirations live request failed: $e');
      _handleLiveError(error: e);
      return _simulatedExpirations();
    }
  }

  /// Full options chain for a given expiration (YYYY-MM-DD).
  /// Returns greeks-enriched [OptionsContract] list, falling back to simulator.
  Future<List<OptionsContract>> fetchChain({required String expiration}) async {
    if (!_shouldAttemptLive()) {
      _liveLog('chain($expiration) -> simulator (${_liveSkipReason()})');
      return _simulatedChainForExpiration(expiration);
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
      _markLiveSuccess();
      return contracts;
    } catch (e) {
      _liveLog('chain($expiration) live request failed: $e');
      _handleLiveError(error: e);
      return _simulatedChainForExpiration(expiration);
    }
  }

  /// Lightweight tick: update premiums for open positions.
  /// Returns [OptionsContract] list with refreshed prices.
  Future<List<OptionsContract>> tickPositions(List<OptionsContract> contracts) async {
    if (!_shouldAttemptLive()) {
      _liveLog('tick -> simulator (${_liveSkipReason()})');
      return _sim.tick();
    }
    // For a live tick we re-fetch the spot and re-price using BS greeks
    // (a full chain re-fetch every second would hit rate limits)
    try {
      final spot = await fetchSpxSpot();
      final now  = DateTime.now();
      final updated = contracts.map((c) {
        final remainingMinutes = c.expiry.difference(now).inMinutes;
        final remainingDteFrac = (remainingMinutes / (24.0 * 60.0))
            .clamp(1.0 / (24.0 * 60.0), 365.0);
        final remainingDteInt = c.expiry.difference(now).inDays.clamp(0, 365);
        final newGreeks = SpxGreeksCalculator.calcGreeks(
          spot: spot,
          strike: c.strike,
          daysToExpiry: remainingDteFrac,
          iv: c.impliedVolatility,
          side: c.side,
        );
        final newPrice = SpxGreeksCalculator.calcPrice(
          spot: spot,
          strike: c.strike,
          daysToExpiry: remainingDteFrac,
          iv: c.impliedVolatility,
          side: c.side,
        );
        return c.copyWith(
          bid:         (newPrice * 0.99).clamp(0.01, double.infinity),
          ask:         newPrice * 1.01,
          lastPrice:   newPrice,
          greeks:      newGreeks,
          daysToExpiry: remainingDteInt,
          lastUpdated: now,
        );
      }).toList();
      _markLiveSuccess();
      return updated;
    } catch (e) {
      _liveLog('tick live request failed: $e');
      _handleLiveError(error: e);
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
    // Use fractional DTE in days so 0DTE options (hours left) still produce
    // valid gamma. Minimum 1 minute to avoid division-by-zero in BS formulas.
    final dteMinutes  = expiryDate.difference(now).inMinutes;
    final dteFractional = (dteMinutes / (24.0 * 60.0)).clamp(1.0 / (24.0 * 60.0), 365.0);
    final dteInt      = expiryDate.difference(now).inDays.clamp(0, 365);
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
          spot: spot, strike: strike, daysToExpiry: dteFractional, iv: iv, side: side,
        );
        final ivRank = SpxGreeksCalculator.calcIvRank(iv, _ivHistoryPlaceholder());
        final signal = _scoreSignal(greeks, ivRank, oi, vol, (bid + ask) / 2, dteInt);

        contracts.add(OptionsContract(
          symbol:            opt['symbol'] as String? ?? '',
          side:              side,
          strike:            strike,
          expiry:            expiryDate,
          daysToExpiry:      dteInt,
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

  /// VIX spot level. Returns null when outside market hours or on error.
  Future<double?> fetchVix() async {
    if (!_shouldAttemptLive()) return null;
    try {
      final uri = Uri.parse('$_baseUrl/markets/quotes?symbols=VIX&greeks=false');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final q = jsonDecode(res.body)['quotes']['quote'];
      final last = (q['last'] as num?)?.toDouble();
      if (last == null || last <= 0) return null;
      return last;
    } catch (e) {
      _liveLog('VIX fetch failed: $e');
      return null;
    }
  }

  /// SPX daily OHLC bars for the past [lookbackCalendarDays] calendar days.
  /// Used to derive prior-day high/low/close and weekly S/R levels.
  Future<List<SpxDailyBar>> fetchSpxDailyBars({int lookbackCalendarDays = 10}) async {
    if (!_canAttemptLive()) return [];
    try {
      final now = DateTime.now().toUtc();
      final start = now.subtract(Duration(days: lookbackCalendarDays));
      String _pad(int n) => n.toString().padLeft(2, '0');
      String _fmt(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
      final uri = Uri.parse(
        '$_baseUrl/markets/history?symbol=SPX&interval=daily'
        '&start=${_fmt(start)}&end=${_fmt(now)}',
      );
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final raw = data['history']?['day'];
      if (raw == null) return [];
      final list = raw is List ? raw : [raw];
      return list.map<SpxDailyBar>((d) => SpxDailyBar(
        date: (d['date'] as String?) ?? '',
        open: (d['open'] as num?)?.toDouble() ?? 0,
        high: (d['high'] as num?)?.toDouble() ?? 0,
        low: (d['low'] as num?)?.toDouble() ?? 0,
        close: (d['close'] as num?)?.toDouble() ?? 0,
      )).toList();
    } catch (e) {
      _liveLog('SPX daily bars fetch failed: $e');
      return [];
    }
  }

  // ── Signal scoring (mirrors simulator logic) ─────────────────────────────

  SpxSignalType _scoreSignal(
    OptionsGreeks greeks,
    double ivRank,
    int oi,
    int volume,
    double midPrice,
    int daysToExpiry,
  ) {
    var score = 0;

    // IV rank gradient (0–3 pts)
    if (ivRank < 25)       score += 3;
    else if (ivRank < 40)  score += 2;
    else if (ivRank < 60)  score += 1;
    else if (ivRank > 75)  score -= 1;

    // Delta quality (0–2 pts)
    final absD = greeks.delta.abs();
    if (absD >= 0.25 && absD <= 0.40)      score += 2;
    else if (absD >= 0.20 && absD <= 0.45) score += 1;

    // Gamma quality (0–1 pt)
    if (greeks.gamma >= 0.003) score += 1;

    // Theta cost as % of premium (0 to −2 pts)
    if (midPrice > 0) {
      final thetaPct = greeks.theta.abs() / midPrice;
      if (thetaPct > 0.20)      score -= 2;
      else if (thetaPct > 0.12) score -= 1;
    }

    // Liquidity (0–3 pts)
    if (oi > 0) {
      final voiRatio = volume / oi;
      if (voiRatio > 0.15)      score += 2;
      else if (voiRatio > 0.05) score += 1;
    }
    if (volume > 500) score += 1;

    // Premium range (−1 to +1 pt)
    if (midPrice < 0.50)                          score -= 1;
    else if (midPrice >= 1.0 && midPrice <= 8.0)  score += 1;
    else if (midPrice > 15.0)                     score -= 1;

    // DTE quality (−1 to +2 pts)
    if (daysToExpiry >= 2 && daysToExpiry <= 7)        score += 2;
    else if (daysToExpiry >= 8 && daysToExpiry <= 14)  score += 1;
    else if (daysToExpiry > 21)                        score -= 1;

    if (score >= 6) return SpxSignalType.buy;
    if (score <= 2) return SpxSignalType.sell;
    return SpxSignalType.watch;
  }

  // ── Market hours guard ───────────────────────────────────────────────────

  /// Returns true during US equities/options market hours (Mon–Fri).
  /// Uses US Eastern time including DST approximation and common US market holidays.
  static bool _isMarketHours([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final et = utc.add(Duration(hours: _easternUtcOffsetHours(utc)));
    if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
      return false;
    }
    if (_isUsMarketHoliday(et)) return false;
    final minutesEt = et.hour * 60 + et.minute;
    return minutesEt >= (9 * 60 + 30) && minutesEt < (16 * 60);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _handleLiveError({Object? error}) {
    _liveFailureCount++;
    final backoffSeconds = _liveFailureCount <= 1
        ? 10
        : (_liveFailureCount <= 3 ? 30 : 120);
    _liveRetryAt = DateTime.now().add(Duration(seconds: backoffSeconds));
    _liveLog(
      'live backoff failures=$_liveFailureCount '
      'retryAt=${_liveRetryAt!.toIso8601String()} '
      'error=${error ?? 'unknown'}',
    );
  }

  void _markLiveSuccess() {
    if (_liveFailureCount > 0 || _liveRetryAt != null) {
      _liveLog('live recovered');
    }
    _liveFailureCount = 0;
    _liveRetryAt = null;
  }

  bool _canAttemptLive() {
    if (!_useLiveData) return false;
    if (_liveRetryAt == null) return true;
    return DateTime.now().isAfter(_liveRetryAt!);
  }

  bool _shouldAttemptLive() {
    if (!_canAttemptLive()) return false;
    if (_enforceMarketHours && !_isMarketHours()) return false;
    return true;
  }

  String _liveSkipReason() {
    if (!_useLiveData) return 'no token';
    if (_liveRetryAt != null && DateTime.now().isBefore(_liveRetryAt!)) {
      final remaining = _liveRetryAt!.difference(DateTime.now()).inSeconds;
      return 'backoff ${remaining}s';
    }
    if (_enforceMarketHours && !_isMarketHours()) return 'outside market hours';
    return 'live disabled';
  }

  void _liveLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[SPX-LIVE] $message');
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

  List<OptionsContract> _simulatedChainForExpiration(String expiration) {
    final expiry = DateTime.tryParse(expiration);
    if (expiry == null) {
      return _sim.refreshChain();
    }
    final dte = expiry.difference(DateTime.now()).inDays.clamp(1, 365);
    return _sim.refreshChain(dteDays: [dte]);
  }

  static int _easternUtcOffsetHours(DateTime utc) {
    final year = utc.year;
    final dstStart = _nthWeekdayOfMonthUtc(year, 3, DateTime.sunday, 2)
        .add(const Duration(hours: 7)); // 2:00 local EST = 07:00 UTC
    final dstEnd = _nthWeekdayOfMonthUtc(year, 11, DateTime.sunday, 1)
        .add(const Duration(hours: 6)); // 2:00 local EDT = 06:00 UTC
    return (utc.isAfter(dstStart) && utc.isBefore(dstEnd)) ? -4 : -5;
  }

  static DateTime _nthWeekdayOfMonthUtc(
    int year,
    int month,
    int weekday,
    int nth,
  ) {
    var day = DateTime.utc(year, month, 1);
    while (day.weekday != weekday) {
      day = day.add(const Duration(days: 1));
    }
    return day.add(Duration(days: (nth - 1) * 7));
  }

  static DateTime _lastWeekdayOfMonthUtc(int year, int month, int weekday) {
    var day = DateTime.utc(year, month + 1, 0);
    while (day.weekday != weekday) {
      day = day.subtract(const Duration(days: 1));
    }
    return day;
  }

  static bool _isUsMarketHoliday(DateTime etDate) {
    final y = etDate.year;
    final d = DateTime.utc(y, etDate.month, etDate.day);
    final newYear = _observedHolidayUtc(DateTime.utc(y, 1, 1));
    final mlk = _nthWeekdayOfMonthUtc(y, 1, DateTime.monday, 3);
    final presidents = _nthWeekdayOfMonthUtc(y, 2, DateTime.monday, 3);
    final memorial = _lastWeekdayOfMonthUtc(y, 5, DateTime.monday);
    final juneteenth = _observedHolidayUtc(DateTime.utc(y, 6, 19));
    final independence = _observedHolidayUtc(DateTime.utc(y, 7, 4));
    final labor = _nthWeekdayOfMonthUtc(y, 9, DateTime.monday, 1);
    final thanksgiving = _nthWeekdayOfMonthUtc(y, 11, DateTime.thursday, 4);
    final christmas = _observedHolidayUtc(DateTime.utc(y, 12, 25));
    final goodFriday = _easterSundayUtc(y).subtract(const Duration(days: 2));

    final holidays = {
      DateTime.utc(newYear.year, newYear.month, newYear.day),
      DateTime.utc(mlk.year, mlk.month, mlk.day),
      DateTime.utc(presidents.year, presidents.month, presidents.day),
      DateTime.utc(goodFriday.year, goodFriday.month, goodFriday.day),
      DateTime.utc(memorial.year, memorial.month, memorial.day),
      DateTime.utc(juneteenth.year, juneteenth.month, juneteenth.day),
      DateTime.utc(independence.year, independence.month, independence.day),
      DateTime.utc(labor.year, labor.month, labor.day),
      DateTime.utc(thanksgiving.year, thanksgiving.month, thanksgiving.day),
      DateTime.utc(christmas.year, christmas.month, christmas.day),
    };
    return holidays.contains(d);
  }

  static DateTime _observedHolidayUtc(DateTime holiday) {
    if (holiday.weekday == DateTime.saturday) {
      return holiday.subtract(const Duration(days: 1));
    }
    if (holiday.weekday == DateTime.sunday) {
      return holiday.add(const Duration(days: 1));
    }
    return holiday;
  }

  // Anonymous Gregorian algorithm
  static DateTime _easterSundayUtc(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime.utc(year, month, day);
  }

  /// Placeholder IV history (252 points ~14–34%).
  /// Replace with persistent storage once historical data is available.
  List<double> _ivHistoryPlaceholder() =>
      List.generate(252, (i) => 0.14 + (i % 20) * 0.001);
}
