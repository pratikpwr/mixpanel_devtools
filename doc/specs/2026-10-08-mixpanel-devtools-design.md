# Mixpanel DevTools - Design

Date: 2026-10-08

## Purpose

Developers often cannot open the Mixpanel web app, for example because access to it is
restricted. They still must check that the app sends the correct events with the correct
properties. They also must record those events in documents.

A console print of `eventName {props}` is hard to read and hard to copy into a document.

This package adds a **Mixpanel** tab to Flutter DevTools. The tab works like the Chrome
"Mixpanel Tools" extension: a live list of events, a property table, a toggle for Mixpanel
system properties, and export.

## Constraint that drives the design

`mixpanel_flutter` sends each call over the `mixpanel_flutter` platform channel to the
native iOS or Android SDK. The native SDK sends HTTP requests in batches (every 60 s by
default). The Dart VM HTTP profile never sees these requests. Thus the tab cannot capture
events without help from the app.

Decision: the package is a **dev_dependency** that holds only the DevTools tab. The app
owns a small **recorder**. The recorder sends each Mixpanel call to the tab through
`dart:developer`. The package documents the protocol and ships a reference recorder in
`example/` that apps copy.

## Protocol (version 1)

The app posts one VM `Extension` stream event per Mixpanel call:

- Event kind: `mixpanel_devtools:record`
- Event data: one record (see below)

The app also registers three service extensions in non-release builds:

| Method | Result | Effect |
|---|---|---|
| `ext.mixpanel_devtools.getRecords` | `{"version": 1, "records": [record, ...]}` | Returns the buffer (most recent 1000 records) |
| `ext.mixpanel_devtools.clear` | `{}` | Empties the buffer |
| `ext.mixpanel_devtools.flush` | `{}` | Calls `Mixpanel.flush()` |

### Record

```json
{
  "id": 7,
  "runId": "1791444012144",
  "timestamp": 1791444276820,
  "kind": "track",
  "name": "Item Viewed",
  "properties": {"screen": "home"},
  "superProperties": {"feature_flags": ["a: true"]},
  "distinctId": "user-1",
  "groups": null
}
```

| Field | Type | Rule |
|---|---|---|
| `id` | int | Increases by 1 for each record in one app run |
| `runId` | String | Unique for each app run (isolate). `runId` + `id` is the record key |
| `timestamp` | int | Milliseconds since epoch, when the app made the call |
| `kind` | String | One of `track`, `people`, `group`, `identity`, `super`, `timing`, `consent`, `flush` |
| `name` | String | Event name for `track`. Operation name for other kinds |
| `properties` | Map | The values the app passed, made JSON-safe |
| `superProperties` | Map? | `track` only. The super properties at the time of the call |
| `distinctId` | String? | The distinct id at the time of the call, if known |
| `groups` | Map? | `trackWithGroups` only |

Operation names for each kind:

| Kind | Names |
|---|---|
| `people` | `$set`, `$set_once`, `$add`, `$append`, `$union`, `$remove`, `$unset`, `$delete`, `trackCharge`, `clearCharges` |
| `identity` | `identify`, `alias`, `reset` |
| `super` | `register`, `register_once`, `unregister`, `clear` |
| `timing` | `timeEvent` |
| `consent` | `optInTracking`, `optOutTracking` |
| `flush` | `flush` |
| `group` | `setGroup`, `addGroup`, `removeGroup`, `deleteGroup` |

JSON-safe rule: `DateTime` becomes an ISO 8601 string. `Uri` becomes a string. A map key
becomes a string. Any other non-JSON value becomes `toString()`.

The tab must ignore unknown fields and unknown kinds (show unknown kinds as-is), so that
later protocol versions do not break it.

## The DevTools tab

### Layout

```
+------------------------------------------------------------------------------+
| (o) Recording | Clear | Mixpanel props: Hidden | Flush | [search....] | Export v|
+---------------------------+--------------------------------------------------+
| Events (8)                | Item Viewed               [Copy JSON] [Copy MD]  |
|  1  Item Viewed      12:01| Property        | Value                | Source  |
|  2  Button Clicked   12:01| screen          | home                 | event   |
|  3  [people] $set    12:02| feature_flags   | [ "a: true", ... ]   | super   |
|                           | time            | 1791444276.82        | mixpanel|
+---------------------------+--------------------------------------------------+
```

- The split between the two panes can be resized.
- A `track` row shows the event name. Other kinds show `[kind] name` in a muted, italic style.
- Each row shows the local time (`HH:mm:ss.SSS`).

### Property table for a `track` record

Rows, in this order, without duplicate keys:

1. `properties` (source `event`)
2. `superProperties` keys that `properties` does not override (source `super`)
3. `time` (seconds, two decimals) and `distinct_id` (source `mixpanel`)

For other kinds, the table shows `properties` (source `event`), then `distinct_id`.

**Mixpanel props: Hidden** (the default) hides rows with source `mixpanel`, and rows whose
key starts with `$` or `mp_`. **Shown** shows all rows.

Values: strings show without quotes. Lists and maps show as indented JSON. The table text
can be selected.

### Controls

| Control | Behavior |
|---|---|
| Recording / Paused | When paused, the tab drops incoming records |
| Clear | Empties the tab list and calls `ext.mixpanel_devtools.clear` |
| Mixpanel props | Toggles Hidden / Shown |
| Other calls | Toggles Shown / Hidden. Hidden shows only `track` records. Numbers count only the shown records, so they stay in sequence |
| Flush | Calls `ext.mixpanel_devtools.flush` |
| Search | Case-insensitive match on name, kind, property keys, and property values |
| Export | Download JSON, Download CSV, Download Markdown, Copy all as Markdown |
| Copy JSON / Copy Markdown | Copies the selected record |

All exports use the current filter and the current Mixpanel-props mode.

- **JSON**: a list of `{"event", "kind", "time", "properties"}` objects. `time` is ISO 8601.
- **CSV**: one row per record. Columns: `#`, `recorded_at`, `kind`, `event`, then the union of
  all property keys in first-seen order. A property key that is the same as a fixed column name
  gets the header `property: <key>`. List and map values are JSON-encoded. RFC 4180 quoting.
- **Markdown**: one `### n. name` heading per record, then a `| Property | Value |` table.
  `|` is escaped and line breaks become `<br>`.

### States

| State | Display |
|---|---|
| Not connected to an app | "Waiting for a running app" |
| Connected, `ext.mixpanel_devtools.getRecords` not registered | Setup help with the recorder snippet |
| Connected, no records | "No events yet. Use the app to send events." |

### Lifecycle

- On connect, and each time `getRecords` becomes available (first start, hot restart), the
  tab fetches the buffer and merges it. It drops duplicate keys (`runId:id`).
- Live records arrive on the `Extension` stream.
- DevTools reloads the extension page on each hot restart (`forceReload`). The tab saves the
  most recent 1000 records and the recording state in `sessionStorage`, keyed by the VM service
  URI, and restores them after the reload. The display modes (Mixpanel props, Other calls) go
  to `localStorage`, so they apply to all apps and all runs. Thus the tab keeps records from earlier runs until
  the user clears them.

## The reference recorder (app side)

`MixpanelDevtoolsRecorder.instrument(mixpanel, token: token)`:

- In release builds it returns `mixpanel` unchanged.
- Otherwise it returns a `RecordingMixpanel` (a subclass of `Mixpanel` with the same token).
  Each recorded method records, then calls `super`. Methods that it does not override go to
  the plugin unchanged.
- `getPeople()` returns a `RecordingPeople` (a subclass of `People`).
- It keeps a super-property snapshot: it reads `getSuperProperties()` at start, then updates
  the snapshot on register, register once, unregister, clear, and reset.
- It caches the distinct id: it reads `getDistinctId()` at start, sets it on `identify`, and
  reads it again after `reset`.
- It records synchronously, so the record order is the call order.
- It registers the service extensions once per isolate. A second recorder replaces the first.

## Limits

- The tab shows what the app passes to the SDK, plus super properties and the distinct id.
  It does not show properties that the native SDK adds later (`$os`, `$model`, and others).
- It cannot confirm that Mixpanel accepted a batch. Use **Flush** to force a send.
- Exported files can contain personal data from the test account. Keep them local.

## Out of scope

- A proxy that captures the native HTTP requests.
- Web and desktop platforms for the recorder (the protocol works there, but it is not tested).
