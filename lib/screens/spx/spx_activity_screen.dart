import 'package:flutter/material.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';

import '../../theme/app_theme.dart';
import 'spx_journal_screen.dart';
import 'spx_opportunities_screen.dart';

enum _SpxActivityTab { opportunities, journal }

class SpxActivityScreen extends StatefulWidget {
  final String? focusOpportunityId;
  final int focusRequestKey;

  const SpxActivityScreen({
    super.key,
    this.focusOpportunityId,
    this.focusRequestKey = 0,
  });

  @override
  State<SpxActivityScreen> createState() => _SpxActivityScreenState();
}

class _SpxActivityScreenState extends State<SpxActivityScreen> {
  _SpxActivityTab _tab = _SpxActivityTab.opportunities;

  @override
  void didUpdateWidget(covariant SpxActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequestKey != oldWidget.focusRequestKey &&
        _tab != _SpxActivityTab.opportunities) {
      setState(() => _tab = _SpxActivityTab.opportunities);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: AppTheme.bg2,
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_SpxActivityTab>(
                  segments: const [
                    ButtonSegment<_SpxActivityTab>(
                      value: _SpxActivityTab.opportunities,
                      label: Text('Opportunities'),
                    ),
                    ButtonSegment<_SpxActivityTab>(
                      value: _SpxActivityTab.journal,
                      label: Text('Trade Journal'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (selection) {
                    setState(() => _tab = selection.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      GoogleFonts.spaceGrotesk(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab == _SpxActivityTab.opportunities ? 0 : 1,
            children: [
              SpxOpportunitiesScreen(
                focusOpportunityId: widget.focusOpportunityId,
                focusRequestKey: widget.focusRequestKey,
              ),
              const SpxJournalScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
