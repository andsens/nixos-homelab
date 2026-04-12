{ lib, ... }:
with builtins;
{
  transformToPortsFlattened =
    cfg: resource:
    let
      newPorts = map (
        portSpec:
        (
          if isInt portSpec then
            { port = toString portSpec; }
          else
            portSpec // { port = toString portSpec.port; }
        )
      ) (lib.attrByPath [ "toPortsFlattened" ] [ ] resource);
    in
    (removeAttrs resource [ "toPortsFlattened" ])
    // lib.optionalAttrs (length newPorts > 0) {
      toPorts = (lib.attrByPath [ "toPorts" ] [ ] resource) ++ [ { ports = newPorts; } ];
    };
}
