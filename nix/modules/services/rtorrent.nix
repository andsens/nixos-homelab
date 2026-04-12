{
  inputs,
  self,
  pkgs,
  lib,
  config,
  ...
}:
{
  options.homeServer.services.rtorrent = {
    enable = lib.mkEnableOption "rtorrent";
    downloadPath = lib.mkOption {
      description = "Download directory";
      type = lib.types.path;
    };
  };
  config =
    let
      ccfg = config.homeServer.cluster;
      flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      cfg = config.homeServer.services.rtorrent;
      kubelib = inputs.kube-generators.lib { inherit pkgs; };
      bittorrentPort = 6881;
      dhtPort = 6881;
      wrapper = pkgs.writeShellScriptBin "rtorrent-wrapper" ''
        set -eo pipefail
        cleanup() {
          set +e
          kill -$1 $RTORRENT_PID
          kill $TAIL_RTORRENT_PID
          kill $TAIL_EXECUTE_PID
          wait $RTORRENT_PID
          exit $?
        }

        main() {
          for signal in TERM HUP INT USR1 USR2 QUIT; do
            # shellcheck disable=2064
            trap "cleanup $signal" $signal
          done
          trap "cleanup TERM" EXIT

          rm -f /var/log/rtorrent.log /var/log/execute.log
          mkfifo /var/log/rtorrent.log /var/log/execute.log
          exec 3<>/var/log/rtorrent.log
          cat <&3 >&2 & TAIL_RTORRENT_PID=$!
          exec 4<>/var/log/execute.log
          cat <&4 >&2 & TAIL_EXECUTE_PID=$!
          rtorrent_opts=(-o system.daemon.set=true)
          [[ $EXTERNAL_IP = 0.0.0.0 ]] || rtorrent_opts+=(-i ''${EXTERNAL_IP})

          printf "Starting rtorrent: rtorrent %s %s\n" "''${rtorrent_opts[*]}" "$*" >&2
          "${pkgs.lib.getExe pkgs.rtorrent}" "''${rtorrent_opts[@]}" "$@" & RTORRENT_PID=$!

          wait $RTORRENT_PID
        }

        main "$@"
      '';
      image = pkgs.dockerTools.buildImage {
        name = "cluster.local/rtorrent";
        copyToRoot = [
          wrapper
          pkgs.cacert
          pkgs.rtorrent
          pkgs.bash
          pkgs.coreutils
        ]
        ++ ccfg.debugTools;
        config.Env = [
          "RTORRENT_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
          "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        ];
        runAsRoot = ''
          #!${pkgs.runtimeShell}
          ${pkgs.dockerTools.shadowSetup}
          groupadd -r -g 100 users
          groupadd -r -g ${toString ccfg.defaultUser.gid} admin
          useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -G users -d ${ccfg.dataPath}/rtorrent rtorrent
        '';
        config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
        config.Entrypoint = [
          (pkgs.lib.getExe wrapper)
        ];
      };

      deployment = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata.name = "rtorrent";
        metadata.namespace = "rtorrent";
        metadata.labels."app.kubernetes.io/name" = "rtorrent";
        spec = {
          strategy.type = "Recreate";
          selector.matchLabels."app.kubernetes.io/name" = "rtorrent";
          template.metadata.labels = {
            "app.kubernetes.io/name" = "rtorrent";
            "cluster.local/internet-egress" = "allow";
          }
          // lib.optionalAttrs (config.homeServer.privacyVPN.enable) {
            "cluster.local/egress-gateway" = "privacy-vpn";
          };
          template.servicePodSpec = {
            name = "rtorrent";
            chownVolumes = [ "bt-downloads" ];
            addDataMount = true;
            terminationGracePeriodSeconds = 10;
            initContainersByName.rm-locks = {
              image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
              imagePullPolicy = "Never";
              args = [
                ''rm -f "${ccfg.dataPath}/rtorrent/rtorrent.pid" "${ccfg.dataPath}/rtorrent/rtorrent.lock"''
              ];
              securityContext.readOnlyRootFilesystem = true;
              volumeMountsByPath."${ccfg.dataPath}/rtorrent" = "data";
            };
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              args = [
                "-n"
                "-d"
                cfg.downloadPath
                "-s"
                "${ccfg.dataPath}/rtorrent"
                "-p"
                "$(BITTORRENT_PORT)-$(BITTORRENT_PORT)"
                "-o"
                "dht.port.set=$(DHT_PORT)"
                "-o"
                "try_import=/etc/rtorrent.rc"
              ];
              livenessProbe.tcpSocket.port = "rpc";
              readinessProbe.tcpSocket.port = "rpc";
              # Not using createServicePod env arg, the ordering is significant when patching the deployment
              env = [
                {
                  name = "EXTERNAL_IP";
                  value = "0.0.0.0";
                }
                {
                  name = "BITTORRENT_PORT";
                  value = builtins.toString bittorrentPort;
                }
                {
                  name = "DHT_PORT";
                  value = builtins.toString dhtPort;
                }
              ];
              ports = [
                {
                  name = "rpc";
                  containerPort = 5000;
                }
                (
                  {
                    name = "bittorrent";
                    protocol = "TCP";
                    containerPort = bittorrentPort;
                  }
                  // (lib.optionalAttrs config.homeServer.privacyVPN.enable {
                    hostPort = bittorrentPort;
                    hostIP =
                      lib.maybeAttr "clientIP4" config.homeServer.privacyVPN.clientIP6
                        config.homeServer.privacyVPN;
                  })
                )
                (
                  {
                    name = "dht";
                    protocol = "UDP";
                    containerPort = dhtPort;
                  }
                  // (lib.optionalAttrs config.homeServer.privacyVPN.enable {
                    hostPort = dhtPort;
                    hostIP =
                      lib.maybeAttr "clientIP4" config.homeServer.privacyVPN.clientIP6
                        config.homeServer.privacyVPN;
                  })
                )
              ];
              hostMounts."${cfg.downloadPath}" = {
                name = "bt-downloads";
                hostPath.type = "DirectoryOrCreate";
              };
              volumeMountsByPath = {
                "/etc/rtorrent.rc" = {
                  name = "config";
                  subPath = "rtorrent.rc";
                };
                "/var/log" = "log";
                "/var/run" = "run";
              };
            };
            volumesByName = {
              config.configMap.name = "config";
              log.emptyDir = { };
              run.emptyDir = { };
            };
          };
        };
      };
      kustomization = kubelib.toYAMLFile {
        apiVersion = "kustomize.config.k8s.io/v1beta1";
        kind = "Kustomization";
        resources = [ "rtorrent.yaml" ];
        patches = [
          {
            path = "ports.yaml";
            target.kind = "Deployment";
            target.name = "rtorrent";
          }
        ];
      };
      applyDeployment = pkgs.writeShellScriptBin "apply-rtorrent-deployment" ''
        set -eo pipefail

        main() {
          local external_ip=$1 bittorrent_port=$2 dht_port=$3 overlay_dir
          overlay_dir=$(mktemp -d --suffix -rtorrent-deployment)
          trap "rm -rf \"$overlay_dir\"" EXIT
          cp "${kustomization}" "$overlay_dir/kustomization.yaml"
          cp "${kubelib.toYAMLFile (inputs.kubetree.lib.transform.transformResource config.kubetree deployment)}" "$overlay_dir/rtorrent.yaml"
          cat >"$overlay_dir/ports.yaml" <<EOF
        - op: replace
          path: /spec/template/spec/containers/0/env/0/value
          value: "$external_ip"
        - op: replace
          path: /spec/template/spec/containers/0/env/1/value
          value: "$bittorrent_port"
        - op: replace
          path: /spec/template/spec/containers/0/env/2/value
          value: "$dht_port"
        - op: replace
          path: /spec/template/spec/containers/0/ports/1/containerPort
          value: $bittorrent_port
        - op: replace
          path: /spec/template/spec/containers/0/ports/2/containerPort
          value: $dht_port
        EOF
          ${lib.getExe pkgs.kubectl} apply -k "$overlay_dir"
        }

        main "$@"
      '';
    in
    lib.mkIf cfg.enable {
      networking.firewall.allowedTCPPorts = [ bittorrentPort ];
      services.k3s.images = [ image ];
      kubetree.resources.rtorrent-deployment.deployment = deployment;
      services.k3s.manifests.rtorrent-deployment.enable = !config.homeServer.privacyVPN.enable;
      kubetree.resources.rtorrent = {
        world-to-rtorrent = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumNetworkPolicy";
          metadata = {
            namespace = "rtorrent";
            name = "world-to-rtorrent";
            labels."app.kubernetes.io/name" = "rtorrent";
          };
          spec.endpointSelector.matchLabels."app.kubernetes.io/name" = "rtorrent";
          spec.ingress = [
            {
              fromEntities = [ "world" ];
              toPortsFlattened = [
                {
                  port = "5001";
                  endPort = 65535;
                }
              ];
            }
          ];
        };
        config = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata.name = "config";
          metadata.namespace = "rtorrent";
          data."rtorrent.rc" = builtins.readFile ./rtorrent.rc;
        };
        namespace = (self.lib.k8s.createNamespace { namespace = "rtorrent"; });
        service = {
          apiVersion = "cluster.local";
          kind = "ServiceService";
          metadata.name = "rtorrent";
          spec.portsByName.scgi = 5000;
        };
        netpols = {
          apiVersion = "cluster.local";
          kind = "ServiceNetpols";
          metadata.name = "rtorrent";
          spec.toPortsFlattened = [ 5000 ];
        };
      };

      systemd.timers."portmap-rtorrent" = lib.mkIf (config.homeServer.privacyVPN.enable) {
        description = "Request the privacy VPN server to forward a port for rtorrent";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "45";
          AccuracySec = "1";
        };
      };

      systemd.services."portmap-rtorrent" = lib.mkIf (config.homeServer.privacyVPN.enable) {
        description = "Request the privacy VPN server to forward a port for rtorrent and setup the rtorrent deployment";
        after = [
          "k3s.service"
          "sys-devices-virtual-net-privacy-vpn.device"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "default.target" ];
        script = ''
          natpmpcmd() { ${lib.getExe pkgs.libnatpmp} -g ${
            lib.maybeAttr "gatewayIP4" config.homeServer.privacyVPN.gatewayIP6 config.homeServer.privacyVPN
          } "$@" | tee >(cat >&2); }
          external_ip=$(natpmpcmd | grep 'Public IP address : ' | cut -d ' ' -f5)
          bittorrent_port=$(natpmpcmd -a 0 ${builtins.toString bittorrentPort} tcp | grep 'Mapped public port' | cut -d ' ' -f4)
          dht_port=$(natpmpcmd -a 0 ${builtins.toString dhtPort} udp | grep 'Mapped public port' | cut -d ' ' -f4)
          ${lib.getExe applyDeployment} "$external_ip" "$bittorrent_port" "$dht_port"
        '';
      };
    };
}
