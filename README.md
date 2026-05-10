# rcc-scripts

Cross-compile build scripts for Rust projects. Build Linux, macOS (Apple Silicon), and Windows binaries from a single Linux machine.

## Usage

```bash
./build.sh
```

Interactive mode — selects all platforms by default. Packages land in `./dist/`.

```bash
./build.sh -t linux          # Linux only (.deb, .rpm, .pkg.tar.zst, tarball)
./build.sh -t linux,macos    # Linux + macOS cross-compile
./build.sh -t all -y         # All platforms, auto-confirm prompts
./build.sh -c                # Clean before building
```

## Prerequisites

| Platform | Requires |
|---|---|
| Linux | cargo, [nfpm](https://nfpm.goreleaser.com) |
| macOS (cross) | zig, cargo-zigbuild, `rustup target add aarch64-apple-darwin` |
| Windows (cross) | mingw-w64, `rustup target add x86_64-pc-windows-gnu` |

On **Arch Linux**, the script can install dependencies automatically (prompts for confirmation).

## Setup for your project

Add as a submodule:

```bash
cd your-project
git submodule add https://github.com/Jarmoco/rcc-scripts rcc-scripts
```

Edit `rcc-scripts/lib/common.sh` and set `BINARY_NAME` to your crate's binary name:

```bash
BINARY_NAME="your-binary-name"
```

Create an `nfpm.yaml` at your project root (see [nfpm docs](https://nfpm.goreleaser.com)):

```yaml
name: "your-binary-name"
arch: "amd64"
platform: "linux"
version: "0.1.0"
contents:
  - src: ./target/release/your-binary-name
    dst: /usr/bin/your-binary-name
```

Then build:

```bash
./scripts/build.sh
```

## How it works

```
build.sh              # orchestrator — selects targets, runs platform scripts
├── build-linux.sh    # cargo build --release + nfpm packaging
├── build-macos.sh    # cargo zigbuild for aarch64-apple-darwin + tarball
└── build-windows.sh  # cargo build --target x86_64-pc-windows-gnu + .exe
```

Each platform script can also be run standalone:

```bash
./build-linux.sh
./build-macos.sh
./build-windows.sh
```

All output goes to `./dist/`.
