import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';

import '../../blocs/auth_bloc.dart';
import '../../services/spx/spx_trade_journal_analytics.dart';
import '../../services/spx/spx_trade_journal_codes.dart';
import '../../services/spx/spx_trade_journal_export_service.dart';
import '../../services/spx/spx_trade_journal_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/number_formatters.dart';

enum _JournalScope { all, closed, open }

enum _JournalHeatmapMetric { winRate, avgPnl }

class SpxJournalScreen extends StatefulWidget {
  const SpxJournalScreen({super.key});

  @override
  State<SpxJournalScreen> createState() => _SpxJournalScreenState();
}

class _SpxJournalScreenState extends State<SpxJournalScreen> {
  _JournalScope _scope = _JournalScope.closed;
  _JournalHeatmapMetric _heatmapMetric = _JournalHeatmapMetric.winRate;
  int _lookbackDays = 30;
  bool _loading = true;
  bool _exporting = false;
  bool _savingReview = false;
  Object? _error;
  List<SpxTradeJournalRecord> _records = const [];

  late final SpxTradeJournalRepository _repository;
  late final SpxTradeJournalExportService _exporter;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SpxTradeJournalRepository>();
    _exporter = SpxTradeJournalExportService(repository: _repository);
    _reload();
  }

  Future<void> _reload() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _records = const [];
        _loading = false;
        _error = 'No authenticated user';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final enteredFrom =
          DateTime.now().subtract(Duration(days: _lookbackDays));
      final records = await _repository.loadAll(
        user.id,
        limit: 2000,
        closedOnly: _scope == _JournalScope.closed,
        openOnly: _scope == _JournalScope.open,
        enteredFrom: enteredFrom,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _export({required bool csv}) async {
    if (_exporting) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    setState(() => _exporting = true);
    try {
      final enteredFrom =
          DateTime.now().subtract(Duration(days: _lookbackDays));
      final payload = csv
          ? await _exporter.exportCsv(
              user.id,
              limit: 2000,
              closedOnly: _scope == _JournalScope.closed,
              openOnly: _scope == _JournalScope.open,
              enteredFrom: enteredFrom,
            )
          : await _exporter.exportJsonLines(
              user.id,
              limit: 2000,
              closedOnly: _scope == _JournalScope.closed,
              openOnly: _scope == _JournalScope.open,
              enteredFrom: enteredFrom,
            );
      await _showExportPreview(
        payload: payload,
        title: csv ? 'CSV' : 'JSONL',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportFeatures() async {
    if (_exporting) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    setState(() => _exporting = true);
    try {
      final enteredFrom =
          DateTime.now().subtract(Duration(days: _lookbackDays));
      final payload = await _exporter.exportFeatureCsv(
        user.id,
        limit: 2000,
        enteredFrom: enteredFrom,
      );
      await _showExportPreview(payload: payload, title: 'FEATURE CSV');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showExportPreview({
    required String payload,
    required String title,
  }) async {
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title copied to clipboard (${payload.length} chars)'),
        backgroundColor: AppTheme.blue.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bg2,
      isScrollControlled: true,
      builder: (context) {
        final lines = payload.split('\n');
        final preview = lines.take(60).join('\n');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title Preview',
                  style: GoogleFonts.syne(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'First ${lines.length < 60 ? lines.length : 60} lines shown. Full export is in clipboard.',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 320,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        preview,
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textPrimary,
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editReview(SpxTradeJournalRecord record) async {
    if (_savingReview) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    String? selectedVerdict = record.reviewVerdict;
    final notesController =
        TextEditingController(text: record.reviewNotes ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.bg2,
              title: Text(
                'Review ${record.symbol}',
                style: GoogleFonts.syne(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selectedVerdict,
                    dropdownColor: AppTheme.bg3,
                    decoration: const InputDecoration(labelText: 'Verdict'),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unreviewed'),
                      ),
                      DropdownMenuItem<String?>(
                        value: SpxReviewVerdictCodes.goodSetup,
                        child: Text('Good Setup'),
                      ),
                      DropdownMenuItem<String?>(
                        value: SpxReviewVerdictCodes.badSetup,
                        child: Text('Bad Setup'),
                      ),
                      DropdownMenuItem<String?>(
                        value: SpxReviewVerdictCodes.neutral,
                        child: Text('Neutral'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedVerdict = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    maxLines: 4,
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      hintText: 'What was right/wrong in this trade?',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (save != true) {
      notesController.dispose();
      return;
    }

    if (!mounted) return;
    setState(() => _savingReview = true);
    try {
      await _repository.upsertReview(
        user.id,
        tradeId: record.tradeId,
        reviewVerdict: selectedVerdict,
        reviewNotes: notesController.text,
        reviewedAt: DateTime.now(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Review saved for ${record.symbol}'),
          backgroundColor: AppTheme.blue.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      await _reload();
    } finally {
      notesController.dispose();
      if (mounted) setState(() => _savingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closed = _records.where((r) => r.exitedAt != null).toList();
    final heatmap = buildSpxTradeHeatmap(closed);
    final netPnl = closed.fold<double>(0, (sum, r) => sum + (r.pnlUsd ?? 0));
    final wins = closed.where((r) => (r.pnlUsd ?? 0) > 0).length;
    final winRate =
        closed.isEmpty ? 0 : ((wins / closed.length) * 100).clamp(0, 100);

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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _stat(
                  'Records',
                  '${_records.length}',
                  AppTheme.textPrimary,
                ),
                _stat(
                  'Closed',
                  '${closed.length}',
                  AppTheme.blue,
                ),
                _stat(
                  'Win Rate',
                  closed.isEmpty ? '—' : '${winRate.toStringAsFixed(0)}%',
                  AppTheme.gold,
                ),
                _stat(
                  'Net PnL',
                  NexusFormatters.usd(netPnl, signed: true),
                  netPnl >= 0 ? AppTheme.green : AppTheme.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _TimeOfDayEdgeHeatmap(
            heatmap: heatmap,
            metric: _heatmapMetric,
            onMetricChanged: (metric) {
              setState(() => _heatmapMetric = metric);
            },
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _EmptyState(text: 'Failed to load journal: $_error')
          else if (_records.isEmpty)
            const _EmptyState(
              text: 'No SPX journal records for the current filter.',
            )
          else
            ..._records.map(_recordTile),
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
              _scopeChip(_JournalScope.closed, 'Closed'),
              const SizedBox(width: 6),
              _scopeChip(_JournalScope.open, 'Open'),
              const SizedBox(width: 6),
              _scopeChip(_JournalScope.all, 'All'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bg3,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _lookbackDays,
                    dropdownColor: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(8),
                    style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                    ),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('7D')),
                      DropdownMenuItem(value: 30, child: Text('30D')),
                      DropdownMenuItem(value: 90, child: Text('90D')),
                      DropdownMenuItem(value: 365, child: Text('1Y')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _lookbackDays = value);
                      _reload();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(csv: true),
                  icon: const Icon(Icons.table_view_outlined, size: 16),
                  label: Text(_exporting ? 'Exporting…' : 'Export CSV'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(csv: false),
                  icon: const Icon(Icons.data_object_rounded, size: 16),
                  label: Text(_exporting ? 'Exporting…' : 'Export JSONL'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : _exportFeatures,
              icon: const Icon(Icons.psychology_alt_outlined, size: 16),
              label: Text(
                _exporting ? 'Exporting…' : 'Export Feature CSV (Model Input)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(_JournalScope scope, String label) {
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
      onSelected: (_) {
        setState(() => _scope = scope);
        _reload();
      },
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.syne(
              color: valueColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(SpxTradeJournalRecord record) {
    final isClosed = record.exitedAt != null;
    final pnl = record.pnlUsd;
    final pnlText =
        pnl == null ? 'OPEN' : NexusFormatters.usd(pnl, signed: true);
    final pnlColor = pnl == null
        ? AppTheme.blue
        : (pnl >= 0 ? AppTheme.green : AppTheme.red);
    final side = record.side.toLowerCase();
    final sideColor = side == 'call' ? AppTheme.blue : AppTheme.red;
    final entered = _dateTime(record.enteredAt);
    final exited = isClosed ? _dateTime(record.exitedAt!) : '—';
    final entryReason = SpxEntryReasonCodes.label(record.entryReasonCode);
    final exitReason = record.exitReasonCode == null
        ? 'Open position'
        : SpxExitReasonCodes.label(record.exitReasonCode!);
    final reviewLabel = record.reviewVerdict == null
        ? 'Unreviewed'
        : SpxReviewVerdictCodes.label(record.reviewVerdict!);
    final reviewColor = switch (record.reviewVerdict) {
      SpxReviewVerdictCodes.goodSetup => AppTheme.green,
      SpxReviewVerdictCodes.badSetup => AppTheme.red,
      SpxReviewVerdictCodes.neutral => AppTheme.gold,
      _ => AppTheme.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
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
              Text(
                record.symbol,
                style: GoogleFonts.syne(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sideColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sideColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  side.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: sideColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                pnlText,
                style: GoogleFonts.syne(
                  color: pnlColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _meta('Strike', NexusFormatters.number(record.strike)),
              _meta('Entry DTE', '${record.dteEntry}'),
              _meta('Exit DTE', '${record.dteExit ?? '—'}'),
              _meta('Contracts', '${record.contracts}'),
              _meta(
                'Entry',
                NexusFormatters.usd(record.entryPremium),
              ),
              _meta(
                'Exit',
                record.exitPremium == null
                    ? '—'
                    : NexusFormatters.usd(record.exitPremium!),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Entry: $entryReason',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 11,
            ),
          ),
          Text(
            'Exit: $exitReason',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$entered  →  $exited',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textDim,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: reviewColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: reviewColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  reviewLabel.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    color: reviewColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _savingReview ? null : () => _editReview(record),
                icon: const Icon(Icons.edit_note_rounded, size: 15),
                label: Text(
                  _savingReview ? 'Saving…' : 'Review',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          if ((record.reviewNotes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Notes: ${record.reviewNotes}',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 10,
            ),
          ),
          TextSpan(
            text: value,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _dateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
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
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(
          color: AppTheme.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TimeOfDayEdgeHeatmap extends StatelessWidget {
  final SpxTradeHeatmap heatmap;
  final _JournalHeatmapMetric metric;
  final ValueChanged<_JournalHeatmapMetric> onMetricChanged;

  const _TimeOfDayEdgeHeatmap({
    required this.heatmap,
    required this.metric,
    required this.onMetricChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasData =
        heatmap.totalClosedTrades > 0 && heatmap.bucketKeys.isNotEmpty;

    return Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIME-OF-DAY EDGE',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasData
                          ? '${heatmap.totalClosedTrades} closed trades grouped by entry time and moneyness.'
                          : 'Closed trades will populate a time-of-day edge map here.',
                      style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _HeatmapMetricChip(
                label: 'Win Rate',
                selected: metric == _JournalHeatmapMetric.winRate,
                onTap: () => onMetricChanged(_JournalHeatmapMetric.winRate),
              ),
              const SizedBox(width: 6),
              _HeatmapMetricChip(
                label: 'Avg PnL',
                selected: metric == _JournalHeatmapMetric.avgPnl,
                onTap: () => onMetricChanged(_JournalHeatmapMetric.avgPnl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            const _EmptyState(
              text:
                  'No closed trades available for heatmap analysis in the current filter.',
            )
          else ...[
            SizedBox(
              height: 210,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 90 + (heatmap.bucketKeys.length * 74),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 90),
                          ...heatmap.bucketKeys.map((bucketKey) {
                            return SizedBox(
                              width: 74,
                              child: Text(
                                heatmap.bucketLabels[bucketKey] ?? bucketKey,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.spaceGrotesk(
                                  color: AppTheme.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...[
                        'itm',
                        'atm',
                        'otm',
                      ].map((rowKey) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  _heatmapRowLabel(rowKey),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _heatmapRowColor(rowKey),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              ...heatmap.bucketKeys.map((bucketKey) {
                                final cell = heatmap.cellsByMoneyness[rowKey]
                                    ?[bucketKey];
                                return _HeatmapCellTile(
                                  summary: cell,
                                  metric: metric,
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              metric == _JournalHeatmapMetric.winRate
                  ? 'Green cells mark stronger win-rate pockets. Tap a cell for sample count and PnL detail.'
                  : 'Green cells mark positive average PnL. Use sample count before trusting a strong-looking patch.',
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textMuted,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeatmapMetricChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HeatmapMetricChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.blue.withValues(alpha: 0.15) : AppTheme.bg3,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.blue : AppTheme.border2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: selected ? AppTheme.blue : AppTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HeatmapCellTile extends StatelessWidget {
  final SpxTradeHeatmapCell? summary;
  final _JournalHeatmapMetric metric;

  const _HeatmapCellTile({
    required this.summary,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    final cellColor = _heatmapCellColor(summary, metric);
    final textColor = summary == null ? AppTheme.textDim : AppTheme.textPrimary;
    final primaryText = summary == null
        ? '—'
        : (metric == _JournalHeatmapMetric.winRate
            ? '${summary!.winRate.toStringAsFixed(0)}%'
            : NexusFormatters.usd(summary!.avgPnlUsd, signed: true));
    final secondaryText = summary == null ? '' : 'n=${summary!.tradeCount}';

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: summary == null
            ? null
            : () => _showHeatmapCellDetails(context, summary!),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 68,
          height: 54,
          decoration: BoxDecoration(
            color: cellColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: summary == null ? AppTheme.border : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                primaryText,
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (secondaryText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondaryText,
                  style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary.withValues(alpha: 0.82),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showHeatmapCellDetails(
  BuildContext context,
  SpxTradeHeatmapCell summary,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.bg2,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${summary.bucketLabel} • ${_heatmapRowLabel(summary.moneynessKey)}',
                style: GoogleFonts.syne(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _HeatmapDetailStat(
                    label: 'Trades',
                    value: '${summary.tradeCount}',
                    color: AppTheme.textPrimary,
                  ),
                  _HeatmapDetailStat(
                    label: 'Win Rate',
                    value: '${summary.winRate.toStringAsFixed(0)}%',
                    color: AppTheme.green,
                  ),
                  _HeatmapDetailStat(
                    label: 'Avg PnL',
                    value: NexusFormatters.usd(summary.avgPnlUsd, signed: true),
                    color:
                        summary.avgPnlUsd >= 0 ? AppTheme.green : AppTheme.red,
                  ),
                  _HeatmapDetailStat(
                    label: 'Avg Win',
                    value: summary.avgWinUsd == 0
                        ? '—'
                        : NexusFormatters.usd(summary.avgWinUsd),
                    color: AppTheme.green,
                  ),
                  _HeatmapDetailStat(
                    label: 'Avg Loss',
                    value: summary.avgLossUsd == 0
                        ? '—'
                        : NexusFormatters.usd(summary.avgLossUsd),
                    color: AppTheme.red,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Use this as a learning signal, not a rule. Small sample cells can look strong by accident.',
                style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HeatmapDetailStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeatmapDetailStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.syne(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _heatmapRowLabel(String rowKey) {
  return switch (rowKey) {
    'itm' => 'ITM',
    'atm' => 'ATM',
    'otm' => 'OTM',
    _ => rowKey.toUpperCase(),
  };
}

Color _heatmapRowColor(String rowKey) {
  return switch (rowKey) {
    'itm' => AppTheme.blue,
    'atm' => AppTheme.gold,
    'otm' => AppTheme.textMuted,
    _ => AppTheme.textPrimary,
  };
}

Color _heatmapCellColor(
  SpxTradeHeatmapCell? summary,
  _JournalHeatmapMetric metric,
) {
  if (summary == null) return AppTheme.bg3;

  final intensity = switch (metric) {
    _JournalHeatmapMetric.winRate =>
      ((summary.winRate - 50).abs() / 50).clamp(0.18, 1.0),
    _JournalHeatmapMetric.avgPnl =>
      (summary.avgPnlUsd.abs() / 500).clamp(0.18, 1.0),
  };
  final base = switch (metric) {
    _JournalHeatmapMetric.winRate =>
      summary.winRate >= 50 ? AppTheme.green : AppTheme.red,
    _JournalHeatmapMetric.avgPnl =>
      summary.avgPnlUsd >= 0 ? AppTheme.green : AppTheme.red,
  };
  return Color.lerp(
        AppTheme.bg3,
        base,
        0.18 + (0.36 * intensity),
      ) ??
      AppTheme.bg3;
}
