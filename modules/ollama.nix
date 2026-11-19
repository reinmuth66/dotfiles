{ config, pkgs, ... }:

let
  # Models to keep pulled. home-manager's services.ollama has no option for this.
  models = [ "qwen3-embedding:0.6b" ];

  ollama = config.services.ollama.package;

  pullModels = pkgs.writeShellScript "ollama-pull-models" ''
    # Wait up to 60 s for the server started by the ollama agent.
    for _ in $(seq 60); do
      ${ollama}/bin/ollama list >/dev/null 2>&1 && break
      sleep 1
    done
    installed=$(${ollama}/bin/ollama list | ${pkgs.gawk}/bin/awk 'NR > 1 { print $1 }')
    for model in ${toString models}; do
      if ! printf '%s\n' "$installed" | grep -qxF "$model"; then
        ${ollama}/bin/ollama pull "$model"
      fi
    done
  '';
in
{
  # Unload a model 1 minute after its last use, so it holds memory only around embedding calls.
  services.ollama = {
    enable = true;
    environmentVariables.OLLAMA_KEEP_ALIVE = "1m";
  };

  # Pull missing models once at login and after each switch; models already present are skipped.
  launchd.agents.ollama-pull-models = {
    enable = true;
    config = {
      ProgramArguments = [ "${pullModels}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ollama-pull-models.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ollama-pull-models.log";
    };
  };
}
