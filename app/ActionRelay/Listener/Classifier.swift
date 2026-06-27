import Foundation

/// Action Button gesture classifier — Swift port of `core/src/classifier.rs`.
///
/// ponytail: this duplicates the Rust logic on purpose. The Rust copy is the
/// canonical, cargo-tested one; this runs in the app until the FFI bridge lands.
/// Keep the two in lockstep — any change here must be mirrored in classifier.rs
/// and re-tested there. Validated against real device timing (docs/signal.md).

enum Phase { case down, up }
enum Gesture { case press, hold, double }

struct ClassifierConfig {
    var pressMaxMs: UInt64 = 350
    var holdMinMs: UInt64 = 600
    var doubleWindowMs: UInt64 = 350
}

final class Classifier {
    private let cfg: ClassifierConfig
    private var downTs: UInt64?
    private var pendingPressUp: UInt64?

    init(_ cfg: ClassifierConfig) { self.cfg = cfg }

    /// Feed one HID transition. Returns Hold or Double to emit immediately; a
    /// single Press is buffered and surfaces later via `poll`.
    func onEvent(_ phase: Phase, _ tsMs: UInt64) -> Gesture? {
        switch phase {
        case .down:
            downTs = tsMs
            return nil
        case .up:
            guard let down = downTs else { return nil } // UP with no DOWN
            downTs = nil
            let dt = tsMs >= down ? tsMs - down : 0

            if dt >= cfg.holdMinMs { return .hold } // hold can't be half a double

            if let prevUp = pendingPressUp,
               tsMs >= prevUp, tsMs - prevUp <= cfg.doubleWindowMs {
                pendingPressUp = nil
                return .double
            }
            pendingPressUp = tsMs
            return nil
        }
    }

    /// Flush a buffered single press once its double-window has elapsed.
    func poll(_ nowMs: UInt64) -> Gesture? {
        if let up = pendingPressUp, nowMs >= up, nowMs - up >= cfg.doubleWindowMs {
            pendingPressUp = nil
            return .press
        }
        return nil
    }
}
