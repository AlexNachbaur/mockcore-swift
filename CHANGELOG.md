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
- `MockCoreTransport` target placeholder; `MockHost` and the `MockService` extension seam land
  in Phase 2 of the extraction plan.
