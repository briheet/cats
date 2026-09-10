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
    nix-shell -p just rustfmt clippy

# Format Rust and Swift sources using the project settings.
fmt:
    cargo fmt --all
    bash scripts/format-swift.sh format

# Verify Rust accounting and Swift snapshot handling.
test:
    cargo test --all-targets
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swift test --package-path macos

# Check both languages' formatting and common Rust mistakes.
check:
    cargo fmt --all -- --check
    cargo clippy --all-targets -- -D warnings
    bash scripts/format-swift.sh check

# Build desktop panels and the embedded collector. No Apple account needed.
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
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -parse-as-library macos/Shared/*.swift macos/Views/{DesktopCard,GlassStyle,TelemetryComponents,TelemetryCards}.swift macos/Preview/*.swift scripts/render.swift -o build/render-preview
    build/render-preview

# Exercise live ingestion and managed process controls in temporary storage.
smoke:
    cargo build --release
    ruby scripts/smoke.rb

# Briefly open two isolated cards, verify their windows, then stop the test UI.
desktop-smoke:
    bash scripts/desktop-smoke.sh

# Check every combination of independently enabled desktop cards.
desktop-selection-smoke:
    for selection in '' large medium small large,medium large,small medium,small large,medium,small; do CATS_WIDGETS="$selection" bash scripts/desktop-smoke.sh; done

# Includes two 60-second reload cycles in isolated temporary storage.
theme-smoke:
    cargo build --release
    CATS_SMOKE_CONFIG=1 ruby scripts/smoke.rb
