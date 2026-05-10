# -----------------------------------------------------------------------------
# common.sh
# Shared utilities for the build scripts.
# Provides: constants, logging, download utilities, error handling,
#           dependency tracking, nfpm.yaml generation.
# -----------------------------------------------------------------------------

# --- Colors ----------------------------------------------------------------

readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_BOLD="\033[1m"

# --- Logging ---------------------------------------------------------------

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_section() {
    echo ""
    echo -e "${COLOR_BOLD}━━━ $* ━━━${COLOR_RESET}"
}

# --- Project root detection ------------------------------------------------

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# --- Configuration loading -------------------------------------------------

CONFIG_FILE="$PROJECT_ROOT/rcc-scripts.conf"

# Default values (used when config file is missing)
PROJECT_NAME="changethis"
PROJECT_DESCRIPTION=""
PROJECT_MAINTAINER=""
PROJECT_VENDOR=""
PROJECT_HOMEPAGE=""
PROJECT_LICENSE="MIT"
BUILD_DIST_DIR="dist"
BUILD_TARGET_DIR="target"
LINUX_DEB_SECTION="default"
LINUX_DEB_PRIORITY="extra"
LINUX_RPM_GROUP="Development/Tools"
LINUX_ARCHLINUX_CATEGORY="utils"
ZIG_VERSION="0.14.0"
NFPM_VERSION="2.34.2"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    log_info "Loaded config: $CONFIG_FILE"
fi

if [[ "$PROJECT_NAME" == "changethis" ]]; then
    log_error "PROJECT_NAME is still set to 'changethis'."
    log_error "Edit $CONFIG_FILE and set PROJECT_NAME to your binary name."
    exit 1
fi

readonly PROJECT_NAME
readonly PROJECT_DESCRIPTION
readonly PROJECT_MAINTAINER
readonly PROJECT_VENDOR
readonly PROJECT_HOMEPAGE
readonly PROJECT_LICENSE
readonly LINUX_DEB_SECTION
readonly LINUX_DEB_PRIORITY
readonly LINUX_RPM_GROUP
readonly LINUX_ARCHLINUX_CATEGORY
readonly ZIG_VERSION
readonly NFPM_VERSION

# --- Derived constants -----------------------------------------------------

readonly URL_ZIG_X86_64="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
readonly URL_ZIG_AARCH64="https://ziglang.org/download/${ZIG_VERSION}/zig-linux-aarch64-${ZIG_VERSION}.tar.xz"
readonly URL_NFPM_X86_64="https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"

readonly DIR_DIST="./$BUILD_DIST_DIR"
readonly DIR_TARGET="./$BUILD_TARGET_DIR"

# --- Tool cache directory --------------------------------------------------

readonly TOOL_CACHE_DIR="${HOME}/.local/share/rcc-scripts/tools"

# --- Dependency tracking ---------------------------------------------------

readonly TRACKING_FILE="/tmp/rcc-scripts-track-$$.lst"
KEEP_DEPS="${KEEP_DEPS:-false}"

dep_track() {
    local type="$1"   # system | rust_target | cargo_tool | download
    local data="$2"
    echo "$type:$data" >> "$TRACKING_FILE"
}

dep_cleanup_all() {
    if [[ "$KEEP_DEPS" == "true" ]]; then
        log_info "Skipping dependency cleanup (--keep-deps)"
        return 0
    fi

    if [[ ! -f "$TRACKING_FILE" ]]; then
        return 0
    fi

    log_section "Cleaning up auto-installed dependencies"

    local lines=()
    while IFS= read -r line; do
        lines=("$line" "${lines[@]}")
    done < "$TRACKING_FILE"

    for entry in "${lines[@]}"; do
        local type="${entry%%:*}"
        local data="${entry#*:}"
        case "$type" in
            system)
                log_info "Removing system package(s): $data"
                local -a _pkgs=($data)
                remove_system_packages _pkgs "$data"
                ;;
            rust_target)
                log_info "Removing Rust target: $data"
                rustup target remove "$data" 2>/dev/null || true
                ;;
            cargo_tool)
                log_info "Uninstalling cargo tool: $data"
                cargo uninstall "$data" 2>/dev/null || true
                ;;
            download)
                log_info "Removing downloaded tool: $data"
                rm -rf "$data" 2>/dev/null || true
                ;;
        esac
    done

    rm -f "$TRACKING_FILE"
    log_success "Dependency cleanup complete"
}

# --- User interaction ------------------------------------------------------

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    local choices="[y/N]"
    if [[ "$default" == "y" ]]; then
        choices="[Y/n]"
    fi

    while true; do
        read -p "$prompt $choices: " -n 1 -r reply
        echo

        if [[ -z "$reply" ]]; then
            reply="$default"
        fi

        if [[ "$reply" =~ ^[Yy]$ ]]; then
            return 0
        elif [[ "$reply" =~ ^[Nn]$ ]]; then
            return 1
        fi

        echo "Please answer y or n"
    done
}

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local num=${#options[@]}

    if [[ "$AUTO_YES" == "true" ]]; then
        echo "0"
        return
    fi

    echo -n "$prompt " >&2
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[0-9]+$ ]] && [[ "$line" -ge 1 ]] && [[ "$line" -le "$num" ]]; then
            echo $((line-1))
            return 0
        fi
        echo "Invalid choice. Please enter 1-$num" >&2
        echo -n "$prompt " >&2
    done
    return 1
}

# --- Download utilities ----------------------------------------------------

download_file() {
    local url="$1"
    local dest="$2"
    local name="$3"

    log_info "Downloading $name..."

    if command -v curl &>/dev/null; then
        curl -fSL --connect-timeout 30 --retry 3 --retry-delay 2 \
            -o "$dest" "$url" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --connect-timeout=30 --tries=3 --wait=2 -O "$dest" "$url" 2>/dev/null
    else
        log_error "Neither curl nor wget available"
        return 1
    fi

    if [[ $? -eq 0 ]] && [[ -s "$dest" ]]; then
        log_success "Downloaded $name"
        return 0
    else
        log_error "Failed to download $name"
        rm -f "$dest"
        return 1
    fi
}

extract_tarball() {
    local archive="$1"
    local dest="$2"

    if [[ "$archive" == *.tar.xz ]]; then
        tar -xJf "$archive" -C "$dest"
    elif [[ "$archive" == *.tar.gz ]] || [[ "$archive" == *.tgz ]]; then
        tar -xzf "$archive" -C "$dest"
    elif [[ "$archive" == *.tar ]]; then
        tar -xf "$archive" -C "$dest"
    else
        log_error "Unknown archive format: $archive"
        return 1
    fi
}

# --- File utilities --------------------------------------------------------

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

clean_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log_info "Cleaning $dir"
        rm -rf "$dir"
    fi
}

cleanup_build_dirs() {
    log_info "Cleaning build directories..."
    clean_dir "$DIR_DIST"
    clean_dir "$DIR_TARGET"
}

# --- Version utilities -----------------------------------------------------

get_version_from_cargo() {
    local toml="Cargo.toml"
    if [[ ! -f "$toml" ]]; then
        if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
            toml="$PROJECT_ROOT/Cargo.toml"
        else
            log_error "Cargo.toml not found"
            return 1
        fi
    fi

    grep -m1 '^version' "$toml" | sed 's/version = "\(.*\)"/\1/'
}

# --- Check utilities -------------------------------------------------------

check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
}

check_file() {
    local file="$1"
    [[ -f "$file" ]]
}

check_rust_target_installed() {
    local target="$1"
    rustup target list 2>/dev/null | grep -q "$target (installed)"
}

# --- nfpm.yaml generation --------------------------------------------------

generate_nfpm_yaml() {
    local output_path="${1:-$PROJECT_ROOT/nfpm.yaml}"
    local version="${2:-$VERSION}"
    local binary_path="./target/release/${PROJECT_NAME}"

    cat > "$output_path" <<- YAML
# Auto-generated by rcc-scripts -- review and edit if needed
name: "${PROJECT_NAME}"
arch: "amd64"
platform: "linux"
version: "${version}"
section: "${LINUX_DEB_SECTION}"
priority: "${LINUX_DEB_PRIORITY}"
maintainer: "${PROJECT_MAINTAINER}"
description: |
  ${PROJECT_DESCRIPTION}
vendor: "${PROJECT_VENDOR}"
homepage: "${PROJECT_HOMEPAGE}"
license: "${PROJECT_LICENSE}"
contents:
  - src: ${binary_path}
    dst: /usr/bin/${PROJECT_NAME}
YAML

    log_success "Generated: $output_path"
}

# --- nfpm.yaml review prompt ----------------------------------------------

prompt_review_nfpm() {
    local file="$1"

    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    echo ""
    log_section "Review nfpm.yaml"
    echo ""
    cat "$file"
    echo ""
    echo "The above nfpm.yaml has been generated for Linux packaging."
    echo "File: $file"
    echo ""

    while true; do
        read -p "Press Enter to continue, 'e' to edit, 'q' to quit: " -n 1 -r reply
        echo
        case "$reply" in
            "")
                return 0
                ;;
            [Ee])
                ${EDITOR:-vi} "$file"
                return 0
                ;;
            [Qq])
                log_info "Build cancelled by user"
                exit 1
                ;;
        esac
    done
}

# --- Error handling --------------------------------------------------------

handle_error() {
    local line=$1
    local exit_code=$?

    echo ""
    log_error "Build failed at line $line (exit code: $exit_code)"
    echo ""
    echo "Partial build artifacts may remain in ./dist/"
    echo "You can run 'rm -rf ./dist ./target' to clean up manually."
    exit "$exit_code"
}

setup_traps() {
    trap 'handle_error $LINENO' ERR
    trap 'log_info "Interrupted"; exit 130' INT
    trap 'log_info "Terminated"; exit 143' TERM
}
