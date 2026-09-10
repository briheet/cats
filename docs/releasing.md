# Distribution

Cats is a source-built macOS desktop overlay, not a WidgetKit extension.
No Apple Developer account, Developer ID certificate, provisioning profile,
App Group or notarization workflow is required for the Home Manager installation.

- `nix build` builds the collector and desktop UI.
- `nix build .#cats-desktop` builds the native Swift/AppKit executable.
- Import `homeManagerModules.default` and set `programs.cats.enable = true`.
- `just build` builds an optional local app bundle using Apple's Swift compiler.

The compiler/linker supplies the minimal ad-hoc executable signatures required
on Apple Silicon. This is not Developer ID signing and does not establish a
trusted publisher for separately downloaded app bundles. Do not disable
Gatekeeper or other macOS security controls.

The Home Manager module starts ordinary per-user launch agents from the Nix
store. It does not copy apps into Applications, register extensions, or read
other apps' containers. Permission denial stops collection/polling; launchd
does not restart failed processes.

See [configuration](configuration.md) for setup and migration from the former
signed-widget architecture. Old signing scripts and the notarization workflow
have been removed. Desktop cards are not listed in Apple's Widget Gallery.
