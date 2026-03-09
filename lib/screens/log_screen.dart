import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/trading_bloc.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingBloc, TradingState>(
      builder: (context, state) {
        if (state.logs.isEmpty) {
          return Center(
            child: Text('No activity yet.',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: AppTheme.textDim)),
          );
        }
        return ListView.builder(
          itemCount: state.logs.length,
          itemBuilder: (context, i) => _LogTile(log: state.logs[i]),
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  final TradeLog log;
  const _LogTile({required this.log});

  Color get _color => switch (log.type) {
        TradeLogType.buy => AppTheme.green,
        TradeLogType.win => AppTheme.green,
        TradeLogType.loss => AppTheme.red,
        TradeLogType.warn => AppTheme.gold,
        TradeLogType.system => AppTheme.blue,
        TradeLogType.sell => AppTheme.red,
        TradeLogType.info => AppTheme.textPrimary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.formattedTime,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: AppTheme.textDim,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              log.message,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: _color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
