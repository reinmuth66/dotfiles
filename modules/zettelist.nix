{
  config,
  inputs,
  pkgs,
  ...
}:

let
  inherit (inputs) zettelist;
  omnigraph = inputs.omnigraph.packages.${pkgs.stdenv.hostPlatform.system}.default;
  home = config.home.homeDirectory;
  data = "${home}/.local/share/zettelist/graph";

  # Create the graph from zettelist's schema on first start, then run the server zl and Studio share.
  startServer = pkgs.writeShellScript "omnigraph-server-start" ''
    set -eu
    export PATH=${omnigraph}/bin:${pkgs.jq}/bin:$PATH
    if [ ! -d ${data} ]; then
      mkdir -p ${data}
      # A half-made graph would be skipped on the next start, so remove it on failure.
      omnigraph cluster apply --target ${data} --config ${zettelist}/schema --as zettelist --json >/dev/null \
        || { rm -rf ${data}; exit 1; }
      # apply keeps its admission lock; release it before the server starts.
      lock=$(omnigraph cluster status --target ${data} --json | jq -r '.lock_id // empty')
      [ -z "$lock" ] || omnigraph cluster force-unlock "$lock" --target ${data} >/dev/null
    fi
    exec omnigraph-server --cluster file://${data} --bind 127.0.0.1:8080 --unauthenticated
  '';
in
{
  home.packages = [ zettelist.packages.${pkgs.stdenv.hostPlatform.system}.default ];

  launchd.agents.omnigraph-server = {
    enable = true;
    config = {
      ProgramArguments = [ "${startServer}" ];
      RunAtLoad = true;
      KeepAlive = true;
      # cluster.yaml reads it; Ollama ignores the value.
      EnvironmentVariables.OLLAMA_API_KEY = "unused";
      StandardOutPath = "${home}/Library/Logs/omnigraph-server.log";
      StandardErrorPath = "${home}/Library/Logs/omnigraph-server.log";
    };
  };

  # Studio resolves target zl here and opens it only if it matches the operator.yaml zl writes, byte for byte.
  home.file.".omnigraph/config.yaml".text = ''
    version: 1
    targets:
      zl:
        kind: server
        endpoint: "http://127.0.0.1:8080"
        auth: {provider: anonymous}
        default_graph: "zettelkasten"
  '';

  xdg.configFile."zettelist/config.toml".text = ''
    [backup]
    repo = "${home}/ghq/github.com/reinmuth66/zettelkasten"
    push = true
  '';
}
