# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`MockHost.stop()` is idempotent.** A second call used to hang forever: it scheduled work on
  an event loop the first call had already shut down. Every call now awaits one shared
  shutdown and reports its outcome, so `stop()` in both a test body and a teardown is safe.
- **Shutdown no longer strands in-flight requests.** Services were shut down while the listener
  was still accepting, and requests already being handled were abandoned — the client saw a
  dropped connection. The listener now closes first, in-flight requests get a grace period to
  answer (then are cancelled, not dropped), and only then are services shut down. A request
  arriving on an open connection after `stop` began gets a `503` rather than reaching a service
  past its `shutdown()`. The event-loop group is released even when closing the listener fails.
- **`if`, `if`/`else`, `switch`, and `for` now compile inside `MockHost.start { … }`.**
  `MockServiceBuilder` declared the optional/either hooks but its `buildBlock` could not accept
  what they returned, so any conditional service was a compile error.
- **`MockHost.start { … }` compiles from a `@MainActor` caller that captures its own state.**
  The builder closure was passed to a nonisolated function, which Swift 6 rejects as a
  potential data race — and `@MainActor` test classes are where XCUITest setup code lives. The
  builder overloads now run on the caller's actor (`isolation: … = #isolation`).
- **IPv6 hosts work.** `MockHost.start(host: "::1")` bound the port and then threw "Cannot form
  host URL"; the literal is now bracketed in `url` and `webSocketURL`.
- `HEAD /health` answers `200` like `GET /health` instead of `404`.
- **YAML errors carry a real `location`.** The line and column were only ever embedded in the
  message text, so `MockError.location` was always `nil` for a malformed document and the
  position printed in Yams' format rather than next to the source name. The offending line and
  caret are kept.
- **`YAMLDecoding.decode(_:sourceName:category:)` honors `category` for every error.** A
  non-string mapping key or unsupported construct was always reported as a *seed* problem —
  including when MockREST was decoding an OpenAPI spec.
- **Invalid JSON seeds say what is wrong.** The message was Foundation's generic "The data
  couldn't be read because it isn't in the correct format"; it now carries the parser's own
  account (on Apple platforms, the unexpected character with its line and column).
- **"Did you mean" suggestions are deterministic.** Equally close candidates resolved by
  iteration order, and callers pass dictionary keys — so the same typo could be answered with
  a different suggestion on each run. Ties now resolve alphabetically, and a case-only match
  always wins.
- `MockRequest.path` no longer includes a `#fragment`, and reduces an absolute-form request
  target (`GET http://host/path`) to its path.

### Changed

- **Field-name inference matches whole words, not substrings.** `updated`, `candidate`, and
  `lifetime` were generated as timestamps, `hourly` and `blinking` as URLs, and `title` and
  `filename` as people's names. Names are now split at camelCase humps, underscores, hyphens,
  and digits, and a rule fires only on a word match (`createdAt`, `created_at`, `avatarURL`).
  `title` is no longer treated as a person's name. Plurals match their singular (`emails`,
  `avatarURLs`), and `nickname` still reads as a name. **Generated values for fields that only
  matched by substring will differ from 0.1.2**; bind a generator explicitly to pin a shape.
- `MockHost.stop(gracePeriod:)` never waits forever: a handler that ignores cancellation — or
  that is itself awaiting `stop()` — is abandoned after a second grace period instead of
  deadlocking the shutdown. A WebSocket upgrade arriving once shutdown has begun is declined
  (the HTTP path answers 503), so no socket is handed to a service about to be shut down.
- `MockError` conforms to `LocalizedError`, so `localizedDescription` — what XCTest failures
  and most logging print — is the full diagnostic instead of "The operation couldn't be
  completed".
- `StateStore.withMutationState(_:)` is `@discardableResult`: a handler whose last expression
  is an `insert` no longer warns at every call site that ignores it.

### Added

- `StateStore.transaction(_:)` — runs a transactional mutation like `withMutationState(_:)`
  and also returns the `StoreData` it committed. A protocol extension resolving a mutation's
  payload (a GraphQL mutation selection, a REST `201` body) previously had to take a second
  `snapshot()` after the transaction, and a concurrent mutation from any service sharing the
  store could land in between — so the payload could describe state the mutation never saw.
  `withMutationState(_:)` is now implemented on top of it and is unchanged for callers.
- `MockHost.withRunning(host:port:services:isolation:_:)` — starts a host, runs a body, and
  stops the host on every exit path. A test that throws past a trailing `stop()` otherwise leaks the port
  and its event-loop thread for the rest of the process.
- `MockHost.stop(gracePeriod:)` — how long in-flight requests may run before being cancelled
  (default 2 seconds).
- `MockServiceBuilder` accepts an array expression, splicing pre-built services in place.

## [0.1.2] - 2026-07-27

### Changed

- **Minimum toolchain is now Swift 6.3** (`swift-tools-version: 6.3`, was 6.1). This aligns
  every package in the platform on one toolchain: the Swift SDK for Android starts at 6.3, and
  `securestore-swift` already required it. Consumers on Swift 6.1 or 6.2 must upgrade.
- CI now builds and tests on **macOS, an iOS simulator, Linux, Windows, and an Android
  emulator**. Windows and iOS were previously untested; the README's claim that SwiftNIO is
  unavailable on Windows was out of date — NIOPosix has carried a Windows port since well
  before 2.101, and `MockCoreTransport` builds and runs there.
- The lint job now gates every other job, and the Linux job gates the expensive runners, so a
  formatting or compile failure is caught before macOS/Windows/Android minutes are spent.
- The documentation build no longer runs in CI. `swift package generate-documentation` remains
  a required local pre-commit step (see AGENTS.md and CONTRIBUTING.md).
- Dependabot now watches the `github-actions` ecosystem in addition to `swift`, grouped into a
  single weekly PR.

## [0.1.1] - 2026-07-17

### Fixed

- WebSocket subprotocol negotiation compares whole tokens per RFC 6455; substring matching
  could echo a protocol the client never offered, and compliant clients abort that handshake.
- `MockRequest.queryItems` percent-decodes each parameter independently, so one malformed
  component cannot disable decoding for the rest; path parsing degrades safely for malformed
  URIs.
- `StoreData.insert` coerces integer ids instead of discarding them, and `StateStore.merge`
  keeps records missing from the order index.
- `HEAD` responses and body-forbidding statuses (1xx/204/304) no longer write body bytes that
  would desynchronize a keep-alive connection.
- `MockHost.start` shuts down already-started services when startup fails partway.
- Timestamp inference requires `At`/`_at` suffix evidence.

### Added

- An `async throws` builder overload of `MockHost.start`, so engines can be constructed inline.

## [0.1.0] - 2026-07-12

### Added

- Initial extraction of the protocol-neutral foundation from
  [mockql-swift](https://github.com/AlexNachbaur/mockql-swift):
  - `MockValue` — the dynamic value model (formerly MockQL's `GraphQLValue`).
  - `StateStore`, `MutationState`, `StoreData` — the transactional in-memory backend.
  - `FieldGenerator`, `GeneratorContext`, `GeneratorRegistry`, `RandomSource` — deterministic
    data generation.
  - `SeedSource` and YAML/JSON seed-document decoding (schema validation stays with each
    protocol extension).
  - Diagnostics: `MockError` (formerly `MockQLError`), `SourceLocation`, `Suggestion`.
- `MockCoreTransport`: the platform's shared SwiftNIO listener and extension seam, generalized
  from MockQL's transport:
  - `MockHost` — one port, many protocols: binds localhost, runs fail-fast `willStart()`
    validation, and routes each request to the first registered service that claims it.
    Unclaimed requests get a diagnostic 404 naming the registered services; `GET /health`
    answers `ok` when unclaimed.
  - `MockService` — the extension seam: `claims(_:)`/`respond(to:)` plus optional
    `webSocketUpgrade(for:)` (used by GraphQL subscriptions), `willStart()`, and `shutdown()`.
  - `MockRequest`/`MockResponse` — the neutral request/response pair, with query/header
    conveniences and JSON/text response builders.

[Unreleased]: https://github.com/AlexNachbaur/mockcore-swift/compare/0.1.2...HEAD
[0.1.2]: https://github.com/AlexNachbaur/mockcore-swift/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/AlexNachbaur/mockcore-swift/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/AlexNachbaur/mockcore-swift/releases/tag/0.1.0
