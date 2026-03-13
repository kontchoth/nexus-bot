import '../../models/crypto_models.dart';

class CryptoOpportunitySignalEngine {
  const CryptoOpportunitySignalEngine();

  CryptoOpportunity score(CryptoOpportunity opportunity) {
    return opportunity.copyWith(score: analyze(opportunity));
  }

  CryptoOpportunityScore analyze(CryptoOpportunity opportunity) {
    final signals = <CryptoOpportunitySignal>[];
    var total = 0.0;

    void addSignal(
      CryptoOpportunitySignalKind kind,
      double delta,
      String label, {
      bool isRisk = false,
    }) {
      total += delta;
      signals.add(
        CryptoOpportunitySignal(
          kind: kind,
          label: label,
          scoreDelta: delta,
          isRisk: isRisk,
        ),
      );
    }

    final priceChange24h = opportunity.priceChange24h;
    final volumeChange24h = opportunity.volumeChange24h ?? 0;
    final marketCap = opportunity.marketCap ?? 0;
    final liquidity = opportunity.liquidityUsd ?? 0;
    final ratio = opportunity.volumeMarketCapRatio;

    if (ratio > 0.3) {
      addSignal(
        CryptoOpportunitySignalKind.volumeMarketCap,
        25,
        'High volume / market cap ratio: ${(ratio * 100).toStringAsFixed(1)}%',
      );
    }

    if (priceChange24h > 10) {
      addSignal(
        CryptoOpportunitySignalKind.momentum24h,
        20,
        'Strong momentum: +${priceChange24h.toStringAsFixed(1)}%',
      );
    }

    if (volumeChange24h > 100) {
      addSignal(
        CryptoOpportunitySignalKind.volumeSpike24h,
        25,
        'Volume spike: +${volumeChange24h.toStringAsFixed(0)}%',
      );
    }

    if (marketCap > 0 && marketCap < 50000000) {
      addSignal(
        CryptoOpportunitySignalKind.lowCap,
        15,
        'Low cap setup: \$${(marketCap / 1000000).toStringAsFixed(1)}M',
      );
    }

    if (priceChange24h < -5 && volumeChange24h > 50) {
      addSignal(
        CryptoOpportunitySignalKind.accumulation,
        15,
        'Possible accumulation: price down, volume up',
      );
    }

    if (opportunity.isDex &&
        (opportunity.pairAgeHours ?? 9999) <= 72 &&
        liquidity >= 50000) {
      addSignal(
        CryptoOpportunitySignalKind.freshDexLiquidity,
        10,
        'Fresh DEX liquidity with usable size',
      );
    }

    if (opportunity.binanceListed &&
        opportunity.macdTrend == MACDTrend.bullish &&
        (opportunity.rsi ?? 0) >= 45 &&
        (opportunity.rsi ?? 0) <= 62) {
      addSignal(
        CryptoOpportunitySignalKind.binanceConfirmation,
        10,
        'Binance technical confirmation is bullish',
      );
    }

    if (liquidity > 0 && liquidity < 25000) {
      addSignal(
        CryptoOpportunitySignalKind.lowLiquidityRisk,
        -20,
        'Low liquidity risk: \$${(liquidity / 1000).toStringAsFixed(1)}K',
        isRisk: true,
      );
    }

    if (marketCap <= 0) {
      addSignal(
        CryptoOpportunitySignalKind.missingMarketCapRisk,
        -8,
        'Missing market cap reduces confidence',
        isRisk: true,
      );
    }

    if (!opportunity.binanceListed &&
        (marketCap <= 0 || marketCap < 100000000) &&
        liquidity < 100000) {
      addSignal(
        CryptoOpportunitySignalKind.noCexConfirmationRisk,
        -10,
        'No CEX confirmation on a thin setup',
        isRisk: true,
      );
    }

    final clampedScore = total.clamp(0, 100).toDouble();
    return CryptoOpportunityScore(
      value: clampedScore,
      grade: _gradeFor(clampedScore),
      signals: List<CryptoOpportunitySignal>.unmodifiable(signals),
    );
  }

  CryptoOpportunityGrade _gradeFor(double score) {
    if (score >= 70) return CryptoOpportunityGrade.elite;
    if (score >= 50) return CryptoOpportunityGrade.strong;
    if (score >= 30) return CryptoOpportunityGrade.watch;
    return CryptoOpportunityGrade.weak;
  }
}
