# ``MockCoreTransport``

The platform's shared HTTP(/WebSocket) listener and the seam protocol extensions plug into:
one host, one port, many protocols.

## Overview

A ``MockHost`` binds a loopback port and serves any number of registered ``MockService``s. For
each request it asks the services ``MockService/claims(_:)`` in registration order and
dispatches to the first match; unclaimed requests get a diagnostic 404 that names the
registered services, and `GET /health` answers `ok` for readiness probes. Every service's
``MockService/willStart()`` runs before the port binds, so a misconfigured server never
accepts a connection.

```swift
let host = try await MockHost.start {
    myRESTService      // claims its spec's paths
    myGraphQLService   // claims POST/GET /graphql
}
app.launchEnvironment["API_BASE_URL"] = host.url.absoluteString
```

Registration order is routing precedence — documented, deterministic, and the user's lever
when two services could claim the same request.

A mock extension is anything conforming to ``MockService``: say whether you want a request,
produce a ``MockResponse``, and optionally join the WebSocket upgrade handshake via
``MockWebSocketUpgrade`` (GraphQL subscriptions use this; REST ignores it). Third parties can
add new protocols without any changes to MockCore.

## Topics

### Hosting

- ``MockHost``

### The extension seam

- ``MockService``
- ``MockServiceBuilder``
- ``MockWebSocketUpgrade``

### Requests and responses

- ``MockRequest``
- ``MockResponse``
