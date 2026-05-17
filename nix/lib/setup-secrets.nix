{ lib, ... }:
{
  mkScript =
    pkgs: script:
    lib.getExe (
      pkgs.writeShellScriptBin "setup-secret-cmd.sh" ''
        set -eo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnugrep
            pkgs.gnused
            pkgs.kubectl
          ]
        }
        getKubeSecret() {
          local namespace=$1 name=$2 field=$3
          kubectl -n "$namespace" get secret "$name" -ogo-template="{{.data.$field | base64decode}}";
        }
        setKubeSecret() {
          local namespace=$1 name=$2 field=$3 value=$4
          kubectl create secret generic --dry-run=client -oyaml -n "$namespace" "$name" \
            --from-literal=$field="$value" | \
            kubectl apply -f -;
        }
        ${script}
      ''
    );
}
