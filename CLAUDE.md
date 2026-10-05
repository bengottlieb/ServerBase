# ServerBase

Shared library for Standalone apps, in two halves: `@standalone/server-base` (Node, `server/`), the crash-report and
support-chat logic AppOutlet and PZLServer share, and the **ServerBase** Swift package (root `Package.swift`,
`Sources/`, `Tests/`), the client side StoreKeeper and PZL share. Node is pure logic only: no database tables, routes,
queues or env access. Those stay in each server, which passes configuration in.

**Rule:** nothing app-specific lives here, in either half: no bundle ids, App Group ids, binary names, header prefixes
(`x-<app>-*`), Info.plist key names, app or server names, URLs or endpoint paths (tests too: use `example` values).
Anything like that is a parameter. When the apps or servers legitimately differ, add a parameter; don't fork.

## Layout

- `server/src/crashes`, `support`, `http`; everything is exported from `server/src/index.ts`.
- `server/test`: vitest, no database. A test that needs a real `llvm-symbolizer` or a large fixture skips itself when
  it's unavailable (none does today: the runner test drives a fake script).
- Node formatting: prettier (`npm run format`), tabs, single quotes, no semicolons, 120 columns.
- Swift products: `CrashReporting` (app), `CrashReporterEngine` (crash-reporter extension), `SupportChat` (app). The
  internal `CrashReportCore` target (Foundation only) holds `CrashReportLocations`, which both crash products re-export.
- `CrashReporterEngine` is the only thing the ExtensionKit extension links. Keep it to `CrashReportCore` and
  `NewsHelicopterExtension`, extension-safe API only (6 MB budget). It can't carry `-application-extension` (SwiftPM
  refuses unsafe flags in remote packages); check it with
  `swift build --target CrashReporterEngine -Xswiftc -application-extension`.
- Swift conventions: Swift 6, Swift Testing, async/await (no GCD), `@Observable`, files around 100 lines, code inside
  `#if` indented one extra tab, logging through Chronicle.

## Build & Run

- Node: `npm install`, `npm test`, `npm run typecheck`, `npm run build` (`prepare` builds on install from GitHub).
- Swift: `swift build`, `swift test`; for iOS,
  `xcodebuild -scheme ServerBase-Package -destination 'generic/platform=iOS Simulator' build`.
- Release: bump `version` in package.json, commit, tag `vX.Y.Z`, push with tags. Servers change their `#vX.Y.Z` and apps
  their `from:`; one tag covers both halves.
- Don't put `kysely`/`fastify` code here until a database-bound part is deliberately moved; they'd be peer dependencies.
