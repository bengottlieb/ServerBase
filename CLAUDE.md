# ServerBase

Shared server library for Standalone apps: `@standalone/server-base` (Node, `server/`). It holds the crash-report and
support-chat logic that AppOutlet and PZLServer share. Pure logic only: no database tables, routes, queues or env
access. Those stay in each server, which passes configuration in.

**Rule:** nothing app-specific lives here: no bundle ids, binary names, header prefixes (`x-<app>-*`), app names or
URLs. Anything like that is a parameter. When the two servers legitimately differ, add a parameter; don't fork.

## Layout

- `server/src/crashes`, `support`, `http`; everything is exported from `server/src/index.ts`.
- `server/test`: vitest, no database. A test that needs a real `llvm-symbolizer` or a large fixture skips itself when
  it's unavailable (none does today: the runner test drives a fake script).
- Formatting: prettier (`npm run format`), tabs, single quotes, no semicolons, 120 columns.

## Build & Run

- `npm install`, `npm test`, `npm run typecheck`, `npm run build` (`prepare` builds on install from GitHub).
- Release: bump `version` in package.json, commit, tag `vX.Y.Z`, push with tags; servers change their `#vX.Y.Z`.
- Don't put `kysely`/`fastify` code here until a database-bound part is deliberately moved; they'd be peer dependencies.
