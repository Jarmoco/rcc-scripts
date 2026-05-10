# -----------------------------------------------------------------------------
# build-linux.sh
# Linux build script using nfpm for packaging.
# Builds: .deb, .rpm, .archlinux packages + generic tarball.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/package-manager.sh"

NFPM_CONFIG="$PROJECT_ROOT/nfpm.yaml"

if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(get_version_from_cargo)
fi

# --- Cleanup handler -------------------------------------------------------

cleanup_linux() {
    log_info "Linux build: cleaning up..."

    if [[ -f "$NFPM_CONFIG" ]]; then
        rm -f "$NFPM_CONFIG"
        log_info "Removed generated $NFPM_CONFIG"
    fi

    dep_cleanup_all
}

# --- Dependency checks -----------------------------------------------------

check_dependencies() {
    log_section "Linux Build: Dependencies"

    if ! verify_command "cargo" "rust"; then
        log_error "Rust/Cargo is required. Install from: https://rustup.rs"
        return 1
    fi

    if ! check_command "nfpm"; then
        echo ""
        log_warn "nfpm not found"

        if ! ask_yes_no "Install nfpm?"; then
            log_info "nfpm required for Linux build. Exiting."
            return 1
        fi

        if ! install_nfpm; then
            return 1
        fi
    fi

    log_success "All dependencies satisfied"
    return 0
}

# --- Build steps -----------------------------------------------------------

build_linux_packages() {
    log_section "Linux Build: Compiling"

    log_info "Building for Linux x86_64..."

    if ! cargo build --release 2>&1; then
        log_error "Cargo build failed"
        return 1
    fi

    BINARY="./target/release/${PROJECT_NAME}"
    if [[ ! -x "$BINARY" ]]; then
        log_error "Binary not found at $BINARY"
        return 1
    fi

    log_success "Linux binary compiled"
    return 0
}

package_linux_binaries() {
    log_section "Linux Build: Packaging"

    ensure_dir "$DIR_DIST"

    generate_nfpm_yaml "$NFPM_CONFIG" "$VERSION"

    if ! prompt_review_nfpm "$NFPM_CONFIG"; then
        return 1
    fi

    log_info "Creating .deb package..."
    if nfpm pkg --packager deb --config "$NFPM_CONFIG" --target "$DIR_DIST/" 2>&1; then
        log_success ".deb package created"
    else
        log_warn ".deb packaging failed (nfpm may need config)"
    fi

    log_info "Creating .rpm package..."
    if nfpm pkg --packager rpm --config "$NFPM_CONFIG" --target "$DIR_DIST/" 2>&1; then
        log_success ".rpm package created"
    else
        log_warn ".rpm packaging failed (nfpm may need config)"
    fi

    log_info "Creating .archlinux package..."
    if nfpm pkg --packager archlinux --config "$NFPM_CONFIG" --target "$DIR_DIST/" 2>&1; then
        log_success ".archlinux package created"
    else
        log_warn ".archlinux packaging failed (nfpm may need config)"
    fi

    log_info "Creating generic tarball..."
    if [[ -n "${BINARY:-}" ]] && [[ -x "$BINARY" ]]; then
        tar -czf "./$DIR_DIST/${PROJECT_NAME}_${VERSION}_linux_x86_64.tar.gz" \
            -C "$(dirname "$BINARY")" "${PROJECT_NAME}"
        log_success "Linux tarball created"
    else
        log_error "Binary not found, cannot create tarball"
        return 1
    fi

    rm -f "$NFPM_CONFIG"
    log_info "Cleaned up $NFPM_CONFIG"
    return 0
}

# --- Main ------------------------------------------------------------------

build_linux() {
    trap cleanup_linux EXIT

    log_section "Linux Build"

    if ! check_dependencies; then
        return 1
    fi

    if ! build_linux_packages; then
        return 1
    fi

    if ! package_linux_binaries; then
        return 1
    fi

    log_success "Linux build complete!"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_linux
fi
