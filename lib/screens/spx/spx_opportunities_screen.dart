import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';

import '../../blocs/auth_bloc.dart';
import '../../blocs/spx/spx_bloc.dart';
import '../../services/spx/spx_opportunity_journal_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';

enum _OpportunityScope { pending, missed }

class SpxOpportunitiesScreen extends StatefulWidget {
  final String? focusOpportunityId;
  final int focusRequestKey;

  const SpxOpportunitiesScreen({
    super.key,
    this.focusOpportunityId,
    this.focusRequestKey = 0,
  });

  @override
  State<SpxOpportunitiesScreen> createState() => _SpxOpportunitiesScreenState();
}

class _SpxOpportunitiesScreenState extends State<SpxOpportunitiesScreen> {
  _OpportunityScope _scope = _OpportunityScope.pending;
  bool _loading = true;
  bool _acting = false;
  Object? _error;
  List<SpxOpportunityJournalRecord> _pending = const [];
  List<SpxOpportunityJournalRecord> _missed = const [];
  _OpportunitySummary _summary = const _OpportunitySummary.empty();
  late final SpxOpportunityJournalRepository _repository;
  Timer? _pollTimer;
  int _lastHandledFocusRequestKey = -1;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SpxOpportunityJournalRepository>();
    _reload();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _reload(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpxOpportunitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequestKey != oldWidget.focusRequestKey) {
      _applyFocusRequest();
    }
  }

  Future<void> _reload({bool silent = false}) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _pending = const [];
        _missed = const [];
        _summary = const _OpportunitySummary.empty();
        _loading = false;
        _error = 'No authenticated user';
      });
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final all = await _repository.loadAll(user.id, limit: 1200);
      final pendingMerged = all
          .where((record) =>
              record.status == SpxOpportunityStatus.pendingUser ||
              record.status == SpxOpportunityStatus.pendingDelay)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final missedMerged = all
          .where((record) =>
              record.status == SpxOpportunityStatus.missed ||
              record.status == SpxOpportunityStatus.rejected)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() {
        _pending = pendingMerged;
        _missed = missedMerged;
        _summary = _OpportunitySummary.fromRecords(all);
        _loading = false;
      });
      _applyFocusRequest();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
        _summary = const _OpportunitySummary.empty();
      });
    }
  }

  Future<void> _approve(SpxOpportunityJournalRecord record) async {
    if (_acting || record.symbol.isEmpty) return;
    if (mounted) setState(() => _acting = true);
    context.read<SpxBloc>().add(
          ApproveSpxOpportunity(
            opportunityId: record.opportunityId,
            symbol: record.symbol,
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _reload(silent: true);
    if (mounted) setState(() => _acting = false);
  }

  void _applyFocusRequest() {
    final focusId = widget.focusOpportunityId?.trim();
    if (focusId == null || focusId.isEmpty) return;
    if (_lastHandledFocusRequestKey == widget.focusRequestKey) return;

    SpxOpportunityJournalRecord? target;
    var targetScope = _OpportunityScope.pending;

    for (final record in _pending) {
      if (record.opportunityId == focusId) {
        target = record;
        targetScope = _OpportunityScope.pending;
        break;
      }
    }
    if (target == null) {
      for (final record in _missed) {
        if (record.opportunityId == focusId) {
          target = record;
          targetScope = _OpportunityScope.missed;
          break;
        }
      }
    }
    if (target == null) return;

    _lastHandledFocusRequestKey = widget.focusRequestKey;
    if (mounted && _scope != targetScope) {
      setState(() => _scope = targetScope);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showFocusedOpportunityDialog(target!);
    });
  }

  Future<void> _showFocusedOpportunityDialog(
    SpxOpportunityJournalRecord record,
  ) async {
    final isPendingUser = record.status == SpxOpportunityStatus.pendingUser;
    final isPendingDelay = record.status == SpxOpportunityStatus.pendingDelay;
    final reason = record.missedReasonCode ??
        (record.signalDetails['reasonText']?.toString().trim().isNotEmpty ==
                true
            ? record.signalDetails['reasonText'].toString()
            : record.status);
    final remainingLabel = isPendingDelay
        ? _remainingLabel(
            record.createdAt.add(Duration(seconds: record.entryDelaySeconds)),
          )
        : isPendingUser
            ? _remainingLabel(
                record.createdAt.add(
                  Duration(seconds: record.validationWindowSeconds),
                ),
              )
            : null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            record.symbol.isEmpty ? 'Opportunity' : record.symbol,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${record.status}'),
              const SizedBox(height: 6),
              Text(
                '${record.side.toUpperCase()} • strike ${NexusFormatters.number(record.strike, decimals: 1)} • ${record.dte}DTE',
              ),
              const SizedBox(height: 6),
              Text('Mode: ${record.executionModeAtDecision}'),
              if (remainingLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  isPendingDelay
                      ? 'Auto executes in: $remainingLabel'
                      : 'Validation window: $remainingLabel',
                ),
              ],
              if (!isPendingUser && !isPendingDelay) ...[
                const SizedBox(height: 6),
                Text('Reason: $reason'),
              ],
            ],
          ),
          actions: [
            if (isPendingUser || isPendingDelay)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (isPendingDelay) {
                    unawaited(_cancelAuto(record));
                  } else {
                    unawaited(_reject(record));
                  }
                },
                child: Text(isPendingDelay ? 'Cancel Auto' : 'Reject'),
              ),
            if (isPendingUser || isPendingDelay)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_approve(record));
                },
                child: const Text('Approve'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reject(SpxOpportunityJournalRecord record) async {
    if (_acting || record.symbol.isEmpty) return;
    if (mounted) setState(() => _acting = true);
    context.read<SpxBloc>().add(
          RejectSpxOpportunity(
            opportunityId: record.opportunityId,
            symbol: record.symbol,
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _reload(silent: true);
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _cancelAuto(SpxOpportunityJournalRecord record) async {
    if (_acting || record.symbol.isEmpty) return;
    if (mounted) setState(() => _acting = true);
    context.read<SpxBloc>().add(
          CancelSpxOpportunity(
            opportunityId: record.opportunityId,
            symbol: record.symbol,
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _reload(silent: true);
    if (mounted) setState(() => _acting = false);
  }

  @override
  Widget build(BuildContext context) {
    final records = _scope == _OpportunityScope.pending ? _pending : _missed;
    return RefreshIndicator(
      onRefresh: _reload,
      color: AppTheme.blue,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _buildControls(),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _EmptyState(text: 'Failed to load opportunities: $_error')
          else if (records.isEmpty)
            _EmptyState(
              text: _scope == _OpportunityScope.pending
                  ? 'No pending opportunities.'
                  : 'No missed opportunities yet.',
            )
          else
            ...records.map((record) => _recordTile(record)),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _scopeChip(
                _OpportunityScope.pending,
                'Pending (${_pending.length})',
              ),
              const SizedBox(width: 6),
              _scopeChip(
                _OpportunityScope.missed,
                'Missed (${_missed.length})',
              ),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh_rounded),
                color: AppTheme.textMuted,
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Approve/reject manual opportunities, cancel auto-delay entries, and review missed outcomes.',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetricPill(
                label: 'Found',
                value: '${_summary.foundCount}',
                color: AppTheme.blue,
              ),
              _MetricPill(
                label: 'Pending',
                value: '${_summary.pendingCount}',
                color: AppTheme.gold,
              ),
              _MetricPill(
                label: 'Executed',
                value: '${_summary.executedCount}',
                color: AppTheme.green,
              ),
              _MetricPill(
                label: 'Missed',
                value: '${_summary.missedCount}',
                color: AppTheme.red,
              ),
              _MetricPill(
                label: 'Avg Decision',
                value: _summary.avgDecisionLabel,
                color: AppTheme.textMuted,
              ),
            ],
          ),
          if (_summary.topMissedReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _summary.topMissedReasons
                    .map(
                      (entry) => _MissedReasonChip(
                        reason: entry.key,
                        count: entry.value,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeChip(_OpportunityScope scope, String label) {
    final selected = _scope == scope;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.blue.withValues(alpha: 0.2),
      backgroundColor: AppTheme.bg3,
      side: BorderSide(
        color: selected ? AppTheme.blue : AppTheme.border2,
      ),
      labelStyle: GoogleFonts.spaceGrotesk(
        color: selected ? AppTheme.blue : AppTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setState(() => _scope = scope),
    );
  }

  Widget _recordTile(SpxOpportunityJournalRecord record) {
    final isPendingUser = record.status == SpxOpportunityStatus.pendingUser;
    final isPendingDelay = record.status == SpxOpportunityStatus.pendingDelay;
    final isPending = isPendingUser || isPendingDelay;
    final reason = record.missedReasonCode ??
        (record.signalDetails['reasonText']?.toString().trim().isNotEmpty ==
                true
            ? record.signalDetails['reasonText'].toString()
            : record.status);
    final symbol = record.symbol.isEmpty ? 'Unknown Symbol' : record.symbol;
    final remainingLabel = isPendingDelay
        ? _remainingLabel(
            record.createdAt.add(
              Duration(seconds: record.entryDelaySeconds),
            ),
          )
        : isPendingUser
            ? _remainingLabel(
                record.createdAt.add(
                  Duration(seconds: record.validationWindowSeconds),
                ),
              )
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  symbol,
                  style: GoogleFonts.syne(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusPill(status: record.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${record.side.toUpperCase()} • strike ${NexusFormatters.number(record.strike, decimals: 1)} • ${record.dte}DTE',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mode: ${record.executionModeAtDecision} • premium ${NexusFormatters.usd(record.premiumAtFind)}',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textDim,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Created: ${_formatTime(record.createdAt)}',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textDim,
              fontSize: 10,
            ),
          ),
          if (remainingLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              isPendingDelay
                  ? 'Auto executes in: $remainingLabel'
                  : 'Validation window: $remainingLabel',
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!isPending) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: $reason',
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _acting
                        ? null
                        : () => isPendingDelay
                            ? _cancelAuto(record)
                            : _reject(record),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(isPendingDelay ? 'Cancel Auto' : 'Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _acting ? null : () => _approve(record),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final y = ts.year.toString().padLeft(4, '0');
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final h = ts.hour.toString().padLeft(2, '0');
    final min = ts.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  String _remainingLabel(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (!remaining.isNegative) {
      final total = remaining.inSeconds;
      final mm = (total ~/ 60).toString().padLeft(2, '0');
      final ss = (total % 60).toString().padLeft(2, '0');
      return '$mm:$ss';
    }
    return 'expired';
  }
}

class _OpportunitySummary {
  final int foundCount;
  final int pendingCount;
  final int executedCount;
  final int missedCount;
  final Duration? avgDecisionLatency;
  final List<MapEntry<String, int>> topMissedReasons;

  const _OpportunitySummary({
    required this.foundCount,
    required this.pendingCount,
    required this.executedCount,
    required this.missedCount,
    required this.avgDecisionLatency,
    required this.topMissedReasons,
  });

  const _OpportunitySummary.empty()
      : foundCount = 0,
        pendingCount = 0,
        executedCount = 0,
        missedCount = 0,
        avgDecisionLatency = null,
        topMissedReasons = const [];

  factory _OpportunitySummary.fromRecords(
    List<SpxOpportunityJournalRecord> records,
  ) {
    if (records.isEmpty) return const _OpportunitySummary.empty();

    var pending = 0;
    var executed = 0;
    var missed = 0;
    final latencies = <Duration>[];
    final reasonCounts = <String, int>{};

    for (final record in records) {
      final status = record.status;
      final isPending = status == SpxOpportunityStatus.pendingUser ||
          status == SpxOpportunityStatus.pendingDelay;
      final isExecuted = status == SpxOpportunityStatus.executed;
      final isMissed = status == SpxOpportunityStatus.missed ||
          status == SpxOpportunityStatus.rejected;

      if (isPending) pending++;
      if (isExecuted) executed++;
      if (isMissed) {
        missed++;
        final reason = (record.missedReasonCode ??
                (status == SpxOpportunityStatus.rejected
                    ? 'user_rejected'
                    : 'unknown'))
            .trim();
        reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
      }

      if (isExecuted || isMissed) {
        final latency = record.updatedAt.difference(record.createdAt);
        if (!latency.isNegative) latencies.add(latency);
      }
    }

    Duration? avgLatency;
    if (latencies.isNotEmpty) {
      final avgMs =
          latencies.fold<int>(0, (sum, d) => sum + d.inMilliseconds) ~/
              latencies.length;
      avgLatency = Duration(milliseconds: avgMs);
    }

    final topReasons = reasonCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _OpportunitySummary(
      foundCount: records.length,
      pendingCount: pending,
      executedCount: executed,
      missedCount: missed,
      avgDecisionLatency: avgLatency,
      topMissedReasons: topReasons.take(3).toList(),
    );
  }

  String get avgDecisionLabel {
    final value = avgDecisionLatency;
    if (value == null) return '—';
    if (value.inMinutes >= 1) {
      final mm = value.inMinutes;
      final ss = value.inSeconds % 60;
      return '${mm}m ${ss}s';
    }
    return '${value.inSeconds}s';
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissedReasonChip extends StatelessWidget {
  final String reason;
  final int count;

  const _MissedReasonChip({
    required this.reason,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.redBg,
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$reason ($count)',
        style: GoogleFonts.spaceGrotesk(
          color: AppTheme.red,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SpxOpportunityStatus.pendingUser => AppTheme.gold,
      SpxOpportunityStatus.pendingDelay => AppTheme.blue,
      SpxOpportunityStatus.rejected => AppTheme.red,
      SpxOpportunityStatus.missed => AppTheme.red,
      SpxOpportunityStatus.executed => AppTheme.green,
      _ => AppTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status,
        style: GoogleFonts.spaceGrotesk(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.inbox_outlined, color: AppTheme.textDim, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
