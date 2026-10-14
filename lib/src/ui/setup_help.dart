import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../protocol.dart';

const _snippet = '''
// 1. Copy example/lib/mixpanel_devtools_recorder.dart from the
//    mixpanel_devtools package into your app.
// 2. Wrap the instance that Mixpanel.init returns:
final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
final recorded = MixpanelDevtoolsRecorder.instrument(mixpanel, token: token);
// 3. Use `recorded` everywhere the app used `mixpanel`.''';

/// Shown when the app runs but does not have the recorder.
class SetupHelp extends StatelessWidget {
  const SetupHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(largeSpacing),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The app does not send Mixpanel records to this tab yet.', style: theme.textTheme.titleMedium),
              const SizedBox(height: denseSpacing),
              Text(
                'mixpanel_flutter sends events through the native iOS and Android SDKs, so DevTools cannot '
                'see them on the network. Add the recorder to the app, then hot restart it.',
                style: theme.regularTextStyle,
              ),
              const SizedBox(height: defaultSpacing),
              RoundedOutlinedBorder(
                child: Padding(
                  padding: const EdgeInsets.all(defaultSpacing),
                  child: SelectableText(_snippet, style: theme.fixedFontStyle),
                ),
              ),
              const SizedBox(height: defaultSpacing),
              Text(
                'The tab looks for the ${MixpanelDevtoolsProtocol.getRecordsMethod} service extension. '
                'Recording runs only in debug and profile builds.',
                style: theme.subtleTextStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
