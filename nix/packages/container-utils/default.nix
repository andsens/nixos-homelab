{
  lib,
  dockerTools,
  bash,
  cacert,
  coreutils,
  curl,
  dig,
  gettext,
  gnugrep,
  iperf2,
  iproute2,
  jq,
  kubectl,
  mtr,
  netcat-gnu,
  socat,
  step-cli,
  step-kms-plugin,
  unixtools,
  util-linux,
  wget,
  xq-xml,
  ...
}:
dockerTools.buildImage {
  name = "cluster.local/utils";
  copyToRoot = [
    bash
    cacert
    coreutils
    curl
    dig
    gettext
    gnugrep
    iperf2
    iproute2
    jq
    kubectl
    mtr
    netcat-gnu
    socat
    step-cli
    step-kms-plugin
    unixtools.ping
    unixtools.procps
    util-linux
    wget
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
