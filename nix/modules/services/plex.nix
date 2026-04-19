{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.plex;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/plex";
    copyToRoot = [
      pkgs.plexRaw
      pkgs.cacert
    ]
    ++ ccfg.debugTools;
    config.Env = [
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g 900 plex
      useradd -r -u 900 -g plex -d /var/lib/plex plex
      # https://github.com/NixOS/nixpkgs/blob/3f40c4f8c496308680d71d9e17bce452928a2e17/pkgs/servers/plex/default.nix#L57
      cat "${pkgs.plexRaw.basedb}" >/db
    '';
    config.User = "900:900";
    config.Entrypoint = [
      "${pkgs.plexRaw}/lib/plexmediaserver/Plex Media Server"
    ];
  };
in
{
  options.homelab.services.plex = {
    # Run `kubectl port-forward -n plex plex-... 32400` after startup to set it up
    # The setup procedure is only enabled when accessing the server via localhost:32400/web
    enable = lib.mkEnableOption "Plex Media Server";
    reservedIPs = lib.mkOption {
      description = "Reserved IPs for the Plex loadbalancer";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    volumes = lib.mkOption {
      description = "Volumes to mount into the container expressed as a map of mountpath to volume source (as specificed on the pod spec).";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Media.Plex = {
      icon = "plex.png";
      description = "Media center";
      href = "https://plex.${ccfg.domain}";
      widget = {
        type = "plex";
        url = "http://plex.plex:32400";
        fields = [
          "streams"
          "movies"
          "tv"
        ];
        key = "{{HOMEPAGE_VAR_PLEX_API_KEY}}";
      };
    };
    homelab.cluster.secretsManager.importSecrets.plex-api-key = {
      extractCommands.PLEX_API_KEY = ''xq -x '//Preferences/@PlexOnlineToken' "/data/Library/Application Support/Plex Media Server/Preferences.xml"'';
      destinations = [ "homepage" ];
    };
    homelab.services.homepage.envByName.HOMEPAGE_VAR_PLEX_API_KEY.valueFrom.secretKeyRef = {
      name = "plex-api-key";
      key = "PLEX_API_KEY";
    };
    homelab.services.homepage.allowEgress = [ "plex" ];
    services.restic.backups.default.paths = [
      "/data/Library/Application Support/Plex Media Server"
    ];
    services.k3s.images = [ image ];
    kubetree.resources.plex = {
      netpol = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumNetworkPolicy";
        metadata = {
          namespace = "plex";
          name = "plex-from-local-lan";
          labels."app.kubernetes.io/name" = "plex";
        };
        spec.endpointSelector.matchLabels."app.kubernetes.io/name" = "plex";
        spec.ingress = [
          {
            fromCIDRSet = [
              { cidrGroupRef = "local-lan"; }
            ];
            toPortsFlattened = [ 32400 ];
          }
        ];
      };
      certificate = {
        apiVersion = "cert-manager.io/v1";
        kind = "Certificate";
        metadata = {
          namespace = "plex";
          name = "plex";
          labels."app.kubernetes.io/name" = "plex";
        };
        spec = {
          secretName = "plex-tls";
          commonName = "plex.${ccfg.domain}";
          dnsNames = [ "plex.${ccfg.domain}" ];
          issuerRef = {
            group = "cert-manager.io";
            kind = "ClusterIssuer";
            name = config.kubetree.service-macros.acmeProvider;
          };
          keystores.pkcs12 = {
            create = true;
            password = "plex";
            profile = "Modern2023";
          };
        };
      };
      external-service = {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          namespace = "plex";
          name = "plex-external";
          labels."app.kubernetes.io/name" = "plex";
          annotations = {
            "external-dns.alpha.kubernetes.io/hostname" = "plex.${ccfg.domain}";
          }
          // lib.optionalAttrs (builtins.length cfg.reservedIPs > 0) ({
            "lbipam.cilium.io/ips" = lib.join "," cfg.reservedIPs;
          });
        };
        spec = {
          type = "LoadBalancer";
          selector."app.kubernetes.io/name" = "plex";
          ipFamilies = (lib.optional ccfg.enableIPv4 "IPv4") ++ (lib.optional ccfg.enableIPv6 "IPv6");
          ports = [
            {
              name = "web";
              port = 443;
              targetPort = 32400;
            }
          ];
        }
        // (lib.optionalAttrs (ccfg.enableIPv4 && ccfg.enableIPv6) {
          ipFamilyPolicy = "RequireDualStack";
        });
      };
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "plex";
        spec = {
          allowEgress = [ "internet" ];
          dataPath = "/var/lib/plex";
          servicePodSpec = {
            initContainersByName.rm-lock = {
              image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
              imagePullPolicy = "Never";
              args = [
                ''rm -f "/var/lib/plex/Library/Application Support/Plex Media Server/plexmediaserver.pid"''
              ];
              securityContext.readOnlyRootFilesystem = true;
              volumeMountsByPath."/var/lib/plex" = "data";
            };
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              portsByName.web = 32400;
              livenessProbe.httpGet = {
                scheme = "HTTPS";
                port = "web";
                path = "/identity";
              };
              readinessProbe.httpGet = {
                scheme = "HTTPS";
                port = "web";
                path = "/identity";
              };
              volumeMountsByPath = {
                "/tls" = "tls";
                "/var/tmp" = "var-tmp";
                "/tmp" = "tmp";
              }
              // lib.mapAttrs' (
                key: value:
                lib.nameValuePair key {
                  name = (self.lib.k8s.pathToMountName key);
                  readOnly = true;
                }
              ) cfg.volumes;
            };
            volumesByName = {
              tls.secret.secretName = "plex-tls";
              var-tmp.emptyDir = { };
              tmp.emptyDir = { };
            }
            // lib.mapAttrs' (
              key: value: lib.nameValuePair (self.lib.k8s.pathToMountName key) value
            ) cfg.volumes;
          };
        };
      };
    };
  };
}
