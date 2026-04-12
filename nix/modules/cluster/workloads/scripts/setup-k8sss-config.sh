#!/usr/bin/env bash
set -eo pipefail

export STEPPATH=/home/step
KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca.crt

main() {
  local config
  printf "Creating CA config\n" >&2
  : "${NODENAME:?}"
  config=$(jq \
    --arg mdnsnodename "${NODENAME%'.local'}.local" \
    --arg uqnodename "${NODENAME%'.local'}" \
    --arg fqnodename "${NODENAME%'.local'}.${DOMAIN:?}" '
      .dnsNames+=([$mdnsnodename, $uqnodename, $fqnodename] | unique)
    ' "$STEPPATH/config-ro/k8sss.json")
  config=$(jq --argjson admin_keys "$(cat /home/step/admin_keys)" '
    .authority.provisioners+=[$admin_keys[] |
      {
       "type": "JWK",
       "name": .kid,
       "key": .,
       "options": { "x509": { "templateFile": "/home/step/templates/admin.tpl" } },
      }
    ]' <<<"$config")
  printf "%s\n" "$config" >"$STEPPATH/config/ca.json"

  local certs_ram_path=$STEPPATH/secrets
  printf "Copying k8sss cert & key to RAM backed volume\n" >&2
  cp "$KUBE_CLIENT_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  cp "$KUBE_CLIENT_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
}

main "$@"
