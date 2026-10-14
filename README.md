# mixpanel_devtools

See every Mixpanel call of your Flutter app, live, in Flutter DevTools. Inspect the events and
their properties, search them, and export them.

![The Mixpanel tab in Flutter DevTools](https://raw.githubusercontent.com/pratikpwr/mixpanel_devtools/main/doc/images/mixpanel_tab.png)

The tab works like the Chrome "Mixpanel Tools" extension, but for Flutter apps on iOS and Android.

Use it when you must check that the app sends the correct events with the correct properties,
but you cannot open the Mixpanel project (for example, because access to it is restricted).

## Quick start

You need Flutter 3.29 or newer and an app that uses `mixpanel_flutter` 2.x. The recorder tests
use `mixpanel_flutter` 2.15.0.

1. Add the package as a dev dependency:

   ```bash
   flutter pub add --dev mixpanel_devtools
   ```

2. Enable the extension in `devtools_options.yaml`, next to `pubspec.yaml`:

   ```yaml
   extensions:
     - mixpanel_devtools: true
   ```

3. Copy the
   [recorder file](https://github.com/pratikpwr/mixpanel_devtools/blob/main/example/lib/mixpanel_devtools_recorder.dart)
   into your app.

4. Wrap the instance that `Mixpanel.init` returns, and use the result everywhere:

   ```dart
   final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
   final recorded = MixpanelDevtoolsRecorder.instrument(mixpanel, token: token);
   ```

   In release builds, `instrument` returns `mixpanel` unchanged and records nothing.

5. Run the app in debug or profile mode. Open DevTools, then open the **mixpanel_devtools** tab.

To see the tab with sample data first, run the [demo app](#try-the-demo-app).

## Features

### Inspect

- **Live event list.** Each `track`, people, identity, super-property, timing, consent, flush,
  and group call appears at once. Each row has a number and the local time.
- **Property table.** Shows the event properties, the super properties sent with the event, and
  `time` / `distinct_id`. Each row shows its source: the event, a super property, or Mixpanel.
- **History.** Shows events that fired before you opened DevTools. Keeps the events of earlier
  runs after a hot restart, until you press **Clear**.

### Filter

- **Search.** Matches event names, kinds, property keys, and property values.
- **Mixpanel props: Hidden / Shown.** Hides or shows `time`, `distinct_id`, and keys that start
  with `$` or `mp_`.
- **Other calls: Shown / Hidden.** Hides people, identity, super-property, timing, consent,
  flush, and group calls, so the list shows only `track` events. The numbers stay in sequence.
- **Recording / Paused.** Pauses the list without changing the app.

### Act and share

- **Flush.** Asks the app to send its queued events to Mixpanel now.
- **Export.** Downloads JSON, CSV (one row per event), or Markdown.
- **Copy.** Copies one event as JSON or Markdown. Copies all events as Markdown for a wiki page
  or an issue.

An export uses the current search and the current display modes.

## How it works

`mixpanel_flutter` sends each call over a platform channel to the native iOS or Android SDK.
The native SDK sends the HTTP requests, in batches. DevTools cannot see that traffic, so the
DevTools Network tab cannot help here.

Thus the app sends each call to the tab itself, through `dart:developer`. The recorder does
this. It records the call, then passes the call to `mixpanel_flutter` unchanged.

```text
your app code
     |
     v
MixpanelDevtoolsRecorder ----> dart:developer ----> Mixpanel tab in DevTools
     |
     v
mixpanel_flutter ----> native SDK ----> Mixpanel (as before)
```

The recorder is one file that you copy into the app. It has no dependency on this package, so
this package stays a `dev_dependency`.

## Try the demo app

```bash
git clone https://github.com/pratikpwr/mixpanel_devtools.git
cd mixpanel_devtools/example
flutter run --dart-define=AUTOPLAY=true
```

The demo sends one call of each kind at start-up. Without `--dart-define=MIXPANEL_TOKEN=...` it
opts out of tracking, so the native SDK sends nothing to Mixpanel.

## Limits

- The tab shows what the app passes to the SDK, plus the super properties and the distinct id
  that the recorder knows. It does not show the properties that the native SDK adds later, such
  as `$os` and `$model`.
- The tab cannot confirm that Mixpanel accepted a batch. Use **Flush** to force a send.
- The recorder sees super properties that the app registers after `instrument`. It reads the
  earlier ones from the SDK once, at start-up.
- Group profile calls (`getGroup(...).set(...)`) and feature-flag calls are not recorded.

## Privacy

Everything stays on your computer: the app, the DevTools page, and the files that you export.
The tab saves the most recent 1000 records in the browser `sessionStorage` of the DevTools tab,
and the two display modes in `localStorage`.
The exports can contain personal data from the test account. Do not share them outside the team.

## Protocol

The tab and the recorder share a small protocol: one `Extension` stream event per call
(`mixpanel_devtools:record`), and three service extensions
(`ext.mixpanel_devtools.getRecords`, `.clear`, `.flush`). See the
[design document](https://github.com/pratikpwr/mixpanel_devtools/blob/main/doc/specs/2026-10-08-mixpanel-devtools-design.md)
for the record format.

## Development

```bash
flutter test                         # extension tests
(cd example && flutter test)         # recorder tests
dart run devtools_extensions build_and_copy --source=. --dest=extension/devtools
dart run devtools_extensions validate --package=.
```

Build and copy again after each change to `lib/`. DevTools loads the extension from
`extension/devtools/build`.

## Issues and license

Report a problem or ask for a feature in the
[issue tracker](https://github.com/pratikpwr/mixpanel_devtools/issues).

This package uses the BSD 3-Clause license. See
[LICENSE](https://github.com/pratikpwr/mixpanel_devtools/blob/main/LICENSE).
