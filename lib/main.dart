import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexusbot/firebase_options.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import 'blocs/auth_bloc.dart';
import 'blocs/crypto/crypto_bloc.dart';
import 'blocs/spx/spx_bloc.dart';
import 'blocs/subscription/subscription_cubit.dart';
import 'screens/subscription/paywall_screen.dart';
import 'widgets/subscription/paywall_gate.dart';
import 'widgets/subscription/trial_banner.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/crypto/scanner_screen.dart';
import 'screens/crypto/positions_screen.dart';
import 'screens/crypto/dashboard_screen.dart';
import 'screens/spx/spx_chain_screen.dart';
import 'screens/spx/spx_positions_screen.dart';
import 'screens/spx/spx_dashboard_screen.dart';
import 'screens/spx/spx_activity_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_repository.dart';
import 'services/app_settings_repository.dart';
import 'services/local_notification_service.dart';
import 'services/remote_push_service.dart';
import 'services/wallet_repository.dart';
import 'services/firebase_auth_repository.dart';
import 'services/spx/spx_opportunity_journal_repository.dart';
import 'services/spx/spx_trade_journal_repository.dart';
import 'services/spx/spx_tradier_secure_storage.dart';
import 'theme/app_theme.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _robinhoodTokenKey = 'robinhood_crypto_token';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthRepository authRepository = InMemoryAuthRepository();
  AppSettingsRepository settingsRepository = LocalAppSettingsRepository();
  WalletRepository walletRepository = LocalWalletRepository();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    final googleEnabled = defaultTargetPlatform != TargetPlatform.iOS ||
        ((options.iosClientId ?? '').isNotEmpty);
    authRepository = FirebaseAuthRepository(googleSignInEnabled: googleEnabled);
    settingsRepository = FirebaseAppSettingsRepository();
    walletRepository = FirebaseWalletRepository();
  } catch (_) {
    // Firebase not configured — keep local in-memory auth for development.
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  try {
    await LocalNotificationService.instance.initialize();
  } catch (_) {
    // Notifications are optional; keep app functional if init fails.
  }
  runApp(NexusBotApp(
    authRepository: authRepository,
    settingsRepository: settingsRepository,
    walletRepository: walletRepository,
  ));
}

class NexusBotApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AppSettingsRepository settingsRepository;
  final WalletRepository walletRepository;
  const NexusBotApp({
    super.key,
    required this.authRepository,
    required this.settingsRepository,
    required this.walletRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(create: (_) => authRepository),
        RepositoryProvider<AppSettingsRepository>(
            create: (_) => settingsRepository),
        RepositoryProvider<WalletRepository>(create: (_) => walletRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepository>(),
            )..add(const AuthStarted()),
          ),
        ],
        child: MaterialApp(
          title: 'NexusBot',
          theme: AppTheme.theme,
          debugShowCheckedModeBanner: false,
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state.status == AuthStatus.loading ||
            state.status == AuthStatus.initial) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (state.status == AuthStatus.authenticated) {
          return _AuthenticatedShell(user: state.user!);
        }
        return const AuthScreen();
      },
    );
  }
}

class _AuthenticatedShell extends StatefulWidget {
  final AuthUser user;
  const _AuthenticatedShell({required this.user});

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell> {
  late final CryptoBloc _cryptoBloc;
  late final SpxBloc _spxBloc;
  late final SubscriptionCubit _subscriptionCubit;
  late final SpxTradeJournalRepository _spxJournalRepository;
  late final SpxOpportunityJournalRepository _spxOpportunityRepository;

  @override
  void initState() {
    super.initState();
    _cryptoBloc = CryptoBloc()..add(InitializeMarket());
    _subscriptionCubit = SubscriptionCubit()
      ..initialize(widget.user.id);
    _spxJournalRepository = Firebase.apps.isNotEmpty
        ? FirebaseSpxTradeJournalRepository()
        : LocalSpxTradeJournalRepository();
    _spxOpportunityRepository = Firebase.apps.isNotEmpty
        ? FirebaseSpxOpportunityJournalRepository()
        : LocalSpxOpportunityJournalRepository();
    if (kDebugMode) {
      debugPrint(
        '[SPX-JOURNAL] Repository: ${_spxJournalRepository.runtimeType}',
      );
      debugPrint(
        '[SPX-OPPORTUNITY] Repository: ${_spxOpportunityRepository.runtimeType}',
      );
    }
    _spxBloc = SpxBloc(
      userId: widget.user.id,
      journalRepository: _spxJournalRepository,
      opportunityJournalRepository: _spxOpportunityRepository,
    );
    _bootstrapTradingState();
  }

  Future<void> _bootstrapTradingState() async {
    var didQueueSpxInit = false;
    final settings =
        await context.read<AppSettingsRepository>().load(widget.user.id);
    final tradierEnvironment = SpxTradierEnvironment.normalize(
      settings.spxTradierEnvironment,
    );
    final tradierToken = await readTradierTokenForEnvironment(
      _secureStorage,
      environment: tradierEnvironment,
    );
    final robinhoodToken =
        (await _secureStorage.read(key: _robinhoodTokenKey) ?? '').trim();
    if (!mounted) return;
    try {
      _cryptoBloc.add(UpdateAlertPreferences(
        alertsEnabled: settings.alertsEnabled,
        hapticsEnabled: settings.hapticsEnabled,
      ));
      _cryptoBloc.add(UpdateRobinhoodToken(robinhoodToken));
      final cryptoProvider = settings.cryptoDataProvider == 'robinhood'
          ? CryptoDataProvider.robinhood
          : CryptoDataProvider.binance;
      _cryptoBloc.add(UpdateCryptoDataProvider(cryptoProvider));
      final mode = settings.spxTermMode == 'range'
          ? SpxTermMode.range
          : SpxTermMode.exact;
      _spxBloc.add(UpdateSpxTermFilter(SpxTermFilter(
        mode: mode,
        exactDte: settings.spxExactDte,
        minDte: settings.spxMinDte,
        maxDte: settings.spxMaxDte,
      )));
      _spxBloc.add(
        UpdateSpxContractTargeting(settings.spxContractTargetingMode),
      );
      _spxBloc.add(UpdateSpxExecutionSettings(
        executionMode: settings.spxOpportunityExecutionMode,
        entryDelaySeconds: settings.spxEntryDelaySeconds,
        validationWindowSeconds: settings.spxValidationWindowSeconds,
        maxSlippagePct: settings.spxMaxSlippagePct,
        notificationsEnabled: settings.alertsEnabled,
      ));
      _spxBloc.add(UpdateTradierCredentials(
        token: tradierToken,
        environment: tradierEnvironment,
      ));
      didQueueSpxInit = true;
      unawaited(
        RemotePushService.instance.configure(
          userId: widget.user.id,
          alertsEnabled: settings.alertsEnabled,
        ),
      );
    } catch (_) {
      // BLoC may have closed before async completed.
    } finally {
      if (!didQueueSpxInit && mounted) {
        try {
          _spxBloc.add(const InitializeSpx());
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    unawaited(RemotePushService.instance.dispose());
    _cryptoBloc.close();
    _spxBloc.close();
    _subscriptionCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SpxTradeJournalRepository>.value(
          value: _spxJournalRepository,
        ),
        RepositoryProvider<SpxOpportunityJournalRepository>.value(
          value: _spxOpportunityRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CryptoBloc>.value(value: _cryptoBloc),
          BlocProvider<SpxBloc>.value(value: _spxBloc),
          BlocProvider<SubscriptionCubit>.value(value: _subscriptionCubit),
        ],
        child: const HomeShell(),
      ),
    );
  }
}

// ── Home Shell ────────────────────────────────────────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  StreamSubscription<TradeAlert>? _cryptoAlertSub;
  StreamSubscription<TradeAlert>? _spxAlertSub;
  StreamSubscription<String>? _notificationTapSub;
  StreamSubscription<String>? _remoteOpenedPayloadSub;
  StreamSubscription<RemotePushMessage>? _remoteForegroundSub;

  // 0 = Crypto, 1 = SPX
  int _activeModule = 0;
  int _cryptoTab = 0;
  int _spxTab = 0;
  int _spxActivityResetToken = 0;
  String? _spxOpportunityFocusId;
  bool _isAppForeground = true;
  static const double _tabletRailBreakpoint = 980;
  static const double _maxContentWidth = 1320;

  List<Widget> get _cryptoScreens => const [
        ScannerScreen(),
        PositionsScreen(),
        DashboardScreen(),
        LogScreen(),
        SettingsScreen(),
      ];

  List<Widget> get _spxScreens => [
        const SpxChainScreen(),
        const SpxPositionsScreen(),
        const SpxDashboardScreen(),
        SpxActivityScreen(
          key: ValueKey<int>(_spxActivityResetToken),
          focusOpportunityId: _spxOpportunityFocusId,
          focusRequestKey: _spxActivityResetToken,
        ),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cryptoAlertSub = context.read<CryptoBloc>().alertsStream.listen((alert) {
      _onAlert(alert, fromSpx: false);
    });
    _spxAlertSub = context.read<SpxBloc>().alertsStream.listen((alert) {
      _onAlert(alert, fromSpx: true);
    });
    _notificationTapSub = LocalNotificationService.instance.tapPayloadStream
        .listen(_handleNotificationPayload);
    _remoteOpenedPayloadSub = RemotePushService.instance.openedPayloadStream
        .listen(_handleNotificationPayload);
    _remoteForegroundSub = RemotePushService.instance.foregroundMessageStream
        .listen(_onRemoteForegroundMessage);
    final launchPayload = LocalNotificationService.instance.takeLaunchPayload();
    if (launchPayload != null) {
      _handleNotificationPayload(launchPayload);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppForeground = state == AppLifecycleState.resumed;
  }

  void _onAlert(TradeAlert alert, {required bool fromSpx}) {
    if (!mounted) return;
    final cryptoPrefs = context.read<CryptoBloc>().state;
    if (!cryptoPrefs.alertsEnabled) return;
    final canDeepLink = fromSpx && _isOpportunityDeepLinkAlert(alert);
    final canNotifyDevice = fromSpx && _isOpportunityAlert(alert);
    if (canNotifyDevice && !_isAppForeground) {
      unawaited(
        LocalNotificationService.instance.showSpxOpportunityNotification(
          title: alert.title,
          body: alert.message,
          payload: alert.payload ?? TradeAlertPayloads.spxOpportunities,
        ),
      );
    }
    final haptics = cryptoPrefs.hapticsEnabled;
    if (haptics) HapticFeedback.selectionClick();
    final color = switch (alert.type) {
      TradeLogType.buy => AppTheme.green,
      TradeLogType.win => AppTheme.green,
      TradeLogType.loss => AppTheme.red,
      TradeLogType.sell => AppTheme.red,
      _ => AppTheme.blue,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${alert.title}: ${alert.message}'),
      backgroundColor: color.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      action: canDeepLink
          ? SnackBarAction(
              label: 'Review',
              textColor: Colors.white,
              onPressed: () {
                if (!mounted) return;
                _openSpxOpportunitiesFromPayload(
                  alert.payload ?? TradeAlertPayloads.spxOpportunities,
                );
              },
            )
          : null,
    ));
  }

  bool _isOpportunityDeepLinkAlert(TradeAlert alert) {
    if (alert.payload != null &&
        (alert.payload == TradeAlertPayloads.spxOpportunities ||
            TradeAlertPayloads.isSpxOpportunity(alert.payload!))) {
      return true;
    }
    final title = alert.title.toLowerCase();
    return title.startsWith('spx opportunity found');
  }

  bool _isOpportunityAlert(TradeAlert alert) {
    if (alert.payload != null &&
        (alert.payload == TradeAlertPayloads.spxOpportunities ||
            TradeAlertPayloads.isSpxOpportunity(alert.payload!))) {
      return true;
    }
    final title = alert.title.toLowerCase();
    return title.startsWith('spx opportunity');
  }

  void _onRemoteForegroundMessage(RemotePushMessage message) {
    final payload = message.payload;
    final fromSpx = payload != null &&
        (payload == TradeAlertPayloads.spxOpportunities ||
            TradeAlertPayloads.isSpxOpportunity(payload));
    _onAlert(
      TradeAlert(
        title: message.title,
        message: message.body,
        type: TradeLogType.info,
        payload: payload,
      ),
      fromSpx: fromSpx,
    );
  }

  void _handleNotificationPayload(String payload) {
    if (!mounted) return;
    _openSpxOpportunitiesFromPayload(payload);
  }

  void _openSpxOpportunitiesFromPayload(String payload) {
    if (!mounted) return;
    final focusId = TradeAlertPayloads.spxOpportunityIdFrom(payload);
    final isListPayload = payload == TradeAlertPayloads.spxOpportunities;
    if (focusId == null && !isListPayload) return;
    setState(() {
      _activeModule = 1;
      _spxTab = 3; // Activity tab
      _spxOpportunityFocusId = focusId;
      _spxActivityResetToken++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cryptoAlertSub?.cancel();
    _spxAlertSub?.cancel();
    _notificationTapSub?.cancel();
    _remoteOpenedPayloadSub?.cancel();
    _remoteForegroundSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCrypto = _activeModule == 0;
    final activeTab = isCrypto ? _cryptoTab : _spxTab;
    final screens = isCrypto ? _cryptoScreens : _spxScreens;
    final useSideRail =
        MediaQuery.sizeOf(context).width >= _tabletRailBreakpoint;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56 + MediaQuery.paddingOf(context).top),
        child: _NexusAppBar(
          activeModule: _activeModule,
          onModuleChanged: (m) => setState(() {
            _activeModule = m;
          }),
        ),
      ),
      body: Row(
        children: [
          if (useSideRail)
            _NexusSideRail(
              activeIndex: activeTab,
              activeModule: _activeModule,
              onTabChanged: (i) => setState(() {
                if (isCrypto) {
                  _cryptoTab = i;
                } else {
                  _spxTab = i;
                }
              }),
            ),
          Expanded(
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final targetWidth =
                      useSideRail && constraints.maxWidth > _maxContentWidth
                          ? _maxContentWidth
                          : constraints.maxWidth;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: targetWidth,
                      height: constraints.maxHeight,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          useSideRail ? 18 : 0,
                          useSideRail ? 14 : 0,
                          useSideRail ? 18 : 0,
                          useSideRail ? 14 : 0,
                        ),
                        child: _SubscriptionAwareContent(
                          activeModule: _activeModule,
                          activeTab: activeTab,
                          screens: screens,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: useSideRail
          ? null
          : _NexusNavBar(
              activeIndex: activeTab,
              activeModule: _activeModule,
              onTabChanged: (i) => setState(() {
                if (isCrypto) {
                  _cryptoTab = i;
                } else {
                  _spxTab = i;
                }
              }),
            ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _NexusAppBar extends StatelessWidget {
  final int activeModule;
  final ValueChanged<int> onModuleChanged;
  const _NexusAppBar({
    required this.activeModule,
    required this.onModuleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCrypto = activeModule == 0;
    final isNarrow = MediaQuery.sizeOf(context).width < 390;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // ── Logo ────────────────────────────────────────────────────
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: 'NEXUS',
                    style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  TextSpan(
                    text: 'BOT',
                    style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              // ── Module switcher pill ─────────────────────────────────────
              _ModulePill(
                activeModule: activeModule,
                onChanged: onModuleChanged,
              ),
              const SizedBox(width: 8),
              // ── Module-specific controls ─────────────────────────────────
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: isCrypto
                        ? _CryptoControls(isNarrow: isNarrow)
                        : _SpxControls(isNarrow: isNarrow),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CRYPTO | SPX segmented toggle pill.
class _ModulePill extends StatelessWidget {
  final int activeModule;
  final ValueChanged<int> onChanged;
  const _ModulePill({required this.activeModule, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillSegment(
            label: 'CRYPTO',
            isActive: activeModule == 0,
            onTap: () => onChanged(0),
          ),
          _PillSegment(
            label: 'SPX',
            isActive: activeModule == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _PillSegment extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _PillSegment({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.blue.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isActive ? AppTheme.blue : AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Right-side controls shown when Crypto module is active.
class _CryptoControls extends StatelessWidget {
  final bool isNarrow;
  const _CryptoControls({required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoBloc, CryptoState>(
      buildWhen: (p, c) =>
          p.botStatus != c.botStatus || p.marketDataMode != c.marketDataMode,
      builder: (context, state) {
        final isActive = state.botStatus == BotStatus.active;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Data mode badge
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8, vertical: 3),
              decoration: BoxDecoration(
                color: state.marketDataMode == MarketDataMode.live
                    ? AppTheme.greenBg
                    : AppTheme.bg3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: state.marketDataMode == MarketDataMode.live
                      ? AppTheme.green.withValues(alpha: 0.45)
                      : AppTheme.border2,
                ),
              ),
              child: Text(
                state.marketDataMode == MarketDataMode.live
                    ? (isNarrow ? 'LIVE' : 'LIVE FEED')
                    : (isNarrow ? 'SIM' : 'SIMULATOR'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: state.marketDataMode == MarketDataMode.live
                        ? AppTheme.green
                        : AppTheme.textMuted,
                    letterSpacing: 0.5),
              ),
            ),
            SizedBox(width: isNarrow ? 6 : 8),
            // Bot toggle
            GestureDetector(
              onTap: () => context.read<CryptoBloc>().add(ToggleBot()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 8 : 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.greenBg : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.green.withValues(alpha: 0.5)
                        : AppTheme.border2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 14,
                      color: isActive ? AppTheme.green : AppTheme.textMuted,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'PAUSE' : 'START',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color:
                                isActive ? AppTheme.green : AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Right-side controls shown when SPX module is active.
class _SpxControls extends StatelessWidget {
  final bool isNarrow;
  const _SpxControls({required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      buildWhen: (p, c) =>
          p.scannerStatus != c.scannerStatus || p.dataMode != c.dataMode,
      builder: (context, state) {
        final isActive = state.scannerStatus == SpxScannerStatus.active;
        final isLive = state.dataMode == SpxDataMode.live;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Data mode badge
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLive ? AppTheme.greenBg : AppTheme.bg3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isLive
                      ? AppTheme.green.withValues(alpha: 0.45)
                      : AppTheme.border2,
                ),
              ),
              child: Text(
                isLive
                    ? (isNarrow ? 'LIVE' : 'TRADIER LIVE')
                    : (isNarrow ? 'SIM' : 'BS SIM'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isLive ? AppTheme.green : AppTheme.textMuted,
                    letterSpacing: 0.5),
              ),
            ),
            SizedBox(width: isNarrow ? 6 : 8),
            // Scanner toggle
            GestureDetector(
              onTap: () =>
                  context.read<SpxBloc>().add(const ToggleSpxScanner()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 8 : 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.greenBg : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.green.withValues(alpha: 0.5)
                        : AppTheme.border2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 14,
                      color: isActive ? AppTheme.green : AppTheme.textMuted,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'SCANNER ON' : 'SCANNER OFF',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color:
                                isActive ? AppTheme.green : AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Nav Bar ───────────────────────────────────────────────────────────────────

class _NexusNavBar extends StatelessWidget {
  final int activeIndex;
  final int activeModule;
  final ValueChanged<int> onTabChanged;
  const _NexusNavBar({
    required this.activeIndex,
    required this.activeModule,
    required this.onTabChanged,
  });

  static const _cryptoItems = [
    (Icons.radar_rounded, 'Scanner'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  static const _spxItems = [
    (Icons.show_chart_rounded, 'Chain'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = activeModule == 0 ? _cryptoItems : _spxItems;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final (icon, label) = entry.value;
              final isActive = i == activeIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTabChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 20,
                          color: isActive ? AppTheme.blue : AppTheme.textMuted),
                      const SizedBox(height: 2),
                      Text(label,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color:
                                  isActive ? AppTheme.blue : AppTheme.textMuted,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NexusSideRail extends StatelessWidget {
  final int activeIndex;
  final int activeModule;
  final ValueChanged<int> onTabChanged;

  const _NexusSideRail({
    required this.activeIndex,
    required this.activeModule,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items =
        activeModule == 0 ? _NexusNavBar._cryptoItems : _NexusNavBar._spxItems;
    return Container(
      width: 108,
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          child: Column(
            children: [
              Text(
                activeModule == 0 ? 'CRYPTO' : 'SPX',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in items.asMap().entries) ...[
                _RailNavItem(
                  icon: entry.value.$1,
                  label: entry.value.$2,
                  isActive: entry.key == activeIndex,
                  onTap: () => onTabChanged(entry.key),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subscription-Aware Content ────────────────────────────────────────────────

/// Renders the active module's screens with subscription gating.
/// - Settings tab (index 4) is always free.
/// - During trial: shows [TrialBanner] above the content.
/// - Without entitlement: shows [PaywallScreen] instead of the content.
class _SubscriptionAwareContent extends StatelessWidget {
  final int activeModule;
  final int activeTab;
  final List<Widget> screens;

  const _SubscriptionAwareContent({
    required this.activeModule,
    required this.activeTab,
    required this.screens,
  });

  static const _settingsTab = 4;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionCubit, SubscriptionState>(
      buildWhen: (p, c) =>
          p.isLoading != c.isLoading ||
          p.hasCryptoPro != c.hasCryptoPro ||
          p.hasSpxPro != c.hasSpxPro ||
          p.isTrialing != c.isTrialing,
      builder: (context, sub) {
        final plan = activeModule == 0
            ? SubscriptionPlan.cryptoPro
            : SubscriptionPlan.spxPro;

        final hasAccess = sub.isLoading ||
            activeTab == _settingsTab ||
            (plan == SubscriptionPlan.cryptoPro
                ? sub.hasCryptoPro || sub.isTrialing
                : sub.hasSpxPro || sub.isTrialing);

        final stack = IndexedStack(index: activeTab, children: screens);

        if (!hasAccess) {
          // Replace non-settings tabs with the paywall.
          return IndexedStack(
            index: activeTab == _settingsTab ? 1 : 0,
            children: [
              PaywallScreen(plan: plan),
              screens[_settingsTab],
            ],
          );
        }

        if (sub.isTrialing && activeTab != _settingsTab) {
          return TrialBanner(plan: plan, child: stack);
        }

        return stack;
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RailNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _RailNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color:
              isActive ? AppTheme.blue.withValues(alpha: 0.12) : AppTheme.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? AppTheme.blue.withValues(alpha: 0.45)
                : AppTheme.border2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 21,
              color: isActive ? AppTheme.blue : AppTheme.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: isActive ? AppTheme.blue : AppTheme.textMuted,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
