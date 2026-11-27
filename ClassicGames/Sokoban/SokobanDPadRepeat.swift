import Foundation

/// 方向键点按 + 长按连发的可测状态机。真正的定时器由 UI 层驱动。
struct SokobanDPadRepeat {
    static let firstDelay: TimeInterval = 0.260
    static let interval: TimeInterval = 0.130
    static let defaultPointSize: Double = 50
    static let accessibilityPointSize: Double = 48
    static let hintStepDuration: TimeInterval = 0.140

    enum StopReason: Equatable, Sendable {
        case released
        case blocked
        case won
        case locked
    }

    enum Action: Equatable, Sendable {
        case step
        case stop(StopReason)
    }

    private(set) var direction: SokobanDirection?
    private var pressedAt: TimeInterval?
    private var lastStepAt: TimeInterval?
    private var firedFirst = false

    var isPressed: Bool { direction != nil }

    /// 按下立刻走第 1 步；若开局就被锁/顶死，立即停且不再连发。
    mutating func press(_ direction: SokobanDirection, at time: TimeInterval, allowed: Bool, locked: Bool, won: Bool) -> Action {
        reset()
        if locked { return .stop(.locked) }
        if won { return .stop(.won) }
        if !allowed { return .stop(.blocked) }
        self.direction = direction
        pressedAt = time
        lastStepAt = time
        firedFirst = true
        return .step
    }

    mutating func tick(at time: TimeInterval, allowed: Bool, locked: Bool, won: Bool) -> Action? {
        guard direction != nil, let pressedAt, firedFirst else { return nil }
        if locked { reset(); return .stop(.locked) }
        if won { reset(); return .stop(.won) }
        if !allowed { reset(); return .stop(.blocked) }
        let due = (lastStepAt ?? pressedAt) + (lastStepAt == pressedAt ? Self.firstDelay : Self.interval)
        // First delay is measured from the initial press/step.
        let firstDue = pressedAt + Self.firstDelay
        let nextDue: TimeInterval
        if lastStepAt == pressedAt {
            nextDue = firstDue
        } else {
            nextDue = (lastStepAt ?? pressedAt) + Self.interval
        }
        _ = due
        guard time >= nextDue else { return nil }
        lastStepAt = time
        return .step
    }

    mutating func release() -> Action? {
        guard direction != nil else { return nil }
        reset()
        return .stop(.released)
    }

    mutating func cancel(_ reason: StopReason) {
        reset()
        _ = reason
    }

    mutating func reset() {
        direction = nil
        pressedAt = nil
        lastStepAt = nil
        firedFirst = false
    }
}
