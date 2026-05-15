# -----------------------------------------------------------------------------
# build-windows.sh
# Windows cross-compile script from Linux using mingw-w64.
# Builds: Windows x86_64 .exe binary.
# Note: On Windows, just run 'cargo build --release' instead.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/package-manager.sh"

if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(get_version_from_cargo)
fi

MINGW_PACKAGES=()

# --- Cleanup handler -------------------------------------------------------

cleanup_windows() {
    log_info "Windows build: cleaning up..."
    dep_cleanup_all
}

# --- Dependency checks -----------------------------------------------------

check_dependencies() {
    log_section "Windows Build: Dependencies"

    if ! verify_command "cargo" "rust"; then
        log_error "Rust/Cargo is required"
        return 1
    fi

    if ! check_rust_target_installed "x86_64-pc-windows-gnu"; then
        echo ""
        log_warn "Windows GNU target not installed"

        if ! ask_yes_no "Install x86_64-pc-windows-gnu target?"; then
            log_info "Windows target required for cross-compile. Exiting."
            return 1
        fi

        if ! install_rust_target "x86_64-pc-windows-gnu" "x86_64-pc-windows-gnu"; then
            return 1
        fi
    fi

    if ! verify_command "x86_64-w64-mingw32-gcc" "mingw-w64"; then
        echo ""
        log_warn "mingw-w64 not found"

        if ! ask_yes_no "Install mingw-w64 for Windows cross-compilation?"; then
            log_info "mingw-w64 required for Windows cross-compile. Exiting."
            return 1
        fi

        if is_arch; then
            MINGW_PACKAGES=(
                "mingw-w64-binutils"
                "mingw-w64-gcc"
                "mingw-w64-headers"
                "mingw-w64-winpthreads"
            )
        elif is_debian; then
            MINGW_PACKAGES=("mingw-w64")
        elif is_fedora; then
            MINGW_PACKAGES=("mingw64-gcc" "mingw64-binutils" "mingw64-crt" "mingw64-headers")
        else
            log_error "Don't know how to install mingw-w64 on this system"
            log_info "Please install mingw-w64 manually:"
            log_info "  Debian/Ubuntu: sudo apt-get install mingw-w64"
            log_info "  Fedora:        sudo dnf install mingw64-gcc mingw64-binutils"
            return 1
        fi

        if ! install_system_packages MINGW_PACKAGES "mingw-w64"; then
            return 1
        fi
    fi

    log_success "All dependencies satisfied"
    return 0
}

# --- Build steps -----------------------------------------------------------

build_windows_binary() {
    log_section "Windows Build: Compiling"

    log_info "Cross-compiling for Windows x86_64..."

    if ! CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc \
         cargo build --target x86_64-pc-windows-gnu --release 2>&1; then
        log_error "Windows cross-compile failed"
        return 1
    fi

    BINARY="./target/x86_64-pc-windows-gnu/release/${PROJECT_NAME}.exe"
    if [[ ! -f "$BINARY" ]]; then
        log_error "Binary not found at $BINARY"
        return 1
    fi

    BINARIES=($(get_workspace_binaries))
    for bin in "${BINARIES[@]}"; do
        if [[ ! -f "./target/x86_64-pc-windows-gnu/release/${bin}.exe" ]]; then
            log_warn "Workspace binary not found: ./target/x86_64-pc-windows-gnu/release/${bin}.exe"
        fi
    done

    log_success "Windows binaries compiled"
    return 0
}

package_windows_binary() {
    log_section "Windows Build: Packaging"

    ensure_dir "$DIR_DIST"

    for bin in "${BINARIES[@]}"; do
        local src="./target/x86_64-pc-windows-gnu/release/${bin}.exe"
        local dest="$DIR_DIST/${bin}_${VERSION}_windows_x86_64.exe"
        if [[ -f "$src" ]]; then
            cp "$src" "$dest"
            log_success "Windows .exe created: $dest"
        else
            log_warn "Windows binary not found: $src"
        fi
    done

    return 0
}

# --- Main ------------------------------------------------------------------

build_windows() {
    trap cleanup_windows EXIT

    log_section "Windows Build"

    if ! check_dependencies; then
        return 1
    fi

    if ! build_windows_binary; then
        return 1
    fi

    if ! package_windows_binary; then
        return 1
    fi

    log_success "Windows build complete!"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_windows
fi
