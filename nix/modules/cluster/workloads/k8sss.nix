{
  inputs,
  self,
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.cluster.k8sss;
  ccfg = config.homelab.cluster;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  adminSSHKeys = lib.splitString "\n" (
    lib.trim (
      builtins.readFile (
        pkgs.stdenvNoCC.mkDerivation {
          name = "k8s-patch-manifest";
          phases = [ "installPhase" ];
          installPhase = ''
            runHook preInstall
            ${lib.join "\n" (
              map (key: ''
                jwk=$(${lib.getExe pkgs.step-cli} crypto key format --jwk <<<"${key}")
                kid=$(${lib.getExe pkgs.step-cli} crypto jwk thumbprint <<<"$jwk")
                ${lib.getExe pkgs.jq} -c --arg kid "$kid" '.kid=$kid' <<<"$jwk" >>$out
              '') config.users.users.admin.openssh.authorizedKeys.keys
            )}
            runHook postInstall
          '';
        }
      )
    )
  );
in
{
  options.homelab.cluster.k8sss = {
    # Generate JWKs with `step crypto jwk create --force --use sig --from-pem=<(step kms key $keyuri) /dev/stdout /dev/null | jq -c`
    adminKeys = lib.mkOption {
      description = "List of JWKs that may request a kubeapi client certificate";
      type = lib.types.listOf lib.types.str;
      default = adminSSHKeys;
      defaultText = "\${config.users.users.admin.openssh.authorizedKeys.keys} converted to JWKs";
    };
  };
  config = {
    networking.firewall.allowedTCPPorts = [ 9000 ];
    kubetree.resources.k8sss = {
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "k8sss";
        spec.toPortsFlattened = [ 9000 ];
      };
      netpol-world = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumNetworkPolicy";
        metadata = {
          namespace = "k8sss";
          name = "k8sss";
          labels."app.kubernetes.io/name" = "k8sss";
        };
        spec.endpointSelector.matchLabels."app.kubernetes.io/name" = "k8sss";
        spec.ingress = [
          {
            fromEntities = [ "world" ];
            toPortsFlattened = [ 9000 ];
          }
        ];
      };
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          namespace = "k8sss";
          name = "admin-keys";
          labels."app.kubernetes.io/name" = "k8sss";
        };
        data.admin-keys = builtins.toJSON (map builtins.fromJSON cfg.adminKeys);
      };
    };
    services.k3s.manifests.k8sss-deployment.source =
      self.lib.k8s.patchManifest { inherit pkgs; }
        (self.lib.k8s.buildKustomization { inherit pkgs; } {
          name = "k8sss";
          src = pkgs.fetchFromGitHub {
            repo = "k8sss";
            owner = "andsens";
            tag = "v0.2.2";
            rootDir = "deploy";
            hash = "sha256-DiBKOnCjoXMlQ2D2m0v2Ghv0E8ld+t/fxCiGJslgBVg=";
          };
          path = "overlays/node-port";
        })
        (
          kubelib.toYAMLStreamFile [
            {
              apiVersion = "v1";
              kind = "ConfigMap";
              metadata.namespace = "k8sss";
              metadata.name = "k8sss-scripts";
              data."setup-k8sss-config.sh" = builtins.readFile ./scripts/setup-k8sss-config.sh;
            }
            {
              apiVersion = "apps/v1";
              kind = "Deployment";
              metadata.namespace = "k8sss";
              metadata.name = "k8sss";
              spec.template.metadata.labels = {
                "cluster.local/apiserver-egress" = "allow";
              };
              spec.template.spec = {
                initContainers = [
                  {
                    name = "setup-k8sss-config";
                    env = [
                      {
                        name = "DOMAIN";
                        value = ccfg.domain;
                      }
                    ];
                    volumeMounts = [
                      {
                        name = "authorized-keys";
                        mountPath = "/home/step/admin_keys";
                        subPath = "admin-keys";
                        readOnly = true;
                      }
                    ];
                  }
                ];
                containers = [
                  {
                    name = "step-ca";
                  }
                ];
                volumes = [
                  {
                    name = "authorized-keys";
                    configMap.name = "admin-keys";
                    hostPath."$patch" = "delete";
                  }
                ];
              };
            }
          ]
        );
  };
}
