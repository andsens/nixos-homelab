{
  inputs,
  config,
  pkgs,
  ...
}:
let
  ccfg = config.homelab.cluster;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  charts = inputs.nixhelm.charts { inherit pkgs; };
  webhook = pkgs.buildGo125Module rec {
    name = "cert-manager-webhook-externaldns";
    version = "0.0.1";
    meta.mainProgram = "certmanager-webhook-externaldns";
    src = pkgs.fetchFromGitHub {
      owner = "andsens";
      repo = name;
      rev = "9e4dcd49111710b86fccfa0259eb1b42934d22c6";
      hash = "sha256-2simuBBnuIQaD9/AqdgJeyJ3yIi6JOCVBb6+evSQu3g=";
    };
    proxyVendor = true;
    vendorHash = "sha256-mCTWdUW+givLKRlLWMZvR3jUg0WB1CEpOnWg2yxWoDc=";

    doCheck = false; # Tests require kubebuilder running through `make test`
  };
  webhookImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/${webhook.name}";
    copyToRoot = [ webhook ] ++ ccfg.debugTools;
    config.User = "1001:1001";
    config.Entrypoint = [
      (pkgs.lib.getExe webhook)
    ];
  };
in
{
  config = {
    services.k3s.images = [ webhookImage ];
    services.k3s.manifests = {
      cert-manager-static.source = ./cert-manager.yaml;
      cert-manager-externaldns-webhook-static.source = ./cert-manager-externaldns-webhook.yaml;
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
    };
    kubetree.resources = {
      cert-manager-externaldns-webhook-dynamic = {
        deployment = {
          apiVersion = "cluster.local";
          kind = "ServiceDeployment";
          metadata = {
            namespace = "cert-manager";
            name = "cert-manager-externaldns-webhook";
          };
          spec.allowEgress = [
            "apiserver"
            "host"
            "remote-node"
          ];
          spec.allowIngress = [ "apiserver" ];
          spec.servicePodSpec = {
            serviceAccountName = "cert-manager-externaldns-webhook";
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
              volumeMountsByPath."/apiserver.local.config" = "config";
              volumeMountsByPath."/tls" = {
                name = "tls";
                readOnly = true;
              };
            };
            volumesByName.config.emptyDir = { };
            volumesByName.tls.secret.secretName = "cert-manager-externaldns-webhook-tls";
          };
        };
        service = {
          apiVersion = "cluster.local";
          kind = "ServiceService";
          metadata.namespace = "cert-manager";
          metadata.name = "cert-manager-externaldns-webhook";
          spec.portsByName.https = {
            port = 443;
            targetPort = 8443;
          };
        };
      };
    };
  };
}
