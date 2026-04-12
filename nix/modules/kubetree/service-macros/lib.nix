{ lib, ... }:
with builtins;
rec {
  replaceInvalidCharacters =
    validCharsRE: replaceWith: string:
    lib.concatStrings (
      map (c: if match validCharsRE c == null then replaceWith else c) (lib.stringToCharacters string)
    );
  mkDotPath =
    resource: path: default:
    if path == "." then resource else lib.attrByPath (lib.splitString "." path) default resource;
  buildMetadata =
    resource:
    let
      dotPath = mkDotPath resource;
      name = dotPath "metadata.name" (throw "You must specify metadata.name");
      namespace = dotPath "metadata.namespace" name;
    in
    {
      inherit namespace;
      labels."app.kubernetes.io/name" = name;
    }
    // dotPath "metadata" (throw "You must specify metadata");
  pathToMountName =
    path:
    let
      cleaned = replaceInvalidCharacters "[a-z0-9-]" "-" (
        lib.toLower (lib.strings.removePrefix "/" path)
      );
    in
    if lib.stringLength cleaned > 63 then
      ((substring 0 54 cleaned) + "-" + (substring 0 8 (hashString "sha256" cleaned)))
    else
      cleaned;
  mkChownContainer = cfg: volumeNames: {
    name = "chown-data";
    image = "${cfg.service-macros.utilityImage}";
    imagePullPolicy = "Never";
    args = [
      "chown ${toString cfg.service-macros.defaultUser.uid}:${toString cfg.service-macros.defaultUser.gid} ${
        lib.escapeShellArgs (map (name: "/vol/${name}") volumeNames)
      }"
    ];
    securityContext.readOnlyRootFilesystem = true;
    volumeMountsByPath = lib.mergeAttrsList (map (name: { "/vol/${name}" = name; }) volumeNames);
  };
  transformServiceMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      servicePodSpec = (dotPath "spec.podSpec" (dotPath "spec.servicePodSpec" null));
      portsByName = (lib.attrByPath [ "mainContainer" "portsByName" ] { } servicePodSpec);
      netpolPorts = lib.mapAttrsToList (
        name: portSpec:
        if isInt portSpec then
          portSpec
        else
          {
            port = portSpec.containerPort;
          }
          // lib.optionalAttrs (hasAttr "protocol" portSpec) { protocol = portSpec.protocol; }
      ) portsByName;
      ingressPort = dotPath "spec.ingressPort" null;
      allowIngress = (lib.optional (ingressPort != null) "gateway") ++ (dotPath "spec.allowIngress" [ ]);
      allowEgress = dotPath "spec.allowEgress" [ ];
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "v1";
          kind = "Namespace";
          metadata.name = metadata.namespace;
        }
        {
          inherit metadata;
          apiVersion = "cluster.local";
          kind = "ServiceDeployment";
          spec = { inherit allowEgress allowIngress servicePodSpec; };
        }
      ]
      ++ (
        lib.optionals (length (attrNames portsByName) > 0) [
          {
            inherit metadata;
            apiVersion = "cluster.local";
            kind = "ServiceService";
            spec.portsByName = lib.mapAttrs (
              name: portSpec:
              if isInt portSpec then
                portSpec
              else
                {
                  inherit name;
                  port = portSpec.containerPort;
                }
                // lib.optionalAttrs (hasAttr "protocol" portSpec) { protocol = portSpec.protocol; }
            ) portsByName;
          }
          {
            inherit metadata;
            apiVersion = "cluster.local";
            kind = "ServiceNetpols";
            spec.toPortsFlattened = netpolPorts;
          }
        ]
        ++ lib.optional (ingressPort != null) ({
          inherit metadata;
          apiVersion = "cluster.local";
          kind = "ServiceGateway";
          spec.port = ingressPort;
        })
      );
    };
  transformServiceDeployment =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      servicePodSpec = dotPath "spec.servicePodSpec" null;
    in
    {
      inherit metadata;
      apiVersion = "apps/v1";
      kind = "Deployment";
      spec =
        lib.recursiveUpdate
          {
            strategy.type = "Recreate";
            selector.matchLabels = {
              "app.kubernetes.io/name" = metadata.name;
            }
            // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels;
            template = {
              metadata.labels = {
                "app.kubernetes.io/name" = metadata.name;
              }
              // lib.optionalAttrs (hasAttr "labels" metadata) metadata.labels
              // (lib.mergeAttrsList (
                (map (service: { "cluster.local/${service}-ingress" = "allow"; }) (dotPath "spec.allowIngress" [ ]))
                ++ (map (service: { "cluster.local/${service}-egress" = "allow"; }) (
                  dotPath "spec.allowEgress" [ ]
                ))
              ));
            }
            // lib.optionalAttrs (servicePodSpec != null) ({
              servicePodSpec = servicePodSpec // {
                name = metadata.name;
              };
            });
          }
          (
            removeAttrs (dotPath "spec" { }) [
              "servicePodSpec"
              "allowIngress"
              "allowEgress"
            ]
          );
    };
  transformServicePod =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      name = dotPath "servicePodSpec.name" (throw "The ServicePodSpec has no name");
      addDataMount = dotPath "servicePodSpec.addDataMount" false;
      _chownVolumes = (dotPath "servicePodSpec.chownVolumes" [ ]) ++ (lib.optional addDataMount "data");
      _volumeMountsByPath =
        (dotPath "servicePodSpec..mainContainer.volumeMountsByPath" { })
        // (lib.optionalAttrs addDataMount {
          "${cfg.service-macros.dataPath}/${name}".name = "data";
        })
        // (mapAttrs (path: hostMount: {
          name = lib.attrByPath [ "name" ] (pathToMountName path) hostMount;
          readOnly = lib.attrByPath [ "readOnly" ] false hostMount;
        }) (dotPath "servicePodSpec.mainContainer.hostMounts" { }));
      _volumesByName =
        (dotPath "servicePodSpec.volumesByName" { })
        // (lib.optionalAttrs addDataMount {
          data = {
            hostPath.path = "${cfg.service-macros.dataPath}/${name}";
            hostPath.type = "DirectoryOrCreate";
          };
        })
        // (lib.mapAttrs' (path: hostMount: {
          name = lib.attrByPath [ "name" ] (pathToMountName path) hostMount;
          value.hostPath.path = path;
          value.hostPath.type = lib.attrByPath [ "type" ] "Directory" hostMount;
        }) (dotPath "servicePodSpec.mainContainer.hostMounts" { }));
    in
    if (dotPath "servicePodSpec" null) == null then
      resource
    else
      lib.recursiveUpdate (removeAttrs resource [ "servicePodSpec" ]) ({
        spec =
          lib.recursiveUpdate
            {
              initContainersByName = lib.optionalAttrs (length _chownVolumes > 0) ({
                chown-data = mkChownContainer cfg _chownVolumes;
              });
              containersByName = {
                "${name}" =
                  lib.recursiveUpdate
                    {
                      inherit name;
                      securityContext = {
                        allowPrivilegeEscalation = false;
                        readOnlyRootFilesystem = true;
                        runAsUser = cfg.service-macros.defaultUser.uid;
                        runAsGroup = cfg.service-macros.defaultUser.gid;
                        capabilities = {
                          add =
                            (dotPath "servicePodSpec.mainContainer.addCapabilities" [ ])
                            ++ lib.optional (
                              length (attrNames (dotPath "servicePodSpec.mainContainer.portsByName" { })) > 0
                            ) "NET_BIND_SERVICE";
                          drop = [ "ALL" ];
                        };
                      };
                      volumeMountsByPath = _volumeMountsByPath;
                    }
                    (
                      removeAttrs (dotPath "servicePodSpec.mainContainer" { }) [
                        "addCapabilities"
                        "hostMounts"
                      ]
                    );
              };
              volumesByName = _volumesByName;
            }
            (
              removeAttrs ((dotPath "servicePodSpec") (throw "Unable to find 'servicePodSpec' attribute")) [
                "name"
                "addDataMount"
                "chownVolumes"
                "mainContainer"
              ]
            );
      });
  transformServiceService =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
    in
    lib.recursiveUpdate
      {
        inherit metadata;
        apiVersion = "v1";
        kind = "Service";
        spec.selector."app.kubernetes.io/name" = metadata.name;
      }
      (
        removeAttrs (dotPath "." (throw null)) [
          "apiVersion"
          "kind"
          "metadata"
        ]
      );
  transformServiceGateway =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      subdomain = dotPath "spec.subdomain" (metadata.name);
      hostname =
        if subdomain == null then
          cfg.service-macros.domain
        else
          "${subdomain}.${cfg.service-macros.domain}";
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = metadata // {
            annotations."cert-manager.io/cluster-issuer" = cfg.service-macros.acmeProvider;
          };
          spec = {
            gatewayClassName = "cilium";
            listeners = [
              {
                inherit hostname;
                name = "${metadata.name}-cleartext-redirect";
                port = 80;
                protocol = "HTTP";
              }
              {
                inherit hostname;
                name = metadata.name;
                port = 443;
                protocol = "HTTPS";
                tls.mode = "Terminate";
                tls.certificateRefs = [ { name = "${metadata.name}-tls"; } ];
              }
            ];
          };
        }
        {
          inherit metadata;
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "HTTPRoute";
          spec = {
            parentRefs = [
              {
                name = metadata.name;
                port = 443;
              }
            ];
            hostnames = [ hostname ];
            rules = [
              (
                {
                  matches = [
                    {
                      path.type = "PathPrefix";
                      path.value = "/";
                    }
                  ];
                  backendRefs = [
                    {
                      name = metadata.name;
                      port = dotPath "spec.port" (throw "You must specificy a port for ServiceGateway");
                    }
                  ];
                }
                // lib.optionalAttrs ((dotPath "spec.requestHeaderModifier" null) != null) {
                  filters = [
                    {
                      type = "RequestHeaderModifier";
                      requestHeaderModifier = dotPath "spec.requestHeaderModifier" null;
                    }
                  ];
                }
              )
            ];
          };
        }
        {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "HTTPRoute";
          metadata = metadata // {
            name = "${metadata.name}-cleartext-redirect";
          };
          spec = {
            parentRefs = [
              {
                name = metadata.name;
                port = 80;
              }
            ];
            hostnames = [ hostname ];
            rules = [
              {
                filters = [
                  {
                    type = "RequestRedirect";
                    requestRedirect.scheme = "https";
                    requestRedirect.statusCode = 301;
                  }
                ];
              }
            ];
          };
        }
      ];
    };
  transformServiceNetpols =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
    in
    {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "cilium.io/v2";
          kind = "CiliumClusterwideNetworkPolicy";
          metadata = removeAttrs metadata [ "namespace" ] // {
            name = "pod-to-${metadata.name}";
          };
          spec.endpointSelector.matchLabels."cluster.local/${metadata.name}-egress" = "allow";
          spec.egress = [
            {
              toEndpoints = [
                {
                  matchLabels = {
                    "k8s:io.kubernetes.pod.namespace" = metadata.namespace;
                    "app.kubernetes.io/name" = metadata.name;
                  };
                }
              ];
              toPortsFlattened = dotPath "spec.toPortsFlattened" [ ];
            }
          ];
        }
        {
          apiVersion = "cilium.io/v2";
          kind = "CiliumNetworkPolicy";
          metadata = metadata // {
            name = "${metadata.name}-from-pod";
          };
          spec.endpointSelector.matchLabels."app.kubernetes.io/name" = metadata.name;
          spec.ingress = [
            {
              fromEndpoints = [
                {
                  matchExpressions = [
                    {
                      "key" = "k8s:io.kubernetes.pod.namespace";
                      "operator" = "Exists";
                    }
                    {
                      "key" = "cluster.local/${metadata.name}-egress";
                      "operator" = "In";
                      "values" = [ "allow" ];
                    }
                  ];
                }
              ];
              toPortsFlattened = dotPath "spec.toPortsFlattened" [ ];
            }
          ];
        }
      ];
    };
}
