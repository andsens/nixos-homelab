{
  lib,
  dockerTools,
  bash,
  coreutils,
  gnugrep,
  gettext,
  dig,
  curl,
  wget,
  kubectl,
  step-cli,
  step-kms-plugin,
  jq,
  cacert,
  netcat-gnu,
  unixtools,
  socat,
  mtr,
  iperf2,
  iproute2,
  xq-xml,
  ...
}:
dockerTools.buildImage {
  name = "cluster.local/utils";
  copyToRoot = [
    bash
    coreutils
    gnugrep
    gettext
    dig
    curl
    wget
    kubectl
    step-cli
    step-kms-plugin
    jq
    cacert
    netcat-gnu
    unixtools.procps
    socat
    unixtools.ping
    mtr
    iperf2
    iproute2
    xq-xml
  ];
  config.Env = [
    "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
  ];
  config.Entrypoint = [
    (lib.getExe bash)
    "-c"
  ];
}
