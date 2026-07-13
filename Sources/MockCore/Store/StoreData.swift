/// The complete in-memory state of a mock server: records grouped by type, per-type insertion
/// order, and the root field bindings.
///
/// A plain value type so it can be snapshotted for reads and transactionally replaced by
/// mutations. Protocol extensions (GraphQL, REST, …) execute against snapshots of this type.
public struct StoreData: Sendable, Hashable {
    /// Records: type name → record id → object value.
    public var records: [String: [String: MockValue]] = [:]
    /// Per-type insertion order of record ids, used for list resolution and pagination.
    public var order: [String: [String]] = [:]
    /// Root field bindings (typically references or lists of references). GraphQL wires these
    /// to root `Query` fields; other protocols may repurpose or ignore them.
    public var roots: [String: MockValue] = [:]
    /// Counter backing generated record ids.
    public var autoIDCounter: Int = 0

    /// Creates empty store data.
    public init() {}

    /// The record of the given type and id, or `nil`.
    public func record(type: String, id: String) -> MockValue? {
        records[type]?[id]
    }

    /// All records of a type, in insertion order.
    public func allRecords(type: String) -> [MockValue] {
        (order[type] ?? []).compactMap { records[type]?[$0] }
    }

    /// Inserts a record, generating an id when the fields don't carry one.
    /// - Returns: The record's id.
    @discardableResult
    public mutating func insert(type: String, fields: [String: MockValue]) -> String {
        var fields = fields
        let id: String
        if let provided = fields["id"]?.stringValue {
            id = provided
        } else {
            autoIDCounter += 1
            id = "\(type.lowercased())-auto-\(autoIDCounter)"
            fields["id"] = .string(id)
        }
        if records[type]?[id] == nil {
            order[type, default: []].append(id)
        }
        records[type, default: [:]][id] = .object(fields)
        return id
    }

    /// Removes a record. Returns `true` when it existed.
    @discardableResult
    public mutating func delete(type: String, id: String) -> Bool {
        guard records[type]?.removeValue(forKey: id) != nil else { return false }
        order[type]?.removeAll { $0 == id }
        return true
    }
}
