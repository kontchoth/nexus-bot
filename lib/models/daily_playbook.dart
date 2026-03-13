import 'dart:convert';

// ── Sub-models ────────────────────────────────────────────────────────────────

class SignalResult {
  final String bias;       // 'bullish' | 'bearish' | 'neutral'
  final double value;
  final double confidence; // 0.0–1.0

  const SignalResult({
    required this.bias,
    required this.value,
    required this.confidence,
  });

  factory SignalResult.neutral() =>
      const SignalResult(bias: 'neutral', value: 0, confidence: 0);

  factory SignalResult.fromJson(Map<String, dynamic> j) => SignalResult(
        bias:       j['bias'] as String? ?? 'neutral',
        value:      (j['value'] as num?)?.toDouble() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'bias':       bias,
        'value':      value,
        'confidence': confidence,
      };
}

class DPLResult {
  final String direction;   // 'LONG' | 'SHORT' | 'NEUTRAL'
  final String color;       // 'green' | 'red' | 'gray'
  final double separation;
  final bool isExpanding;

  const DPLResult({
    required this.direction,
    required this.color,
    required this.separation,
    required this.isExpanding,
  });

  factory DPLResult.neutral() => const DPLResult(
        direction:   'NEUTRAL',
        color:       'gray',
        separation:  0,
        isExpanding: false,
      );

  factory DPLResult.fromJson(Map<String, dynamic> j) => DPLResult(
        direction:   j['direction'] as String? ?? 'NEUTRAL',
        color:       j['color'] as String? ?? 'gray',
        separation:  (j['separation'] as num?)?.toDouble() ?? 0,
        isExpanding: j['is_expanding'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'direction':    direction,
        'color':        color,
        'separation':   separation,
        'is_expanding': isExpanding,
      };
}

class BreadthResult {
  final double ratio;
  final String bias;          // 'bullish' | 'bearish' | 'neutral'
  final String participation; // 'broad' | 'mixed' | 'narrow'

  const BreadthResult({
    required this.ratio,
    required this.bias,
    required this.participation,
  });

  factory BreadthResult.neutral() =>
      const BreadthResult(ratio: 0.5, bias: 'neutral', participation: 'mixed');

  factory BreadthResult.fromJson(Map<String, dynamic> j) => BreadthResult(
        ratio:         (j['ratio'] as num?)?.toDouble() ?? 0.5,
        bias:          j['bias'] as String? ?? 'neutral',
        participation: j['participation'] as String? ?? 'mixed',
      );

  Map<String, dynamic> toJson() => {
        'ratio':         ratio,
        'bias':          bias,
        'participation': participation,
      };
}

class PlaybookSignals {
  final SignalResult spyComponent;
  final SignalResult iTod;
  final SignalResult optimizedTod;
  final SignalResult todGap;
  final DPLResult    dpl;
  final BreadthResult ad65;
  final SignalResult domGap;

  const PlaybookSignals({
    required this.spyComponent,
    required this.iTod,
    required this.optimizedTod,
    required this.todGap,
    required this.dpl,
    required this.ad65,
    required this.domGap,
  });

  factory PlaybookSignals.empty() => PlaybookSignals(
        spyComponent: SignalResult.neutral(),
        iTod:         SignalResult.neutral(),
        optimizedTod: SignalResult.neutral(),
        todGap:       SignalResult.neutral(),
        dpl:          DPLResult.neutral(),
        ad65:         BreadthResult.neutral(),
        domGap:       SignalResult.neutral(),
      );

  factory PlaybookSignals.fromJson(Map<String, dynamic> j) => PlaybookSignals(
        spyComponent: SignalResult.fromJson(
            (j['spy_component'] as Map<String, dynamic>?) ?? {}),
        iTod:        SignalResult.fromJson(
            (j['iToD'] as Map<String, dynamic>?) ?? {}),
        optimizedTod: SignalResult.fromJson(
            (j['optimized_tod'] as Map<String, dynamic>?) ?? {}),
        todGap:      SignalResult.fromJson(
            (j['tod_gap'] as Map<String, dynamic>?) ?? {}),
        dpl:         DPLResult.fromJson(
            (j['dpl'] as Map<String, dynamic>?) ?? {}),
        ad65:        BreadthResult.fromJson(
            (j['ad_6_5'] as Map<String, dynamic>?) ?? {}),
        domGap:      SignalResult.fromJson(
            (j['dom_gap'] as Map<String, dynamic>?) ?? {}),
      );
}

// ── Main model ────────────────────────────────────────────────────────────────

enum PlaybookStatus { premarket, open, locked }

enum PlaybookRecommendation { goLong, goShort, wait, none }

extension PlaybookRecommendationExt on PlaybookRecommendation {
  String get label => switch (this) {
        PlaybookRecommendation.goLong  => 'GO LONG',
        PlaybookRecommendation.goShort => 'GO SHORT',
        PlaybookRecommendation.wait    => 'WAIT / REASSESS',
        PlaybookRecommendation.none    => 'AWAITING DATA',
      };

  static PlaybookRecommendation parse(String? v) => switch (v) {
        'GO_LONG'  => PlaybookRecommendation.goLong,
        'GO_SHORT' => PlaybookRecommendation.goShort,
        'WAIT'     => PlaybookRecommendation.wait,
        _          => PlaybookRecommendation.none,
      };
}

class DailyPlaybook {
  final String date;             // YYYY-MM-DD
  final String generatedAt;      // ISO UTC
  final PlaybookStatus status;

  // ── Previous day ──────────────────────────────────────────────────────────
  final double yesterdayClose;

  // ── GEX ───────────────────────────────────────────────────────────────────
  final double netGex;
  final double flipLevel;
  final double gammaWall;
  final double putWall;
  final String regime;

  // ── Walls & range ─────────────────────────────────────────────────────────
  final List<List<double>> wallRally; // [[strike, OI], ...]
  final List<List<double>> wallDrop;
  final double spxRangeEst;

  // ── Premarket ─────────────────────────────────────────────────────────────
  final String premkBias;
  final double premkPrice;

  // ── Signals ───────────────────────────────────────────────────────────────
  final PlaybookSignals signals;

  // ── Algorithm resolution ──────────────────────────────────────────────────
  final int? algorithmStep;        // 1 | 2 | 3
  final PlaybookRecommendation recommendation;
  final bool? signalUnity;
  final String? reason;

  // ── Minute-14 lock ────────────────────────────────────────────────────────
  final double? min14High;
  final double? min14Low;
  final double? otmLongStrike;
  final double? otmShortStrike;

  // ── Live refresh ──────────────────────────────────────────────────────────
  final String? lastRefreshedAt;
  final DPLResult? dplLive;

  const DailyPlaybook({
    required this.date,
    required this.generatedAt,
    required this.status,
    required this.yesterdayClose,
    required this.netGex,
    required this.flipLevel,
    required this.gammaWall,
    required this.putWall,
    required this.regime,
    required this.wallRally,
    required this.wallDrop,
    required this.spxRangeEst,
    required this.premkBias,
    required this.premkPrice,
    required this.signals,
    required this.recommendation,
    this.algorithmStep,
    this.signalUnity,
    this.reason,
    this.min14High,
    this.min14Low,
    this.otmLongStrike,
    this.otmShortStrike,
    this.lastRefreshedAt,
    this.dplLive,
  });

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get isLocked => status == PlaybookStatus.locked;

  DPLResult get activeDpl => dplLive ?? signals.dpl;

  int get upSignals => _biases.where((b) => b == 'bullish').length;
  int get downSignals => _biases.where((b) => b == 'bearish').length;
  int get neutralSignals => _biases.where((b) => b == 'neutral').length;
  bool get allSignalsAligned => upSignals == 7 || downSignals == 7;

  List<String> get _biases => [
        signals.spyComponent.bias,
        signals.iTod.bias,
        signals.optimizedTod.bias,
        signals.todGap.bias,
        signals.dpl.direction == 'LONG' ? 'bullish' : signals.dpl.direction == 'SHORT' ? 'bearish' : 'neutral',
        signals.ad65.bias,
        signals.domGap.bias,
      ];

  // ── Deserialisation ────────────────────────────────────────────────────────

  factory DailyPlaybook.fromJson(Map<String, dynamic> j) {
    PlaybookStatus parseStatus(String? v) => switch (v) {
          'open'   => PlaybookStatus.open,
          'locked' => PlaybookStatus.locked,
          _        => PlaybookStatus.premarket,
        };

    List<List<double>> parseWalls(dynamic raw) {
      if (raw == null) return [];
      return (raw as List)
          .map((item) => (item as List).map((v) => (v as num).toDouble()).toList())
          .toList();
    }

    return DailyPlaybook(
      date:           j['date'] as String? ?? '',
      generatedAt:    j['generated_at'] as String? ?? '',
      status:         parseStatus(j['status'] as String?),
      yesterdayClose: (j['yesterday_close'] as num?)?.toDouble() ?? 0,
      netGex:         (j['net_gex'] as num?)?.toDouble() ?? 0,
      flipLevel:      (j['flip_level'] as num?)?.toDouble() ?? 0,
      gammaWall:      (j['gamma_wall'] as num?)?.toDouble() ?? 0,
      putWall:        (j['put_wall'] as num?)?.toDouble() ?? 0,
      regime:         j['regime'] as String? ?? '',
      wallRally:      parseWalls(j['wall_rally']),
      wallDrop:       parseWalls(j['wall_drop']),
      spxRangeEst:    (j['spx_range_est'] as num?)?.toDouble() ?? 0,
      premkBias:      j['premarket_bias'] as String? ?? '',
      premkPrice:     (j['premarket_price'] as num?)?.toDouble() ?? 0,
      signals:        PlaybookSignals.fromJson(
          (j['signals'] as Map<String, dynamic>?) ?? {}),
      algorithmStep:  j['algorithm_step'] as int?,
      recommendation: PlaybookRecommendationExt.parse(j['recommendation'] as String?),
      signalUnity:    j['signal_unity'] as bool?,
      reason:         j['reason'] as String?,
      min14High:      (j['min14_high'] as num?)?.toDouble(),
      min14Low:       (j['min14_low'] as num?)?.toDouble(),
      otmLongStrike:  (j['otm_long_strike'] as num?)?.toDouble(),
      otmShortStrike: (j['otm_short_strike'] as num?)?.toDouble(),
      lastRefreshedAt: j['last_refreshed_at'] as String?,
      dplLive:        j['dpl_live'] != null
          ? DPLResult.fromJson(j['dpl_live'] as Map<String, dynamic>)
          : null,
    );
  }
}
