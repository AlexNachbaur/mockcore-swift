# ``MockCore``

The portable foundation of the MockCore mocking platform: the shared value model, state store,
data generators, seed primitives, and diagnostics — no networking dependencies.

## Overview

`MockCore` is what the protocol extensions (MockQL for GraphQL, MockREST for REST) have in
common. Values flow through the platform as ``MockValue`` trees; records live in an
actor-guarded ``StateStore`` with transactional writes; fields nobody seeded are filled by
deterministic generators; and every user-facing error is a ``MockError`` carrying a source
location or document path and, where a typo is plausible, a "did you mean" suggestion.

Because several services can share one ``StateStore``, a mutation performed through one
protocol is visible to queries made through another — that sharing is the platform's headline
feature, and this module is where it lives.

```swift
import MockCore

let store = StateStore()
await store.withMutationState { state in
    state.insert("User", ["id": "u1", "name": "Avery Quinn"])
}
let user = await store.record(type: "User", id: "u1")
```

`MockCore` never imports SwiftNIO; the HTTP listener and the service seam live in the
`MockCoreTransport` module so this one stays portable to every platform Swift runs on.

## Topics

### Values

- ``MockValue``

### State

- ``StateStore``
- ``MutationState``
- ``StoreData``

### Data generation

- ``FieldGenerator``
- ``GeneratorContext``
- ``GeneratorRegistry``
- ``RandomSource``

### Seeding

- ``SeedSource``
- ``YAMLDecoding``

### Diagnostics

- ``MockError``
- ``SourceLocation``
- ``Suggestion``
