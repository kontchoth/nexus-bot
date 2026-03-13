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
import 'blocs/spx/spx_bloc.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/spx/spx_chain_screen.dart';
import 'screens/spx/spx_positions_screen.dart';
import 'screens/spx/spx_dashboard_screen.dart';
import 'screens/spx/spx_activity_screen.dart';
import 'screens/spx/spx_signal_sheet_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_repository.dart';
import 'services/app_settings_repository.dart';
import 'services/local_notification_service.dart';
import 'services/remote_push_service.dart';
import 'services/firebase_auth_repository.dart';
import 'services/spx/spx_opportunity_journal_repository.dart';
import 'services/spx/spx_trade_journal_repository.dart';
import 'services/spx/spx_tradier_secure_storage.dart';
import 'theme/app_theme.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthRepository authRepository = InMemoryAuthRepository();
  AppSettingsRepository settingsRepository = LocalAppSettingsRepository();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    final googleEnabled = defaultTargetPlatform != TargetPlatform.iOS ||
        ((options.iosClientId ?? '').isNotEmpty);
    authRepository = FirebaseAuthRepository(googleSignInEnabled: googleEnabled);
    settingsRepository = FirebaseAppSettingsRepository();
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
  ));
}

class NexusBotApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AppSettingsRepository settingsRepository;
  const NexusBotApp({
    super.key,
    required this.authRepository,
    required this.settingsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(create: (_) => authRepository),
        RepositoryProvider<AppSettingsRepository>(
            create: (_) => settingsRepository),
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
  late final SpxBloc _spxBloc;
  late final SpxTradeJournalRepository _spxJournalRepository;
  late final SpxOpportunityJournalRepository _spxOpportunityRepository;

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    try {
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
    _spxBloc.close();
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
      child: BlocProvider<SpxBloc>.value(
        value: _spxBloc,
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
  StreamSubscription<TradeAlert>? _spxAlertSub;
  StreamSubscription<String>? _notificationTapSub;
  StreamSubscription<String>? _remoteOpenedPayloadSub;
  StreamSubscription<RemotePushMessage>? _remoteForegroundSub;

  int _activeTab = 0;
  int _activityResetToken = 0;
  String? _spxOpportunityFocusId;
  bool _isAppForeground = true;

  List<Widget> get _screens => [
        const SpxChainScreen(),
        const SpxPositionsScreen(),
        const SpxDashboardScreen(),
        const SpxSignalSheetScreen(),
        SpxActivityScreen(
          key: ValueKey<int>(_activityResetToken),
          focusOpportunityId: _spxOpportunityFocusId,
          focusRequestKey: _activityResetToken,
        ),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spxAlertSub =
        context.read<SpxBloc>().alertsStream.listen(_onAlert);
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

  void _onAlert(TradeAlert alert) {
    if (!mounted) return;
    final canDeepLink = _isOpportunityDeepLinkAlert(alert);
    final canNotifyDevice = _isOpportunityAlert(alert);
    if (canNotifyDevice && !_isAppForeground) {
      unawaited(
        LocalNotificationService.instance.showSpxOpportunityNotification(
          title: alert.title,
          body: alert.message,
          payload: alert.payload ?? TradeAlertPayloads.spxOpportunities,
        ),
      );
    }
    HapticFeedback.selectionClick();
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
    return alert.title.toLowerCase().startsWith('spx opportunity found');
  }

  bool _isOpportunityAlert(TradeAlert alert) {
    if (alert.payload != null &&
        (alert.payload == TradeAlertPayloads.spxOpportunities ||
            TradeAlertPayloads.isSpxOpportunity(alert.payload!))) {
      return true;
    }
    return alert.title.toLowerCase().startsWith('spx opportunity');
  }

  void _onRemoteForegroundMessage(RemotePushMessage message) {
    _onAlert(TradeAlert(
      title: message.title,
      message: message.body,
      type: TradeLogType.info,
      payload: message.payload,
    ));
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
      _activeTab = 4; // Activity tab
      _spxOpportunityFocusId = focusId;
      _activityResetToken++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spxAlertSub?.cancel();
    _notificationTapSub?.cancel();
    _remoteOpenedPayloadSub?.cancel();
    _remoteForegroundSub?.cancel();
    super.dispose();
  }

  bool _needsToken(BuildContext context) {
    final token = context.watch<SpxBloc>().state.tradierToken ?? '';
    return token.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final missingToken = _needsToken(context);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(56 + MediaQuery.paddingOf(context).top),
        child: const _NexusAppBar(),
      ),
      body: Column(
        children: [
          if (missingToken)
            GestureDetector(
              onTap: () => setState(() => _activeTab = 5),
              child: Container(
                width: double.infinity,
                color: Colors.orange.withValues(alpha: 0.15),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tradier API token not configured — tap to go to Settings',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 14, color: Colors.orange),
                  ],
                ),
              ),
            ),
          Expanded(
              child: IndexedStack(index: _activeTab, children: _screens)),
        ],
      ),
      bottomNavigationBar: _NexusNavBar(
        activeIndex: _activeTab,
        onTabChanged: (i) => setState(() => _activeTab = i),
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _NexusAppBar extends StatelessWidget {
  const _NexusAppBar();

  @override
  Widget build(BuildContext context) {
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
              const Spacer(),
              _SpxControls(isNarrow: isNarrow),
            ],
          ),
        ),
      ),
    );
  }
}

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
                            color: isActive
                                ? AppTheme.green
                                : AppTheme.textMuted),
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
  final ValueChanged<int> onTabChanged;
  const _NexusNavBar({
    required this.activeIndex,
    required this.onTabChanged,
  });

  static const _items = [
    (Icons.show_chart_rounded, 'Chain'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.assignment_outlined, 'Sheet'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: _items.asMap().entries.map((entry) {
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
                          color:
                              isActive ? AppTheme.blue : AppTheme.textMuted),
                      const SizedBox(height: 2),
                      Text(label,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color: isActive
                                  ? AppTheme.blue
                                  : AppTheme.textMuted,
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
