import Foundation

/// Where a seed document comes from: a file on disk, an inline string, or a document assembled
/// in Swift (result-builder initializers produce the latter).
///
/// `SeedSource` only locates and parses the raw document; validating it against a schema is the
/// job of each protocol extension's seed loader.
public struct SeedSource: Sendable {
    enum Kind: Sendable {
        case file(String)
        case yaml(String)
        case json(String)
        case document(MockValue, sourceName: String?)
    }

    let kind: Kind

    /// Loads the seed document from a file. `.json` files parse as JSON; anything else parses
    /// as YAML (of which JSON is a subset).
    public static func file(_ path: String) -> SeedSource {
        SeedSource(kind: .file(path))
    }

    /// An inline YAML seed document.
    public static func yaml(_ text: String) -> SeedSource {
        SeedSource(kind: .yaml(text))
    }

    /// An inline JSON seed document.
    public static func json(_ text: String) -> SeedSource {
        SeedSource(kind: .json(text))
    }

    /// A seed document assembled programmatically (used by result-builder DSLs).
    public static func document(_ value: MockValue, sourceName: String? = nil) -> SeedSource {
        SeedSource(kind: .document(value, sourceName: sourceName))
    }

    /// The name used for this source in diagnostics.
    public var sourceName: String? {
        switch kind {
        case .file(let path): return path
        case .yaml: return "inline YAML seed"
        case .json: return "inline JSON seed"
        case .document(_, let name): return name ?? "seed builder"
        }
    }

    /// Reads and parses the raw document value (no schema validation yet).
    public func rawDocument() throws -> MockValue {
        switch kind {
        case .document(let value, _):
            return value
        case .yaml(let text):
            return try YAMLDecoding.decode(text, sourceName: sourceName)
        case .json(let text):
            return try Self.decodeJSON(text, sourceName: sourceName)
        case .file(let path):
            let text: String
            do {
                text = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                throw MockError(
                    category: .seed,
                    message: "Cannot read seed file: \(error.localizedDescription)",
                    sourceName: path
                )
            }
            if path.lowercased().hasSuffix(".json") {
                return try Self.decodeJSON(text, sourceName: path)
            }
            return try YAMLDecoding.decode(text, sourceName: path)
        }
    }

    private static func decodeJSON(_ text: String, sourceName: String?) throws -> MockValue {
        do {
            return try MockValue.fromJSONString(text)
        } catch {
            throw MockError(
                category: .seed,
                message: "Seed document is not valid JSON: \(error.localizedDescription)",
                sourceName: sourceName
            )
        }
    }
}
