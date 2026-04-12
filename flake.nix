{
  description = "NixOS Homelab";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs =
    {
      systems,
      flake-parts,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        flake-parts-lib,
        self,
        lib,
        ...
      }@mkFlakeArgs:
      let
        inherit (flake-parts-lib) importApply;
      in
      {
        flake = {
          lib = {
            helpers = import ./nix/lib/helpers.nix { inherit lib; };
            ip = import ./nix/lib/ip.nix { inherit lib; };
            k8s = import ./nix/lib/k8s.nix { inherit lib; };
          };
          nixosModules = {
            admin = args: { imports = [ (importApply ./nix/modules/admin mkFlakeArgs) ]; };
            backup = args: { imports = [ (importApply ./nix/modules/backup mkFlakeArgs) ]; };
            client-vpn = args: { imports = [ (importApply ./nix/modules/client-vpn mkFlakeArgs) ]; };
            cluster = args: { imports = [ (importApply ./nix/modules/cluster mkFlakeArgs) ]; };
            fileshares = args: { imports = [ (importApply ./nix/modules/fileshares mkFlakeArgs) ]; };
            cilium = args: { imports = [ (importApply ./nix/modules/kubetree/cilium mkFlakeArgs) ]; };
            service-macros = args: {
              imports = [ (importApply ./nix/modules/kubetree/service-macros mkFlakeArgs) ];
            };
            privacy-vpn = args: { imports = [ (importApply ./nix/modules/privacy-vpn mkFlakeArgs) ]; };
            services = args: { imports = [ (importApply ./nix/modules/services mkFlakeArgs) ]; };
            zfs = args: { imports = [ (importApply ./nix/modules/zfs mkFlakeArgs) ]; };
          };
        };
        perSystem =
          { pkgs, system, ... }:
          {
            packages = {
              container-utils = pkgs.callPackage ./nix/packages/container-utils { };
            };
          };
      }
    );
}
