import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../models/mixpanel_record.dart';
import '../models/property_row.dart';

/// The Property / Value table of the selected record.
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.record,
    required this.showMixpanelProps,
    required this.onCopyJson,
    required this.onCopyMarkdown,
  });

  final MixpanelRecord? record;
  final bool showMixpanelProps;
  final VoidCallback? onCopyJson;
  final VoidCallback? onCopyMarkdown;

  @override
  Widget build(BuildContext context) {
    final record = this.record;
    return RoundedOutlinedBorder(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AreaPaneHeader(
            title: const Text('Properties'),
            includeTopBorder: false,
            roundedTopBorder: false,
            actions: [
              DevToolsButton(icon: Icons.data_object, label: 'Copy JSON', onPressed: onCopyJson),
              const SizedBox(width: densePadding),
              DevToolsButton(icon: Icons.table_chart_outlined, label: 'Copy Markdown', onPressed: onCopyMarkdown),
            ],
          ),
          Expanded(
            child:
                record == null
                    ? Center(
                      child: Text('Select an event to see its properties.', style: Theme.of(context).subtleTextStyle),
                    )
                    : _PropertyTable(record: record, showMixpanelProps: showMixpanelProps),
          ),
        ],
      ),
    );
  }
}

class _PropertyTable extends StatelessWidget {
  const _PropertyTable({required this.record, required this.showMixpanelProps});

  final MixpanelRecord record;
  final bool showMixpanelProps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = buildPropertyRows(record, showMixpanelProps: showMixpanelProps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(defaultSpacing, denseSpacing, defaultSpacing, denseSpacing),
          child: Text(record.label, style: theme.boldTextStyle.copyWith(color: theme.colorScheme.primary)),
        ),
        const _TableRow(property: Text('Property'), value: Text('Value'), source: Text('Source'), isHeader: true),
        const Divider(height: 1),
        Expanded(
          child:
              rows.isEmpty
                  ? Center(child: Text(_emptyMessage, style: theme.subtleTextStyle))
                  : SelectionArea(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _TableRow(
                          property: Text(
                            row.key,
                            style: theme.regularTextStyle.copyWith(color: theme.colorScheme.primary),
                          ),
                          value: Text(row.displayValue, style: theme.fixedFontStyle),
                          source:
                              row.source == PropertySource.event
                                  ? const SizedBox.shrink()
                                  : Text(row.source.label, style: theme.subtleTextStyle),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  String get _emptyMessage {
    if (showMixpanelProps) {
      return 'This call has no properties.';
    }
    return 'No custom properties. Show the Mixpanel props to see the rest.';
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.property, required this.value, required this.source, this.isHeader = false});

  final Widget property;
  final Widget value;
  final Widget source;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: defaultSpacing, vertical: densePadding + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: property),
          const SizedBox(width: defaultSpacing),
          Expanded(flex: 5, child: value),
          const SizedBox(width: denseSpacing),
          SizedBox(width: 64, child: source),
        ],
      ),
    );
    if (!isHeader) {
      return row;
    }
    return DefaultTextStyle.merge(style: Theme.of(context).boldTextStyle, child: row);
  }
}
