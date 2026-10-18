# Contributing to MockCore

Thanks for your interest in contributing! MockCore is the shared foundation of a young platform
and is moving quickly, so this guide is short — when in doubt, open an issue and ask.

## What lives here (and what doesn't)

MockCore is the **protocol-neutral** foundation: the `MockValue` model, the `StateStore`, data
generators, seed primitives, diagnostics, and the `MockHost`/`MockService` transport seam.
Anything specific to one protocol belongs in that protocol's extension package instead:

- GraphQL → [mockql-swift](https://github.com/AlexNachbaur/mockql-swift)
- REST/OpenAPI → [mockrest-swift](https://github.com/AlexNachbaur/mockrest-swift)

The test for "does this belong in MockCore?" is: *would every protocol extension want it, with
no knowledge of any particular schema language?*

## Getting started

1. Install a **Swift 6.3** toolchain — Xcode 26.5+ on macOS, a [swift.org](https://swift.org/install/)
   toolchain on Linux or Windows, or the `swift:6.3` Docker image (which is what CI uses).
2. Fork and clone the repository.
3. Build and test from the command line:

   ```sh
   swift build
   swift test
   ```

   On macOS you can also open `Package.swift` in Xcode 26.5 or later.

Dependencies are Yams (in `MockCore`) and SwiftNIO (in `MockCoreTransport` only — `MockCore`
must stay NIO-free and portable).

## Reporting bugs and requesting features

- Search [existing issues](https://github.com/AlexNachbaur/mockcore-swift/issues) first.
- Use the issue templates — a minimal reproduction makes bugs dramatically faster to fix.
- For anything security-sensitive, **do not open a public issue** — see [SECURITY.md](SECURITY.md).

## Code style

Formatting is enforced by `swift-format` using the checked-in [.swift-format](.swift-format)
configuration. CI will fail on lint violations, so run this before pushing:

```sh
swift format lint --strict --recursive Sources Tests Package.swift
```

Beyond formatting, the project follows these rules:

- **120-character line length, 4-space indentation.**
- **No force unwraps** (`!`) in production code.
- **No `DispatchQueue`** — use Swift concurrency (`async`/`await`, actors, structured tasks).
- **Prefer value types** (structs, enums with cases) over reference types.
- **Never use caseless enums as namespaces.** Enums are for enumerated values only. For
  singletons or groupings of static members, use a `struct` with static properties or a
  `final class` with `static let shared`.
- **Error messages are a product feature.** Every user-facing error carries a source name,
  location, or document path, and a "did you mean" suggestion where a typo is plausible. Never
  regress diagnostic quality.
- **Stay cross-platform.** `MockCore` supports macOS, iOS, Linux, Windows, and Android. Don't
  import Apple-only frameworks, and stick to Foundation APIs available in
  swift-corelibs-foundation. CI builds and tests on macOS, an iOS simulator, Linux, Windows,
  and an Android emulator, and must pass on all five.

## Compatibility responsibilities

MockCore sits underneath the protocol extensions, so changes here can break them. For any
change to public API, build and test `mockql-swift` and `mockrest-swift` against your branch
(both resolve MockCore by version; a local path override or `swift package edit` works for
development) and call out anything that needs a coordinated release in the PR description.

## Pull requests

- Branch from `main`; keep PRs focused on a single change.
- Add or update tests for any behavioral change.
- Update documentation (README, doc comments, DocC) when the public API changes.
- Note user-visible changes under the **Unreleased** heading in [CHANGELOG.md](CHANGELOG.md).
- Make sure `swift build`, `swift test`, and the lint command above all pass locally.

While the project is pre-1.0, the public API may change without deprecation cycles, but each
breaking change should be called out in the changelog.

## Design discussions

Larger changes (the `MockService` seam, the state model, the transport) should start as an
issue describing the problem and the proposed approach before any code is written. The platform
design documents currently live in
[mockrest-swift/docs/design](https://github.com/AlexNachbaur/mockrest-swift/tree/main/docs/design).

## Code of conduct

All participation in this project is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).
