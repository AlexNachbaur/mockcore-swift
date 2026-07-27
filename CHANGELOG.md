# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[0.1.0]: https://github.com/AlexNachbaur/mockcore-swift/releases/tag/0.1.0
