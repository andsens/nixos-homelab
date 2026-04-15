{
  description = "NixOS Homelab";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kubetree = {
      url = "github:andsens/nix-kubetree";
      # url = "git+file:///home/anders/Workspace/nix-kubetree";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    nixhelm = {
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kube-generators.url = "github:farcaller/nix-kube-generators";
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
        systems = import systems;
        flake = {
          lib = {
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
