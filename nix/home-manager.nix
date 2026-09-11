{
  imports = [
    (import ./product-module.nix "llm")
    (import ./product-module.nix "metrics")
  ];
}
