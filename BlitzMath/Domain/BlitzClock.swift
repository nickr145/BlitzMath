//
//  BlitzClock.swift
//  BlitzMath
//
//  Monotonic elapsed-time source for the Blitz Engine (SRS FR-BLZ).
//  Immune to wall-clock adjustment. Paused intervals are excluded.
//

import Foundation

// MARK: - Time source

/// Abstracted so tests can drive time deterministically.
protocol MonotonicTimeSource: Sendable {
    var now: TimeInterval { get }
}

struct SystemMonotonicTimeSource: MonotonicTimeSource {
    /// Seconds since an arbitrary fixed reference, unaffected by clock changes.
    var now: TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// Manual source for unit tests.
final class ManualTimeSource: MonotonicTimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(start: TimeInterval = 0) { value = start }

    var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value += interval
    }
}

// MARK: - Clock

@MainActor
@Observable
final class BlitzClock {

    enum State: String, Sendable { case idle, running, paused, stopped }

    private(set) var state: State = .idle
    /// Published elapsed time, refreshed by the tick loop at `tickInterval`.
    private(set) var elapsed: TimeInterval = 0

    private let source: MonotonicTimeSource
    private let tickInterval: Duration
    private var segmentStart: TimeInterval?
    private var accumulated: TimeInterval = 0
    private var tickTask: Task<Void, Never>?

    /// 10 Hz satisfies FR-BLZ-002 without pushing the question surface into a rebuild loop.
    init(source: MonotonicTimeSource = SystemMonotonicTimeSource(),
         tickInterval: Duration = .milliseconds(100)) {
        self.source = source
        self.tickInterval = tickInterval
    }

    // No deinit: the tick loop captures [weak self] and returns once the
    // clock deallocates, so the task cancels itself. deinit is nonisolated
    // and cannot touch @MainActor state.

    // MARK: Control

    func start() {
        guard state == .idle || state == .stopped else { return }
        accumulated = 0
        elapsed = 0
        segmentStart = source.now
        state = .running
        startTicking()
    }

    func pause() {
        guard state == .running else { return }
        accumulate()
        state = .paused
        tickTask?.cancel()
        tickTask = nil
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = source.now
        state = .running
        startTicking()
    }

    /// Stops and returns the final measurement. Called before answer validation (FR-BLZ-008).
    @discardableResult
    func stop() -> TimeInterval {
        if state == .running { accumulate() }
        state = .stopped
        tickTask?.cancel()
        tickTask = nil
        elapsed = accumulated
        return accumulated
    }

    func reset() {
        tickTask?.cancel()
        tickTask = nil
        segmentStart = nil
        accumulated = 0
        elapsed = 0
        state = .idle
    }

    // MARK: Derived values

    /// Fraction of the SCT consumed, clamped to 1.0 for the progress ring (FR-BLZ-004).
    func sctFraction(target: TimeInterval) -> Double {
        guard target > 0 else { return 0 }
        return min(1.0, elapsed / target)
    }

    /// Ring state thresholds at 0.75 and 1.0 of the SCT (FR-BLZ-005).
    enum Pace: String, Sendable { case comfortable, tightening, overTarget }

    func pace(target: TimeInterval) -> Pace {
        guard target > 0 else { return .comfortable }
        let fraction = elapsed / target
        if fraction >= 1.0 { return .overTarget }
        if fraction >= 0.75 { return .tightening }
        return .comfortable
    }

    // MARK: Internals

    private func accumulate() {
        guard let segmentStart else { return }
        accumulated += source.now - segmentStart
        self.segmentStart = nil
        elapsed = accumulated
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self, self.state == .running else { return }
                self.refreshElapsed()
            }
        }
    }

    private func refreshElapsed() {
        guard let segmentStart else { return }
        elapsed = accumulated + (source.now - segmentStart)
    }
}
