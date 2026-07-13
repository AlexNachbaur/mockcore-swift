import Foundation
import MockCore
import Testing

@testable import MockCoreTransport

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A minimal service for exercising the host: claims one path prefix and echoes request
/// details back as JSON.
private struct EchoService: MockService {
    let name: String
    let prefix: String
    let store: StateStore

    func claims(_ request: MockRequest) -> Bool {
        request.path.hasPrefix(prefix)
    }

    func respond(to request: MockRequest) async -> MockResponse {
        await store.withMutationState { state in
            state.insert("Request", ["path": .string(request.path)])
        }
        let count = await store.records(ofType: "Request").count
        let body: MockValue = [
            "service": .string(name),
            "method": .string(request.method),
            "path": .string(request.path),
            "requestCount": .int(count),
        ]
        return (try? .json(body)) ?? MockResponse(status: 500)
    }
}

/// A service whose startup validation always fails, to prove hosts refuse to bind.
private struct MisconfiguredService: MockService {
    let name = "Misconfigured"

    func claims(_ request: MockRequest) -> Bool {
        false
    }

    func respond(to request: MockRequest) async -> MockResponse {
        MockResponse(status: 500)
    }

    func willStart() async throws {
        throw MockError(category: .configuration, message: "intentionally broken")
    }
}

@Suite struct MockHostTests {
    private func get(_ url: URL) async throws -> (status: Int, body: Data) {
        let (data, response) = try await URLSession.shared.data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    @Test func routesToTheFirstClaimingServiceInRegistrationOrder() async throws {
        let store = StateStore()
        let host = try await MockHost.start {
            EchoService(name: "Alpha", prefix: "/alpha", store: store)
            EchoService(name: "Wide", prefix: "/", store: store)
        }

        let alpha = try await get(#require(URL(string: "/alpha/x", relativeTo: host.url)))
        #expect(alpha.status == 200)
        let alphaBody = try MockValue.fromJSONData(alpha.body)
        #expect(alphaBody["service"] == .string("Alpha"))

        let other = try await get(#require(URL(string: "/anything", relativeTo: host.url)))
        let otherBody = try MockValue.fromJSONData(other.body)
        #expect(otherBody["service"] == .string("Wide"))
        try await host.stop()
    }

    @Test func servicesShareOneStateStore() async throws {
        let store = StateStore()
        let host = try await MockHost.start {
            EchoService(name: "Alpha", prefix: "/alpha", store: store)
            EchoService(name: "Beta", prefix: "/beta", store: store)
        }

        _ = try await get(#require(URL(string: "/alpha/one", relativeTo: host.url)))
        let second = try await get(#require(URL(string: "/beta/two", relativeTo: host.url)))
        let body = try MockValue.fromJSONData(second.body)
        // Beta sees the record Alpha's request inserted: one shared backend, two services.
        #expect(body["requestCount"] == .int(2))
        try await host.stop()
    }

    @Test func unclaimedRequestsGetADiagnostic404() async throws {
        let host = try await MockHost.start {
            EchoService(name: "Alpha", prefix: "/alpha", store: StateStore())
        }

        let missing = try await get(#require(URL(string: "/nope", relativeTo: host.url)))
        #expect(missing.status == 404)
        let body = try MockValue.fromJSONData(missing.body)
        let message = try #require(body["error"].stringValue)
        #expect(message.contains("GET /nope"))
        #expect(message.contains("Alpha"))
        try await host.stop()
    }

    @Test func healthEndpointAnswersWhenNoServiceClaimsIt() async throws {
        let host = try await MockHost.start {
            EchoService(name: "Alpha", prefix: "/alpha", store: StateStore())
        }

        let health = try await get(#require(URL(string: "/health", relativeTo: host.url)))
        #expect(health.status == 200)
        #expect(String(decoding: health.body, as: UTF8.self) == "ok")
        try await host.stop()
    }

    @Test func failingWillStartPreventsBinding() async {
        do {
            _ = try await MockHost.start { MisconfiguredService() }
            Issue.record("Expected willStart to fail the start")
        } catch let error as MockError {
            #expect(error.category == .configuration)
            #expect(error.message == "intentionally broken")
        } catch {
            Issue.record("Expected a MockError, got \(error)")
        }
    }

    @Test func startingWithNoServicesIsAConfigurationError() async {
        do {
            _ = try await MockHost.start(services: [])
            Issue.record("Expected a configuration error")
        } catch let error as MockError {
            #expect(error.category == .configuration)
        } catch {
            Issue.record("Expected a MockError, got \(error)")
        }
    }

    @Test func ephemeralPortsGiveEachHostItsOwnAddress() async throws {
        let first = try await MockHost.start { EchoService(name: "A", prefix: "/", store: StateStore()) }
        let second = try await MockHost.start { EchoService(name: "B", prefix: "/", store: StateStore()) }
        #expect(first.port != second.port)
        #expect(first.url.absoluteString == "http://127.0.0.1:\(first.port)/")
        #expect(first.webSocketURL.absoluteString == "ws://127.0.0.1:\(first.port)/")
        try await first.stop()
        try await second.stop()
    }
}

@Suite struct MockRequestTests {
    @Test func pathStripsTheQueryString() {
        let request = MockRequest(method: "get", uri: "/users/u1?expand=cart&limit=5")
        #expect(request.method == "GET")
        #expect(request.path == "/users/u1")
        #expect(request.queryValue("expand") == "cart")
        #expect(request.queryValue("limit") == "5")
        #expect(request.queryValue("missing") == nil)
    }

    @Test func headerLookupIsCaseInsensitive() {
        let request = MockRequest(method: "POST", uri: "/x", headers: [("Content-Type", "application/json")])
        #expect(request.header("content-type") == "application/json")
        #expect(request.header("Accept") == nil)
    }
}
