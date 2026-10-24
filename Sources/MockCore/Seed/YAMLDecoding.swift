import Yams

/// Converts YAML text into a `MockValue` tree using core-schema-style scalar resolution
/// (null/bool/int and unambiguous decimal floats resolve; exotic spellings like hex, octal,
/// and `.inf` stay strings). Anchors and aliases are resolved during composition.
///
/// Used for seed documents and by protocol extensions for their own YAML inputs (e.g. MockREST
/// decodes OpenAPI specs through it), so all YAML diagnostics behave identically.
public struct YAMLDecoding {
    /// Decodes a YAML document. Quoted scalars stay strings; plain scalars resolve to
    /// null/bool/int/float where they match, matching what YAML authors expect.
    ///
    /// - Parameters:
    ///   - text: The YAML text.
    ///   - sourceName: The name reported in diagnostics (usually a file path).
    ///   - category: The error category thrown for malformed documents; `.seed` by default.
    public static func decode(
        _ text: String,
        sourceName: String?,
        category: MockError.Category = .seed
    ) throws -> MockValue {
        let context = Context(sourceName: sourceName, category: category)
        let root: Node?
        do {
            root = try Yams.compose(yaml: text)
        } catch let error as YamlError {
            let failure = describe(error)
            throw MockError(
                category: category,
                message: "\(context.documentKind) is not valid YAML: \(failure.detail)",
                sourceName: sourceName,
                location: failure.location
            )
        }
        guard let root else {
            return .object([:])
        }
        return try value(from: root, context: context)
    }

    /// What a diagnostic needs to know about the document being decoded.
    private struct Context {
        let sourceName: String?
        let category: MockError.Category

        /// How the document is named in a message: only a seed is called a seed, so a
        /// malformed OpenAPI spec is never reported as a seed problem.
        var documentKind: String {
            category == .seed ? "Seed document" : "Document"
        }
    }

    /// Splits a Yams failure into a structured location and the explanation that goes with it.
    ///
    /// Yams' own description leads with `line:column: error: parser:`; the position belongs in
    /// ``MockError/location`` — where it prints once, next to the source name, and where tools
    /// can read it — so the text here is rebuilt from the parts without it. The offending line
    /// and caret are kept: they are the most useful part of the message.
    private static func describe(_ error: YamlError) -> (detail: String, location: SourceLocation?) {
        switch error {
        case .scanner(let context, let problem, let mark, let yaml),
            .parser(let context, let problem, let mark, let yaml),
            .composer(let context, let problem, let mark, let yaml):
            var detail = problem
            if let context {
                detail += " \(context.text) (line \(context.mark.line), column \(context.mark.column))"
            }
            detail += ":\n" + mark.snippet(from: yaml)
            return (detail, SourceLocation(line: mark.line, column: mark.column))
        default:
            return ("\(error)", nil)
        }
    }

    private static func location(of node: Node) -> SourceLocation? {
        node.mark.map { SourceLocation(line: $0.line, column: $0.column) }
    }

    private static func value(from node: Node, context: Context) throws -> MockValue {
        switch node {
        case .scalar(let scalar):
            return scalarValue(scalar)
        case .sequence(let sequence):
            return .list(try sequence.map { try value(from: $0, context: context) })
        case .mapping(let mapping):
            var fields: [String: MockValue] = [:]
            for (keyNode, valueNode) in mapping {
                guard let key = keyNode.string else {
                    throw MockError(
                        category: context.category,
                        message: "\(context.documentKind) mapping keys must be strings",
                        sourceName: context.sourceName,
                        location: location(of: keyNode)
                    )
                }
                fields[key] = try value(from: valueNode, context: context)
            }
            return .object(fields)
        default:
            throw MockError(
                category: context.category,
                message: "Unsupported YAML construct in \(context.documentKind.lowercased())",
                sourceName: context.sourceName,
                location: location(of: node)
            )
        }
    }

    private static func scalarValue(_ scalar: Node.Scalar) -> MockValue {
        // Quoted or block scalars are always strings; only plain scalars resolve to other types.
        guard scalar.style == .plain || scalar.style == .any else {
            return .string(scalar.string)
        }
        let text = scalar.string
        if ["null", "Null", "NULL", "~", ""].contains(text) {
            return .null
        }
        if ["true", "True", "TRUE"].contains(text) {
            return .bool(true)
        }
        if ["false", "False", "FALSE"].contains(text) {
            return .bool(false)
        }
        if let int = Int(text) {
            return .int(int)
        }
        if isFloatLiteral(text), let double = Double(text) {
            return .double(double)
        }
        return .string(text)
    }

    /// Only resolve floats for unambiguous numeric literals — `Double("1e5")` and friends would
    /// otherwise swallow strings like version numbers.
    private static func isFloatLiteral(_ text: String) -> Bool {
        var mantissa = Substring(text)
        if mantissa.hasPrefix("-") || mantissa.hasPrefix("+") {
            mantissa = mantissa.dropFirst()
        }
        guard mantissa.contains(".") else { return false }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
            && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
