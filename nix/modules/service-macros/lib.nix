{ lib, transform, ... }:
with builtins;
let
  inherit (transform) mkDotPath buildMetadata;
in
{
  transformServiceMacro =
    cfg: resource:
    let
      dotPath = mkDotPath resource;
      metadata = buildMetadata resource;
      dataPath = dotPath "spec.dataPath" null;
      servicePodSpec = dotPath "spec.servicePodSpec" null;
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
          spec =
            lib.recursiveUpdate
              (removeAttrs (dotPath "spec" { }) [
                "allowEgress"
                "allowIngress"
                "dataPath"
                "servicePodSpec"
                "ingressPort"
              ])
              {
                inherit allowEgress allowIngress;
                servicePodSpec =
                  if dataPath != null then
                    lib.recursiveUpdate {
                      mainContainer.volumeMountsByPath.${dataPath} = "data";
                      volumesByName.data.persistentVolumeClaim.claimName = metadata.name;
                    } servicePodSpec
                  else
                    servicePodSpec;
              };
        }
      ]
      ++ (lib.optional (dataPath != null) {
        apiVersion = "v1";
        kind = "PersistentVolumeClaim";
        inherit metadata;
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          volumeMode = "Filesystem";
        };
      })
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
            spec.ports = netpolPorts;
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
    in
    if (dotPath "servicePodSpec" null) == null then
      resource
    else
      lib.recursiveUpdate (removeAttrs resource [ "servicePodSpec" ]) ({
        spec =
          lib.recursiveUpdate
            {
              securityContext = {
                runAsUser = cfg.service-macros.securityContext.runAsUser;
                runAsGroup = cfg.service-macros.securityContext.runAsGroup;
                supplementalGroups = cfg.service-macros.securityContext.supplementalGroups;
                fsGroup = cfg.service-macros.securityContext.runAsGroup;
              };
              containersByName = {
                "${name}" =
                  lib.recursiveUpdate
                    {
                      inherit name;
                      securityContext = {
                        allowPrivilegeEscalation = false;
                        readOnlyRootFilesystem = true;
                        capabilities.add =
                          (dotPath "servicePodSpec.mainContainer.addCapabilities" [ ])
                          ++ lib.optional (
                            length (attrNames (dotPath "servicePodSpec.mainContainer.portsByName" { })) > 0
                          ) "NET_BIND_SERVICE";
                        capabilities.drop = [ "ALL" ];
                      };
                      volumeMountsByPath = dotPath "servicePodSpec.mainContainer.volumeMountsByPath" { };
                    }
                    (
                      removeAttrs (dotPath "servicePodSpec.mainContainer" { }) [
                        "addCapabilities"
                      ]
                    );
              };
              volumesByName = dotPath "servicePodSpec.volumesByName" { };
            }
            (
              removeAttrs ((dotPath "servicePodSpec") (throw "Unable to find 'servicePodSpec' attribute")) [
                "name"
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
            gatewayClassName = cfg.service-macros.gatewayClassName;
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
}
