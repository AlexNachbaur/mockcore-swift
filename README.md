# MockCore

The shared foundation of the MockCore mocking platform: a family of native-Swift mock servers
for local UI-test automation that share one in-memory backend, one data-generation system, and
one HTTP listener — so a single test process can present a virtual server that answers multiple
protocols on one port.

Protocol extensions build on this package and are adopted independently:

- [MockQL](https://github.com/AlexNachbaur/mockql-swift) — GraphQL (queries, mutations,
  `graphql-transport-ws` subscriptions)
- MockREST — REST/OpenAPI (in development)

## Modules

- **`MockCore`** — pure portable Swift (no networking): the `MockValue` dynamic value model, the
  transactional `StateStore`, deterministic data generators (`FieldGenerator`,
  `GeneratorRegistry`, seeded `RandomSource`), seed-document primitives (`SeedSource`), and
  diagnostics (`MockError`, `SourceLocation`, `Suggestion`). Runs anywhere Swift runs: macOS,
  iOS, Linux, Windows, Android.
- **`MockCoreTransport`** — the SwiftNIO HTTP/WebSocket listener (`MockHost`) and the
  `MockService` seam protocol extensions conform to. One host, one port, many protocols.

## Status

Pre-1.0; being extracted from MockQL (see `mockql-swift`'s design docs for the platform
architecture). Public API may change until 1.0.

## License

MIT — see [LICENSE](LICENSE).
