import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/gex_stream_models.dart';
import '../../models/spx_models.dart';
import 'gex_calculator.dart';
import 'spx_options_service.dart';

/// Holds the latest computed buffer + gamma levels + quote data.
class GexStreamUpdate {
  final List<GexStreamPoint> points;
  final GexLevels levels;
  final SpxQuoteData quote;
  final List<GexStrikeBar> strikeBars;

  const GexStreamUpdate({
    required this.points,
    required this.levels,
    required this.quote,
    required this.strikeBars,
  });
}

/// Polls Tradier (or the simulator) on [pollInterval] and maintains a rolling
/// intraday buffer of [GexStreamPoint]s (max 390 = a full 6.5-hour day at 1min
/// cadence). Ratios are recalculated across the full session window after each
/// new bar so they always reflect the day's range.
class GexStreamService {
  static const _maxPoints = 390;
  static const _defaultPollInterval = Duration(seconds: 2);

  final SpxOptionsService _options;
  final Duration _pollInterval;

  final _buffer = <GexStreamPoint>[];
  GexLevels _levels = GexLevels.empty;

  Timer? _timer;
  final _controller = StreamController<GexStreamUpdate>.broadcast();

  bool _ticking = false;

  GexStreamService({
    required SpxOptionsService optionsService,
    Duration pollInterval = _defaultPollInterval,
  })  : _options = optionsService,
        _pollInterval = pollInterval;

  Stream<GexStreamUpdate> get stream => _controller.stream;
  List<GexStreamPoint> get buffer => List.unmodifiable(_buffer);
  GexLevels get levels => _levels;
  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _tick();
    _timer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    if (!_controller.isClosed) _controller.close();
  }

  Future<void> _tick() async {
    if (_ticking) return; // don't overlap slow fetches
    _ticking = true;
    try {
      // Fetch multiple near-term expirations so GEX is spread across all
      // strikes realistically (single 0DTE only gives a hairline ATM spike).
      final expirations = await _options.fetchExpirations(limit: 4);
      if (expirations.isEmpty) return;

      final quote = await _options.fetchSpxQuote();
      if (quote.spot <= 0) return;

      // Aggregate chain across all fetched expirations
      final chains = await Future.wait(
        expirations.map((exp) => _options.fetchChain(expiration: exp)),
      );
      final chain = chains.expand((c) => c).toList();
      if (chain.isEmpty) return;

      final snapshot = GexCalculator.compute(chain, quote.spot);
      final prevFlow = _buffer.isEmpty ? 0.0 : _buffer.last.netFlow;
      final cumulativeFlow = prevFlow + (snapshot.callVol - snapshot.putVol);

      _buffer.add(GexStreamPoint(
        time: DateTime.now(),
        price: quote.spot,
        netGex: snapshot.netGex,
        netFlow: cumulativeFlow,
        netIv: snapshot.netIv,
        callVol: snapshot.callVol,
        putVol: snapshot.putVol,
        gexRatio: 0,
        flowRatio: 0,
        ivRatio: 0,
      ));

      if (_buffer.length > _maxPoints) _buffer.removeAt(0);

      _recomputeRatios();
      _levels = snapshot.levels;

      if (!_controller.isClosed) {
        _controller.add(GexStreamUpdate(
          points: List.unmodifiable(_buffer),
          levels: _levels,
          quote: quote,
          strikeBars: snapshot.strikeBars,
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GEX-STREAM] tick error: $e');
    } finally {
      _ticking = false;
    }
  }

  void _recomputeRatios() {
    if (_buffer.isEmpty) return;

    final gexValues = _buffer.map((p) => p.netGex).toList();
    final ivValues = _buffer.map((p) => p.netIv).toList();

    final gexMin = gexValues.reduce((a, b) => a < b ? a : b);
    final gexMax = gexValues.reduce((a, b) => a > b ? a : b);
    final ivMin = ivValues.reduce((a, b) => a < b ? a : b);
    final ivMax = ivValues.reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < _buffer.length; i++) {
      final p = _buffer[i];
      final total = (p.callVol + p.putVol).toDouble();
      _buffer[i] = p.copyWith(
        gexRatio: _ratio(p.netGex, gexMin, gexMax),
        flowRatio: total > 0 ? (p.callVol / total).clamp(0.0, 1.0) : 0.5,
        ivRatio: _ratio(p.netIv, ivMin, ivMax),
      );
    }
  }

  static double _ratio(double v, double min, double max) {
    if (max == min) return 0.5;
    return ((v - min) / (max - min)).clamp(0.0, 1.0);
  }
}
