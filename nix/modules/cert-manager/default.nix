{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.cert-manager;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  charts = inputs.nixhelm.charts { inherit pkgs; };
  webhook = pkgs.buildGo126Module rec {
    name = "cert-manager-webhook-libdns";
    version = "0.7.0";
    meta.mainProgram = "cert-manager-webhook-libdns";
    src = pkgs.fetchFromGitHub {
      owner = "andsens";
      repo = name;
      rev = "774e7ccfdf1396ab94ad8b987f7758c875a99c4f";
      hash = "sha256-YHAW3CCYbLJ0HFe7stQJVVVCuWx2I/fz5tD/gD2KCPI=";
    };
    proxyVendor = true;
    vendorHash = "sha256-kQ8Le4CBOVPSgtDT/oL+h+qNKk5VqrcE1gu21OjLdjo=";

    doCheck = false; # Tests require kubebuilder running through `make test`
  };
  webhookImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/${webhook.name}";
    copyToRoot = [
      webhook
      pkgs.cacert
    ]
    ++ lib.optionals cfg.debug ccfg.debugTools;
    config.User = "1001:1001";
    config.Entrypoint = [
      (pkgs.lib.getExe webhook)
    ];
  };
  libdnsWebhookConfig = lib.types.submodule {
    options = {
      provider = lib.mkOption {
        description = "Name of the DNS provider";
        type = lib.types.str;
      };
      secretName = lib.mkOption {
        description = "Name of the DNS provider credentials secret in the cert-manager namespace";
        type = lib.types.str;
      };
    };
  };
in
{
  options.homelab.cert-manager = {
    debug = lib.mkEnableOption "debug mode";
    acme-staging-issuer.webhook-config = lib.mkOption {
      description = "LibDNS webhook configuration for the ACME staging issuer";
      type = libdnsWebhookConfig;
    };
    acme-production-issuer.webhook-config = lib.mkOption {
      description = "LibDNS webhook configuration for the ACME production issuer";
      type = libdnsWebhookConfig;
    };
  };
  config = {
    services.k3s.images = [ webhookImage ];
    services.k3s.manifests = {
      cert-manager-helm.source = kubelib.buildHelmChart {
        name = "cert-manager";
        namespace = "cert-manager";
        chart = charts.jetstack.cert-manager;
        values = {
          crds.enabled = true;
          config.enableGatewayAPI = true;
          podLabels = {
            "cluster.local/apiserver-egress" = "allow";
            "cluster.local/internet-egress" = "allow";
          };
          webhook.podLabels."cluster.local/apiserver-egress" = "allow";
          cainjector.podLabels."cluster.local/apiserver-egress" = "allow";
          startupapicheck.podLabels."cluster.local/apiserver-egress" = "allow";
        };
      };
      cert-manager-webhook-libdns-static.source = ./cert-manager-webhook-libdns.yaml;
    };
    kubetree.resources = {
      cert-manager = {
        namespace = (self.lib.k8s.createNamespace { namespace = "cert-manager"; });
        netpol-controller-to-webhook = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumNetworkPolicy";
          metadata = {
            namespace = "cert-manager";
            name = "controller-to-webhook";
            labels = {
              "app.kubernetes.io/name" = "cert-manager";
              "app.kubernetes.io/component" = "controller";
              "app.kubernetes.io/instance" = "cert-manager";
            };
          };
          spec.endpointSelector.matchLabels = {
            "app.kubernetes.io/name" = "cert-manager";
            "app.kubernetes.io/component" = "controller";
            "app.kubernetes.io/instance" = "cert-manager";
          };
          spec.egress = [
            {
              toEndpoints = [
                {
                  matchLabels = {
                    "app.kubernetes.io/name" = "webhook";
                    "app.kubernetes.io/component" = "webhook";
                    "app.kubernetes.io/instance" = "cert-manager";
                  };
                }
              ];
              toPortsFlattened = [ 10250 ];
            }
          ];
        };
        netpol-webhook-from-controller = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumNetworkPolicy";
          metadata = {
            namespace = "cert-manager";
            name = "webhook-from-controller";
            labels = {
              "app.kubernetes.io/name" = "webhook";
              "app.kubernetes.io/component" = "webhook";
              "app.kubernetes.io/instance" = "cert-manager";
            };
          };
          spec.endpointSelector.matchLabels = {
            "app.kubernetes.io/name" = "webhook";
            "app.kubernetes.io/component" = "webhook";
            "app.kubernetes.io/instance" = "cert-manager";
          };
          spec.ingress = [
            {
              fromEntities = [ "kube-apiserver" ];
              toPortsFlattened = [ 10250 ];
            }
            {
              fromEndpoints = [
                {
                  matchLabels = {
                    "app.kubernetes.io/name" = "cert-manager";
                    "app.kubernetes.io/component" = "controller";
                    "app.kubernetes.io/instance" = "cert-manager";
                  };
                }
              ];
              toPortsFlattened = [ 10250 ];
            }
          ];
        };
        selfsigned-issuer = {
          apiVersion = "cert-manager.io/v1";
          kind = "ClusterIssuer";
          metadata.name = "selfsigned";
          spec.selfSigned = { };
        };
        acme-staging-issuer = {
          apiVersion = "cert-manager.io/v1";
          kind = "ClusterIssuer";
          metadata.name = "letsencrypt-staging";
          spec.acme = {
            server = "https://acme-staging-v02.api.letsencrypt.org/directory";
            privateKeySecretRef.name = "letsencrypt-staging";
            solvers = [
              {
                dns01.webhook = {
                  groupName = "cluster.local";
                  solverName = "libdns";
                  config = {
                    provider = cfg.acme-staging-issuer.webhook-config.provider;
                    secretRef = {
                      namespace = "cert-manager";
                      name = cfg.acme-staging-issuer.webhook-config.secretName;
                    };
                  };
                };
              }
            ];
          };
        };
        acme-production-issuer = {
          apiVersion = "cert-manager.io/v1";
          kind = "ClusterIssuer";
          metadata.name = "letsencrypt-production";
          spec.acme = {
            server = "https://acme-v02.api.letsencrypt.org/directory";
            privateKeySecretRef.name = "letsencrypt-production";
            solvers = [
              {
                dns01.webhook = {
                  groupName = "cluster.local";
                  solverName = "libdns";
                  config = {
                    provider = cfg.acme-production-issuer.webhook-config.provider;
                    secretRef = {
                      namespace = "cert-manager";
                      name = cfg.acme-production-issuer.webhook-config.secretName;
                    };
                  };
                };
              }
            ];
          };
        };
        webhook-libdns-deployment = {
          apiVersion = "cluster.local";
          kind = "ServiceDeployment";
          metadata = {
            namespace = "cert-manager";
            name = "cert-manager-webhook-libdns";
          };
          spec.allowEgress = [
            "apiserver"
            "internet"
          ];
          spec.allowIngress = [ "apiserver" ];
          spec.servicePodSpec = {
            serviceAccountName = "cert-manager-webhook-libdns";
            securityContext.fsGroup = 1001;
            mainContainer = {
              image = "${webhookImage.buildArgs.name}:${webhookImage.imageTag}";
              imagePullPolicy = "Never";
              args = [
                "--tls-cert-file=/tls/tls.crt"
                "--tls-private-key-file=/tls/tls.key"
                "--secure-port=8443"
              ];
              envByName.GROUP_NAME = "cluster.local";
              portsByName.https = 8443;
              livenessProbe = {
                httpGet = {
                  scheme = "HTTPS";
                  path = "/healthz";
                  port = "https";
                };
              };
              readinessProbe = {
                httpGet = {
                  scheme = "HTTPS";
                  path = "/healthz";
                  port = "https";
                };
              };
              volumeMountsByPath."/tls" = {
                name = "tls";
                readOnly = true;
              };
            };
            volumesByName.tls.secret.secretName = "cert-manager-webhook-libdns-tls";
          };
        };
        webhook-libdns-service = {
          apiVersion = "cluster.local";
          kind = "ServiceService";
          metadata.namespace = "cert-manager";
          metadata.name = "cert-manager-webhook-libdns";
          spec.portsByName.https = {
            port = 443;
            targetPort = 8443;
          };
        };
        webhook-libdns-secret-reader-role = {
          apiVersion = "rbac.authorization.k8s.io/v1";
          kind = "Role";
          metadata = {
            namespace = "cert-manager";
            name = "cert-manager-webhook-libdns:secret-reader";
            labels."app.kubernetes.io/name" = "cert-manager-webhook-libdns";
          };
          rules = [
            {
              apiGroups = [ "" ];
              resources = [ "secrets" ];
              resourceNames = [
                cfg.acme-staging-issuer.webhook-config.secretName
                cfg.acme-production-issuer.webhook-config.secretName
              ];
              verbs = [
                "get"
                "watch"
              ];
            }
          ];
        };
      };
    };
  };
}
