import Foundation
import MockCore
import Testing

@testable import MockCoreTransport

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Records lifecycle events in the order they happen, so tests can assert ordering.
private actor EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// A service whose handler stays in flight until released (or cancelled), announcing when it
/// has been entered so a test can stop the host at a known point.
private struct SlowService: MockService {
    let name = "Slow"
    let log: EventLog
    let entered: AsyncStream<Void>.Continuation
    let delay: Duration

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/slow"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        entered.yield()
        do {
            try await Task.sleep(for: delay)
            await log.record("responded")
        } catch {
            await log.record("cancelled")
        }
        return .text("done")
    }

    func shutdown() async {
        await log.record("shutdown")
    }
}

/// Claims everything and answers with its own name.
private struct NamedService: MockService {
    let name: String
    var log: EventLog?

    func claims(_ request: MockRequest) -> Bool {
        request.path == "/\(name)"
    }

    func respond(to request: MockRequest) async -> MockResponse {
        .text(name)
    }

    func shutdown() async {
        await log?.record("shutdown \(name)")
    }
}

private struct ExpectedFailure: Error {}

@Suite struct HostLifecycleTests {
    private func status(_ path: String, on host: MockHost, method: String = "GET") async throws -> Int {
        var request = URLRequest(url: try #require(URL(string: path, relativeTo: host.url)))
        request.httpMethod = method
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    @Test(.timeLimit(.minutes(1))) func stoppingTwiceReturnsBothTimes() async throws {
        let log = EventLog()
        let host = try await MockHost.start(services: [NamedService(name: "a", log: log)])
        try await host.stop()
        try await host.stop()
        // The second call joins the finished shutdown rather than running another.
        #expect(await log.events == ["shutdown a"])
    }

    @Test(.timeLimit(.minutes(1))) func concurrentStopsShareOneShutdown() async throws {
        let log = EventLog()
        let host = try await MockHost.start(services: [NamedService(name: "a", log: log)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { try await host.stop() }
            }
            try await group.waitForAll()
        }
        #expect(await log.events == ["shutdown a"])
    }

    @Test(.timeLimit(.minutes(1))) func inFlightRequestsFinishBeforeServicesShutDown() async throws {
        let log = EventLog()
        let (entered, continuation) = AsyncStream.makeStream(of: Void.self)
        let host = try await MockHost.start(
            services: [SlowService(log: log, entered: continuation, delay: .milliseconds(200))]
        )

        async let inFlight = status("/slow", on: host)
        for await _ in entered { break }
        try await host.stop()

        #expect(try await inFlight == 200)
        #expect(await log.events == ["responded", "shutdown"])
    }

    @Test(.timeLimit(.minutes(1))) func requestsOutlastingTheGracePeriodAreCancelledNotDropped() async throws {
        let log = EventLog()
        let (entered, continuation) = AsyncStream.makeStream(of: Void.self)
        let host = try await MockHost.start(
            services: [SlowService(log: log, entered: continuation, delay: .seconds(600))]
        )

        async let inFlight = status("/slow", on: host)
        for await _ in entered { break }
        try await host.stop(gracePeriod: .milliseconds(50))

        // Cancellation ends the handler's delay early; the client still gets its response.
        #expect(try await inFlight == 200)
        #expect(await log.events == ["cancelled", "shutdown"])
    }

    @Test func withRunningStopsTheHostWhenTheBodyThrows() async throws {
        let log = EventLog()
        await #expect(throws: ExpectedFailure.self) {
            try await MockHost.withRunning(services: [NamedService(name: "a", log: log)]) { _ in
                throw ExpectedFailure()
            }
        }
        #expect(await log.events == ["shutdown a"])
    }

    @Test func withRunningReturnsTheBodyResultAndStops() async throws {
        let log = EventLog()
        let code = try await MockHost.withRunning(services: [NamedService(name: "a", log: log)]) { host in
            try await status("/a", on: host)
        }
        #expect(code == 200)
        #expect(await log.events == ["shutdown a"])
    }

    @Test func healthAnswersHEAD() async throws {
        let code = try await MockHost.withRunning(services: [NamedService(name: "a")]) { host in
            try await status("/health", on: host, method: "HEAD")
        }
        #expect(code == 200)
    }

    @Test func ipv6LiteralsAreBracketedInEndpointURLs() throws {
        #expect(
            try MockHost.endpointURL(scheme: "http", host: "::1", port: 8080).absoluteString == "http://[::1]:8080/")
        #expect(try MockHost.endpointURL(scheme: "ws", host: "[::1]", port: 8080).absoluteString == "ws://[::1]:8080/")
        #expect(
            try MockHost.endpointURL(scheme: "http", host: "127.0.0.1", port: 80).absoluteString
                == "http://127.0.0.1:80/"
        )
    }
}

/// The builder's control-flow support, exercised from the main actor because that is where
/// XCUITest `setUp` code — the primary caller — lives.
@Suite @MainActor struct MockServiceBuilderTests {
    private let includeOptional = true
    private let useFirstBranch = false

    @Test func conditionalsAndLoopsContributeServicesInDeclarationOrder() async throws {
        let host = try await MockHost.start {
            NamedService(name: "always")
            if includeOptional {
                NamedService(name: "optional")
            }
            if useFirstBranch {
                NamedService(name: "first")
            } else {
                NamedService(name: "second")
            }
            for index in 1...2 {
                NamedService(name: "loop\(index)")
            }
            [NamedService(name: "spliced")]
        }
        #expect(host.services.map(\.name) == ["always", "optional", "second", "loop1", "loop2", "spliced"])
        try await host.stop()
    }

    @Test func asyncBuilderBlocksRunOnTheCallersActor() async throws {
        let host = try await MockHost.start {
            try await makeService(named: "async")
        }
        #expect(host.services.map(\.name) == ["async"])
        try await host.stop()
    }

    private func makeService(named name: String) async throws -> NamedService {
        NamedService(name: name)
    }
}
