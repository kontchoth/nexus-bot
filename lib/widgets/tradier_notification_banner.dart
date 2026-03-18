import 'dart:async';
import 'package:flutter/material.dart';
import '../services/spx/tradier_notifications_service.dart';
import '../theme/app_theme.dart';
import '../theme/google_fonts_stub.dart';

/// Polls Tradier for account notifications and renders a dismissable
/// warning banner for each one (e.g. SPY dividend alerts, margin calls).
///
/// Usage:
/// ```dart
/// TradierNotificationBanner(
///   apiToken: state.tradierToken,
///   useSandbox: SpxTradierEnvironment.isSandbox(state.tradierEnvironment),
/// )
/// ```
class TradierNotificationBanner extends StatefulWidget {
  final String? apiToken;
  final bool useSandbox;

  const TradierNotificationBanner({
    super.key,
    required this.apiToken,
    required this.useSandbox,
  });

  @override
  State<TradierNotificationBanner> createState() =>
      _TradierNotificationBannerState();
}

class _TradierNotificationBannerState
    extends State<TradierNotificationBanner> {
  static const _pollInterval = Duration(minutes: 10);

  List<TradierNotification> _notifications = [];
  final Set<String> _dismissed = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  @override
  void didUpdateWidget(TradierNotificationBanner old) {
    super.didUpdateWidget(old);
    if (old.apiToken != widget.apiToken ||
        old.useSandbox != widget.useSandbox) {
      _dismissed.clear();
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final token = widget.apiToken;
    if (token == null || token.isEmpty) return;
    final svc = TradierNotificationsService(
      apiToken: token,
      useSandbox: widget.useSandbox,
    );
    final results = await svc.fetchNotifications();
    if (mounted) {
      setState(() => _notifications = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _notifications
        .where((n) => !_dismissed.contains(n.id))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final n in visible) ...[
          _NotificationBanner(
            notification: n,
            onDismiss: () => setState(() => _dismissed.add(n.id)),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  final TradierNotification notification;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded,
                size: 14, color: AppTheme.red),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.text,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close,
                size: 14,
                color: Colors.white.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}
