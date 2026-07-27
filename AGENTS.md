# AGENTS.md

Instructions for AI coding agents working **in this repository**. MockCore is the shared
foundation of the MockCore mocking platform; if you are building a mock server for an app's
tests, you almost certainly want a protocol extension instead —
[mockql-swift](https://github.com/AlexNachbaur/mockql-swift) (GraphQL) or
[mockrest-swift](https://github.com/AlexNachbaur/mockrest-swift) (REST).

## Build, test, lint

```sh
swift build
swift test
swift format lint --strict --recursive Sources Tests Package.swift
swift package generate-documentation --target MockCore --target MockCoreTransport   # docs must build clean
```

All four must pass before any commit. The documentation build is deliberately a **local** step:
CI does not run it, so a DocC regression will only ever be caught here.

CI builds and tests on macOS, an iOS simulator, Linux (`swift:6.3` container), Windows, and an
Android emulator, and must pass on all five. Do not introduce Apple-only framework imports, and
stick to Foundation APIs that swift-corelibs-foundation also provides.

## Architecture (settled decisions — do not relitigate)

- Two modules: `MockCore` (portable — **never import NIO here**) and `MockCoreTransport`
  (SwiftNIO `MockHost` + the `MockService` seam).
- Protocol-neutrality is the admission test: nothing in this package may know about GraphQL
  SDL, OpenAPI, or any other schema language. Schema-specific validation lives in the
  extensions.
- Routing is `claims(_:) -> Bool`, first match in registration order. One shared `StateStore`
  across services is the default composition model (`StateStore.merge` exists for a second
  service's seed).
- Diagnostics are a product feature: every user-facing error is a `MockError` with a source
  name/location or document path, plus `Suggestion` "did you mean" clauses for plausible typos.
  Never regress an error message.
- Dependencies are fixed: Yams (`MockCore`), SwiftNIO (`MockCoreTransport`), swift-docc-plugin
  (build-time). Adding any other dependency requires asking the maintainer first.

## Downstream compatibility

mockql-swift and mockrest-swift build against tagged releases of this package, and MockQL's
public API relies on re-exports (`GraphQLValue = MockValue`, `MockQLError = MockError`).
Renaming or removing public symbols here breaks them — check both consumers before changing
public API, and call out coordinated releases in the PR.

## Code style (enforced)

- swift-format with the checked-in `.swift-format`: 120 columns, 4-space indent.
- No force unwraps anywhere (tests use `try #require(...)`); no `DispatchQueue` — Swift
  concurrency only; prefer value types.
- Never use caseless enums as namespaces; use structs with static members.
- Swift Testing (`import Testing`) for all tests, never XCTest.
- Every public symbol gets a doc comment; DocC must build with zero warnings.

## Testing rules

- Everything requires unit tests (`Tests/MockCoreTests`); transport behavior is tested over
  real HTTP with stub services in `Tests/MockCoreTransportTests`.
- Stop `MockHost`s explicitly at the end of a test (`try await host.stop()`) — never in a
  detached `Task` from `defer`, which races process teardown.
- Update `CHANGELOG.md` (Unreleased section) for user-visible changes.
