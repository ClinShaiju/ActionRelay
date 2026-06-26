//! C ABI surface for Swift. Minimal on purpose: one export locks in the
//! staticlib link shape so CI proves the cross-compile, without committing to a
//! full FFI before the tunnel exists. Expand (cbindgen header + classifier
//! handle exports) when the Rust core is linked into the NE.

/// ABI/version probe. Swift calls this to confirm the static lib linked.
/// Returns the core's ABI version (bump on any breaking ABI change).
#[no_mangle]
pub extern "C" fn actionrelay_abi_version() -> u32 {
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_stable() {
        assert_eq!(actionrelay_abi_version(), 1);
    }
}
