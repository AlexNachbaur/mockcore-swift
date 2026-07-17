import Foundation
import MockCore
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
///     MockREST(spec: .file("api.yaml"))
///     MockGraphQL(schema: .file("shop.graphqls"))
/// }
/// app.launchEnvironment["API_BASE_URL"] = host.url.absoluteString
/// ```
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

    private init(
        services: [any MockService],
        channel: Channel,
        group: MultiThreadedEventLoopGroup,
        port: Int,
        host: String
    ) throws {
        self.services = services
        self.channel = channel
        self.group = group
        self.port = port
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/"
        guard let httpURL = components.url else {
            throw MockError(category: .configuration, message: "Cannot form host URL for host '\(host)'")
        }
        components.scheme = "ws"
        guard let wsURL = components.url else {
            throw MockError(category: .configuration, message: "Cannot form WebSocket URL for host '\(host)'")
        }
        self.url = httpURL
        self.webSocketURL = wsURL
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
    ///   - services: The services to serve, in routing precedence order.
    public static func start(
        host: String = "127.0.0.1",
        port: Int = 0,
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
    public static func start(
        host: String = "127.0.0.1",
        port: Int = 0,
        @MockServiceBuilder services: () async throws -> [any MockService]
    ) async throws -> MockHost {
        try await start(host: host, port: port, services: try await services())
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
                let httpHandler = HostHTTPHandler(services: services)
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
            return try MockHost(services: services, channel: channel, group: group, port: boundPort, host: host)
        } catch {
            for service in services {
                await service.shutdown()
            }
            try? await group.shutdownGracefully()
            throw error
        }
    }

    /// Stops accepting connections, shuts down every service, and releases the port.
    public func stop() async throws {
        for service in services {
            await service.shutdown()
        }
        try await channel.close()
        try await group.shutdownGracefully()
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
