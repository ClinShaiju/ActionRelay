//! ActionRelay core.
//!
//! What is real today: the gesture `classifier` (fully tested).
//! What is scaffolding pending Phase 0 + hardware: `relay` (wire-format notes)
//! and `ffi` (one export to lock in the C ABI shape). The tunnel itself lives
//! in `idevice`/`minimuxer`/`em_proxy` and is wired in once Phase 0 confirms a
//! usable signal — see PROJECT.md §10 and docs/signal.md.

pub mod classifier;
pub mod ffi;
pub mod relay;
