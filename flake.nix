{
  description = "NixOS Homelab";
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    kubetree = {
      url = "github:andsens/nix-kubetree";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    setup-secrets = {
      url = "github:andsens/nixos-setup-secrets";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    k8sss = {
      url = "github:andsens/k8sss";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.kubetree.follows = "kubetree";
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
        inputs,
        lib,
        ...
      }:
      let
        inherit (flake-parts-lib) importApply;
      in
      {
        systems = import systems;
        flake = {
          lib = {
            ip = import ./nix/lib/ip.nix { inherit lib; };
            k8s = import ./nix/lib/k8s.nix { inherit lib; };
            setup-secrets = import ./nix/lib/setup-secrets.nix { inherit lib; };
          };
          nixosModules = {
            client-vpn = importApply ./nix/modules/client-vpn { inherit self inputs; };
            cluster = importApply ./nix/modules/cluster { inherit self inputs; };
            fileshares = importApply ./nix/modules/fileshares { inherit self inputs; };
            cilium = importApply ./nix/modules/kubetree/cilium { inherit self inputs; };
            service-macros = importApply ./nix/modules/kubetree/service-macros { inherit self inputs; };
            privacy-vpn = importApply ./nix/modules/privacy-vpn { inherit self inputs; };
            services = importApply ./nix/modules/services { inherit self inputs; };
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
