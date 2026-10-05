import NIOConcurrencyHelpers

/// Tracks the requests a ``MockHost`` has handed to services, so shutdown can wait for them.
///
/// Service handlers are `async`, so each claimed request runs in its own task. Without a
/// record of those tasks a stopping host could neither let them finish nor keep new ones from
/// reaching a service that has already been shut down — both of which surface in a test as a
/// connection error with no obvious cause.
final class RequestTracker: Sendable {
    private struct State {
        var isAccepting = true
        var nextID: UInt64 = 0
        var tasks: [UInt64: Task<Void, Never>] = [:]
    }

    private let state = NIOLockedValueBox(State())

    /// Runs `operation` as a tracked task.
    ///
    /// - Returns: `false`, without running `operation`, once ``stopAccepting()`` has been
    ///   called — the caller must answer the request itself.
    func run(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        state.withLockedValue { state in
            guard state.isAccepting else { return false }
            let id = state.nextID
            state.nextID += 1
            // Created under the lock so the task is registered before it can possibly finish:
            // `finish` takes the same lock and therefore always finds its entry.
            state.tasks[id] = Task {
                await operation()
                self.finish(id)
            }
            return true
        }
    }

    /// Refuses every later ``run(_:)``. Requests already running are unaffected.
    func stopAccepting() {
        state.withLockedValue { $0.isAccepting = false }
    }

    /// Waits for every tracked request to finish.
    ///
    /// Requests still running after `gracePeriod` are cancelled, then awaited: a handler that
    /// honors cancellation (as `Task.sleep`-based delays do) answers promptly, so its client
    /// still receives a response rather than a dropped connection.
    func drain(gracePeriod: Duration) async {
        let tasks = state.withLockedValue { Array($0.tasks.values) }
        guard !tasks.isEmpty else { return }
        let canceller = Task {
            try await Task.sleep(for: gracePeriod)
            for task in tasks {
                task.cancel()
            }
        }
        for task in tasks {
            await task.value
        }
        canceller.cancel()
    }

    private func finish(_ id: UInt64) {
        state.withLockedValue { state in
            state.tasks[id] = nil
        }
    }
}
