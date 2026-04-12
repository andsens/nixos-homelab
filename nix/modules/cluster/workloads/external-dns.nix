{ ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  external-dns = pkgs.buildGo125Module rec {
    name = "external-dns";
    version = "v0.20.0";
    meta.mainProgram = "external-dns";
    src = pkgs.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = name;
      tag = "v0.20.0";
      hash = "sha256-hKmUpRKrefu0nseBc7BKjpvUHVvfLcAnod0kHwW2X14=";
    };
    patches = [ ./external-dns-support-txt-records.patch ];
    proxyVendor = true;
    vendorHash = "sha256-RpbiLUwea+xyCiFU2B3ypQlQH1PLCumOWhoYl7KrM08=";

    doCheck = false; # Tests require kubebuilder running through `make test`
  };
  externalDNSImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/${external-dns.name}";
    copyToRoot = [ external-dns ] ++ ccfg.debugTools;
    config.User = "65534:65534";
    config.Entrypoint = [
      (pkgs.lib.getExe external-dns)
    ];
  };
in
{
  options.homelab.cluster.external-dns = {
    deploymentOverlay = lib.mkOption {
      description = "Strategic merge overlay for external-dns deployment";
      type = lib.types.anything;
      default = { };
    };
  };
  config = {
    services.k3s.images = [ externalDNSImage ];
    services.k3s.manifests = {
      dnsendpoint.source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/kubernetes-sigs/external-dns/refs/tags/v0.20.0/charts/external-dns/crds/dnsendpoints.externaldns.k8s.io.yaml";
        hash = "sha256-lvQ4PVUKBNfHizMS7cbg+dq5d32Blf9M/cdqDKlYe74=";
      };
      external-dns-static.source = ./external-dns.yaml;
    };
    kubetree.resources = {
      external-dns-deployment.content = {
        apiVersion = "cluster.local";
        kind = "ServiceDeployment";
        metadata.name = "external-dns";
        spec = {
          allowEgress = [
            "apiserver"
            "internet"
          ];
          servicePodSpec = {
            serviceAccountName = "external-dns";
            mainContainer = {
              image = "${externalDNSImage.buildArgs.name}:${externalDNSImage.imageTag}";
              securityContext = {
                runAsGroup = 65534;
                runAsUser = 65534;
              };
              envByName = {
                EXTERNAL_DNS_SOURCE = ''
                  crd
                  service
                  ingress
                  gateway-httproute
                  gateway-tlsroute
                  gateway-grpcroute
                '';
                EXTERNAL_DNS_MANAGED_RECORD_TYPES = ''
                  A
                  AAAA
                  CNAME
                  TXT
                  MX
                '';
                EXTERNAL_DNS_EVENTS_EMIT = ''
                  RecordReady
                  RecordDeleted
                  RecordError
                '';
                EXTERNAL_DNS_TXT_PREFIX = "edns-%{record_type}.";
                EXTERNAL_DNS_TXT_OWNER_ID = "homelab";
                EXTERNAL_DNS_EVENTS = "1";
                EXTERNAL_DNS_INTERVAL = "5m";
              };
              portsByName.metrics = 7979;
              livenessProbe.httpGet = {
                path = "/healthz";
                port = "metrics";
              };
              readinessProbe.httpGet = {
                path = "/healthz";
                port = "metrics";
              };
            };
            containersByName.external-dns-node-source = {
              image = "${externalDNSImage.buildArgs.name}:${externalDNSImage.imageTag}";
              securityContext = {
                runAsGroup = 65534;
                runAsUser = 65534;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities.add = [ "NET_BIND_SERVICE" ];
                capabilities.drop = [ "ALL" ];
              };
              envByName = {
                EXTERNAL_DNS_METRICS_ADDRESS = ":7980";
                EXTERNAL_DNS_FQDN_TEMPLATE = "{{ .Name }}.${ccfg.domain}";
                EXTERNAL_DNS_SOURCE = "node";
                EXTERNAL_DNS_EXPOSE_INTERNAL_IPV6 = "1";
                EXTERNAL_DNS_EVENTS_EMIT = ''
                  RecordReady
                  RecordDeleted
                  RecordError
                '';
                EXTERNAL_DNS_TXT_PREFIX = "edns-%{record_type}.";
                EXTERNAL_DNS_TXT_OWNER_ID = "homelab-node-source";
                EXTERNAL_DNS_EVENTS = "1";
                EXTERNAL_DNS_INTERVAL = "5m";
              };
              portsByName.metrics-node = 7980;
              livenessProbe.httpGet = {
                path = "/healthz";
                port = "metrics-node";
              };
              readinessProbe.httpGet = {
                path = "/healthz";
                port = "metrics-node";
              };
            };
          };
        };
      };
    };
  };
}
