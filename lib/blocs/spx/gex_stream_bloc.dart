import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/gex_stream_models.dart';
import '../../models/spx_models.dart';
import '../../services/app_settings_repository.dart';
import '../../services/spx/gex_stream_service.dart';
import '../../services/spx/spx_options_service.dart';

// ── Events ────────────────────────────────────────────────────────────────────

abstract class GexStreamEvent extends Equatable {
  const GexStreamEvent();
  @override
  List<Object?> get props => [];
}

class GexStreamStarted extends GexStreamEvent {
  const GexStreamStarted();
}

class GexStreamStopped extends GexStreamEvent {
  const GexStreamStopped();
}

class _GexStreamTicked extends GexStreamEvent {
  final GexStreamUpdate update;
  const _GexStreamTicked(this.update);
  @override
  List<Object?> get props => [update];
}

// ── State ─────────────────────────────────────────────────────────────────────

class GexStreamState extends Equatable {
  final List<GexStreamPoint> points;
  final GexLevels levels;
  final SpxQuoteData quote;
  final bool isRunning;
  final DateTime? lastUpdated;
  final List<GexStrikeBar> strikeBars;

  const GexStreamState({
    this.points = const [],
    this.levels = GexLevels.empty,
    this.quote = SpxQuoteData.empty,
    this.isRunning = false,
    this.lastUpdated,
    this.strikeBars = const [],
  });

  GexStreamState copyWith({
    List<GexStreamPoint>? points,
    GexLevels? levels,
    SpxQuoteData? quote,
    bool? isRunning,
    DateTime? lastUpdated,
    List<GexStrikeBar>? strikeBars,
  }) {
    return GexStreamState(
      points: points ?? this.points,
      levels: levels ?? this.levels,
      quote: quote ?? this.quote,
      isRunning: isRunning ?? this.isRunning,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      strikeBars: strikeBars ?? this.strikeBars,
    );
  }

  @override
  List<Object?> get props => [points, levels, quote, isRunning, lastUpdated, strikeBars];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class GexStreamBloc extends Bloc<GexStreamEvent, GexStreamState> {
  late final GexStreamService _service;
  StreamSubscription<GexStreamUpdate>? _sub;

  GexStreamBloc({
    required String? tradierToken,
    required String tradierEnvironment,
  })  : super(const GexStreamState()) {
    _service = GexStreamService(
      optionsService: SpxOptionsService(
        apiToken: tradierToken,
        useSandbox: SpxTradierEnvironment.isSandbox(tradierEnvironment),
        enforceMarketHours: false,
      ),
    );
    on<GexStreamStarted>(_onStarted);
    on<GexStreamStopped>(_onStopped);
    on<_GexStreamTicked>(_onTicked);
  }

  void _onStarted(GexStreamStarted _, Emitter<GexStreamState> emit) {
    if (state.isRunning) return;
    _sub = _service.stream.listen(
      (update) => add(_GexStreamTicked(update)),
      onError: (_) {},
    );
    _service.start();
    emit(state.copyWith(isRunning: true));
  }

  void _onStopped(GexStreamStopped _, Emitter<GexStreamState> emit) {
    _sub?.cancel();
    _sub = null;
    _service.stop();
    emit(state.copyWith(isRunning: false));
  }

  void _onTicked(_GexStreamTicked event, Emitter<GexStreamState> emit) {
    emit(state.copyWith(
      points: event.update.points,
      levels: event.update.levels,
      quote: event.update.quote,
      strikeBars: event.update.strikeBars,
      lastUpdated: DateTime.now(),
    ));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _service.dispose();
    return super.close();
  }
}
