# https://github.com/arnarg/nixidy/blob/65723ff09083d27d58792a739bb56a7885215f07/lib/kustomize.nix
{ lib, ... }:
{
  k8s = with builtins; {
    createNamespace =
      { namespace }:
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = namespace;
      };
    buildKustomization =
      { pkgs, ... }:
      {
        # Only used for derivation name.
        name,
        # Derivation containing the kustomization entrypoint and
        # all relative bases that it might reference.
        src,
        # Path in the derivation to build
        path ? ".",
        # Options to serialize into a configmap named "options", saved in options.yaml
        options ? null,
        # Map {dst = src} of additional files to copy into the derivation
        extraFiles ? { },
      }:
      pkgs.stdenvNoCC.mkDerivation {
        inherit src;
        name = "kustomize-${name}";

        phases = [
          "unpackPhase"
          "patchPhase"
          "installPhase"
        ];

        patchPhase =
          lib.join "\n" (lib.mapAttrsToList (dst: src: ''cp "${src}" "${dst}"'') extraFiles)
          + pkgs.lib.optionalString (!isNull options) ''
            cat >"${path}/options.yaml" <<EOF
            ${toJSON {
              apiVersion = "v1";
              kind = "ConfigMap";
              metadata.name = "options";
              metadata.annotations."config.kubernetes.io/local-config" = "true";
              data = toJSON options;
            }}
            EOF
          '';

        installPhase = ''
          ls -al >&2
          ${pkgs.kubectl}/bin/kubectl kustomize "${path}" -o "$out"
        '';
      };
    patchManifest =
      { pkgs, ... }:
      src: patch:
      pkgs.stdenvNoCC.mkDerivation {
        name = "k8s-patch-manifest";

        phases = [
          "buildPhase"
          "installPhase"
        ];

        buildPhase = ''
          runHook preBuild
          cp ${src} resource.yaml
          cp ${patch} patch.yaml
          cat >kustomization.yaml <<EOF
          apiVersion: kustomize.config.k8s.io/v1beta1
          kind: Kustomization
          resources: [resource.yaml]
          patches: [{path: patch.yaml}]
          EOF
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          ${pkgs.kubectl}/bin/kubectl kustomize . -o "$out"
          runHook postInstall
        '';
      };
  };
}
