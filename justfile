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
    cargo test --workspace --all-targets
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swift test --package-path macos

# Check both languages' formatting and common Rust mistakes.
check:
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets -- -D warnings
    bash scripts/format-swift.sh check

# Build desktop panels and the embedded collector. No Apple account needed.
build:
    bash scripts/build.sh

build-product product:
    bash scripts/build.sh {{product}}

metrics *args:
    cargo run -p cats-metrics -- {{args}}

metrics-preview:
    mkdir -p build
    cargo run -q -p cats-llm -- themes > build/themes.json
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -D METRICS -parse-as-library macos/UI/*.swift macos/MetricsShared/*.swift macos/MetricsApp/{MetricsModel,MetricsCard}.swift scripts/render-metrics.swift -o build/render-metrics
    build/render-metrics

metrics-refresh-smoke:
    mkdir -p build
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -parse-as-library macos/UI/ThemeState.swift macos/MetricsShared/*.swift macos/MetricsApp/MetricsModel.swift scripts/metrics-refresh-smoke.swift -o build/metrics-refresh-smoke
    build/metrics-refresh-smoke

ecosystem-smoke:
    cargo build --release --workspace
    ruby scripts/ecosystem-smoke.rb

profile-ecosystem:
    CATS_TEST_SECONDS=70 ruby scripts/ecosystem-smoke.rb --ui

# Run the collector (pass --once or --profile as needed).
run *args:
    cargo run -- {{args}}

# Open the built app.
open: build
    open build/Build/Products/Release/CatsLLM.app

# Install to ~/Applications. Existing installations are preserved.
install product:
    bash scripts/install.sh {{product}}

# Measure the optimized collector.
profile:
    cargo run --release -- --profile

# Synthetic 20k-record collector workload and 70-second UI CPU/RSS sample.
profile-ui: build
    ruby -rtime scripts/profile-ui.rb

# Observe actual AppState publications against an isolated snapshot.
refresh-smoke:
    mkdir -p build
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -parse-as-library macos/Shared/*.swift macos/UI/*.swift macos/CatsApp/{AppState,CollectorProcess}.swift scripts/refresh-smoke.swift -o build/refresh-smoke
    build/refresh-smoke

# Render the actual SwiftUI widget views in light and dark mode.
preview:
    mkdir -p build
    cargo run --quiet -- themes > build/themes.json
    env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -parse-as-library macos/Shared/*.swift macos/UI/*.swift macos/Views/{DesktopCard,TelemetryComponents,TelemetryCards,CardVariants}.swift macos/Preview/*.swift scripts/render.swift -o build/render-preview
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
    for selection in '' large medium small large,medium large,small medium,small large,medium,small; do CATS_LLM_WIDGETS="$selection" bash scripts/desktop-smoke.sh; done

desktop-variants-smoke:
    for selection in medium-agents small-agents small-burn-rate large,medium,medium-agents,small,small-agents,small-burn-rate; do CATS_LLM_WIDGETS="$selection" bash scripts/desktop-smoke.sh; done
    for size in 10 16 20; do CATS_LLM_FONT_SIZE="$size" CATS_LLM_FONT_FAMILY='Helvetica Neue' CATS_LLM_WIDGETS=small-agents bash scripts/desktop-smoke.sh; done

# Includes two 60-second reload cycles in isolated temporary storage.
theme-smoke:
    cargo build --release
    CATS_LLM_SMOKE_CONFIG=1 ruby scripts/smoke.rb
