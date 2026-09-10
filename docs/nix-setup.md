# Nix and Home Manager setup

## Add the flake input

Add Cats to your existing flake inputs:

```nix
inputs.cats = {
  url = "github:briheet/cats";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Pass `inputs` through Home Manager's `extraSpecialArgs`. With Home Manager inside
nix-darwin, set `home-manager.extraSpecialArgs = { inherit inputs; };` in a Darwin
module where your flake's `inputs` is in scope.

Create `modules/common/cats.nix`:

```nix
{ inputs, ... }:
{
  imports = [ inputs.cats.homeManagerModules.default ];
  programs.cats = {
    enable = true;
    service.enable = true;
    desktop = {
      enable = true;
      position = "top-right";
      margin = 24;
      large.enable = true;
      medium.enable = true;
      small.enable = false;
      small.variants = [ "spend" ];
      medium.variants = [ "providers" ];
      font = { family = "system"; size = 12; };
    };
    settings = {
      theme = "nord";
      budget-usd = 20;
    };
  };
}
```

The example shows the card defaults. Each switch is independent; all three false
leaves the menu bar without cards. `desktop.enable = false` disables the UI
service. `service.enable = false` disables collection; disable both for an
install-only setup. Position accepts `top-left` or `top-right`; margin is 0–200 points.

The default flake targets Apple Silicon. See [distribution](releasing.md) for Intel.

| Card | Content | Size in points |
| --- | --- | --- |
| Large | Overview (one type) | 760 × 250 |
| Medium | `providers`, `agents` | 340 × 170 |
| Small | `spend`, `agents`, `burn-rate` | 170 × 170 |

Variant lists select one or multiple cards, in list order. For all six:

```nix
programs.cats.desktop = {
  large.enable = true;
  medium = { enable = true; variants = [ "providers" "agents" ]; };
  small = { enable = true; variants = [ "spend" "agents" "burn-rate" ]; };
  font = { family = "Helvetica Neue"; size = 14; };
};
```

`font.family` accepts an installed font family/PostScript name; unavailable fonts
fall back to the system font. Add `pkgs` to the common module's arguments and set
`font.package = pkgs.nerd-fonts.jetbrains-mono;` with
`font.family = "JetBrainsMono Nerd Font";` to install a Nerd Font through Home Manager.
The package is optional and defaults to null. `font.size` accepts 10–20
points, default 12. Typography, spacing, and card dimensions scale together by
`size / 12` so larger text retains the design's proportions. Cards wrap into rows;
at large sizes you may need fewer cards to fit your display. Reapply Home Manager
to restart the UI with changed variants or typography.

## Import the module

For a host file at `hosts/YOUR_HOST/home.nix`:

```nix
{ ... }:
{
  imports = [ ../../modules/common/cats.nix ];
}
```

In the nix-darwin module that configures Home Manager, pass the flake inputs and
select that host file:

```nix
{
  home-manager.extraSpecialArgs = { inherit inputs; };
  home-manager.users.YOUR_USER = import ./hosts/YOUR_HOST/home.nix;
}
```

For standalone Home Manager, pass `extraSpecialArgs = { inherit inputs; };` to
`homeManagerConfiguration`, include your common module in `modules`, and activate
with `home-manager switch --flake .#YOUR_USER`.

For nix-darwin, activate after importing the module:

```sh
sudo darwin-rebuild switch --flake .#YOUR_HOST
```

## Update

```sh
nix flake update cats
nix build .#darwinConfigurations.YOUR_HOST.system --no-link
sudo darwin-rebuild switch --flake .#YOUR_HOST
```

Updating the lock selects a commit. Building validates it; switching activates it.
See [settings and themes](configuration.md) for customization.

## Troubleshooting

- **No cards:** show the desktop; panels are behind normal windows. Check enabled
  sizes, then use **Show widgets** in the menu.
- **Stale counts:** allow five seconds after ingestion. Counts reflect log activity, not open windows.
- **Collector unavailable:** inspect `launchctl print gui/$(id -u)/org.nix-community.home.cats`
  and run `cats config`. Do not start another collector against the same directory.
- **Permission denied:** use accessible paths. Do not grant broad access or reset
  privacy settings to force collection.
- **Bootstrap error 5:** check disabled flags and whether the agent is already
  loaded; this error alone does not identify the cause.

If you previously disabled Cats, inspect `launchctl print-disabled gui/$(id -u)`.
Re-enable these labels without sudo, then apply Home Manager again:

```sh
launchctl enable gui/$(id -u)/org.nix-community.home.cats
launchctl enable gui/$(id -u)/org.nix-community.home.cats-app
```

For old WidgetKit setups, remove `appPackage`, `app.autostart`, and local app inputs.
Cats does not migrate or read the old Group Container.
