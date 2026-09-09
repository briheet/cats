set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Validate declarative packaging and Home Manager settings.
nix-check:
    nix flake check

# Validate and print application settings without starting a collector.
config *args:
    cargo run -- {{args}} config

# Enter a development shell with the optional tools.
dev:
    nix-shell -p just xcodegen rustfmt clippy

# Format Rust sources.
fmt:
    cargo fmt --all

# Verify Rust accounting and Swift snapshot handling.
test:
    cargo test --all-targets
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swift test --package-path macos

# Check formatting and common Rust mistakes.
check:
    cargo fmt --all -- --check
    cargo clippy --all-targets -- -D warnings

# Build the native app, widget extension, and embedded collector.
build:
    bash scripts/build.sh

# Run the collector (pass --once or --profile as needed).
run *args:
    cargo run -- {{args}}

# Open the built app.
open: build
    open build/Build/Products/Release/Cats.app

# Install to ~/Applications. Existing installations are preserved.
install:
    bash scripts/install.sh

# Measure the optimized collector.
profile:
    cargo run --release -- --profile

# Render the actual SwiftUI widget views in light and dark mode.
preview:
    mkdir -p build
    cargo run --quiet -- themes > build/themes.json
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -parse-as-library macos/Shared/WidgetState.swift macos/Shared/StateReader.swift macos/Shared/GlassStyle.swift macos/Shared/TelemetryViews.swift macos/Shared/WidgetViews.swift macos/Shared/DesignGallery.swift scripts/render.swift -o build/render-preview
    build/render-preview

# Exercise live ingestion and managed process controls in temporary storage.
smoke:
    cargo build --release
    ruby scripts/smoke.rb

# Includes two 60-second reload cycles in isolated temporary storage.
theme-smoke:
    cargo build --release
    CATS_SMOKE_CONFIG=1 ruby scripts/smoke.rb
