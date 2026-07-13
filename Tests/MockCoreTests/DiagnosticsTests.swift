import Testing

@testable import MockCore

@Suite struct SuggestionTests {
    @Test func suggestsCloseMatches() {
        let candidates = ["currentUser", "cart", "products"]
        #expect(Suggestion.nearest(to: "curentUser", in: candidates) == "currentUser")
        #expect(Suggestion.nearest(to: "poducts", in: candidates) == "products")
    }

    @Test func prefersCaseOnlyMismatches() {
        #expect(Suggestion.nearest(to: "currentuser", in: ["currentUser"]) == "currentUser")
    }

    @Test func rejectsDistantInputs() {
        #expect(Suggestion.nearest(to: "zebra", in: ["currentUser", "cart"]) == nil)
    }

    @Test func neverSuggestsTheInputItself() {
        #expect(Suggestion.nearest(to: "cart", in: ["cart"]) == nil)
    }

    @Test func clauseFormatsSuggestion() {
        #expect(Suggestion.clause(for: "usr", in: ["user"]) == " Did you mean 'user'?")
        #expect(Suggestion.clause(for: "zzz", in: ["user"]).isEmpty)
    }
}

@Suite struct MockErrorTests {
    @Test func descriptionIncludesSourceAndLocation() {
        let error = MockError(
            category: .seed,
            message: "Unknown field 'emial' on type 'User'. Did you mean 'email'?",
            sourceName: "checkout.yaml",
            location: SourceLocation(line: 12, column: 7)
        )
        #expect(error.description == "checkout.yaml:12:7: Unknown field 'emial' on type 'User'. Did you mean 'email'?")
    }

    @Test func descriptionIncludesDocumentPathWhenNoLocation() {
        let error = MockError(category: .seed, message: "Dangling reference", documentPath: "data.Cart[0].owner")
        #expect(error.description == "Dangling reference (at data.Cart[0].owner)")
    }
}
