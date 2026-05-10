# rcc-scripts

Cross-compile build scripts for Rust projects. Build Linux, macOS (Apple Silicon), and Windows binaries from a single Linux machine.

## How to setup for your project

```bash
cd your-project
git submodule add https://github.com/Jarmoco/rcc-scripts rcc-scripts
```

Create `rcc-scripts.conf` in your project root (see configuration below).

Then build:

```bash
./rcc-scripts/build.sh
```
Missing build tools are auto-installed (with confirmation) on **Arch Linux**, **Debian/Ubuntu**, and **Fedora**. On other distros, zig and nfpm are downloaded as pre-compiled tarballs.

## Configuration

Copy `rcc-scripts.conf.example` to `rcc-scripts.conf` in your project root (sibling to `rcc-scripts/`) and configure it for your needs:

```bash
# rcc-scripts.conf
PROJECT_NAME="my-app"
PROJECT_DESCRIPTION="My awesome Rust CLI"
PROJECT_MAINTAINER="Your Name"
PROJECT_VENDOR="Your Company"
PROJECT_HOMEPAGE="https://github.com/you/my-app"
PROJECT_LICENSE="MIT"

# Tool versions
ZIG_VERSION="0.14.0"
NFPM_VERSION="2.34.2"
```

See `rcc-scripts/rcc-scripts.conf.example` for all available options.

## Usage

```bash
./rcc-scripts/build.sh
```

Interactive mode — selects all platforms by default. Packages land in `./dist/`.

```bash
./rcc-scripts/build.sh -t linux          # Linux only (.deb, .rpm, .pkg.tar.zst, tarball)
./rcc-scripts/build.sh -t linux,macos    # Linux + macOS cross-compile
./rcc-scripts/build.sh -t all -y         # All platforms, auto-confirm prompts
./rcc-scripts/build.sh -c                # Clean before building
./rcc-scripts/build.sh -k                # Keep auto-installed deps after build
```

## nfpm.yaml generation

The Linux build script auto-generates `nfpm.yaml` from your config and Cargo.toml. You will be prompted to review it before packaging begins, so you can make adjustments. The file is cleaned up after the build completes.

## How it works

```
build.sh              # orchestrator — selects targets, runs platform scripts
├── build-linux.sh    # cargo build --release + nfpm packaging
├── build-macos.sh    # cargo zigbuild for aarch64-apple-darwin + tarball
└── build-windows.sh  # cargo build --target x86_64-pc-windows-gnu + .exe
```

Each platform script can also be run standalone. All output goes to `./dist/`.

## Dependency cleanup

Auto-installed build dependencies are cleaned up after each platform build (unless `-k`/`--keep-deps` is passed). This includes system packages, Rust targets, cargo tools, and downloaded binaries.
