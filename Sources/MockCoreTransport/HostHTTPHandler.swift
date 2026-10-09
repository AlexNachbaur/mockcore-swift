import Foundation
import MockCore
import NIOCore
import NIOHTTP1

/// Routes each complete HTTP request to the first registered service that claims it.
///
/// The host also answers `GET /health` (for readiness probes) when no service claims it, and
/// turns unclaimed requests into a 404 that names the registered services — a diagnostic, not
/// a mystery.
///
/// `@unchecked Sendable`: mutable state is confined to the channel's event loop, per NIO's
/// channel-handler threading model.
final class HostHTTPHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let services: [any MockService]
    private let tracker: RequestTracker
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(services: [any MockService], tracker: RequestTracker) {
        self.services = services
        self.tracker = tracker
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var chunk):
            bodyBuffer?.writeBuffer(&chunk)
        case .end:
            guard let head = requestHead else { return }
            let body = bodyBuffer
            requestHead = nil
            bodyBuffer = nil
            route(head: head, body: body, channel: context.channel)
        }
    }

    /// The Sendable subset of a request head needed to write a response.
    private struct ResponseContext: Sendable {
        let version: HTTPVersion
        let keepAlive: Bool
        let isHEAD: Bool

        /// The same context, but closing the connection once the response is written.
        var closingConnection: ResponseContext {
            ResponseContext(version: version, keepAlive: false, isHEAD: isHEAD)
        }
    }

    private func route(head: HTTPRequestHead, body: ByteBuffer?, channel: Channel) {
        let responseContext = ResponseContext(
            version: head.version,
            keepAlive: head.isKeepAlive,
            isHEAD: head.method == .HEAD
        )
        let request = MockRequest(
            method: head.method.rawValue,
            uri: head.uri,
            headers: head.headers.map { ($0.name, $0.value) },
            body: body.map { Data($0.readableBytesView) } ?? Data()
        )
        guard let service = services.first(where: { $0.claims(request) }) else {
            // HEAD is answered too: readiness probes commonly use it, and `send` already
            // suppresses the body for HEAD.
            if request.method == "GET" || request.method == "HEAD", request.path == "/health" {
                Self.send(MockResponse.text("ok"), response: responseContext, channel: channel)
                return
            }
            let notFound = Self.unclaimedResponse(for: request, services: services)
            Self.send(notFound, response: responseContext, channel: channel)
            return
        }
        let accepted = tracker.run {
            let response = await service.respond(to: request)
            Self.send(response, response: responseContext, channel: channel)
        }
        if !accepted {
            // The host is stopping and its services are about to be (or already are) shut
            // down. Answer here rather than hand a request to a service past its `shutdown()`.
            Self.send(Self.stoppingResponse, response: responseContext.closingConnection, channel: channel)
        }
    }

    /// The 503 for a request that arrives on an open connection after the host began stopping.
    private static let stoppingResponse = MockResponse(
        status: 503,
        headers: [("Content-Type", "text/plain")],
        body: Data("The mock host is stopping".utf8)
    )

    /// The 404 for a request no service claims: names what is registered so a typo'd path is
    /// diagnosable from the response alone.
    private static func unclaimedResponse(for request: MockRequest, services: [any MockService]) -> MockResponse {
        let names = services.map(\.name).joined(separator: ", ")
        let message = "No registered mock service claims \(request.method) \(request.path) (registered: \(names))"
        let body: MockValue = ["error": .string(message)]
        return (try? MockResponse.json(body, status: 404))
            ?? MockResponse(status: 404, body: Data(message.utf8))
    }

    /// Writes a complete response. Safe to call from any thread; NIO serializes channel writes.
    ///
    /// Statuses that forbid a message body (1xx/204/304) and HEAD responses write headers only —
    /// stray body bytes would desynchronize a keep-alive connection.
    private static func send(_ mockResponse: MockResponse, response: ResponseContext, channel: Channel) {
        var headers = HTTPHeaders()
        for (name, value) in mockResponse.headers {
            headers.add(name: name, value: value)
        }
        let bodyForbidden =
            mockResponse.status == 204 || mockResponse.status == 304
            || (100..<200).contains(mockResponse.status)
        if !bodyForbidden {
            // HEAD keeps the Content-Length the corresponding GET would have had.
            headers.replaceOrAdd(name: "Content-Length", value: String(mockResponse.body.count))
        }
        if !response.keepAlive {
            headers.add(name: "Connection", value: "close")
        }
        let status = HTTPResponseStatus(statusCode: mockResponse.status)
        let responseHead = HTTPResponseHead(version: response.version, status: status, headers: headers)
        channel.write(HTTPServerResponsePart.head(responseHead), promise: nil)
        if !bodyForbidden, !response.isHEAD {
            var buffer = channel.allocator.buffer(capacity: mockResponse.body.count)
            buffer.writeBytes(mockResponse.body)
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        }
        let promise: EventLoopPromise<Void>? = response.keepAlive ? nil : channel.eventLoop.makePromise()
        if let promise {
            promise.futureResult.whenComplete { _ in
                channel.close(promise: nil)
            }
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: promise)
    }
}
