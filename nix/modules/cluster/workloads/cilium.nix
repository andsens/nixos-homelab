{ inputs, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ccfg = config.homelab.cluster;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  charts = inputs.nixhelm.charts { inherit pkgs; };
in
{
  options.homelab.cluster = {
    lbCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the load balancers";
      type = lib.types.str;
      default = "10.44.0.0/16";
    };
    lbCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the load balancers";
      type = lib.types.str;
    };
    firewall.enable = lib.mkEnableOption "the Cilium host firewall (disables the NixOS firewall)";
    masquerade.enable = lib.mkOption {
      description = "Whether to turn on masquerading (automatically turned on if \${config.homelab.privacyVPN.enable} is on)";
      type = lib.types.bool;
      default = config.homelab.privacyVPN.enable;
    };
    ciliumConfig = lib.mkOption {
      description = "Additional Cilium helm configuration values to apply";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    bgp = {
      enable = lib.mkEnableOption "the provisioning of Cilium BGP configurations";
      routerIP4 = lib.mkOption {
        description = "IPv4 of the router for BGP communication";
        type = lib.types.str;
      };
      routerIP6 = lib.mkOption {
        description = "IPv6 of the router for BGP communication";
        type = lib.types.str;
      };
      clusterASN = lib.mkOption {
        description = "BGP ASN of the cluster";
        type = lib.types.int;
        default = 65000;
      };
      routerASN = lib.mkOption {
        description = "BGP ASN of the router";
        type = lib.types.int;
        default = 64512;
      };
    };
  };
  config = {
    assertions = [
      {
        assertion = !config.homelab.privacyVPN.enable || ccfg.masquerade.enable;
        message = "In order to use the privacy VPN, masquerading must be enabled (homelab.cluster.masquerade.enable)";
      }
    ];
    services.k3s.disable = [
      "traefik"
      "servicelb"
    ];
    services.k3s.manifests = {
      gatewayapi.source = pkgs.fetchurl {
        url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml";
        hash = "sha256-ZOx2YJpqyIXgQF3qecpQnCKfoBnTQvCFeqi2vci4upI=";
      };
      cilium-helm.source = kubelib.buildHelmChart {
        name = "cilium";
        namespace = "cilium";
        chart = charts.cilium.cilium;
        values = lib.recursiveUpdate (
          {
            hostFirewall.enabled = ccfg.firewall.enable;

            ipam.mode = "kubernetes";

            routingMode = "native";
            autoDirectNodeRoutes = true;

            kubeProxyReplacement = true;

            bgpControlPlane.enabled = ccfg.bgp.enable;
            nodeIPAM.enabled = true; # TODO: Needed?

            egressGateway.enabled = config.homelab.privacyVPN.enable;

            tls.secretsNamespace.name = "cilium";
            operator.replicas = 1;
            kubeConfigPath = "/etc/rancher/k3s/k3s.yaml";
            k8sServiceHost = "127.0.0.1";
            k8sServicePort = "6443";

            envoy.enabled = false;
            hubble.enabled = false;
            hubble.relay.gops.enabled = false;

            gatewayAPI.enabled = true;
            gatewayAPI.enableAlpn = true;
            gatewayAPI.enableAppProtocol = true;
            gatewayAPI.gatewayClass.create = "true";

            ipv4.enabled = ccfg.enableIPv4;
            ipv6.enabled = ccfg.enableIPv6;
            k8s.requireIPv4PodCIDR = ccfg.enableIPv4;
            k8s.requireIPv6PodCIDR = ccfg.enableIPv6;

            bpf.masquerade = ccfg.masquerade.enable;
          }
          // lib.optionalAttrs ccfg.enableIPv4 {
            ipv4NativeRoutingCIDR = ccfg.podCidr4;
            enableIPv4Masquerade = ccfg.masquerade.enable;
          }
          // lib.optionalAttrs ccfg.enableIPv6 {
            ipv6NativeRoutingCIDR = ccfg.podCidr6;
            enableIPv6Masquerade = ccfg.masquerade.enable;
          }
        ) ccfg.ciliumConfig;
      };
    };

    kubetree.resources.cilium-lbippool.pool = {
      apiVersion = "cilium.io/v2";
      kind = "CiliumLoadBalancerIPPool";
      metadata.name = "main";
      spec.blocks =
        (lib.optional ccfg.enableIPv4 { cidr = ccfg.lbCidr4; })
        ++ (lib.optional ccfg.enableIPv6 { cidr = ccfg.lbCidr6; });
    };

    kubetree.resources.cidrgroups = {
      pods = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumCIDRGroup";
        metadata.name = "pods";
        spec.externalCIDRs =
          (lib.optional ccfg.enableIPv4 ccfg.podCidr4) ++ (lib.optional ccfg.enableIPv6 ccfg.podCidr6);
      };
      services = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumCIDRGroup";
        metadata.name = "services";
        spec.externalCIDRs =
          (lib.optional ccfg.enableIPv4 ccfg.svcCidr4) ++ (lib.optional ccfg.enableIPv6 ccfg.svcCidr6);
      };
      load-balancers = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumCIDRGroup";
        metadata.name = "load-balancers";
        spec.externalCIDRs =
          (lib.optional ccfg.enableIPv4 ccfg.lbCidr4) ++ (lib.optional ccfg.enableIPv6 ccfg.lbCidr6);
      };
      local-lan = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumCIDRGroup";
        metadata.name = "local-lan";
        spec.externalCIDRs =
          lib.optional (ccfg.localLANCIDR4 != null) ccfg.localLANCIDR4
          ++ lib.optional (ccfg.localLANCIDR6 != null) ccfg.localLANCIDR6;
      };
    };

    networking.firewall.allowedUDPPorts = pkgs.lib.optional ccfg.firewall.enable 68; # DHCP, seems cilium host firewall blocks this
    services.k3s.manifests.cilium-hostfirewall-policy.enable = ccfg.firewall.enable;
    kubetree.resources.cilium-hostfirewall-policy.policy = {
      apiVersion = "cilium.io/v2";
      kind = "CiliumClusterwideNetworkPolicy";
      metadata = {
        name = "host-firewall";
      };
      spec.nodeSelector.matchLabels = { };
      spec.ingress = [
        { fromEntities = [ "cluster" ]; }
        {
          toPortsFlattened =
            (map (port: {
              port = builtins.toString port;
              protocol = "TCP";
            }) config.networking.firewall.allowedTCPPorts)
            ++ (map (port: {
              port = builtins.toString port;
              protocol = "UDP";
            }) config.networking.firewall.allowedUDPPorts)
            ++ (map (
              { from, to }:
              {
                port = builtins.toString from;
                endPort = to;
                protocol = "TCP";
              }
            ) config.networking.firewall.allowedTCPPortRanges)
            ++ (map (
              { from, to }:
              {
                port = builtins.toString from;
                endPort = to;
                protocol = "UDP";
              }
            ) config.networking.firewall.allowedUDPPortRanges);
        }
        {
          icmps = [
            { fields = lib.optional config.networking.firewall.allowPing { type = "EchoRequest"; }; }
          ];
        }
      ];
    };

    networking.firewall.allowedTCPPorts = pkgs.lib.optional ccfg.bgp.enable 179;
    services.k3s.manifests.cilium-bgpconfig.enable = ccfg.bgp.enable;
    kubetree.resources.cilium-bgpconfig =
      (lib.optionalAttrs ccfg.enableIPv4 {
        peer4 = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumBGPPeerConfig";
          metadata.name = "cilium-peer4";
          spec = {
            timers.holdTimeSeconds = 9;
            timers.keepAliveTimeSeconds = 3;
            gracefulRestart.enabled = true;
            gracefulRestart.restartTimeSeconds = 15;
            families = [
              {
                afi = "ipv4";
                safi = "unicast";
                advertisements.matchLabels.advertise = "bgp";
              }
            ];
          };
        };
      })
      // (lib.optionalAttrs ccfg.enableIPv6 {
        peer6 = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumBGPPeerConfig";
          metadata.name = "cilium-peer6";
          spec = {
            timers.holdTimeSeconds = 9;
            timers.keepAliveTimeSeconds = 3;
            gracefulRestart.enabled = true;
            gracefulRestart.restartTimeSeconds = 15;
            families = [
              {
                afi = "ipv6";
                safi = "unicast";
                advertisements.matchLabels.advertise = "bgp";
              }
            ];
          };
        };
      })
      // {
        router = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumBGPClusterConfig";
          metadata.name = "router";
          spec.bgpInstances = lib.optionals ccfg.bgp.enable [
            {
              name = "router";
              localASN = ccfg.bgp.clusterASN;
              peers =
                lib.optional ccfg.enableIPv4 {
                  name = "router4";
                  peerASN = ccfg.bgp.routerASN;
                  peerAddress = ccfg.bgp.routerIP4;
                  peerConfigRef.name = "cilium-peer4";
                }
                ++ lib.optional ccfg.enableIPv6 {
                  name = "router6";
                  peerASN = ccfg.bgp.routerASN;
                  peerAddress = ccfg.bgp.routerIP6;
                  peerConfigRef.name = "cilium-peer6";
                };
            }
          ];
        };
        advertisements = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumBGPAdvertisement";
          metadata.name = "bgp-advertisements";
          metadata.labels.advertise = "bgp";
          spec.advertisements = [
            {
              advertisementType = "PodCIDR";
              attributes.communities.standard = [ "65000:99" ];
              attributes.localPreference = 99;
            }
            {
              advertisementType = "Service";
              service.addresses = [
                "ClusterIP"
                "ExternalIP"
                "LoadBalancerIP"
              ];
              selector.matchExpressions = [
                {
                  key = "somekey";
                  operator = "NotIn";
                  values = [ "never-used-value" ];
                }
              ];
            }
          ];
        };
      };
  };
}
