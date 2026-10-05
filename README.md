# ServerBase

Shared server and client logic for Standalone apps: the crash-report and support-chat code AppOutlet and PZLServer
(server side) and StoreKeeper and PZL (app side) each used to carry a copy of. One repo, two halves:

| Path | What |
|---|---|
| `package.json`, `server/` | **@standalone/server-base**: pure TypeScript, no database tables, routes, queues or environment |
| `Package.swift`, `Sources/`, `Tests/` | **ServerBase**, the Swift package: `CrashReporting`, `CrashReporterEngine`, `SupportChat` |

## Server: what's in it

- `crashes/`: MetricKit stack reading and report signatures (`attributedFrames`, `signatureFor`), the dSYM cache
  (`symbolFile`), the `llvm-symbolizer` runner and output parser, Swift demangling, the database-free half of
  symbolication (`resolveFrameGroup`, `crashTitle`, `symbolicationState`), the dSYM upload headers
  (`parseSymbolUpload`) and a `ConcurrencyLimiter`.
- `support/`: the JPEG attachment validator, the message input schema and its submission hash, and `AttemptWindow`, an
  in-memory rate limit.
- `http/`: `bearerMatches`, a constant-time bearer token check.

## Swift: products

iOS 27 / macOS 27, Swift 6.

- **CrashReporting** (the app): `CrashReporter` (`start(_:)`, `flush()`, `setScreen(_:)`, `note(_:)`, and
  `sendSample()` in Debug) subscribes to MetricKit, moves the crash-reporter extension's NewsHelicopter reports onto
  one on-disk queue (`CrashReportQueue`, 50 reports) and uploads them with `CrashReportUploader`. Reports
  (`CrashReport`) keep MetricKit's JSON with exact integers, prune stacks deeper than 48 frames and are built off the
  main thread. `CrashDevice` is a ready-made device description; `CrashDeviceSnapshot` carries it, or any `Encodable`
  the app already describes its devices with.
- **CrashReporterEngine** (the ExtensionKit crash-reporter extension, and nothing else): re-exports
  `NewsHelicopterExtension` and `CrashReportLocations`, and adds `CrashReportLocations.store(keys:)`, the extension's
  report store as its Info.plist names it. **The extension links only this product**: it must stay under 6 MB and
  extension-safe.
- **SupportChat** (over FeedbackKit's `CustomerFeedbackKit`): `SupportChatModel` (one session per account and
  credential; `handlePending()` decides whether a tapped reply opens the conversation), `SupportChatPush` (arrivals and
  the pending tap), `SupportReplyPush` (parses a reply's payload in the server's `Format`) and the
  `SupportReplyTransport` protocol the app implements over its own server client.

`CrashReportLocations` (in both crash products) is the App Group and group-relative directory the extension writes to
and the app reads, plus the Info.plist keys (`InfoKeys`) that name them for the extension.

## Swift: what an app configures

Nothing app-specific has a default. An app passes:

- `CrashReportLocations(appGroup:groupRelativePath:)` and its `InfoKeys(appGroup:directory:)`. The extension's
  Info.plist repeats both under those keys, and the app's own test checks `CrashReportLocations(info:keys:)` against
  its value.
- `CrashReporter.Configuration`:
  - `queueDirectory`;
  - `newsHelicopterDirectory` (`locations.directory`);
  - `bundleID` (defaults to `Bundle.main`'s);
  - `endpoint`, the full crash-report URL (nil holds reports);
  - `device`, a `CrashDeviceSnapshot`, for example from `CrashDevice.current(installID:distribution:)`, whose
    distribution detection is a closure;
  - `authorize`: `CrashReportUploader.bearer { token }`, a signature, or both;
  - `transport`.
- For support chat: a `SupportReplyTransport`, the push `Format` (`container`, `kindKey`, `kind`) and the account id,
  plus a credential when a new token should start a new session.

The extension:

```swift
guard let store = CrashReportLocations.store(keys: .init(appGroup: "MyCrashAppGroup", directory: "MyCrashDirectory")) else { return }
NewsHelicopterReporter(store: store, logSubsystem: Bundle.main.bundleIdentifier ?? "CrashReporter").process(process)
```

## Using it

- Swift: `.package(url: "https://github.com/bengottlieb/ServerBase", from: "0.2.0")`, products `CrashReporting` (app),
  `CrashReporterEngine` (crash-reporter extension), `SupportChat` (app). Tests: `swift test`.
- Node: `"@standalone/server-base": "github:bengottlieb/ServerBase#v0.1.0"`, built on install by `prepare` (the build
  image needs `git`). `zod` is a peer dependency; `swift-demangle-wasm` comes with the package. Tests: `npm test`.

Server-side, app-specific values are parameters too, never defaults: the bundle id → binary map (`AppBinaries`), the
symbol upload header prefix, the cache directory, the symbolizer path, rate-limit sizes.
