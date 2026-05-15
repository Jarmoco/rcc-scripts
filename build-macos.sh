# -----------------------------------------------------------------------------
# build-macos.sh
# macOS cross-compile script from Linux using cargo-zigbuild.
# Builds: macOS aarch64 (Apple Silicon) binary as tarball.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/package-manager.sh"

if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(get_version_from_cargo)
fi

# --- Cleanup handler -------------------------------------------------------

cleanup_macos() {
    log_info "macOS build: cleaning up..."
    dep_cleanup_all
}

# --- Dependency checks -----------------------------------------------------

check_dependencies() {
    log_section "macOS Build: Dependencies"

    if ! verify_command "cargo" "rust"; then
        log_error "Rust/Cargo is required"
        return 1
    fi

    if ! check_command "zig"; then
        echo ""
        log_warn "zig not found"

        if ! ask_yes_no "Install zig?"; then
            log_info "zig required for macOS cross-compile. Exiting."
            return 1
        fi

        if ! install_zig; then
            return 1
        fi
    fi

    if ! check_command "cargo-zigbuild"; then
        echo ""
        log_warn "cargo-zigbuild not found"

        if ! ask_yes_no "Install cargo-zigbuild via cargo?"; then
            log_info "cargo-zigbuild required for macOS cross-compile. Exiting."
            return 1
        fi

        if ! install_cargo_tool "cargo-zigbuild" "cargo-zigbuild"; then
            return 1
        fi
    fi

    if ! check_rust_target_installed "aarch64-apple-darwin"; then
        echo ""
        log_warn "macOS aarch64 target not installed"

        if ! ask_yes_no "Install aarch64-apple-darwin target?"; then
            log_info "macOS target required for cross-compile. Exiting."
            return 1
        fi

        if ! install_rust_target "aarch64-apple-darwin" "aarch64-apple-darwin"; then
            return 1
        fi
    fi

    log_success "All dependencies satisfied"
    return 0
}

# --- Build steps -----------------------------------------------------------

build_macos_binary() {
    log_section "macOS Build: Compiling"

    log_info "Cross-compiling for macOS aarch64..."

    if ! CFLAGS_aarch64_apple_darwin="-Wno-unknown-warning-option" \
        cargo zigbuild --target aarch64-apple-darwin --release 2>&1; then
        log_error "cargo zigbuild failed"
        return 1
    fi

    BINARY="./target/aarch64-apple-darwin/release/${PROJECT_NAME}"
    if [[ ! -x "$BINARY" ]]; then
        log_error "Binary not found at $BINARY"
        return 1
    fi

    BINARIES=($(get_workspace_binaries))
    for bin in "${BINARIES[@]}"; do
        if [[ ! -x "./target/aarch64-apple-darwin/release/$bin" ]]; then
            log_warn "Workspace binary not found: ./target/aarch64-apple-darwin/release/$bin"
        fi
    done

    log_success "macOS binaries compiled"
    return 0
}

package_macos_binary() {
    log_section "macOS Build: Packaging"

    ensure_dir "$DIR_DIST"

    for bin in "${BINARIES[@]}"; do
        log_info "Creating tarball for $bin..."
        tar -czf "./$DIR_DIST/${bin}_${VERSION}_macos_aarch64.tar.gz" \
            -C "./target/aarch64-apple-darwin/release" "$bin"
        log_success "Tarball for $bin created"
    done

    return 0
}

# --- Main ------------------------------------------------------------------

build_macos() {
    trap cleanup_macos EXIT

    log_section "macOS Build"

    if ! check_dependencies; then
        return 1
    fi

    if ! build_macos_binary; then
        return 1
    fi

    if ! package_macos_binary; then
        return 1
    fi

    log_success "macOS build complete!"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_macos
fi
