# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
