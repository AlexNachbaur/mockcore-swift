import Testing

@testable import MockCoreTransport

// Phase 2 of the extraction plan lands MockHost/MockService here, with real tests. This file
// exists so the test target builds during Phase 0/1.
@Suite struct TransportPlaceholderTests {
    @Test func targetBuilds() {
        #expect(Bool(true))
    }
}
