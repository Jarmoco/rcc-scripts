# -----------------------------------------------------------------------------
# package-manager.sh
# Package installation utilities for build scripts.
# Supports Arch Linux, Debian/Ubuntu, Fedora, and direct downloads.
# -----------------------------------------------------------------------------

# --- Package manager -------------------------------------------------------

is_arch() {
    check_command pacman
}

is_debian() {
    check_command apt-get
}

is_fedora() {
    check_command dnf
}

# --- AUR helper -----------------------------------------------------------

has_aur_helper() {
    if check_command yay; then
        echo "yay"
    elif check_command paru; then
        echo "paru"
    else
        echo ""
    fi
}

# --- System package installation -------------------------------------------

install_system_packages() {
    local -n packages=$1
    local name="${2:-packages}"

    log_info "Installing $name..."

    if is_arch; then
        sudo pacman -S --noconfirm "${packages[@]}" 2>/dev/null
    elif is_debian; then
        sudo apt-get install -y "${packages[@]}" 2>/dev/null
    elif is_fedora; then
        sudo dnf install -y "${packages[@]}" 2>/dev/null
    else
        return 2
    fi

    local ret=$?
    if [[ $ret -eq 0 ]]; then
        log_success "Installed $name"
        dep_track "system" "${packages[*]}"
        return 0
    else
        log_error "Failed to install $name"
        return 1
    fi
}

# --- System package removal ------------------------------------------------

remove_system_packages() {
    local -n packages=$1
    local name="${2:-packages}"

    log_info "Removing $name..."

    if is_arch; then
        sudo pacman -Rs --noconfirm "${packages[@]}" 2>/dev/null || true
    elif is_debian; then
        sudo apt-get remove --autoremove -y "${packages[@]}" 2>/dev/null || true
    elif is_fedora; then
        sudo dnf remove -y "${packages[@]}" 2>/dev/null || true
    fi

    log_success "Removed $name"
    return 0
}

# --- AUR installation ------------------------------------------------------

install_aur() {
    local package="$1"
    local name="${2:-$package}"
    local aur_helper

    if check_command "$package"; then
        return 1
    fi

    aur_helper=$(has_aur_helper)

    if [[ -z "$aur_helper" ]]; then
        log_error "No AUR helper (yay/paru)"
        return 2
    fi

    log_info "Installing $name from AUR..."
    if $aur_helper -S --noconfirm "$package" 2>/dev/null; then
        dep_track "system" "$package"
        log_success "Installed $name"
        return 0
    else
        log_error "Failed to install $name from AUR"
        return 1
    fi
}

# --- Rust target installation ----------------------------------------------

install_rust_target() {
    local target="$1"
    local name="$2"

    if check_rust_target_installed "$target"; then
        return 1
    fi

    log_info "Installing Rust target: $name..."
    if rustup target add "$target" 2>/dev/null; then
        dep_track "rust_target" "$target"
        log_success "Installed $target"
        return 0
    else
        log_error "Failed to install $target"
        return 1
    fi
}

# --- Cargo tool installation -----------------------------------------------

install_cargo_tool() {
    local tool="$1"
    local name="${2:-$tool}"

    if check_command "$tool"; then
        return 1
    fi

    log_info "Installing cargo tool: $name..."
    if cargo install "$tool" 2>/dev/null; then
        dep_track "cargo_tool" "$tool"
        log_success "Installed $name"
        return 0
    else
        log_error "Failed to install $name"
        return 1
    fi
}

# --- Tarball download installation -----------------------------------------

install_from_url() {
    local url="$1"
    local extract_to="$2"
    local binary_name="$3"

    if check_command "$binary_name"; then
        return 1
    fi

    local temp_dir="/tmp/${PROJECT_NAME}-build"
    mkdir -p "$temp_dir"
    local archive="$temp_dir/$(basename "$url")"

    if ! download_file "$url" "$archive" "$binary_name"; then
        return 1
    fi

    mkdir -p "$extract_to"
    if ! extract_tarball "$archive" "$extract_to"; then
        log_error "Failed to extract $binary_name"
        rm -f "$archive"
        return 1
    fi

    rm -f "$archive"
    dep_track "download" "$extract_to"
    export PATH="$extract_to:$PATH"
    log_success "Installed $binary_name"
    return 0
}

# --- nfpm installation -----------------------------------------------------

install_nfpm() {
    if check_command "nfpm"; then
        return 1
    fi

    log_info "Installing nfpm..."

    if is_debian; then
        if sudo apt-get install -y nfpm 2>/dev/null; then
            dep_track "system" "nfpm"
            log_success "Installed nfpm"
            return 0
        fi
        log_info "apt nfpm not available, trying direct download"
    elif is_fedora; then
        if sudo dnf install -y nfpm 2>/dev/null; then
            dep_track "system" "nfpm"
            log_success "Installed nfpm"
            return 0
        fi
        log_info "dnf nfpm not available, trying direct download"
    fi

    local extract_to="$TOOL_CACHE_DIR/nfpm-$NFPM_VERSION"
    local archive="/tmp/nfpm-$NFPM_VERSION.tar.gz"

    ensure_dir "$extract_to"

    if ! download_file "$URL_NFPM_X86_64" "$archive" "nfpm"; then
        return 1
    fi

    if ! extract_tarball "$archive" "$extract_to"; then
        rm -f "$archive"
        return 1
    fi
    rm -f "$archive"

    local binary="$extract_to/nfpm"
    if [[ -f "$binary" ]]; then
        chmod +x "$binary"
        dep_track "download" "$extract_to"
        export PATH="$extract_to:$PATH"
        log_success "Installed nfpm $NFPM_VERSION"
        return 0
    fi

    log_error "nfpm binary not found in extracted archive"
    return 1
}

# --- zig installation ------------------------------------------------------

install_zig() {
    if check_command "zig"; then
        return 1
    fi

    log_info "Installing zig..."

    if is_arch; then
        if sudo pacman -S --noconfirm zig 2>/dev/null; then
            dep_track "system" "zig"
            log_success "Installed zig"
            return 0
        fi
        if install_aur "zig" "zig"; then
            return 0
        fi
    fi

    # Try distro packages first
    if is_fedora; then
        if sudo dnf install -y zig 2>/dev/null; then
            dep_track "system" "zig"
            log_success "Installed zig"
            return 0
        fi
        log_info "dnf zig not available, trying direct download"
    elif is_debian; then
        if sudo apt-get install -y zig 2>/dev/null; then
            dep_track "system" "zig"
            log_success "Installed zig"
            return 0
        fi
        log_info "apt zig not available, trying direct download"
    fi

    # Fallback: download from ziglang.org
    local arch
    arch=$(uname -m)
    local url="$URL_ZIG_X86_64"
    local dirname="zig-linux-x86_64-$ZIG_VERSION"

    if [[ "$arch" == "aarch64" ]]; then
        url="$URL_ZIG_AARCH64"
        dirname="zig-linux-aarch64-$ZIG_VERSION"
    fi

    local extract_to="$TOOL_CACHE_DIR/$dirname"

    if [[ -d "$extract_to" ]]; then
        export PATH="$extract_to:$PATH"
        log_success "Found cached zig $ZIG_VERSION"
        return 0
    fi

    local archive="/tmp/zig-$ZIG_VERSION.tar.xz"
    ensure_dir "$TOOL_CACHE_DIR"

    if ! download_file "$url" "$archive" "zig"; then
        return 1
    fi

    if ! extract_tarball "$archive" "$TOOL_CACHE_DIR"; then
        rm -f "$archive"
        return 1
    fi
    rm -f "$archive"

    if [[ -d "$extract_to" ]]; then
        export PATH="$extract_to:$PATH"
        dep_track "download" "$extract_to"
        log_success "Installed zig $ZIG_VERSION"
        return 0
    fi

    log_error "Failed to find zig binary after extraction"
    return 1
}

# --- Verification ----------------------------------------------------------

verify_command() {
    local cmd="$1"
    local package="$2"

    if ! check_command "$cmd"; then
        log_error "$cmd not found"
        if [[ -n "$package" ]]; then
            echo "  Install with: sudo pacman -S $package"
        fi
        return 1
    fi
    return 0
}
