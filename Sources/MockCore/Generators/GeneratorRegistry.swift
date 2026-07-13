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
    public static func inferred(fieldName: String, scalarTypeName: String) -> FieldGenerator {
        let lowered = fieldName.lowercased()
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
            if lowered.contains("email") { return .email }
            if lowered.contains("phone") { return .phoneNumber }
            if lowered.contains("url") || lowered.contains("website") || lowered.contains("link") { return .url }
            if lowered.contains("username") || lowered.contains("handle") { return .username }
            if lowered.contains("firstname") { return .firstName }
            if lowered.contains("lastname") || lowered.contains("surname") { return .lastName }
            if lowered.contains("name") || lowered.contains("title") { return .fullName }
            if lowered.contains("description") || lowered.contains("summary") || lowered.contains("bio") {
                return .sentence
            }
            if lowered.contains("date") || lowered.contains("time") || lowered.hasSuffix("at") { return .dateTime }
            return .sentence
        default:
            // Custom scalars: date-like names get timestamps; anything else gets an opaque string.
            if lowered.contains("date") || lowered.contains("time") || lowered.hasSuffix("at")
                || scalarTypeName.lowercased().contains("date") || scalarTypeName.lowercased().contains("time")
            {
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
