# MockCore

[![Build](https://github.com/AlexNachbaur/mockcore-swift/actions/workflows/build.yml/badge.svg)](https://github.com/AlexNachbaur/mockcore-swift/actions/workflows/build.yml)
[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20Linux%20%7C%20Android-blue.svg)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

The shared foundation of a family of native-Swift mock servers for local UI-test automation.

MockCore exists so that a single test process can present **one virtual server** — one port,
one in-memory world — that answers multiple protocols at once. Protocol extensions are
independent packages that plug into it and are adopted separately:

| Extension | Protocol | Status |
|---|---|---|
| [MockQL](https://github.com/AlexNachbaur/mockql-swift) | GraphQL (queries, mutations, `graphql-transport-ws` subscriptions) | Available |
| [MockREST](https://github.com/AlexNachbaur/mockrest-swift) | REST / OpenAPI 3.0–3.1 | Available |

> **Status: pre-1.0.** The platform seam (`MockService`) is validated by two shipping
> extensions, but the API may still evolve before `1.0.0`; breaking changes are called out in
> the [CHANGELOG](CHANGELOG.md).

## One host, many protocols

Each extension works standalone, but the platform's headline feature is composition: register
several services on one `MockHost` and hand them one shared `StateStore`. A mutation performed
through REST is instantly visible to a GraphQL query, and vice versa — because there is only
one world.

```swift
import MockQL
import MockREST

let store = StateStore()
let host = try await MockHost.start {
    try await MockRESTEngine(spec: .file("api.yaml"), seed: .file("world.yaml"), store: store)
    try await MockQLEngine(schema: .file("shop.graphqls"), store: store)
}

app.launchEnvironment["API_BASE_URL"] = host.url.absoluteString   // one URL, both protocols
```

The host asks registered services `claims(_:)` in registration order and routes each request to
the first match; unclaimed requests get a diagnostic 404 that names the registered services.

## Modules

- **`MockCore`** — pure portable Swift (no networking):
  - `MockValue` — the dynamic value tree every extension speaks (seeds, arguments, records,
    responses), with literal conformances, subscripts, and JSON/YAML codecs.
  - `StateStore` / `MutationState` — an actor-guarded in-memory backend with transactional,
    atomically-committed writes; shareable across services.
  - `FieldGenerator` / `GeneratorRegistry` / `RandomSource` — deterministic data generation
    (names, emails, phone numbers, UUIDs, timestamps, …), stable per record + field and
    reproducible from a server seed.
  - `SeedSource` + YAML/JSON decoding — seed-document primitives (schema validation belongs to
    each extension).
  - `MockError` / `SourceLocation` / `Suggestion` — diagnostics with locations, document paths,
    and "did you mean" suggestions.
- **`MockCoreTransport`** — the SwiftNIO listener:
  - `MockHost` — binds a loopback port, runs every service's fail-fast `willStart()` before
    accepting connections, routes requests, answers `GET /health`.
  - `MockService` — the extension seam: `claims(_:)`, `respond(to:)`, and optional hooks for
    WebSocket upgrades, startup validation, and shutdown.
  - `MockRequest` / `MockResponse` — the neutral request/response pair.

## Writing your own extension

A mock extension is any `Sendable` type that can say whether it wants a request and produce a
response. That's the whole seam — MockCore needs no changes to host a new protocol:

```swift
import MockCore
import MockCoreTransport

struct StatusService: MockService {
    let name = "Status"
    let store: StateStore

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/status"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        let count = await store.records(ofType: "User").count
        return (try? .json(["users": .int(count)])) ?? MockResponse(status: 500)
    }
}
```

Conventions the shipping extensions follow (and yours should too):

- **Validate everything at startup** (specs, seeds, configuration) in your initializer or
  `willStart()` — never mid-test. Use `MockError` with paths and `Suggestion` for typos.
- **Speak `MockValue`** for state, and store records as `(type, id)` pairs so cross-protocol
  reference resolution works.
- **Key generators as `"Type.field"`**, where `Type` is your schema's namespace.

## Installation

Add the package (usually to your UI-test target only, via one of the protocol extensions —
depend on MockCore directly only when building a new extension):

```swift
dependencies: [
    .package(url: "https://github.com/AlexNachbaur/mockcore-swift.git", from: "0.1.0")
],
targets: [
    .target(name: "MyMockExtension", dependencies: [
        .product(name: "MockCore", package: "mockcore-swift"),
        .product(name: "MockCoreTransport", package: "mockcore-swift"),
    ])
]
```

## Requirements

- **Swift 6.1+** (strict concurrency).
- Apple platforms: macOS 14+ / iOS 17+ (minimums exist only for Swift concurrency APIs).
- Linux and Android are fully supported and exercised in CI; `MockCore` itself has no
  networking dependency and also builds where SwiftNIO isn't available (e.g. Windows).
- Dependencies: [Yams](https://github.com/jpsim/Yams) (`MockCore`),
  [SwiftNIO](https://github.com/apple/swift-nio) (`MockCoreTransport`).

## Documentation

- [API documentation](https://swiftpackageindex.com/AlexNachbaur/mockcore-swift/documentation)
  (DocC) — the value model, state store, generators, and the hosting/extension seam.
- Platform design documents live in
  [mockrest-swift/docs/design](https://github.com/AlexNachbaur/mockrest-swift/tree/main/docs/design)
  (architecture, extraction plan, REST format).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
