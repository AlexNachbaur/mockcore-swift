import Foundation
import MockCore
import NIOCore
import NIOWebSocket
import Testing

@testable import MockCoreTransport

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Echoes request details — including the body — so tests can assert what the host delivered.
private struct BodyEchoService: MockService {
    let name = "BodyEcho"

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/echo"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        let body: MockValue = [
            "method": .string(request.method),
            "body": .string(String(decoding: request.body, as: UTF8.self)),
            "contentType": .string(request.header("Content-Type") ?? ""),
        ]
        return (try? .json(body)) ?? MockResponse(status: 500)
    }
}

/// Returns a fixed custom status, headers, and body.
private struct TeapotService: MockService {
    let name = "Teapot"

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/teapot"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        MockResponse(
            status: 418,
            headers: [("X-Custom", "yes"), ("Location", "/kettle")],
            body: Data("short and stout".utf8)
        )
    }
}

/// A WebSocket echo service negotiating the `wsproto` subprotocol.
private struct WSEchoService: MockService {
    let name = "WSEcho"

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/ws"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        MockResponse(status: 400, body: Data("WebSocket only".utf8))
    }

    func webSocketUpgrade(for request: MockRequest) -> MockWebSocketUpgrade? {
        guard request.path == "/ws" else { return nil }
        return MockWebSocketUpgrade(subprotocol: "wsproto") {
            TextEchoHandler()
        }
    }
}

/// Echoes every text frame back. `@unchecked Sendable`: state-free, event-loop confined.
private final class TextEchoHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .text else { return }
        var buffer = context.channel.allocator.buffer(capacity: frame.unmaskedData.readableBytes)
        var unmasked = frame.unmaskedData
        buffer.writeBuffer(&unmasked)
        context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: buffer)), promise: nil)
    }
}

@Suite struct TransportBehaviorTests {
    @Test func requestBodiesReachTheService() async throws {
        let host = try await MockHost.start { BodyEchoService() }
        var request = URLRequest(url: try #require(URL(string: "/echo", relativeTo: host.url)))
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"hello": "world"}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        let body = try MockValue.fromJSONData(data)
        #expect(body["method"] == .string("POST"))
        #expect(body["body"] == .string(#"{"hello": "world"}"#))
        #expect(body["contentType"] == .string("application/json"))
        try await host.stop()
    }

    @Test func customStatusAndHeadersPassThrough() async throws {
        let host = try await MockHost.start { TeapotService() }
        let (data, response) = try await URLSession.shared.data(
            from: try #require(URL(string: "/teapot", relativeTo: host.url)))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 418)
        #expect(http.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(http.value(forHTTPHeaderField: "Location") == "/kettle")
        #expect(String(decoding: data, as: UTF8.self) == "short and stout")
        try await host.stop()
    }

    @Test func headRequestsGetHeadersButNoBody() async throws {
        let host = try await MockHost.start { TeapotService() }
        var request = URLRequest(url: try #require(URL(string: "/teapot", relativeTo: host.url)))
        request.httpMethod = "HEAD"
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 418)
        #expect(http.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(data.isEmpty)
        try await host.stop()
    }

    @Test func asyncThrowingBuilderConstructsServicesInline() async throws {
        func makeService() async throws -> some MockService {
            TeapotService()
        }
        let host = try await MockHost.start {
            try await makeService()
        }
        let (_, response) = try await URLSession.shared.data(
            from: try #require(URL(string: "/teapot", relativeTo: host.url)))
        #expect((response as? HTTPURLResponse)?.statusCode == 418)
        try await host.stop()
    }

    @Test func webSocketUpgradeEchoesAnExactlyOfferedSubprotocol() async throws {
        let host = try await MockHost.start { WSEchoService() }
        let url = try #require(URL(string: "/ws", relativeTo: host.webSocketURL)).absoluteURL
        let task = URLSession.shared.webSocketTask(with: url, protocols: ["wsproto"])
        task.resume()
        try await task.send(.string("hello"))
        let reply = try await task.receive()
        if case .string(let text) = reply {
            #expect(text == "hello")
        } else {
            Issue.record("Expected a text echo, got \(reply)")
        }
        let http = task.response as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "wsproto")
        task.cancel(with: .normalClosure, reason: nil)
        try await host.stop()
    }

    @Test func subprotocolMatchingComparesWholeTokensNotSubstrings() async throws {
        let host = try await MockHost.start { WSEchoService() }
        let url = try #require(URL(string: "/ws", relativeTo: host.webSocketURL)).absoluteURL
        // "zz-wsproto-zz" contains "wsproto" as a substring; per RFC 6455 the server must NOT
        // select a protocol the client never offered — a substring match here would make
        // URLSession abort the handshake.
        let task = URLSession.shared.webSocketTask(with: url, protocols: ["zz-wsproto-zz"])
        task.resume()
        try await task.send(.string("ping"))
        let reply = try await task.receive()
        if case .string(let text) = reply {
            #expect(text == "ping")
        } else {
            Issue.record("Expected a text echo, got \(reply)")
        }
        let http = task.response as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == nil)
        task.cancel(with: .normalClosure, reason: nil)
        try await host.stop()
    }

    @Test func queryDecodingIsUniformPerParameter() {
        let request = MockRequest(method: "GET", uri: "/x?a=hello%20world&b=1%&c=&d")
        #expect(request.queryValue("a") == "hello world")
        // An invalid escape passes through raw instead of disabling decoding for everything.
        #expect(request.queryValue("b") == "1%")
        #expect(request.queryValue("c") == "")
        #expect(request.queryValue("d") == "")
    }

    @Test func pathDegradesSafelyForMalformedURIs() {
        #expect(MockRequest(method: "GET", uri: "?a=1").path == "")
        #expect(MockRequest(method: "GET", uri: "/plain").path == "/plain")
        #expect(MockRequest(method: "GET", uri: "/x?y=1?z=2").path == "/x")
    }
}
