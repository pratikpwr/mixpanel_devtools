import 'package:flutter/material.dart';

import 'src/mixpanel_devtools_extension.dart';

/// Starts the Mixpanel tab. Flutter DevTools loads this app from `extension/devtools/build`.
void main() {
  runApp(const MixpanelDevtoolsExtension());
}
