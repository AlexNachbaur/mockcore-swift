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
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(services: [any MockService]) {
        self.services = services
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
    }

    private func route(head: HTTPRequestHead, body: ByteBuffer?, channel: Channel) {
        let responseContext = ResponseContext(version: head.version, keepAlive: head.isKeepAlive)
        let request = MockRequest(
            method: head.method.rawValue,
            uri: head.uri,
            headers: head.headers.map { ($0.name, $0.value) },
            body: body.map { Data($0.readableBytesView) } ?? Data()
        )
        guard let service = services.first(where: { $0.claims(request) }) else {
            if request.method == "GET", request.path == "/health" {
                Self.send(MockResponse.text("ok"), response: responseContext, channel: channel)
                return
            }
            let notFound = Self.unclaimedResponse(for: request, services: services)
            Self.send(notFound, response: responseContext, channel: channel)
            return
        }
        Task {
            let response = await service.respond(to: request)
            Self.send(response, response: responseContext, channel: channel)
        }
    }

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
    private static func send(_ mockResponse: MockResponse, response: ResponseContext, channel: Channel) {
        var headers = HTTPHeaders()
        for (name, value) in mockResponse.headers {
            headers.add(name: name, value: value)
        }
        headers.replaceOrAdd(name: "Content-Length", value: String(mockResponse.body.count))
        if !response.keepAlive {
            headers.add(name: "Connection", value: "close")
        }
        let status = HTTPResponseStatus(statusCode: mockResponse.status)
        let responseHead = HTTPResponseHead(version: response.version, status: status, headers: headers)
        var buffer = channel.allocator.buffer(capacity: mockResponse.body.count)
        buffer.writeBytes(mockResponse.body)
        channel.write(HTTPServerResponsePart.head(responseHead), promise: nil)
        channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        let promise: EventLoopPromise<Void>? = response.keepAlive ? nil : channel.eventLoop.makePromise()
        if let promise {
            promise.futureResult.whenComplete { _ in
                channel.close(promise: nil)
            }
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: promise)
    }
}
