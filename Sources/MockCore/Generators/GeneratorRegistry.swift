/// The set of generators configured for a server, plus the inference rules used when a field
/// has no explicit generator.
///
/// Explicit bindings are keyed `"Type.field"`, where `Type` is the namespace the protocol
/// extension defines (a GraphQL object type name, an OpenAPI schema name, a resource name, …):
///
/// ```swift
/// generators: [
///     "User.name": .fullName,
///     "User.email": .email,
/// ]
/// ```
public struct GeneratorRegistry: Sendable {
    private var bindings: [String: FieldGenerator]
    private let serverSeed: UInt64

    /// Creates a registry.
    ///
    /// - Parameters:
    ///   - bindings: Explicit generators keyed by `"Type.field"`.
    ///   - serverSeed: The seed all generated values derive from. Servers created with the same
    ///     seed generate identical data.
    public init(bindings: [String: FieldGenerator] = [:], serverSeed: UInt64 = 0) {
        self.bindings = bindings
        self.serverSeed = serverSeed
    }

    /// The keys of all explicit bindings, sorted. Protocol extensions validate these against
    /// their own schema model at startup (MockCore has no schema of its own).
    public var bindingKeys: [String] {
        bindings.keys.sorted()
    }

    /// Adds or replaces a binding.
    public mutating func bind(typeName: String, fieldName: String, generator: FieldGenerator) {
        bindings["\(typeName).\(fieldName)"] = generator
    }

    /// Generates a stable value for a scalar-typed field of a record.
    ///
    /// Resolution order: the explicit `Type.field` binding, then field-name inference
    /// (`email` → an email address, `name` → a full name, …), then a type-appropriate default
    /// for the scalar. The result is a pure function of (server seed, type, record id, field),
    /// so repeated reads return the same value.
    public func value(
        typeName: String,
        recordID: String?,
        field fieldName: String,
        scalarTypeName: String
    ) -> MockValue {
        let seed = RandomSource.stableSeed(
            serverSeed: serverSeed,
            typeName: typeName,
            recordID: recordID,
            fieldName: fieldName
        )
        var context = GeneratorContext(
            typeName: typeName,
            fieldName: fieldName,
            recordID: recordID,
            random: RandomSource(seed: seed)
        )
        let generator =
            bindings["\(typeName).\(fieldName)"]
            ?? GeneratorRegistry.inferred(fieldName: fieldName, scalarTypeName: scalarTypeName)
        return generator.generate(&context)
    }

    /// Picks a stable enum member for a field with no seeded value.
    public func enumValue(typeName: String, recordID: String?, field fieldName: String, cases: [String]) -> MockValue {
        let seed = RandomSource.stableSeed(
            serverSeed: serverSeed,
            typeName: typeName,
            recordID: recordID,
            fieldName: fieldName
        )
        var context = GeneratorContext(
            typeName: typeName,
            fieldName: fieldName,
            recordID: recordID,
            random: RandomSource(seed: seed)
        )
        if let generator = bindings["\(typeName).\(fieldName)"] {
            return generator.generate(&context)
        }
        guard let picked = cases.randomElement(using: &context.random) else { return .null }
        return .enumValue(picked)
    }

    /// The generator used when no explicit binding exists: inferred from the field name where
    /// the name strongly implies a shape, otherwise a sensible default for the scalar type.
    ///
    /// Names are matched by **word**, not by substring: `fieldName` is split at camelCase
    /// humps, underscores, hyphens, and digits, and a rule fires only when one of its words is
    /// present. Substring matching reads `updated` as a date, `hourly` as a URL, and `filename`
    /// as a person — a wrong guess that looks deliberate in a rendered UI.
    public static func inferred(fieldName: String, scalarTypeName: String) -> FieldGenerator {
        let name = FieldNameWords(fieldName)
        switch scalarTypeName {
        case "ID":
            return .uuid
        case "Int":
            return .int()
        case "Float":
            return .double()
        case "Boolean":
            return .bool
        case "String":
            if name.containsAny(of: ["email"]) { return .email }
            if name.containsAny(of: ["phone", "telephone", "mobile"]) { return .phoneNumber }
            if name.containsAny(of: ["url", "uri", "website", "link"]) { return .url }
            if name.containsAny(of: ["username", "handle"]) { return .username }
            if name.containsAny(of: ["firstname", "givenname"]) { return .firstName }
            if name.containsAny(of: ["lastname", "surname", "familyname"]) { return .lastName }
            if name.containsAny(of: ["name", "nickname"]) { return .fullName }
            if name.isDateLike { return .dateTime }
            return .sentence
        default:
            // Custom scalars: date-like names get timestamps; anything else gets an opaque string.
            if name.isDateLike || FieldNameWords(scalarTypeName).isDateLike {
                return .dateTime
            }
            return .custom(scalarTypeName: scalarTypeName) { context in
                var random = context.random
                let word = GeneratorData.words.randomElement(using: &random) ?? "amber"
                let digits = Int.random(in: 100...999, using: &random)
                return .string("\(word)-\(digits)")
            }
        }
    }
}

/// A field (or scalar type) name split into lowercased words, for name-based inference.
///
/// `createdAt`, `created_at`, and `created-at` all become `["created", "at"]`; an acronym run
/// stays together, so `avatarURL` is `["avatar", "url"]` and `HTMLBody` is `["html", "body"]`.
struct FieldNameWords {
    let words: [String]

    init(_ name: String) {
        var words: [String] = []
        var current = ""
        let characters = Array(name)
        for (index, character) in characters.enumerated() {
            guard character.isLetter else {
                // Separators and digits end a word and belong to none.
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            if character.isUppercase, let previous = current.last {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let afterNext = index + 2 < characters.count ? characters[index + 2] : nil
                // A plural `s` on an acronym (`URLs`, `imageURLs`) belongs to the acronym, so it
                // must not be read as the start of a new word.
                let nextIsPlural = next == "s" && !(afterNext?.isLowercase ?? false)
                let nextStartsWord = (next?.isLowercase ?? false) && !nextIsPlural
                // A hump starts a word (`created|At`), and so does the last capital of an
                // acronym run when a lowercase letter follows it (`HTML|Body`).
                if previous.isLowercase || (previous.isUppercase && nextStartsWord) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty {
            words.append(current)
        }
        self.words = words.map { $0.lowercased() }
    }

    /// Whether any of `terms` appears as a word, or as adjacent words that spell it — so
    /// `"username"` matches both `username` and `userName`, but `"name"` does not match
    /// `filename`. A plural matches its singular term (`emails`, `avatarURLs`), since list
    /// fields are routinely named that way.
    func containsAny(of terms: [String]) -> Bool {
        terms.contains { term in
            let plural = term + "s"
            for start in words.indices {
                var joined = ""
                for word in words[start...] {
                    joined += word
                    if joined == term || joined == plural { return true }
                    if joined.count >= plural.count { break }
                }
            }
            return false
        }
    }

    /// Whether the name reads as a point in time: it mentions a date or time word, or ends in
    /// the `…At` / `…_at` convention (`createdAt`, `deleted_at`).
    var isDateLike: Bool {
        containsAny(of: ["date", "datetime", "time", "timestamp", "birthdate", "birthday"]) || words.last == "at"
    }
}
