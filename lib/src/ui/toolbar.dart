import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../connection/app_connection.dart';
import '../records_controller.dart';

enum ExportAction {
  downloadJson('Download JSON'),
  downloadCsv('Download CSV'),
  downloadMarkdown('Download Markdown'),
  copyMarkdown('Copy all as Markdown');

  const ExportAction(this.label);

  final String label;
}

/// Recording, Clear, Mixpanel props, Other calls, Flush, Search, Export, and the connection status.
class MixpanelToolbar extends StatelessWidget {
  const MixpanelToolbar({
    super.key,
    required this.controller,
    required this.status,
    required this.searchController,
    required this.onClear,
    required this.onFlush,
    required this.onExport,
  });

  final RecordsController controller;
  final ConnectionStatus status;
  final TextEditingController searchController;
  final VoidCallback onClear;
  final VoidCallback? onFlush;
  final ValueChanged<ExportAction> onExport;

  @override
  Widget build(BuildContext context) {
    final hasRecords = controller.records.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(denseSpacing, denseSpacing, denseSpacing, 0),
      child: Wrap(
        spacing: denseSpacing,
        runSpacing: denseSpacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DevToolsButton(
            icon: controller.recording ? Icons.fiber_manual_record : Icons.pause,
            label: controller.recording ? 'Recording' : 'Paused',
            color: controller.recording ? Colors.redAccent : null,
            tooltip: controller.recording ? 'Pause recording' : 'Resume recording',
            onPressed: controller.toggleRecording,
          ),
          DevToolsButton(
            icon: Icons.block,
            label: 'Clear',
            tooltip: 'Remove all events from this list and from the app buffer',
            onPressed: hasRecords ? onClear : null,
          ),
          DevToolsButton(
            icon: controller.showMixpanelProps ? Icons.visibility : Icons.visibility_off,
            label: controller.showMixpanelProps ? 'Mixpanel props: Shown' : 'Mixpanel props: Hidden',
            tooltip: r'Show or hide time, distinct_id, and $ or mp_ properties',
            onPressed: controller.toggleMixpanelProps,
          ),
          DevToolsButton(
            icon: controller.showOtherCalls ? Icons.filter_alt_off : Icons.filter_alt,
            label: controller.showOtherCalls ? 'Other calls: Shown' : 'Other calls: Hidden',
            tooltip:
                'Show or hide people, identity, super property, timing, consent, flush, and group calls. '
                'Track events always show.',
            onPressed: controller.toggleOtherCalls,
          ),
          DevToolsButton(
            icon: Icons.send,
            label: 'Flush',
            tooltip: 'Ask the app to send its queued events to Mixpanel now',
            onPressed: onFlush,
          ),
          SizedBox(
            width: mediumSearchFieldWidth,
            height: defaultTextFieldHeight,
            child: DevToolsClearableTextField(
              controller: searchController,
              hintText: 'Search events and properties',
              prefixIcon: const Icon(Icons.search, size: defaultIconSize),
              onChanged: controller.setQuery,
              additionalSuffixActions: const [],
            ),
          ),
          MenuAnchor(
            builder: (context, menu, _) {
              return DevToolsButton(
                icon: Icons.file_download,
                label: 'Export',
                tooltip: 'Export the visible events',
                onPressed: controller.visibleRecords.isEmpty ? null : () => menu.isOpen ? menu.close() : menu.open(),
              );
            },
            menuChildren: [
              for (final action in ExportAction.values)
                MenuItemButton(onPressed: () => onExport(action), child: Text(action.label)),
            ],
          ),
          _StatusLabel(status: status),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, text, tooltip) = switch (status) {
      ConnectionStatus.ready => (Colors.green, 'Recorder connected', 'The app sends its Mixpanel calls to this tab'),
      ConnectionStatus.notInstrumented => (
        Colors.amber,
        'No recorder in app',
        'The app runs, but it has not registered the recorder',
      ),
      ConnectionStatus.disconnected => (Colors.grey, 'No app', 'DevTools is not connected to a running app'),
    };
    return DevToolsTooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: densePadding),
          Text(text, style: Theme.of(context).subtleTextStyle),
        ],
      ),
    );
  }
}
