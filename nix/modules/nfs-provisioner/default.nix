{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.homelab.nfs-provisioner;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
in
{
  options.homelab.nfs-provisioner = {
    enable = lib.mkEnableOption "the NFS volume provisioner";
    server = lib.mkOption {
      description = "NFS server to use as persistent data store";
      type = lib.types.str;
      defaultText = "\${config.networking.hostName}.\${config.homelab.cluster.domain}";
      default = "${config.networking.hostName}.${config.homelab.cluster.domain}";
    };
    path = lib.mkOption {
      description = "Export on the NFS server to use as the root";
      type = lib.types.str;
    };
    pathPattern = lib.mkOption {
      description = "Naming scheme for volumes on the NFS server";
      type = lib.types.str;
      default = "\${.PVC.namespace}-\${.PVC.name}";
    };
    mountpointOwnership = {
      mode = lib.mkOption {
        description = "Filesystem mode to create the mountpoint with";
        type = lib.types.str;
        default = "777";
      };
      uid = lib.mkOption {
        description = "UID ownership of the mountpoint";
        type = lib.types.int;
        default = 0;
      };
      gid = lib.mkOption {
        description = "GID ownership of the mountpoint";
        type = lib.types.int;
        default = 0;
      };
    };
  };
  config = {
    kubetree.resources.nfs-provisioner.namespace = self.lib.k8s.createNamespace {
      namespace = "nfs-provisioner";
    };
    services.k3s.manifests = {
      nfs-provisioner-helm.source =
        self.lib.k8s.patchManifest { inherit pkgs; }
          (kubelib.buildHelmChart {
            name = "nfs-subdir-external-provisioner";
            namespace = "nfs-provisioner";
            chart = pkgs.fetchFromGitHub {
              # 4.0.18 has a broken helm chart
              repo = "nfs-subdir-external-provisioner";
              owner = "kubernetes-sigs";
              rev = "f4d56f8285ebab2a8f245a3983271e418c9f84e4";
              rootDir = "charts/nfs-subdir-external-provisioner";
              hash = "sha256-TUhR+si3/branwUj9t0MnXwWhm+sXX7GJzuckHhJKmc=";
            };
            values = {
              nfs = {
                server = cfg.server;
                path = cfg.path;
                defaultMode = ''"${cfg.mountpointOwnership.mode}"'';
                defaultUid = ''"${builtins.toString cfg.mountpointOwnership.uid}"'';
                defaultGid = ''"${builtins.toString cfg.mountpointOwnership.gid}"'';
              };
              storageClass = {
                defaultClass = true;
                reclaimPolicy = "Retain";
                pathPattern = cfg.pathPattern;
              };
            };
          })
          (
            kubelib.toYAMLStreamFile [
              {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata.namespace = "nfs-provisioner";
                metadata.name = "nfs-subdir-external-provisioner";
                spec.template.metadata.labels."cluster.local/apiserver-egress" = "allow";
              }
            ]
          );
    };
  };
}
