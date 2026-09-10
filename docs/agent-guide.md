# Engineering and design brief for future agents

Use this as my working preferences for implementation tasks. Read the repository's
instructions and current plan first. These preferences do not authorize unrelated
changes, publishing, system activation, or destructive actions.

## Working style

- Start from the actual request, `docs/plan.md`, relevant docs, and reference images.
  Do not replace the intended product with a different kind of application.
- Make a short plan. Break complex components into small responsibilities and
  visible details before implementing them.
- Work autonomously within scope. Make sensible, reversible assumptions and state
  them; avoid repeatedly asking questions. Stop when missing authority or a
  consequential product decision genuinely blocks safe progress.
- When stuck or unsure, research the problem. Prefer official documentation and
  primary sources; verify version-sensitive APIs instead of guessing.
- Give concise progress updates, including failed checks and changes of diagnosis.
  Do not call something complete merely because it compiles.

## Code conventions and architecture

- Keep code minimal, readable, and idiomatic—not compressed or clever. Use
  descriptive names, small cohesive functions, and explicit ownership.
- Follow the language's conventions and the repository's formatters. Do not
  impose the same patterns on every language.
- Model domain concepts with types. Prefer enums and exhaustive matching over
  scattered string comparisons. Convert strings at serialization boundaries.
- In Rust, use structs with `impl` blocks for concrete behavior and traits for
  real shared contracts, such as provider parsers. Use Clap for CLI parsing and
  Serde for serialization. Do not introduce a trait for every struct.
- In Swift, use focused views, typed models, explicit state ownership, and
  main-actor isolation for UI state. Keep lifecycle and process management out
  of presentation components.
- Separate ingestion, domain rules, storage, configuration, and rendering.
  Avoid duplicating business rules across the backend and UI.
- Justify dependencies, persistence, and abstraction. A database is not mandatory:
  keep SQLite only when durable cursors, deduplication, transactions, or queries
  justify it. Do not replace working infrastructure solely for stylistic purity.
- Handle malformed input and recoverable failures explicitly. Preserve existing
  configuration and data formats, or provide a deliberate migration.
- Comment on reasons, invariants, and surprising constraints—not obvious syntax.
- After changes, remove superseded code, unused options, duplicate paths, and
  obsolete documentation. Preserve unrelated user work and useful reference files.

## Premium UI means deliberate execution

- Aim for Apple-inspired clarity: glanceable information, restrained glass,
  consistent hierarchy, careful typography, and generous but purposeful spacing.
  “Premium” is not more gradients, blur, decoration, or animation.
- Match the supplied reference's composition and intent. Inspect the actual image;
  do not assume that rounded cards alone satisfy the design.
- Specify each component's content, alignment, padding, type scale, colors,
  corner radius, glass treatment, overflow behavior, and interaction states.
- Use shared visual primitives and theme tokens. Keep surfaces, corners, spacing,
  and text treatment consistent across sizes and variants.
- Keep information dense enough to be useful without feeling crowded. Avoid large
  accidental empty regions and repeated explanatory headings users already understand.
- Treat empty, loading, stale, failed, over-budget, and overflow states as designed
  states—not afterthoughts. Preserve readability over busy wallpapers.
- Support configured themes and fonts, sensible font fallbacks, and size extremes.
  Do not make meaning depend on color alone; label meaningful controls and indicators.
- Render previews from the production components. Inspect them, fix problems,
  render again, and check live behavior. A screenshot of a separate mock is not proof.

## Configuration and distribution

- Make user-facing choices declarative, discoverable, and validated. Follow the
  spirit of configurable tools such as Helix: good defaults, explicit overrides,
  documented settings, and reusable themes.
- Expose relevant options through a flake and Home Manager module. Keep host
  configuration in an imported common module rather than cluttering `home.nix`.
- Support themes such as Nord and Rosé Pine without hardcoded per-view colors.
  Expose font family and size; allow an optional Nix font package, including Nerd Fonts.
- Preserve existing defaults and distinguish package installation, service startup,
  build validation, and activation. Do not silently activate a user's system.
- Avoid requiring an Apple Developer account or certificate-based distribution.
  Explain platform-required ad-hoc signatures honestly; do not promise literally
  unsigned binaries when the platform requires them.
- Minimize permissions. Never request broad access or reset privacy settings just
  to make tests pass. Stop repeated permission prompts rather than retrying forever.
- Use a `justfile` for repeatable workflows. Prefer the pinned development shell;
  obtain missing ad-hoc tools through `nix-shell -p`, not global installation.

## Testing and performance are part of implementation

- Run formatting, static checks, tests, and a production build appropriate to the
  change. Add regression tests for bugs and changed domain/configuration behavior.
- Test boundaries: invalid input, unknown enum values, missing files, denied access,
  stale snapshots, empty collections, large values, and configuration combinations.
- Exercise integration paths with isolated temporary data. Never profile against
  real provider logs or stop unrelated running processes as a test shortcut.
- For UI work, inspect all affected sizes and variants, themes, custom/fallback
  fonts, clipping, rounded corners, overflow, and window placement.
- Test actual refresh behavior, including changed data and suppression of unchanged
  updates. A configured timer interval alone does not prove freshness.
- Run representative workloads in optimized builds. Measure cold/import work and
  unchanged/incremental work separately; verify the workload was actually processed.
- For sustained UI checks, measure CPU and resident memory while data changes.
  Use stack samples or platform profilers when investigating bottlenecks.
- Record platform, build mode, input size, duration, card configuration, and test
  conditions. Keep reproducible commands and results in development/performance docs.
- Do not equate RSS with physical footprint, collector speed with rendering speed,
  or a short CPU sample with battery efficiency. State unmeasured areas explicitly.
- Never weaken a failing test just to get green output. Investigate whether the
  cause is implementation, harness, or environment; report unresolved failures.

## Documentation and delivery

- Keep the README concise and product-focused: what it does, how to install it,
  and where to configure it. Move development commands to `docs/development.md`
  and detailed Home Manager instructions to `docs/nix-setup.md`.
- Explain from first principles without padding. Include complete, usable examples
  and document actual behavior and limitations rather than aspirations.
- Ignore build output, caches, and local previews. For Cats, also ignore `docs/*.png`;
  do not accidentally publish local references, logs, or private data.
- Before handoff, inspect the diff for dead code, compatibility breaks, unintended
  files, incorrect docs, and remaining test failures.
- When asked to publish: commit scoped changes, push normally, then update only the
  requested consumer flake input. Preserve unrelated changes in both repositories.
- Validate the consumer build when relevant. Report the commit, changed settings,
  checks run, failures/limitations, and whether activation is still required.

## Cats-specific product decisions

These are current Cats requirements, not universal defaults for other projects:

- The product name is **Cats**. No C monogram or redundant “Your AI Workspace” /
  “Usage by providers” subtitles.
- Desktop widgets are native desktop panels, not an ordinary app window presented
  as a widget and not a WidgetKit extension requiring account-based distribution.
- Small has spend, agents, and burn-rate variants; medium has providers and agents;
  large has one overview. Selection is configurable through Home Manager.
- The large overview shows at most five agent rows and indicates overflow.
- The UI checks data every five seconds and publishes only changed readings.
- Activity counts and spend are estimates; never fabricate running sessions or
  imply that estimated token cost is an authoritative provider bill.

## Definition of done

The requested behavior is implemented, the actual UI has been inspected where
relevant, scoped checks and workloads have run, obsolete code has been reviewed,
documentation/configuration agree with the implementation, and the handoff states
what passed, what remains unresolved, and what was or was not deployed.
