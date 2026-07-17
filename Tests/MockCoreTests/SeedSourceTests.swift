import Testing

@testable import MockCore

@Suite struct SeedSourceTests {
    @Test func yamlScalarsResolveByCoreSchema() throws {
        let document = try SeedSource.yaml(
            """
            version: 1
            data:
              flag: true
              count: 3
              price: 4.5
              name: Avery
              quoted: "3"
              nothing: null
            """
        ).rawDocument()
        let data = document["data"]
        #expect(document["version"] == .int(1))
        #expect(data["flag"] == .bool(true))
        #expect(data["count"] == .int(3))
        #expect(data["price"] == .double(4.5))
        #expect(data["name"] == .string("Avery"))
        #expect(data["quoted"] == .string("3"))
        #expect(data["nothing"] == .null)
    }

    @Test func versionLikeStringsStayStrings() throws {
        let document = try SeedSource.yaml("release: 1.2.3").rawDocument()
        #expect(document["release"] == .string("1.2.3"))
    }

    @Test func jsonParsesIntoValues() throws {
        let document = try SeedSource.json(#"{"user": {"id": "u1", "age": 34}}"#).rawDocument()
        #expect(document["user"]["id"] == .string("u1"))
        #expect(document["user"]["age"] == .int(34))
    }

    @Test func invalidYAMLIsASeedError() {
        #expect(throws: MockError.self) {
            try SeedSource.yaml("data: [unclosed").rawDocument()
        }
    }

    @Test func invalidJSONIsASeedError() {
        do {
            _ = try SeedSource.json("{not json").rawDocument()
            Issue.record("Expected a seed error")
        } catch let error as MockError {
            #expect(error.category == .seed)
        } catch {
            Issue.record("Expected a MockError, got \(error)")
        }
    }

    @Test func missingFileIsASeedErrorNamingThePath() {
        do {
            _ = try SeedSource.file("/nonexistent/world.yaml").rawDocument()
            Issue.record("Expected a seed error")
        } catch let error as MockError {
            #expect(error.category == .seed)
            #expect(error.sourceName == "/nonexistent/world.yaml")
        } catch {
            Issue.record("Expected a MockError, got \(error)")
        }
    }

    @Test func yamlAnchorsAndAliasesResolve() throws {
        let document = try SeedSource.yaml(
            """
            first: &price 100
            second: *price
            """
        ).rawDocument()
        #expect(document["first"] == .int(100))
        #expect(document["second"] == .int(100))
    }

    @Test func documentSourcePassesThroughUnchanged() throws {
        let value: MockValue = ["version": 1, "data": ["User": [["id": "u1"]]]]
        let document = try SeedSource.document(value).rawDocument()
        #expect(document == value)
    }

    @Test func sourceNamesDescribeTheOrigin() {
        #expect(SeedSource.file("a/b.yaml").sourceName == "a/b.yaml")
        #expect(SeedSource.yaml("x: 1").sourceName == "inline YAML seed")
        #expect(SeedSource.json("{}").sourceName == "inline JSON seed")
        #expect(SeedSource.document(.object([:])).sourceName == "seed builder")
        #expect(SeedSource.document(.object([:]), sourceName: "fixtures").sourceName == "fixtures")
    }
}
