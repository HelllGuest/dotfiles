# rust-toolchain.sh — sourced helper. Stage A installs rustup (not rust), and a
# fresh rustup has no default toolchain: cargo/rustc then fail ("rustup could
# not choose a version"). Anything that builds Rust calls ensure_rust_toolchain.
# shellcheck shell=bash

# ensure_rust_toolchain: 0 when cargo works (after `rustup default stable` if
# rustup has no default yet), 1 when there is no usable Rust at all.
ensure_rust_toolchain() {
    if command -v cargo >/dev/null 2>&1 && cargo --version >/dev/null 2>&1; then
        return 0
    fi
    if command -v rustup >/dev/null 2>&1; then
        echo "No default Rust toolchain configured; running 'rustup default stable'..."
        rustup default stable || return 1
        cargo --version >/dev/null 2>&1
        return
    fi
    return 1
}
