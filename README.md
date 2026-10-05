# ServerBase

Shared server logic for Standalone apps (AppOutlet, PZLServer): the crash-report and support-chat code both servers
used to carry a copy of. Node first; a Swift package may join it at the repo root later.

| Path | What |
|---|---|
| `package.json`, `server/` | **@standalone/server-base**: pure TypeScript, no database tables, routes, queues or environment |

## What's in it

- `crashes/`: MetricKit stack reading and report signatures (`attributedFrames`, `signatureFor`), the dSYM cache
  (`symbolFile`), the `llvm-symbolizer` runner and output parser, Swift demangling, the database-free half of
  symbolication (`resolveFrameGroup`, `crashTitle`, `symbolicationState`), the dSYM upload headers
  (`parseSymbolUpload`) and a `ConcurrencyLimiter`.
- `support/`: the JPEG attachment validator, the message input schema and its submission hash, and `AttemptWindow`, an
  in-memory rate limit.
- `http/`: `bearerMatches`, a constant-time bearer token check.

## Using it

Node: `"@standalone/server-base": "github:bengottlieb/ServerBase#v0.1.0"`, built on install by `prepare` (the build
image needs `git`). `zod` is a peer dependency; `swift-demangle-wasm` comes with the package.

App-specific values are parameters, never defaults: the bundle id → binary map (`AppBinaries`), the symbol upload
header prefix, the cache directory, the symbolizer path, rate-limit sizes. Tests: `npm test`.
