import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:nexusbot/firebase_options.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import 'blocs/auth_bloc.dart';
import 'blocs/trading_bloc.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/positions_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_repository.dart';
import 'services/app_settings_repository.dart';
import 'services/wallet_repository.dart';
import 'services/firebase_auth_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthRepository authRepository = InMemoryAuthRepository();
  AppSettingsRepository settingsRepository = LocalAppSettingsRepository();
  WalletRepository walletRepository = LocalWalletRepository();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(
      options: options,
    );
    final googleEnabled = defaultTargetPlatform != TargetPlatform.iOS ||
        ((options.iosClientId ?? '').isNotEmpty);
    authRepository = FirebaseAuthRepository(
      googleSignInEnabled: googleEnabled,
    );
    settingsRepository = FirebaseAppSettingsRepository();
    walletRepository = FirebaseWalletRepository();
  } catch (_) {
    // Firebase is not configured yet; keep local in-memory auth for development.
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
        RepositoryProvider<AuthRepository>(
          create: (_) => authRepository,
        ),
        RepositoryProvider<AppSettingsRepository>(
          create: (_) => settingsRepository,
        ),
        RepositoryProvider<WalletRepository>(
          create: (_) => walletRepository,
        ),
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
            body: Center(child: CircularProgressIndicator()),
          );
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
  late final TradingBloc _tradingBloc;

  @override
  void initState() {
    super.initState();
    _tradingBloc = TradingBloc()..add(InitializeMarket());
    _loadAlertPreferences();
  }

  Future<void> _loadAlertPreferences() async {
    final settings = await context.read<AppSettingsRepository>().load(
          widget.user.id,
        );
    if (!mounted) return;
    _tradingBloc.add(
      UpdateAlertPreferences(
        alertsEnabled: settings.alertsEnabled,
        hapticsEnabled: settings.hapticsEnabled,
      ),
    );
  }

  @override
  void dispose() {
    _tradingBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TradingBloc>.value(
      value: _tradingBloc,
      child: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  StreamSubscription<TradeAlert>? _alertSub;

  static const _screens = [
    ScannerScreen(),
    PositionsScreen(),
    DashboardScreen(),
    LogScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final bloc = context.read<TradingBloc>();
    _alertSub = bloc.alertsStream.listen((alert) {
      if (!mounted) return;
      if (bloc.state.hapticsEnabled) {
        HapticFeedback.selectionClick();
      }
      final color = switch (alert.type) {
        TradeLogType.buy => AppTheme.green,
        TradeLogType.win => AppTheme.green,
        TradeLogType.loss => AppTheme.red,
        TradeLogType.sell => AppTheme.red,
        _ => AppTheme.blue,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${alert.title}: ${alert.message}'),
          backgroundColor: color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingBloc, TradingState>(
      buildWhen: (prev, curr) =>
          prev.activeTab != curr.activeTab ||
          prev.botStatus != curr.botStatus ||
          prev.marketDataMode != curr.marketDataMode ||
          prev.selectedExchange != curr.selectedExchange ||
          prev.selectedTimeframe != curr.selectedTimeframe,
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(
              56 + MediaQuery.paddingOf(context).top,
            ),
            child: _NexusAppBar(state: state),
          ),
          body: IndexedStack(
            index: state.activeTab,
            children: _screens,
          ),
          bottomNavigationBar: _NexusNavBar(activeIndex: state.activeTab),
        );
      },
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _NexusAppBar extends StatelessWidget {
  final TradingState state;
  const _NexusAppBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final isActive = state.botStatus == BotStatus.active;
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
              // Logo
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'NEXUS',
                      style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text: 'BOT',
                      style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isNarrow ? 6 : 8),
              // Status dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? AppTheme.green : AppTheme.red,
                  boxShadow: [
                    BoxShadow(
                      color: (isActive ? AppTheme.green : AppTheme.red)
                          .withOpacity(0.5),
                      blurRadius: 6,
                    )
                  ],
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 4),
                Text(
                  isActive ? 'LIVE' : 'PAUSED',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppTheme.green : AppTheme.red,
                    letterSpacing: 1,
                  ),
                ),
              ],
              SizedBox(width: isNarrow ? 6 : 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: state.marketDataMode == MarketDataMode.live
                      ? AppTheme.greenBg
                      : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: state.marketDataMode == MarketDataMode.live
                        ? AppTheme.green.withOpacity(0.45)
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
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(width: isNarrow ? 6 : 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Exchange selector
                        _CompactDropdown<Exchange>(
                          value: state.selectedExchange,
                          items: Exchange.values,
                          labelOf: (e) => e == Exchange.all ? 'All' : e.label,
                          onChanged: (e) => context
                              .read<TradingBloc>()
                              .add(ChangeExchange(e!)),
                        ),
                        SizedBox(width: isNarrow ? 6 : 8),
                        // Timeframe selector
                        _CompactDropdown<Timeframe>(
                          value: state.selectedTimeframe,
                          items: Timeframe.values,
                          labelOf: (t) => t.label,
                          onChanged: (t) => context
                              .read<TradingBloc>()
                              .add(ChangeTimeframe(t!)),
                        ),
                        SizedBox(width: isNarrow ? 6 : 8),
                        // Bot toggle
                        GestureDetector(
                          onTap: () =>
                              context.read<TradingBloc>().add(ToggleBot()),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 8 : 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.greenBg : AppTheme.bg3,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isActive
                                    ? AppTheme.green.withOpacity(0.5)
                                    : AppTheme.border2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 14,
                                  color: isActive
                                      ? AppTheme.green
                                      : AppTheme.textMuted,
                                ),
                                if (!isNarrow) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    isActive ? 'PAUSE' : 'START',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isActive
                                          ? AppTheme.green
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: isNarrow ? 6 : 8),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BlocProvider.value(
                                value: context.read<TradingBloc>(),
                                child: const SettingsScreen(),
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.bg3,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.border2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.settings_outlined,
                                  size: 14,
                                  color: AppTheme.textMuted,
                                ),
                                if (!isNarrow) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    'SETTINGS',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _CompactDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border2),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(
                    labelOf(e),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, color: AppTheme.textPrimary),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        dropdownColor: AppTheme.bg3,
        icon: const Icon(Icons.arrow_drop_down,
            size: 14, color: AppTheme.textMuted),
        style:
            GoogleFonts.spaceGrotesk(fontSize: 10, color: AppTheme.textPrimary),
        isDense: true,
      ),
    );
  }
}

// ── Nav Bar ───────────────────────────────────────────────────────────────────

class _NexusNavBar extends StatelessWidget {
  final int activeIndex;
  const _NexusNavBar({required this.activeIndex});

  static const _items = [
    (Icons.radar_rounded, 'Scanner'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.receipt_long_outlined, 'Activity'),
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
                  onTap: () => context.read<TradingBloc>().add(ChangeTab(i)),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: isActive ? AppTheme.blue : AppTheme.textMuted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: isActive ? AppTheme.blue : AppTheme.textMuted,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
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
