import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusbot/blocs/crypto/crypto_bloc.dart';
import 'package:nexusbot/models/crypto_models.dart';
import 'package:nexusbot/services/crypto/crypto_opportunity_service.dart';

void main() {
  group('CryptoBloc opportunities', () {
    blocTest<CryptoBloc, CryptoState>(
      'loads opportunities and selects the top-ranked item',
      build: () => CryptoBloc(
        opportunityService: _FakeCryptoOpportunityService(
          opportunities: [
            _scoredOpportunity(id: 'alpha', symbol: 'ALPHA', score: 82),
            _scoredOpportunity(id: 'beta', symbol: 'BETA', score: 55),
          ],
        ),
      ),
      act: (bloc) => bloc.add(LoadCryptoOpportunities()),
      expect: () => [
        isA<CryptoState>().having(
          (state) => state.opportunitiesLoading,
          'opportunitiesLoading',
          isTrue,
        ),
        isA<CryptoState>()
            .having((state) => state.opportunitiesLoading, 'loading', isFalse)
            .having((state) => state.opportunities.length, 'count', 2)
            .having(
              (state) => state.selectedOpportunityId,
              'selectedOpportunityId',
              'alpha',
            ),
      ],
    );

    blocTest<CryptoBloc, CryptoState>(
      'switches into opportunities mode on demand',
      build: () => CryptoBloc(
        opportunityService: _FakeCryptoOpportunityService(
          opportunities: const [],
        ),
      ),
      act: (bloc) => bloc.add(
        const ChangeCryptoScannerView(CryptoScannerViewMode.opportunities),
      ),
      expect: () => [
        isA<CryptoState>().having(
          (state) => state.scannerViewMode,
          'scannerViewMode',
          CryptoScannerViewMode.opportunities,
        ),
        isA<CryptoState>()
            .having(
              (state) => state.scannerViewMode,
              'scannerViewMode',
              CryptoScannerViewMode.opportunities,
            )
            .having(
              (state) => state.opportunitiesLoading,
              'opportunitiesLoading',
              isTrue,
            ),
        isA<CryptoState>()
            .having(
              (state) => state.scannerViewMode,
              'scannerViewMode',
              CryptoScannerViewMode.opportunities,
            )
            .having(
              (state) => state.opportunitiesLoading,
              'opportunitiesLoading',
              isFalse,
            ),
      ],
    );
  });
}

class _FakeCryptoOpportunityService extends CryptoOpportunityService {
  _FakeCryptoOpportunityService({
    required this.opportunities,
  });

  final List<CryptoOpportunity> opportunities;

  @override
  Future<List<CryptoOpportunity>> loadOpportunities({
    bool forceRefresh = false,
    Iterable<CoinData> scannerCoins = const <CoinData>[],
    bool useScannerConfirmation = false,
  }) async {
    return List<CryptoOpportunity>.unmodifiable(opportunities);
  }
}

CryptoOpportunity _scoredOpportunity({
  required String id,
  required String symbol,
  required double score,
}) {
  final grade = score >= 70
      ? CryptoOpportunityGrade.elite
      : score >= 50
          ? CryptoOpportunityGrade.strong
          : score >= 30
              ? CryptoOpportunityGrade.watch
              : CryptoOpportunityGrade.weak;

  return CryptoOpportunity(
    id: id,
    symbol: symbol,
    name: symbol,
    priceUsd: 1.5,
    priceChange24h: 8,
    marketCap: 50000000,
    volume24h: 15000000,
    sources: const [CryptoOpportunitySource.coinGecko],
    lastUpdated: DateTime(2026, 3, 12, 10),
    score: CryptoOpportunityScore(
      value: score,
      grade: grade,
      signals: const [
        CryptoOpportunitySignal(
          kind: CryptoOpportunitySignalKind.momentum24h,
          label: 'Momentum',
          scoreDelta: 20,
        ),
      ],
    ),
  );
}
