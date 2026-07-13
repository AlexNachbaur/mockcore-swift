import Testing

@testable import MockCore

@Suite struct MockValueLiteralTests {
    @Test func literalsProduceExpectedCases() {
        let value: MockValue = [
            "id": "user-1",
            "age": 34,
            "score": 1.5,
            "active": true,
            "nickname": nil,
            "tags": ["a", "b"],
        ]
        #expect(value["id"] == .string("user-1"))
        #expect(value["age"] == .int(34))
        #expect(value["score"] == .double(1.5))
        #expect(value["active"] == .bool(true))
        #expect(value["nickname"] == .null)
        #expect(value["tags"] == .list([.string("a"), .string("b")]))
    }
}

@Suite struct MockValueAccessorTests {
    @Test func typedAccessorsReturnWrappedValues() {
        #expect(MockValue.bool(true).boolValue == true)
        #expect(MockValue.int(7).intValue == 7)
        #expect(MockValue.int(7).doubleValue == 7.0)
        #expect(MockValue.double(2.5).doubleValue == 2.5)
        #expect(MockValue.string("hi").stringValue == "hi")
        #expect(MockValue.enumValue("USD").enumName == "USD")
        #expect(MockValue.null.isNull)
    }

    @Test func mismatchedAccessorsReturnNil() {
        #expect(MockValue.string("true").boolValue == nil)
        #expect(MockValue.string("7").intValue == nil)
        #expect(MockValue.int(1).stringValue == nil)
        #expect(MockValue.string("USD").enumName == nil)
    }

    @Test func objectSubscriptChainsThroughMissingFields() {
        let value: MockValue = ["user": ["profile": ["name": "Avery"]]]
        #expect(value["user"]["profile"]["name"] == .string("Avery"))
        #expect(value["user"]["missing"]["deeper"] == .null)
        #expect(MockValue.int(1)["anything"] == .null)
    }

    @Test func objectSubscriptWritesFields() {
        var value: MockValue = ["name": "Avery"]
        value["name"] = "Riley"
        value["email"] = "riley@example.com"
        #expect(value["name"] == .string("Riley"))
        #expect(value["email"] == .string("riley@example.com"))
    }

    @Test func writingToNonObjectCreatesObject() {
        var value = MockValue.null
        value["name"] = "Avery"
        #expect(value == .object(["name": .string("Avery")]))
    }

    @Test func listSubscriptReadsAndWrites() {
        var value: MockValue = [10, 20, 30]
        #expect(value[1] == .int(20))
        #expect(value[9] == .null)
        value[1] = 25
        #expect(value[1] == .int(25))
    }

    @Test func appendBuildsLists() {
        var items = MockValue.null
        items.append(["quantity": 1])
        items.append(["quantity": 2])
        #expect(items.count == 2)
        #expect(items[1]["quantity"] == .int(2))
    }

    @Test func appendToScalarIsIgnored() {
        var value = MockValue.int(5)
        value.append("x")
        #expect(value == .int(5))
    }
}

@Suite struct MockValueReferenceTests {
    @Test func referenceAccessorRoundTrips() {
        let reference = MockValue.reference("User", id: "u1")
        #expect(reference.referenceValue?.typeName == "User")
        #expect(reference.referenceValue?.id == "u1")
        #expect(MockValue.string("u1").referenceValue == nil)
    }

    @Test func dynamicIDOverloadAcceptsStringsAndInts() {
        #expect(MockValue.reference("User", id: .string("u1")) == .reference("User", id: "u1"))
        #expect(MockValue.reference("User", id: .int(7)) == .reference("User", id: "7"))
        #expect(MockValue.reference("User", id: .null) == .null)
        #expect(MockValue.reference("User", id: .bool(true)) == .null)
    }
}

@Suite struct MockValueCodableTests {
    @Test func jsonRoundTripPreservesValues() throws {
        let original: MockValue = [
            "string": "hello",
            "int": 42,
            "double": 3.5,
            "bool": false,
            "null": nil,
            "nested": ["list": [1, 2, 3]],
        ]
        let data = try original.jsonData()
        let decoded = try MockValue.fromJSONData(data)
        #expect(decoded == original)
    }

    @Test func decodesFromJSONString() throws {
        let value = try MockValue.fromJSONString(#"{"a": [true, null, 1.5], "b": "text"}"#)
        #expect(value["a"][0] == .bool(true))
        #expect(value["a"][1] == .null)
        #expect(value["a"][2] == .double(1.5))
        #expect(value["b"] == .string("text"))
    }

    @Test func boolsAndNumbersStayDistinct() throws {
        let value = try MockValue.fromJSONString(#"{"flag": true, "count": 1}"#)
        #expect(value["flag"] == .bool(true))
        #expect(value["count"] == .int(1))
    }

    @Test func enumValueEncodesAsString() throws {
        let json = try MockValue.enumValue("USD").jsonString()
        #expect(json == "\"USD\"")
    }

    @Test func jsonOutputIsDeterministic() throws {
        let value: MockValue = ["b": 2, "a": 1, "c": 3]
        #expect(try value.jsonString() == #"{"a":1,"b":2,"c":3}"#)
    }
}

@Suite struct MockValueDescriptionTests {
    @Test func descriptionRendersGraphQLStyleLiterals() {
        let value: MockValue = ["name": "Avery", "age": 34]
        #expect(value.description == #"{age: 34, name: "Avery"}"#)
        #expect(MockValue.enumValue("USD").description == "USD")
        #expect(MockValue.list([.null, .bool(true)]).description == "[null, true]")
    }
}
