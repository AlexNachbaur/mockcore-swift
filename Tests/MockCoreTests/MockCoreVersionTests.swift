import Testing

@testable import MockCore

@Suite struct MockCoreVersionTests {
    @Test func versionIsSemanticVersionShaped() {
        let components = MockCoreVersion.current.split(separator: ".")
        #expect(components.count == 3)
        #expect(components.allSatisfy { Int($0) != nil })
    }
}
