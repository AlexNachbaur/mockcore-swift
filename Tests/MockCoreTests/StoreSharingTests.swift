import Testing

@testable import MockCore

/// The store operations that make cross-protocol sharing work: merging a second service's seed
/// and snapshotting mid-transaction state.
@Suite struct StoreSharingTests {
    @Test func mergeAddsRecordsAndPreservesExistingOrder() async {
        let store = StateStore()
        var first = StoreData()
        first.insert(type: "User", fields: ["id": "u1", "name": "Avery"])
        first.roots["me"] = .reference("User", id: "u1")
        await store.load(first)

        var second = StoreData()
        second.insert(type: "User", fields: ["id": "u2", "name": "Blake"])
        second.insert(type: "Product", fields: ["id": "p1"])
        second.roots["featured"] = .reference("Product", id: "p1")
        await store.merge(second)

        let users = await store.records(ofType: "User")
        #expect(users.map { $0["id"] } == [.string("u1"), .string("u2")])
        #expect(await store.records(ofType: "Product").count == 1)
        #expect(await store.root("me") == .reference("User", id: "u1"))
        #expect(await store.root("featured") == .reference("Product", id: "p1"))
    }

    @Test func mergeIncomingWinsOnIdCollision() async {
        let store = StateStore()
        var first = StoreData()
        first.insert(type: "User", fields: ["id": "u1", "name": "Original"])
        await store.load(first)

        var second = StoreData()
        second.insert(type: "User", fields: ["id": "u1", "name": "Replacement"])
        await store.merge(second)

        let user = await store.record(type: "User", id: "u1")
        #expect(user?["name"] == .string("Replacement"))
        #expect(await store.records(ofType: "User").count == 1)
    }

    @Test func mergeKeepsTheHigherAutoIDCounter() async {
        let store = StateStore()
        var incoming = StoreData()
        incoming.insert(type: "User", fields: [:])
        await store.merge(incoming)
        // A subsequent generated id must not collide with the merged one.
        await store.withMutationState { state in
            state.insert("User", .object([:]))
        }
        #expect(await store.records(ofType: "User").count == 2)
    }

    @Test func mergeKeepsRecordsMissingFromTheOrderIndex() async {
        let store = StateStore()
        var incoming = StoreData()
        // A caller can legally populate `records` without an `order` entry; merge must not
        // silently drop such records.
        incoming.records["User"] = ["u1": .object(["id": .string("u1"), "name": .string("Avery")])]
        await store.merge(incoming)
        #expect(await store.record(type: "User", id: "u1")?["name"] == .string("Avery"))
        #expect(await store.records(ofType: "User").count == 1)
    }

    @Test func insertCoercesIntegerIdsToStrings() async {
        let store = StateStore()
        await store.withMutationState { state in
            state.insert("User", ["id": 42, "name": "Avery"])
        }
        let record = await store.record(type: "User", id: "42")
        #expect(record?["id"] == .string("42"))
    }

    @Test func storeDataExposesUncommittedWritesToTheTransaction() async {
        let store = StateStore()
        await store.withMutationState { state in
            state.insert("User", ["id": "u1", "name": .string("Avery")])
            let snapshot = state.storeData
            #expect(snapshot.record(type: "User", id: "u1")?["name"] == .string("Avery"))
        }
    }
}
