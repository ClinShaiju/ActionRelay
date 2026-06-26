//! Action Button gesture classifier — the §8.1 state machine.
//!
//! Pure logic, no I/O, no clock of its own: the caller feeds `(phase, ts_ms)`
//! pairs and periodically calls `poll(now_ms)` to flush a buffered single press.
//! This is the one genuinely hardware-independent, fully-testable piece of the
//! project, so it is the canonical implementation. The Swift port in
//! `tunnel/Classifier.swift` must stay byte-for-byte equivalent until the FFI
//! bridge replaces it.
//!
//! ponytail: timestamps are plain u64 milliseconds (monotonic). No Duration
//! wrapper — upgrade only if we need sub-ms or cross-platform clock types.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Down,
    Up,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Gesture {
    Press,
    Hold,
    Double,
}

/// Tunables (§8.1). Live in config so they can be patched per-iOS without a rebuild.
#[derive(Clone, Copy, Debug)]
pub struct Config {
    /// up-down dt strictly below this ⇒ press.
    pub press_max_ms: u64,
    /// up-down dt at or above this ⇒ hold.
    pub hold_min_ms: u64,
    /// two presses whose UPs fall within this window ⇒ double.
    pub double_window_ms: u64,
}

impl Default for Config {
    fn default() -> Self {
        Config { press_max_ms: 350, hold_min_ms: 600, double_window_ms: 350 }
    }
}

pub struct Classifier {
    cfg: Config,
    /// Timestamp of the most recent unmatched DOWN, if the button is currently down.
    down_ts: Option<u64>,
    /// UP timestamp of a single press buffered awaiting a possible second press.
    pending_press_up: Option<u64>,
}

impl Classifier {
    pub fn new(cfg: Config) -> Self {
        Classifier { cfg, down_ts: None, pending_press_up: None }
    }

    /// Feed one HID transition. Returns a gesture that must be emitted *now*
    /// (Hold or Double). A single Press is never returned here — it is buffered
    /// and surfaces later via `poll` so a second press can supersede it.
    pub fn on_event(&mut self, phase: Phase, ts_ms: u64) -> Option<Gesture> {
        match phase {
            Phase::Down => {
                // Latest DOWN wins; a stray repeated DOWN just refreshes the anchor.
                self.down_ts = Some(ts_ms);
                None
            }
            Phase::Up => {
                let down = self.down_ts.take()?; // UP with no DOWN: ignore.
                let dt = ts_ms.saturating_sub(down);

                if dt >= self.cfg.hold_min_ms {
                    // Hold fires immediately; it cannot be half of a double.
                    return Some(Gesture::Hold);
                }
                // press (dt < press_max) or ambiguous (press_max..hold_min) ⇒ treat as press.

                if let Some(prev_up) = self.pending_press_up {
                    if ts_ms.saturating_sub(prev_up) <= self.cfg.double_window_ms {
                        self.pending_press_up = None;
                        return Some(Gesture::Double);
                    }
                }
                // Buffer this press; `poll` flushes it once the double window closes.
                self.pending_press_up = Some(ts_ms);
                None
            }
        }
    }

    /// Flush a buffered single press whose double-window has elapsed.
    /// Call on a timer (or on each new event) with the current monotonic time.
    pub fn poll(&mut self, now_ms: u64) -> Option<Gesture> {
        if let Some(up) = self.pending_press_up {
            if now_ms.saturating_sub(up) >= self.cfg.double_window_ms {
                self.pending_press_up = None;
                return Some(Gesture::Press);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c() -> Classifier {
        Classifier::new(Config::default())
    }

    #[test]
    fn single_press_buffers_then_flushes() {
        let mut k = c();
        assert_eq!(k.on_event(Phase::Down, 0), None);
        assert_eq!(k.on_event(Phase::Up, 100), None); // press buffered, not yet emitted
        assert_eq!(k.poll(300), None); // window (350) not elapsed
        assert_eq!(k.poll(450), Some(Gesture::Press)); // elapsed ⇒ emit
        assert_eq!(k.poll(500), None); // only once
    }

    #[test]
    fn hold_emits_immediately() {
        let mut k = c();
        k.on_event(Phase::Down, 0);
        assert_eq!(k.on_event(Phase::Up, 700), Some(Gesture::Hold));
        assert_eq!(k.poll(2000), None); // hold never buffers
    }

    #[test]
    fn ambiguous_treated_as_press() {
        let mut k = c();
        k.on_event(Phase::Down, 0);
        // 500ms: between press_max(350) and hold_min(600) ⇒ ambiguous ⇒ press
        assert_eq!(k.on_event(Phase::Up, 500), None);
        assert_eq!(k.poll(900), Some(Gesture::Press));
    }

    #[test]
    fn double_press_within_window() {
        let mut k = c();
        k.on_event(Phase::Down, 0);
        k.on_event(Phase::Up, 80); // first press buffered (up@80)
        k.on_event(Phase::Down, 200);
        // second up@300, within 350 of 80? 300-80=220 ≤ 350 ⇒ double
        assert_eq!(k.on_event(Phase::Up, 300), Some(Gesture::Double));
        assert_eq!(k.poll(1000), None); // buffer cleared by the double
    }

    #[test]
    fn two_far_apart_presses_are_two_singles() {
        let mut k = c();
        k.on_event(Phase::Down, 0);
        k.on_event(Phase::Up, 80);
        assert_eq!(k.poll(500), Some(Gesture::Press)); // first flushes
        k.on_event(Phase::Down, 600);
        k.on_event(Phase::Up, 680);
        assert_eq!(k.poll(1100), Some(Gesture::Press)); // second flushes separately
    }

    #[test]
    fn up_without_down_is_ignored() {
        let mut k = c();
        assert_eq!(k.on_event(Phase::Up, 100), None);
        assert_eq!(k.poll(1000), None);
    }

    #[test]
    fn hold_does_not_pair_with_a_following_press() {
        let mut k = c();
        k.on_event(Phase::Down, 0);
        assert_eq!(k.on_event(Phase::Up, 700), Some(Gesture::Hold));
        // a press right after a hold is still just a single press
        k.on_event(Phase::Down, 800);
        assert_eq!(k.on_event(Phase::Up, 880), None);
        assert_eq!(k.poll(1300), Some(Gesture::Press));
    }
}
