import Testing

@testable import MockCore

/// What a user is told when a YAML or JSON document cannot be read, and how suggestions are
/// chosen — the parts of "diagnostics are a product feature" that live in MockCore.
@Suite struct DocumentDiagnosticsTests {
    @Test func invalidYAMLReportsWhereItWentWrong() throws {
        let error = try #require(throws: MockError.self) {
            try SeedSource.yaml("data:\n  - [unclosed\n").rawDocument()
        }
        #expect(error.location == SourceLocation(line: 3, column: 1))
        // The position is reported once, structurally — not repeated inside the message.
        #expect(
            error.description == """
                inline YAML seed:3:1: Seed document is not valid YAML: did not find expected ',' or ']' \
                while parsing a flow sequence (line 2, column 5):
                  - [unclosed
                ^
                """
        )
    }

    @Test func structuralYAMLErrorsKeepTheCallersCategory() throws {
        let error = try #require(throws: MockError.self) {
            try YAMLDecoding.decode("paths:\n  [a, b]: 1\n", sourceName: "api.yaml", category: .schema)
        }
        #expect(error.category == .schema)
        #expect(error.message == "Document mapping keys must be strings")
        #expect(error.location == SourceLocation(line: 2, column: 3))
    }

    @Test func structuralYAMLErrorsInSeedsStillSaySeed() throws {
        let error = try #require(throws: MockError.self) {
            try SeedSource.yaml("[a, b]: 1").rawDocument()
        }
        #expect(error.category == .seed)
        #expect(error.message == "Seed document mapping keys must be strings")
    }

    @Test func invalidJSONExplainsTheProblem() throws {
        let error = try #require(throws: MockError.self) {
            try SeedSource.json("{not json").rawDocument()
        }
        #expect(error.message.hasPrefix("Seed document is not valid JSON: "))
        // Foundation's generic sentence carries no information; the parser's own account must
        // be what reaches the user.
        #expect(!error.message.contains("in the correct format"))
    }

    @Test func equallyCloseSuggestionsResolveAlphabeticallyWhateverTheOrder() {
        #expect(Suggestion.nearest(to: "ab", in: ["ad", "ac"]) == "ac")
        #expect(Suggestion.nearest(to: "ab", in: ["ac", "ad"]) == "ac")
    }

    @Test func caseOnlyMatchesOutrankEdits() {
        #expect(Suggestion.nearest(to: "user", in: ["users", "User"]) == "User")
        #expect(Suggestion.nearest(to: "user", in: ["User", "users"]) == "User")
    }

    @Test func localizedDescriptionCarriesTheFullDiagnostic() {
        let error: any Error = MockError(
            category: .seed,
            message: "Unknown field 'emial'. Did you mean 'email'?",
            sourceName: "checkout.yaml",
            location: SourceLocation(line: 12, column: 7)
        )
        #expect(error.localizedDescription == "checkout.yaml:12:7: Unknown field 'emial'. Did you mean 'email'?")
    }
}

/// Field-name inference: which generator an unbound field gets from its name alone.
@Suite struct GeneratorInferenceTests {
    /// The generator inferred for a field, identified by the shape of what it produces.
    private func inferredKind(_ fieldName: String, scalar: String = "String") -> String {
        let generator = GeneratorRegistry.inferred(fieldName: fieldName, scalarTypeName: scalar)
        var context = GeneratorContext(
            typeName: "T",
            fieldName: fieldName,
            recordID: "1",
            random: RandomSource(seed: 7)
        )
        let value = generator.generate(&context).stringValue ?? ""
        if value.contains("@") { return "email" }
        if value.hasPrefix("http") { return "url" }
        if value.hasSuffix("Z"), value.contains("T"), value.contains(":") { return "dateTime" }
        return "text"
    }

    @Test func inferenceMatchesWholeWordsAcrossNamingConventions() {
        #expect(inferredKind("email") == "email")
        #expect(inferredKind("contactEmail") == "email")
        #expect(inferredKind("contact_email") == "email")
        #expect(inferredKind("avatarURL") == "url")
        #expect(inferredKind("website") == "url")
        #expect(inferredKind("createdAt") == "dateTime")
        #expect(inferredKind("created_at") == "dateTime")
        #expect(inferredKind("startDate") == "dateTime")
        #expect(inferredKind("expiry", scalar: "DateTime") == "dateTime")
    }

    @Test func inferenceIgnoresWordsThatMerelyContainATrigger() {
        // Each of these contains "date", "time", "url", or "link" as a substring only.
        for name in ["updated", "candidate", "lifetime", "hourly", "blinking", "sentiment"] {
            #expect(inferredKind(name) == "text", "\(name) should not infer a special shape")
        }
    }

    @Test func pluralsAndAcronymPluralsKeepTheirShape() {
        // Names that inferred correctly before word matching, and must still.
        #expect(inferredKind("emails") == "email")
        #expect(inferredKind("urls") == "url")
        #expect(inferredKind("links") == "url")
        #expect(inferredKind("imageURLs") == "url")
        #expect(inferredKind("URLs") == "url")
        #expect(inferredKind("emailAddress") == "email")
        #expect(inferredKind("avatar_url") == "url")
        #expect(inferredKind("birthDate") == "dateTime")
        #expect(FieldNameWords("imageURLs").words == ["image", "urls"])
        #expect(FieldNameWords("URLs").words == ["urls"])
        #expect(FieldNameWords("names").containsAny(of: ["name"]))
        #expect(FieldNameWords("nickname").containsAny(of: ["nickname"]))
    }

    @Test func fieldNamesSplitIntoWords() {
        #expect(FieldNameWords("createdAt").words == ["created", "at"])
        #expect(FieldNameWords("created_at").words == ["created", "at"])
        #expect(FieldNameWords("avatarURL").words == ["avatar", "url"])
        #expect(FieldNameWords("HTMLBody").words == ["html", "body"])
        #expect(FieldNameWords("address2Line").words == ["address", "line"])
        #expect(FieldNameWords("filename").containsAny(of: ["name"]) == false)
        #expect(FieldNameWords("userName").containsAny(of: ["username"]))
    }
}
