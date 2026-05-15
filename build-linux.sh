# -----------------------------------------------------------------------------
# build-linux.sh
# Linux build script using nfpm for packaging.
# Builds: .deb, .rpm, .archlinux packages + generic tarball.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/package-manager.sh"

if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(get_version_from_cargo)
fi

# --- Cleanup handler -------------------------------------------------------

cleanup_linux() {
    log_info "Linux build: cleaning up..."

    rm -f "$PROJECT_ROOT"/*-nfpm.yaml 2>/dev/null || true

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

    BINARIES=($(get_workspace_binaries))
    for bin in "${BINARIES[@]}"; do
        if [[ ! -x "./target/release/$bin" ]]; then
            log_warn "Workspace binary not found: ./target/release/$bin"
        fi
    done

    log_success "Linux binaries compiled"
    return 0
}

package_linux_binaries() {
    log_section "Linux Build: Packaging"

    ensure_dir "$DIR_DIST"

    for bin in "${BINARIES[@]}"; do
        local cfg="$PROJECT_ROOT/${bin}-nfpm.yaml"

        generate_nfpm_yaml "$cfg" "$VERSION" "$bin"

        if [[ ${#BINARIES[@]} -eq 1 ]]; then
            if ! prompt_review_nfpm "$cfg"; then
                rm -f "$cfg"
                return 1
            fi
        fi

        log_info "Creating .deb package for $bin..."
        if nfpm pkg --packager deb --config "$cfg" --target "$DIR_DIST/" 2>&1; then
            log_success ".deb package for $bin created"
        else
            log_warn ".deb packaging for $bin failed"
        fi

        log_info "Creating .rpm package for $bin..."
        if nfpm pkg --packager rpm --config "$cfg" --target "$DIR_DIST/" 2>&1; then
            log_success ".rpm package for $bin created"
        else
            log_warn ".rpm packaging for $bin failed"
        fi

        log_info "Creating .archlinux package for $bin..."
        if nfpm pkg --packager archlinux --config "$cfg" --target "$DIR_DIST/" 2>&1; then
            log_success ".archlinux package for $bin created"
        else
            log_warn ".archlinux packaging for $bin failed"
        fi

        log_info "Creating tarball for $bin..."
        tar -czf "./$DIR_DIST/${bin}_${VERSION}_linux_x86_64.tar.gz" \
            -C "./target/release" "$bin"
        log_success "Tarball for $bin created"

        rm -f "$cfg"
    done

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
