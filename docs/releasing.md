# Distribution and updates

## Build outputs

| Build | Output |
| --- | --- |
| `nix build .#cats-llm` | Rust collector only |
| `nix build .#cats-llm-desktop` | Swift/AppKit UI with its collector dependency |
| `nix build .#cats-metrics` | Independent metrics collector |
| `nix build .#cats-metrics-desktop` | Metrics UI with its own collector dependency |
| `just build` | Local `CatsLLM.app` and `CatsMetrics.app` under `build/Build/Products/Release` |

There is no ambiguous default package. `just build-product llm` or
`just build-product metrics` builds one product. `just install llm` or
`just install metrics` explicitly installs and launches that bundle; builds and
tests never install anything.

Home Manager launches executables from the Nix store. It does not install a
WidgetKit extension or copy an app bundle into Applications.

The compiler/linker supplies Apple Silicon's ad-hoc executable signatures. No
Apple Developer account, Developer ID certificate, provisioning profile, or
notarization service is used. A separately downloaded app bundle is not thereby
a trusted-publisher release. Do not disable Gatekeeper.

The default Nix output is `aarch64-darwin`. The flake exposes `x86_64-darwin` when
supplied Nixpkgs reports a version before 26.11; use the 26.05 line with compatible
Home Manager for Intel. Intel Nix builds need separate verification.

## Publish and consume a change

1. Run the checks in [development](development.md).
2. Review and commit source/docs only. Build output and `docs/*.png` are ignored.
3. Push and check GitHub CI. A local build does not prove remote CI passed.

Consumers stay on the commit in their lock file until they update it. In the
consumer's configuration repository:

```sh
nix flake update cats
nix build .#darwinConfigurations.YOUR_HOST.system --no-link
sudo darwin-rebuild switch --flake .#YOUR_HOST
```

Build validates a generation; switch activates it. Launchd disable flags survive
rebuilds—see [troubleshooting](nix-setup.md#troubleshooting).
