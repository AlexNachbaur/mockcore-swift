import Foundation
import MockCore
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// The shared HTTP(/WebSocket) listener of the MockCore platform.
///
/// A host binds one port and serves any number of registered ``MockService``s — so a single
/// test process can present one virtual server that answers, say, both REST and GraphQL. For
/// each request the host asks the services `claims(_:)` in registration order and dispatches
/// to the first match; unclaimed requests get a 404 that names the registered services.
///
/// ```swift
/// let host = try await MockHost.start {
///     try await MockRESTEngine(spec: .file("api.yaml"), store: store)
///     try await MockQLEngine(schema: .file("shop.graphqls"), store: store)
/// }
/// app.launchEnvironment["API_BASE_URL"] = host.url.absoluteString
/// ```
///
/// A host owns a listening socket and an event-loop thread until ``stop(gracePeriod:)`` is
/// called. Where the host's lifetime is one lexical scope, prefer
/// ``withRunning(host:port:services:isolation:_:)``, which stops it on every exit path.
public final class MockHost: Sendable {
    /// The HTTP base endpoint (`http://127.0.0.1:<port>/`). Services define paths beneath it.
    public let url: URL
    /// The WebSocket base endpoint (`ws://127.0.0.1:<port>/`).
    public let webSocketURL: URL
    /// The port the host is listening on.
    public let port: Int
    /// The registered services, in registration (= routing precedence) order.
    public let services: [any MockService]

    private let channel: Channel
    private let group: MultiThreadedEventLoopGroup
    private let tracker: RequestTracker
    /// The one shutdown every `stop` call shares; `nil` while the host is running.
    private let shutdown = NIOLockedValueBox<Task<Void, any Error>?>(nil)

    private init(
        services: [any MockService],
        channel: Channel,
        group: MultiThreadedEventLoopGroup,
        tracker: RequestTracker,
        port: Int,
        host: String
    ) throws {
        self.services = services
        self.channel = channel
        self.group = group
        self.tracker = tracker
        self.port = port
        self.url = try Self.endpointURL(scheme: "http", host: host, port: port)
        self.webSocketURL = try Self.endpointURL(scheme: "ws", host: host, port: port)
    }

    /// Forms a base endpoint URL for a bound interface.
    ///
    /// An IPv6 literal (`::1`) must be bracketed in a URL authority (RFC 3986 §3.2.2); the
    /// bind address is taken unbracketed, so the brackets are added here.
    static func endpointURL(scheme: String, host: String, port: Int) throws -> URL {
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        guard let url = URL(string: "\(scheme)://\(authority):\(port)/") else {
            throw MockError(category: .configuration, message: "Cannot form \(scheme) URL for host '\(host)'")
        }
        return url
    }

    /// Starts a host serving the given services on localhost.
    ///
    /// Every service's ``MockService/willStart()`` runs (in registration order) before the port
    /// binds, so misconfiguration fails fast and no connection is ever accepted by a
    /// half-validated server.
    ///
    /// - Parameters:
    ///   - host: Interface to bind; loopback by default — mock servers are test tools and
    ///     should not be exposed to real networks.
    ///   - port: Port to bind; `0` picks an ephemeral free port (recommended for parallel
    ///     tests).
    ///   - isolation: The actor the `services` block runs on; the caller's by default, so the
    ///     block can be written inside a `@MainActor` test and capture that test's state.
    ///   - services: The services to serve, in routing precedence order.
    public static func start(
        host: String = "127.0.0.1",
        port: Int = 0,
        isolation: isolated (any Actor)? = #isolation,
        @MockServiceBuilder services: () -> [any MockService]
    ) async throws -> MockHost {
        try await start(host: host, port: port, services: services())
    }

    /// Starts a host whose services are themselves created asynchronously — so engines can be
    /// constructed right inside the block:
    ///
    /// ```swift
    /// let host = try await MockHost.start {
    ///     try await MockRESTEngine(spec: .file("api.yaml"), store: store)
    ///     try await MockQLEngine(schema: .file("shop.graphqls"), store: store)
    /// }
    /// ```
    ///
    /// The block runs on the caller's actor (`isolation` defaults to it), so it can be written
    /// inside a `@MainActor` test and capture that test's state.
    public static func start(
        host: String = "127.0.0.1",
        port: Int = 0,
        isolation: isolated (any Actor)? = #isolation,
        @MockServiceBuilder services: () async throws -> [any MockService]
    ) async throws -> MockHost {
        try await start(host: host, port: port, services: try await services())
    }

    /// Starts a host, runs `body` with it, and stops it on every exit path — including when
    /// `body` throws.
    ///
    /// ```swift
    /// try await MockHost.withRunning(services: [engine]) { host in
    ///     let (data, _) = try await URLSession.shared.data(from: host.url)
    ///     …
    /// }
    /// ```
    ///
    /// Prefer this in tests: a failed expectation that throws past a trailing `stop()` call
    /// otherwise leaks the listening port and its event-loop thread for the rest of the
    /// process. An error thrown by `body` takes precedence over one thrown while stopping.
    ///
    /// - Parameters:
    ///   - host: Interface to bind; loopback by default.
    ///   - port: Port to bind; `0` picks an ephemeral free port.
    ///   - services: The services to serve, in routing precedence order.
    ///   - isolation: The actor `body` runs on; the caller's by default.
    ///   - body: The work to do while the host is serving.
    /// - Returns: Whatever `body` returns.
    public static func withRunning<Result>(
        host: String = "127.0.0.1",
        port: Int = 0,
        services: [any MockService],
        isolation: isolated (any Actor)? = #isolation,
        _ body: (MockHost) async throws -> sending Result
    ) async throws -> sending Result {
        let running = try await start(host: host, port: port, services: services)
        let result: Result
        do {
            result = try await body(running)
        } catch {
            // The body's error is the one worth reporting; a failure to stop afterwards would
            // only mask it.
            try? await running.stop()
            throw error
        }
        try await running.stop()
        return result
    }

    /// Starts a host serving the given services on localhost.
    public static func start(host: String = "127.0.0.1", port: Int = 0, services: [any MockService]) async throws
        -> MockHost
    {
        guard !services.isEmpty else {
            throw MockError(category: .configuration, message: "A MockHost needs at least one registered service")
        }
        // Run startup validation in registration order; if any service refuses to start, shut
        // down the ones that already did so nothing leaks resources.
        var started: [any MockService] = []
        do {
            for service in services {
                try await service.willStart()
                started.append(service)
            }
        } catch {
            for service in started {
                await service.shutdown()
            }
            throw error
        }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let tracker = RequestTracker()
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 20,
            shouldUpgrade: { channel, head in
                let request = MockRequest(head: head)
                guard let upgrade = Self.webSocketUpgrade(for: request, in: services) else {
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                var headers = HTTPHeaders()
                if let subprotocol = upgrade.subprotocol {
                    // RFC 6455 §4.2.2: the server may only select a subprotocol the client
                    // offered, compared as whole tokens — substring matching would echo a
                    // protocol the client never sent and compliant clients abort the handshake.
                    let requested = head.headers[canonicalForm: "Sec-WebSocket-Protocol"]
                    if requested.contains(where: { String($0).caseInsensitiveCompare(subprotocol) == .orderedSame }) {
                        headers.add(name: "Sec-WebSocket-Protocol", value: subprotocol)
                    }
                }
                return channel.eventLoop.makeSucceededFuture(headers)
            },
            upgradePipelineHandler: { channel, head in
                let request = MockRequest(head: head)
                guard let upgrade = Self.webSocketUpgrade(for: request, in: services) else {
                    // Unreachable: shouldUpgrade only accepts requests a service claims.
                    return channel.eventLoop.makeSucceededFuture(())
                }
                return channel.pipeline.addHandler(upgrade.makeHandler())
            }
        )
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = HostHTTPHandler(services: services, tracker: tracker)
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (
                        upgraders: [upgrader],
                        // Once the connection upgrades to WebSocket, the HTTP handler must
                        // leave the pipeline or it would try to decode WebSocket frames.
                        completionHandler: { _ in
                            channel.pipeline.removeHandler(httpHandler, promise: nil)
                        }
                    )
                ).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            guard let boundPort = channel.localAddress?.port else {
                try await channel.close()
                try await group.shutdownGracefully()
                throw MockError(category: .configuration, message: "Host bound without a local address")
            }
            do {
                return try MockHost(
                    services: services,
                    channel: channel,
                    group: group,
                    tracker: tracker,
                    port: boundPort,
                    host: host
                )
            } catch {
                // The port is bound but no host exists to release it.
                try? await channel.close()
                throw error
            }
        } catch {
            for service in services {
                await service.shutdown()
            }
            try? await group.shutdownGracefully()
            throw error
        }
    }

    /// Stops accepting connections, lets in-flight requests finish, shuts down every service,
    /// and releases the port.
    ///
    /// The order is what makes shutdown clean for the client: the listener closes first, so no
    /// request can reach a service after its ``MockService/shutdown()``; requests already being
    /// handled are then given `gracePeriod` to answer before they are cancelled.
    ///
    /// Safe to call more than once and from several tasks: every call awaits the same shutdown
    /// and reports the same outcome.
    ///
    /// - Parameter gracePeriod: How long in-flight requests may keep running before they are
    ///   cancelled. A handler that ignores cancellation delays `stop` until it returns.
    public func stop(gracePeriod: Duration = .seconds(2)) async throws {
        let task = shutdown.withLockedValue { existing in
            if let existing {
                return existing
            }
            let task = Task { try await self.performStop(gracePeriod: gracePeriod) }
            existing = task
            return task
        }
        try await task.value
    }

    private func performStop(gracePeriod: Duration) async throws {
        tracker.stopAccepting()
        var failure: (any Error)?
        do {
            try await channel.close()
        } catch {
            failure = error
        }
        await tracker.drain(gracePeriod: gracePeriod)
        for service in services {
            await service.shutdown()
        }
        // Always reached, so a listener that failed to close cannot also leak the event loop.
        do {
            try await group.shutdownGracefully()
        } catch {
            failure = failure ?? error
        }
        if let failure {
            throw failure
        }
    }

    private static func webSocketUpgrade(
        for request: MockRequest,
        in services: [any MockService]
    ) -> MockWebSocketUpgrade? {
        for service in services {
            if let upgrade = service.webSocketUpgrade(for: request) {
                return upgrade
            }
        }
        return nil
    }
}

extension MockRequest {
    /// Creates a request from an HTTP head (no body), used for upgrade negotiation.
    init(head: HTTPRequestHead) {
        self.init(
            method: head.method.rawValue,
            uri: head.uri,
            headers: head.headers.map { ($0.name, $0.value) }
        )
    }
}
