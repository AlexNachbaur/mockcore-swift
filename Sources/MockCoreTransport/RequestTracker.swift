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

    /// Whether ``run(_:)`` still accepts work.
    var isAccepting: Bool {
        state.withLockedValue { $0.isAccepting }
    }

    /// Waits for every tracked request to finish, for at most twice `gracePeriod`.
    ///
    /// Requests still running after `gracePeriod` are cancelled and given a second grace
    /// period: a handler that honors cancellation (as `Task.sleep`-based delays do) answers
    /// promptly, so its client still receives a response rather than a dropped connection. A
    /// handler that ignores cancellation — or that is itself awaiting this host's `stop()` —
    /// is then abandoned rather than awaited forever; the channel it eventually writes to
    /// will already be closed.
    func drain(gracePeriod: Duration) async {
        let tasks = state.withLockedValue { Array($0.tasks.values) }
        guard !tasks.isEmpty else { return }
        if await Self.allFinished(tasks, within: gracePeriod) {
            return
        }
        for task in tasks {
            task.cancel()
        }
        _ = await Self.allFinished(tasks, within: gracePeriod)
    }

    /// Whether every task finished before the timeout elapsed.
    ///
    /// `await task.value` cannot be cancelled, so the wait is raced against a timer through a
    /// one-shot continuation; whichever side loses keeps running to completion on its own.
    private static func allFinished(_ tasks: [Task<Void, Never>], within timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            let resumed = NIOLockedValueBox(false)
            let finish: @Sendable (Bool) -> Void = { finished in
                let alreadyResumed = resumed.withLockedValue { resumed in
                    defer { resumed = true }
                    return resumed
                }
                if !alreadyResumed {
                    continuation.resume(returning: finished)
                }
            }
            Task {
                for task in tasks {
                    await task.value
                }
                finish(true)
            }
            Task {
                try? await Task.sleep(for: timeout)
                finish(false)
            }
        }
    }

    private func finish(_ id: UInt64) {
        state.withLockedValue { state in
            state.tasks[id] = nil
        }
    }
}
