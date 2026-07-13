/// A transactional, value-semantics view of server state handed to mutation handlers.
///
/// Everything a handler changes becomes visible to subsequent operations only when the handler
/// returns successfully; a thrown error discards all of its writes. The same surface is handed
/// to handler closures by every protocol extension, so mutation code is portable across them:
///
/// ```swift
/// Mutation("addToCart") { input, state in
///     state.update("Cart", id: "cart-1") { cart in
///         cart["items"].append([
///             "product": .reference("Product", id: input["productId"]),
///             "quantity": input["quantity"] ?? 1,
///         ])
///     }
///     return state["Cart", id: "cart-1"]
/// }
/// ```
public struct MutationState: Sendable {
    var data: StoreData

    /// Creates a transactional view over a snapshot of store data.
    ///
    /// Most code should mutate through ``StateStore/withMutationState(_:)``, which commits the
    /// writes atomically; construct one directly only to exercise handler closures in tests.
    public init(data: StoreData) {
        self.data = data
    }

    /// Reads or replaces a whole record. Reading a missing record returns `.null`.
    public subscript(type: String, id id: String) -> MockValue {
        get {
            data.record(type: type, id: id) ?? .null
        }
        set {
            guard var fields = newValue.objectValue else { return }
            fields["id"] = .string(id)
            if data.records[type]?[id] == nil {
                data.order[type, default: []].append(id)
            }
            data.records[type, default: [:]][id] = .object(fields)
        }
    }

    /// Mutates a record in place. Does nothing when the record doesn't exist.
    public mutating func update(_ type: String, id: String, _ body: (inout MockValue) -> Void) {
        guard var record = data.record(type: type, id: id) else { return }
        body(&record)
        self[type, id: id] = record
    }

    /// Inserts a new record and returns it (including its — possibly generated — id).
    @discardableResult
    public mutating func insert(_ type: String, _ fields: MockValue) -> MockValue {
        let id = data.insert(type: type, fields: fields.objectValue ?? [:])
        return data.record(type: type, id: id) ?? .null
    }

    /// Deletes a record. Returns `true` when it existed.
    @discardableResult
    public mutating func delete(_ type: String, id: String) -> Bool {
        data.delete(type: type, id: id)
    }

    /// All records of a type, in insertion order.
    public func records(ofType type: String) -> [MockValue] {
        data.allRecords(type: type)
    }

    /// The ids of all records of a type, in insertion order.
    public func ids(ofType type: String) -> [String] {
        data.order[type] ?? []
    }

    /// Reads a root field binding. Missing roots read as `.null`.
    public func root(_ field: String) -> MockValue {
        data.roots[field] ?? .null
    }

    /// Binds a root field to a value — usually a `.reference` or a list of references.
    public mutating func setRoot(_ field: String, to value: MockValue) {
        data.roots[field] = value
    }
}
