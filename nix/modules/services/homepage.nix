{ ... }@moduleArgs:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage;
  backgroundImage = pkgs.fetchurl {
    name = "backgroundImage.png";
    url = "https://images.unsplash.com/photo-1502790671504-542ad42d5189?auto=format&fit=crop&w=2560&q=80";
    hash = "sha256-ixg2MEbI/0tvJXAQ9V2JB9yyiUrOPgIE5QNtpahIIQE=";
  };
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/homepage";
    fromImage = pkgs.dockerTools.pullImage {
      imageName = "ghcr.io/gethomepage/homepage";
      imageDigest = "sha256:baffd41118d17202632c4c86d07bed10bd853115630dcbbe4907442742a594b8";
      sha256 = "sha256-VRkoBsahzKSNPdiBszWGeNq8ayfe6NEeuzFf9Fqgnbc=";
      os = "linux";
      arch = "x86_64";
    };
    copyToRoot = [ pkgs.bash ] ++ ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      cp -r /app/.next/server/pages /app/.next/server/pages-template
    '';
    config.WorkingDir = "/app";
    config.Entrypoint = [
      (pkgs.lib.getExe (
        pkgs.writeShellScriptBin "setup-pages" ''
          cp -r /app/.next/server/pages-template/. /app/.next/server/pages/.
          exec "$@"
        ''
      ))
    ];
    config.Cmd = [
      "node"
      "server.js"
    ];
  };
  toSortedList =
    attrs:
    (lib.sortOn ({ name, value }: if (lib.hasAttr "sort" value) then value.sort else 100) (
      lib.filter ({ name, value }: if (lib.hasAttr "show" value) then value.show else true) (
        lib.attrsToList attrs
      )
    ));
in
{
  options.homelab.services.homepage = {
    enable = lib.mkEnableOption "homepage";
    allowEgress = lib.mkOption {
      description = "Which services homepage should be allowed access to";
      type = lib.types.listOf lib.types.str;
    };
    envByName = lib.mkOption {
      description = "Additional environment options to add to the homepage container";
      type = lib.types.attrsOf lib.types.anything;
    };
    widgets = lib.mkOption {
      description = "Widgets to add to homepage";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    services = lib.mkOption {
      description = "Services to add to homepage";
      type = lib.types.attrsOf (
        lib.types.attrsOf (lib.types.either (lib.types.int) (lib.types.attrsOf lib.types.anything))
      );
      default = { };
    };
  };
  imports = map (path: import path moduleArgs) [
    ./homepage-integrations/flood.nix
    ./homepage-integrations/ghostfolio.nix
    ./homepage-integrations/grafana.nix
    ./homepage-integrations/plex.nix
    ./homepage-integrations/prowlarr.nix
    ./homepage-integrations/radarr.nix
    ./homepage-integrations/sabnzbd.nix
    ./homepage-integrations/sonarr.nix
  ];
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Media = {
      sort = lib.mkDefault 50;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.services.homepage.services.Managers = {
      sort = lib.mkDefault 100;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.services.homepage.services.Download = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.services.homepage.services.Finance = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    homelab.services.homepage.services.Monitoring = {
      sort = lib.mkDefault 150;
      layout = lib.mkDefault {
        header = false;
        style = "row";
        columns = 3;
      };
    };
    services.k3s.images = [ image ];
    services.k3s.manifests.homepage-static.source = ./homepage.yaml;
    kubetree.resources = {
      homepage-dynamic = {
        config = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata.name = "config";
          metadata.namespace = "homepage";
          data = {
            "kubernetes.yaml" = builtins.toJSON { mode = "cluster"; };
            "bookmarks.yaml" = builtins.toJSON [ ];
            "services.yaml" = builtins.toJSON (
              map (
                { name, value }:
                {
                  ${name} =
                    map
                      (
                        { name, value }:
                        {
                          ${name} = lib.removeAttrs value [ "sort" ];
                        }
                      )
                      (
                        toSortedList (
                          lib.removeAttrs value [
                            "sort"
                            "layout"
                          ]
                        )
                      );
                }
              ) (toSortedList cfg.services)
            );
            "widgets.yaml" = builtins.toJSON (
              map (
                { name, value }:
                {
                  ${name} = lib.removeAttrs value [ "sort" ];
                }
              ) (toSortedList cfg.widgets)
            );
            "docker.yaml" = "";
            "settings.yaml" = builtins.toJSON {
              disableUpdateCheck = true;
              background = "/images/background.png";
              cardBlur = "xs";
              layout = map (
                { name, value }:
                {
                  ${name} = value.layout or { };
                }
              ) (toSortedList cfg.services);
            };
            "proxmox.yaml" = "";
            "custom.css" = "";
            "custom.js" = "";
          };
        };
        service-macro = {
          apiVersion = "cluster.local";
          kind = "ServiceMacro";
          metadata.name = "homepage";
          spec = {
            allowIngress = [ "gateway" ];
            allowEgress = [
              "apiserver"
            ]
            ++ cfg.allowEgress;
            ingressPort = null;
            servicePodSpec.mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              envByName = cfg.envByName // {
                HOMEPAGE_ALLOWED_HOSTS = ccfg.domain;
                PUID = "1000";
                PGID = "1000";
              };
              portsByName.web = 3000;
              livenessProbe.httpGet.port = "web";
              readinessProbe.httpGet.port = "web";
              volumeMountsByPath =
                (lib.mergeAttrsList (
                  map
                    (filename: {
                      "/app/config/${filename}" = {
                        name = "config";
                        subPath = filename;
                      };
                    })
                    [
                      "custom.js"
                      "custom.css"
                      "bookmarks.yaml"
                      "docker.yaml"
                      "kubernetes.yaml"
                      "proxmox.yaml"
                      "services.yaml"
                      "settings.yaml"
                      "widgets.yaml"
                    ]
                ))
                // {
                  "/app/.next/server/pages" = "pages";
                  "/app/config/logs" = "logs";
                  "/app/public/images/background.png" = "background-image";
                };
            };
            servicePodSpec.volumesByName = {
              config.configMap.name = "config";
              logs.emptyDir = { };
              pages.emptyDir = { };
              background-image = {
                hostPath.path = backgroundImage;
                hostPath.type = "File";
              };
            };
          };
        };
        gateway = {
          apiVersion = "cluster.local";
          kind = "ServiceGateway";
          metadata.name = "homepage";
          spec.port = 3000;
          spec.subdomain = null;
        };
      };
    };
  };
}
