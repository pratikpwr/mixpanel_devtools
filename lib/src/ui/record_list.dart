import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../models/mixpanel_record.dart';

/// The numbered list of records. It follows new records while the user is at the bottom.
class RecordList extends StatefulWidget {
  const RecordList({
    super.key,
    required this.records,
    required this.totalCount,
    required this.selected,
    required this.numberOf,
    required this.onSelected,
  });

  /// The records that match the search.
  final List<MixpanelRecord> records;

  /// The number of records before the search.
  final int totalCount;
  final MixpanelRecord? selected;
  final int Function(MixpanelRecord record) numberOf;
  final ValueChanged<MixpanelRecord> onSelected;

  @override
  State<RecordList> createState() => _RecordListState();
}

class _RecordListState extends State<RecordList> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(RecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.records.length <= oldWidget.records.length || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - defaultListItemHeight) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.records.length;
    final title = count == widget.totalCount ? 'Events ($count)' : 'Events ($count of ${widget.totalCount})';
    return RoundedOutlinedBorder(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AreaPaneHeader(title: Text(title), includeTopBorder: false, roundedTopBorder: false),
          Expanded(
            child:
                count == 0
                    ? Center(
                      child: Text(
                        'No events match the search or the filters.',
                        style: Theme.of(context).subtleTextStyle,
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      itemCount: count,
                      itemExtent: _rowHeight,
                      itemBuilder: (context, index) {
                        final record = widget.records[index];
                        return _RecordRow(
                          record: record,
                          number: widget.numberOf(record),
                          isSelected: identical(record, widget.selected),
                          onTap: () => widget.onSelected(record),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

const _rowHeight = 28.0;

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.number, required this.isSelected, required this.onTap});

  final MixpanelRecord record;
  final int number;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle =
        record.isTrack ? theme.regularTextStyle : theme.subtleTextStyle.copyWith(fontStyle: FontStyle.italic);
    return Material(
      color: isSelected ? theme.colorScheme.selectedRowBackgroundColor : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: denseSpacing),
          child: Row(
            children: [
              SizedBox(width: 40, child: Text('$number.', style: theme.subtleTextStyle)),
              Expanded(child: Text(record.label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: denseSpacing),
              Text(formatClockTime(record.timestamp), style: theme.subtleFixedFontStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// `HH:mm:ss.SSS` in local time.
String formatClockTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$millis';
}
