import 'dart:async';

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../connection/app_connection.dart';
import '../export/record_exporter.dart';
import '../models/mixpanel_record.dart';
import '../records_controller.dart';
import 'properties_panel.dart';
import 'record_list.dart';
import 'setup_help.dart';
import 'toolbar.dart';

typedef CopyToClipboard = void Function(String text, String successMessage);
typedef DownloadFile = void Function(String fileName, String content, String mimeType);

/// The Mixpanel tab: a toolbar, the list of records, and the property table.
class MixpanelScreen extends StatefulWidget {
  const MixpanelScreen({
    super.key,
    required this.controller,
    required this.connection,
    required this.copyToClipboard,
    required this.download,
    this.now = DateTime.now,
  });

  final RecordsController controller;
  final AppConnection connection;
  final CopyToClipboard copyToClipboard;
  final DownloadFile download;

  /// Gives the time for export file names.
  final DateTime Function() now;

  @override
  State<MixpanelScreen> createState() => _MixpanelScreenState();
}

class _MixpanelScreenState extends State<MixpanelScreen> {
  late final StreamSubscription<MixpanelRecord> _liveSubscription;
  late final StreamSubscription<List<MixpanelRecord>> _backlogSubscription;
  final _searchController = TextEditingController();

  RecordsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _liveSubscription = widget.connection.liveRecords.listen(_controller.add);
    _backlogSubscription = widget.connection.backlogs.listen(_controller.merge);
  }

  @override
  void dispose() {
    unawaited(_liveSubscription.cancel());
    unawaited(_backlogSubscription.cancel());
    _searchController.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    unawaited(widget.connection.clear());
  }

  void _export(ExportAction action) {
    final records = _controller.visibleRecords;
    final exporter = RecordExporter(showMixpanelProps: _controller.showMixpanelProps);
    final baseName = 'mixpanel_events_${_fileStamp(widget.now())}';
    switch (action) {
      case ExportAction.downloadJson:
        widget.download('$baseName.json', exporter.toJson(records), 'application/json');
      case ExportAction.downloadCsv:
        widget.download('$baseName.csv', exporter.toCsv(records), 'text/csv');
      case ExportAction.downloadMarkdown:
        widget.download('$baseName.md', exporter.toMarkdown(records), 'text/markdown');
      case ExportAction.copyMarkdown:
        widget.copyToClipboard(exporter.toMarkdown(records), 'Copied ${records.length} events as Markdown');
    }
  }

  void _copySelected({required bool asMarkdown}) {
    final record = _controller.selected;
    if (record == null) {
      return;
    }
    final exporter = RecordExporter(showMixpanelProps: _controller.showMixpanelProps);
    if (asMarkdown) {
      widget.copyToClipboard(
        exporter.recordToMarkdown(record, index: _controller.numberOf(record)),
        'Copied "${record.label}" as Markdown',
      );
      return;
    }
    widget.copyToClipboard(exporter.recordToJson(record), 'Copied "${record.label}" as JSON');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, widget.connection.status]),
      builder: (context, _) {
        final status = widget.connection.status.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MixpanelToolbar(
              controller: _controller,
              status: status,
              searchController: _searchController,
              onClear: _clear,
              onFlush: status == ConnectionStatus.ready ? () => unawaited(widget.connection.flush()) : null,
              onExport: _export,
            ),
            const SizedBox(height: densePadding),
            Expanded(child: _buildBody(status)),
          ],
        );
      },
    );
  }

  Widget _buildBody(ConnectionStatus status) {
    if (_controller.records.isEmpty) {
      switch (status) {
        case ConnectionStatus.disconnected:
          return const _CenteredMessage('Waiting for a running app. Start the app in debug mode.');
        case ConnectionStatus.notInstrumented:
          return const SetupHelp();
        case ConnectionStatus.ready:
          if (_controller.recording) {
            return const _CenteredMessage('No events yet. Use the app to send events.');
          }
          return const _CenteredMessage('Recording is paused. Press "Paused" to record again.');
      }
    }
    final selected = _controller.selected;
    return SplitPane(
      axis: Axis.horizontal,
      initialFractions: const [0.35, 0.65],
      children: [
        RecordList(
          records: _controller.visibleRecords,
          totalCount: _controller.records.length,
          selected: selected,
          numberOf: _controller.numberOf,
          onSelected: _controller.select,
        ),
        PropertiesPanel(
          record: selected,
          showMixpanelProps: _controller.showMixpanelProps,
          onCopyJson: selected == null ? null : () => _copySelected(asMarkdown: false),
          onCopyMarkdown: selected == null ? null : () => _copySelected(asMarkdown: true),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(largeSpacing),
        child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).subtleTextStyle),
      ),
    );
  }
}

String _fileStamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}_${two(time.hour)}${two(time.minute)}${two(time.second)}';
}
