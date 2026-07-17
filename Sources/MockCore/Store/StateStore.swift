/// The actor guarding a mock server's in-memory state.
///
/// Reads take an immutable snapshot; mutations run against a transactional ``MutationState``
/// whose writes are committed atomically when the handler returns. One store can be shared by
/// several protocol extensions on the same host, so a mutation performed through one protocol
/// is visible to queries made through another.
public actor StateStore {
    private var data = StoreData()

    /// Creates an empty store.
    public init() {}

    /// Replaces the entire store contents (used by seed loading).
    public func load(_ data: StoreData) {
        self.data = data
    }

    /// Merges seed data into the existing contents — how a second protocol extension loads its
    /// seed into a store it shares with a sibling. Incoming records win on id collisions;
    /// insertion order of existing records is preserved.
    public func merge(_ incoming: StoreData) {
        for (type, records) in incoming.records {
            var merged: Set<String> = []
            for id in incoming.order[type] ?? [] {
                guard let record = records[id] else { continue }
                if data.records[type]?[id] == nil {
                    data.order[type, default: []].append(id)
                }
                data.records[type, default: [:]][id] = record
                merged.insert(id)
            }
            // Records a caller stored without an `order` entry still merge (sorted for
            // determinism) rather than silently vanishing.
            for id in records.keys.sorted() where !merged.contains(id) {
                if data.records[type]?[id] == nil {
                    data.order[type, default: []].append(id)
                }
                data.records[type, default: [:]][id] = records[id]
            }
        }
        for (field, value) in incoming.roots {
            data.roots[field] = value
        }
        data.autoIDCounter = max(data.autoIDCounter, incoming.autoIDCounter)
    }

    /// An immutable snapshot of the current state for query execution.
    public func snapshot() -> StoreData {
        data
    }

    /// Runs a transactional mutation. Writes are committed only when `body` returns without
    /// throwing.
    public func withMutationState<T: Sendable>(
        _ body: @Sendable (inout MutationState) throws -> T
    ) rethrows -> T {
        var state = MutationState(data: data)
        let result = try body(&state)
        data = state.data
        return result
    }

    // MARK: - Convenience accessors

    /// The record of the given type and id, or `nil`.
    public func record(type: String, id: String) -> MockValue? {
        data.record(type: type, id: id)
    }

    /// All records of a type, in insertion order.
    public func records(ofType type: String) -> [MockValue] {
        data.allRecords(type: type)
    }

    /// The current root binding for a field, or `.null`.
    public func root(_ field: String) -> MockValue {
        data.roots[field] ?? .null
    }

    /// Removes all records and roots.
    public func reset() {
        data = StoreData()
    }
}
