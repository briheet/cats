# Widget distribution

Cats is a widget-first product. The containing `Cats.app` hosts its WidgetKit extension and provides an optional menu-bar view; the Rust collector is a separate background service. Installing the collector alone cannot install a widget.

## Current status

There is **no signed public release yet**. `nix/releases.json` is deliberately empty; Home Manager warns when it can only install the collector. A local ad-hoc-signed bundle can be installed for development, but PlugInKit registration does not prove that macOS will display or execute its widgets. Do not present it as a working public widget release.

## End-user configuration

```nix
inputs.cats.url = "github:briheet/cats";
inputs.cats.inputs.nixpkgs.follows = "nixpkgs";
inputs.cats.inputs.home-manager.follows = "home-manager";
```

In a Home Manager module receiving `inputs`:

```nix
{ inputs, ... }: {
  imports = [ inputs.cats.homeManagerModules.default ];
  programs.cats = {
    enable = true;
    settings = { theme = "nord"; budget-usd = 20; };
  };
}
```

Once a signed release is pinned, this installs the bundle to `~/Applications/Cats.app`, registers it with LaunchServices, and starts the collector and lightweight host via launchd. Then right-click the desktop → Edit Widgets → Cats. Placement is user-controlled. Users do not need Xcode or an Apple Developer account.

An existing unmanaged `Cats.app` is never overwritten. Managed updates preserve the previous bundle in a hidden `.cats-install.*` directory under Applications. Disabling the module stops managing launchd jobs but leaves the copied bundle and backups; remove those manually if uninstalling. No system widget caches or unrelated processes are reset.

## Publish a signed release

Use an Apple-issued **Developer ID Application** certificate and notarization for public distribution. Apple documents [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), and [macOS App Group identifiers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). Release builds use `TEAMID.dev.cats.shared`, consistently embedded into the app/widget entitlements, their Info.plists, and the collector's launchd environment. The older development group remains separate; existing development data is not moved automatically.

Add these repository Actions secrets through GitHub's settings, **never through Nix or source control**:

- `CATS_CERTIFICATE_P12`: base64-encoded Developer ID certificate plus private key.
- `CATS_CERTIFICATE_PASSWORD`: password protecting that export.
- `CATS_SIGN_IDENTITY`: full `Developer ID Application: …` identity name.
- `CATS_TEAM_ID`: ten-character developer team ID.
- `CATS_APPLE_ID`: notarization Apple account.
- `CATS_APPLE_APP_PASSWORD`: its app-specific password.

Dispatch **Signed release**, supplying a fresh `vX.Y.Z` tag. It builds Apple Silicon and Intel bundles on separate runners, signs nested code from the inside out, notarizes, staples, checks Gatekeeper, and publishes ZIPs plus a hash-pinned `releases.json`. Missing credentials fail the release; there is no unsigned fallback.

Download that release's `releases.json`, review it, replace `nix/releases.json`, run `nix flake check`, and commit/push the manifest. This explicit promotion makes the bundle the module's default. Consumers then update their Cats flake input and rebuild. Check the widget gallery and actual snapshot access on a signed installation before announcing the release as verified.

For local signed release builds, set `CATS_SIGN_IDENTITY`, `CATS_TEAM_ID`, and `CATS_NOTARY_PROFILE` (a configured `notarytool` keychain profile), then run `just release`.

## Local development bundle

`just build` produces an ad-hoc-signed app with the widget's sandbox entitlement retained. `just install` copies and registers it; this is a development installation, not a signing bypass. It may still be absent from the widget gallery.

To import this bundle declaratively for your own machine, add a temporary non-flake input pointing at the built `Cats.app`, then:

```nix
programs.cats.appPackage = inputs.cats.lib.mkApp {
  inherit pkgs;
  src = inputs.cats-local-app;
};
```

The local input is machine-specific. Remove it and this override after promoting the first signed release. For a manually signed bundle, also pass its exact `appGroup` to `mkApp`.
