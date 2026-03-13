# Crypto Opportunity Engine Plan

## Goal

Add a second crypto discovery layer that scores coins and pairs from broader market + on-chain sources, then surfaces ranked opportunities inside the existing crypto module.

This should complement the current live market scanner, not replace it.

## Current Repo Baseline

The repo already has:

- `CryptoBloc` managing coins, positions, logs, alerts, and provider selection in `lib/blocs/crypto/crypto_bloc.dart`
- `CoinData` and `TechnicalIndicators` models for the current Binance/Robinhood scanner in `lib/models/crypto_models.dart`
- a `ScannerScreen` and signal-driven crypto dashboard in `lib/screens/crypto/scanner_screen.dart` and `lib/screens/crypto/dashboard_screen.dart`
- live Binance candles/tickers in `lib/services/crypto/live_market_service.dart`
- Robinhood market data in `lib/services/crypto/robinhood_market_service.dart`
- alert plumbing already exposed through `TradeAlert` and `LocalNotificationService`

The current scanner is a technical-signal engine over a fixed coin universe. The new feature should add a broader opportunity engine with its own models, provider aggregation, and score explanations.

## Product Direction

Build this as an `Opportunities` mode inside the existing Crypto `Scanner` tab.

Why:

- the current shell already has 5 crypto destinations; adding a 6th tab is unnecessary friction
- the opportunity list is conceptually part of scanning/discovery
- it lets users switch between:
  - `Market Scanner`: current Binance/Robinhood signal feed
  - `Opportunities`: ranked CoinGecko/DEXScreener style opportunities

## Data Source Plan

### Phase 1 sources

Start with:

- `CoinGecko`
  - price
  - market cap
  - 24h change
  - total volume
  - trending / market list candidates
- `DEXScreener`
  - pair liquidity
  - 24h volume
  - pair age / new listings
  - price and volume acceleration

Keep existing:

- `Binance`
  - OHLCV for RSI / MACD / momentum confirmation on symbols that are listed there

### Phase 2 optional sources

- `Moralis`
  - wallet activity
  - smart-money accumulation
  - token holder / transfer signals
- `CoinMarketCap`
  - trending / gainers / losers
  - only if free-tier limits and key management justify it

## Architecture Plan

### 1. Add a separate opportunity domain

Do not overload `CoinData`.

Add dedicated models such as:

- `CryptoOpportunity`
- `CryptoOpportunityScore`
- `CryptoOpportunitySignal`
- `CryptoOpportunitySourceSnapshot`
- `CryptoOpportunityVenue`

Suggested fields:

- identity: `id`, `symbol`, `name`, `chain`, `logoUrl`
- pricing: `priceUsd`, `priceChange24h`
- liquidity: `marketCap`, `volume24h`, `liquidityUsd`, `volumeMarketCapRatio`
- source metadata: `isDex`, `dexId`, `pairAddress`, `listedAt`, `sourceNames`
- confirmation: `binanceListed`, `rsi`, `macdTrend`
- scoring: `score`, `grade`, `signals`, `riskFlags`
- freshness: `lastUpdated`

### 2. Add source clients under `lib/services/crypto/`

New services:

- `coingecko_market_service.dart`
- `dex_screener_service.dart`
- `crypto_opportunity_service.dart`

Responsibilities:

- each source client fetches and normalizes raw API responses
- the aggregator service merges candidates by symbol / contract / pair
- the aggregator returns scored `CryptoOpportunity` objects

Use `Dio`, not `http`, to stay consistent with current crypto services.

### 3. Add a dedicated scoring engine

Create:

- `crypto_opportunity_signal_engine.dart`

This should convert merged source data into:

- numeric score
- human-readable reasons
- risk flags

Base scoring in phase 1:

- high `volume / market cap` ratio
- strong 24h momentum
- strong volume acceleration
- low / mid cap upside bucket
- accumulation pattern: price down but volume up
- DEX new-pair / fresh-liquidity bonus
- Binance technical confirmation bonus when RSI / MACD agree

Base penalties:

- very low liquidity
- extreme spread / unreliable pair
- missing market cap
- suspiciously new pair with weak liquidity
- no centralized exchange confirmation for thin names

## State Management Plan

Use the existing `CryptoBloc`, not a new Cubit.

Add state fields in `CryptoState`:

- `List<CryptoOpportunity> opportunities`
- `bool opportunitiesLoading`
- `String? opportunitiesError`
- `DateTime? opportunitiesUpdatedAt`
- `String opportunitySortMode`
- `String opportunityFilterMode`
- `String? selectedOpportunityId`
- `List<String> watchedOpportunityIds`

Add events in `crypto_event.dart`:

- `LoadCryptoOpportunities`
- `RefreshCryptoOpportunities`
- `SelectCryptoOpportunity`
- `UpdateOpportunitySort`
- `UpdateOpportunityFilter`
- `ToggleOpportunityWatchlist`

Behavior:

- `InitializeMarket` should continue booting the normal crypto scanner
- opportunity loading should run in parallel but independently
- failures in CoinGecko / DEXScreener must not break the core scanner

## UI Plan

### Scanner tab structure

Inside `lib/screens/crypto/scanner_screen.dart`:

- add a top segmented control:
  - `Scanner`
  - `Opportunities`

### Opportunities mode

Add:

- ranked list of scored opportunities
- score badge
- source badges: `CoinGecko`, `DEX`, `Binance`, `Moralis`
- flat signal bullets instead of long paragraphs
- risk chips like:
  - `Low Liquidity`
  - `New Pair`
  - `No CEX Confirm`

Card content should show:

- symbol / name
- score
- price and 24h move
- market cap
- volume
- liquidity
- top 3-5 reasons

### Opportunity detail panel

When selected, show:

- sparkline / recent move
- signal explanation
- supporting metrics
- venue/source summary
- `Add to Watchlist`
- `Open in Scanner` if symbol exists in the main `CoinData` feed

### Dashboard integration

Add a small `Top Opportunities` card to `lib/screens/crypto/dashboard_screen.dart` showing:

- top 3 names
- score
- 1-line rationale

## Refresh and Caching Plan

### Refresh cadence

- manual refresh from UI
- auto-refresh every 5 minutes for opportunities
- keep existing fast tick cadence for the core scanner

### Caching

Add short-lived in-memory caching inside the opportunity service:

- CoinGecko: 3-5 minutes
- DEXScreener: 1-3 minutes
- Binance confirmation candles: aligned to selected timeframe

Reason:

- avoid rate-limit churn
- keep scanner responsive
- prevent the opportunity view from spamming public endpoints

## Settings Plan

Extend `lib/screens/settings_screen.dart` and app preferences with:

- enabled opportunity sources
  - CoinGecko
  - DEXScreener
  - Binance confirm
  - Moralis optional
- refresh interval
- minimum score threshold
- minimum liquidity
- watchlist alerts enabled

Secrets:

- CoinGecko free mode: no key initially
- DEXScreener: no key initially
- Moralis / CoinMarketCap: secure storage keys only when phase 2 starts

## Alerting Plan

Reuse the existing crypto alert stream and local notifications.

Add opportunity alerts for:

- score crossing threshold
- watched coin improving sharply
- new DEX pair exceeding liquidity + score minimum

Guardrails:

- only alert once per symbol / pair inside a cooldown window
- suppress repeats unless score meaningfully increases

## Suggested Implementation Order

### Slice 1: Opportunity domain + engine skeleton

- add opportunity models
- add `CryptoOpportunitySignalEngine`
- add mocked / fixture-based tests for scoring

### Slice 2: CoinGecko integration

- add CoinGecko client
- fetch top market candidates
- score and surface them in state

### Slice 3: Opportunities UI inside Scanner tab

- segmented switch
- opportunity cards
- loading / empty / error states

### Slice 4: DEXScreener merge

- enrich candidates with DEX liquidity and new-pair info
- add risk chips and source badges

### Slice 5: Binance confirmation

- enrich scored opportunities with RSI / MACD confirmation
- add confirmation bonus / penalty

### Slice 6: Alerts + watchlist

- threshold notifications
- watchlist persistence

### Slice 7: Optional source expansion

- Moralis
- CoinMarketCap

## Testing Plan

Add tests for:

- source response normalization
- scoring weights and penalties
- merge behavior when CoinGecko and DEXScreener disagree or partially overlap
- bloc loading / refresh / error states
- alert cooldown behavior
- widget rendering for opportunity cards and empty states

Start with pure tests for:

- `crypto_opportunity_signal_engine_test.dart`
- `crypto_opportunity_service_test.dart`

## Acceptance Criteria

Phase 1 is done when:

- the crypto scanner tab has a working `Opportunities` mode
- CoinGecko candidates load reliably
- DEXScreener enrichment appears on supported names
- each result has a clear score and human-readable reasons
- refresh works without affecting the existing scanner
- users can identify at least top 10 ranked opportunities
- alerts can be enabled for high-score opportunities

## Important Design Constraint

Do not collapse the existing technical scanner into this engine.

Keep two layers:

- `Scanner`: technical signal feed on the tracked live universe
- `Opportunities`: broader market discovery and ranking engine

That separation keeps the current trading flow stable while adding the wider discovery system the user described.
