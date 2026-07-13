import NIOCore

/// A mockable protocol handler that a ``MockHost`` can serve.
///
/// REST and GraphQL are the first two conformers; any protocol that maps onto HTTP requests
/// (or a WebSocket upgrade) can be added by a third party without changes to MockCore. Services
/// registered on one host typically share a `StateStore` and `GeneratorRegistry`, so a mutation
/// performed through one protocol is visible to queries made through another.
public protocol MockService: Sendable {
    /// Human-readable name for diagnostics and startup logging (e.g. `"MockREST"`).
    var name: String { get }

    /// Whether this service claims the request. The host asks registered services in
    /// registration order and routes to the first that returns `true`; registration order is
    /// therefore the user's precedence lever.
    func claims(_ request: MockRequest) -> Bool

    /// Produces the response for a claimed request.
    func respond(to request: MockRequest) async -> MockResponse

    /// How to handle a WebSocket upgrade for a request this service wants, or `nil` when the
    /// service does not speak WebSocket at that path. Defaults to `nil`; REST services never
    /// implement this, GraphQL uses it for `graphql-transport-ws` subscriptions.
    func webSocketUpgrade(for request: MockRequest) -> MockWebSocketUpgrade?

    /// Called once, in registration order, before the host starts accepting connections.
    /// Services do fail-fast validation here (or earlier, at construction). Defaults to a no-op.
    func willStart() async throws

    /// Called on host shutdown to release resources and end any streams. Defaults to a no-op.
    func shutdown() async
}

extension MockService {
    public func webSocketUpgrade(for request: MockRequest) -> MockWebSocketUpgrade? {
        nil
    }

    public func willStart() async throws {}

    public func shutdown() async {}
}

/// A service's answer to a WebSocket upgrade request: which subprotocol to negotiate and the
/// channel handler that will speak the upgraded socket.
///
/// This seam is NIO-level by design for now — every current transport is SwiftNIO — and may be
/// abstracted before 1.0 if a non-NIO host appears.
public struct MockWebSocketUpgrade: Sendable {
    /// The WebSocket subprotocol to negotiate (e.g. `"graphql-transport-ws"`), echoed in the
    /// `Sec-WebSocket-Protocol` response header when the client requested it; `nil` to
    /// negotiate none.
    public let subprotocol: String?
    /// Creates the channel handler installed on the upgraded connection.
    public let makeHandler: @Sendable () -> any ChannelHandler & Sendable

    /// Creates an upgrade description.
    public init(subprotocol: String? = nil, makeHandler: @escaping @Sendable () -> any ChannelHandler & Sendable) {
        self.subprotocol = subprotocol
        self.makeHandler = makeHandler
    }
}

/// Collects the services registered on a ``MockHost`` in declaration order.
@resultBuilder
public struct MockServiceBuilder {
    public static func buildBlock(_ services: any MockService...) -> [any MockService] {
        services
    }

    public static func buildOptional(_ services: [any MockService]?) -> [any MockService] {
        services ?? []
    }

    public static func buildEither(first services: [any MockService]) -> [any MockService] {
        services
    }

    public static func buildEither(second services: [any MockService]) -> [any MockService] {
        services
    }
}
