{ pkgs, lib, config, ... }:

let
  zenoSrc = pkgs.fetchFromGitHub {
    owner = "yuki-yano";
    repo = "zeno.zsh";
    rev = "2e8fbecce0fc3692a5fcc9033ecca7ab35263e56";
    sha256 = "1mjhl82rr2jlgnz9rvnldpbhijyxrv5illxjyylp4j7zcgav17yk";
  };
  zenoDir = "${config.home.homeDirectory}/.local/share/zeno.zsh";
in

{
  home.packages = [ pkgs.deno ];

  home.sessionVariables = {
    DENO_DIR = "${config.home.homeDirectory}/.cache/deno";
    ZENO_ROOT = zenoDir;
  };

  home.activation.zenoSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [[ ! -f "${zenoDir}/.nix-source" ]] || \
       [[ "$(cat "${zenoDir}/.nix-source")" != "${zenoSrc}" ]]; then
      rm -rf "${zenoDir}"
      cp -r "${zenoSrc}" "${zenoDir}"
      chmod -R u+w "${zenoDir}"
      echo "${zenoSrc}" > "${zenoDir}/.nix-source"
    fi
  '';

  programs.zsh.initContent = lib.mkAfter ''
    source "${zenoDir}/zeno.zsh"
    bindkey ' ' zeno-auto-snippet
    bindkey '^m' zeno-auto-snippet-and-accept-line
    bindkey '^i' zeno-completion
    (( $+functions[_zsh_highlight_bind_widgets] )) && _zsh_highlight_bind_widgets

    # Fix: zeno-completion declares 'local options' (scalar) which shadows
    # zsh/parameter's special 'options' (associative array) via dynamic scoping.
    # When _zsh_highlight is called via zle-line-pre-redraw inside zeno-completion,
    # expanding options as key-value pairs on a scalar returns 1 element, causing
    # "bad set of key/value pairs for associative array".
    # Override the hook to detect and mask the shadowed scalar with an empty assoc.
    if (( $+functions[_zsh_highlight__zle-line-pre-redraw] )); then
      _zsh_highlight__zle-line-pre-redraw() {
        [[ ''${(t)options} != *association* ]] && local -A options
        true && _zsh_highlight "$@"
      }
    fi

    # zeno-start-server uses `nohup ... &!` (disown), so servers survive when
    # zsh is killed. The zshexit hook (zeno-stop-server) also has a failure
    # mode: it deletes the socket file but skips the kill when ZENO_PID is
    # unset, leaving a server running with no socket on disk.
    # Detect orphans by reading ZENO_SOCK from each deno process's environment
    # and checking whether the owning zsh PID is still alive.
    () {
      local deno_pid sock zsh_pid
      for deno_pid in ''${(f)"$(pgrep -f 'zeno.zsh/src/server' 2>/dev/null)"}; do
        sock="$(ps eww -p "''${deno_pid}" 2>/dev/null | tr ' ' '\n' | grep '^ZENO_SOCK=' | head -1)"
        sock="''${sock#ZENO_SOCK=}"
        [[ -z "''${sock}" ]] && continue
        zsh_pid="''${''${sock:t}#zeno-}"
        zsh_pid="''${zsh_pid%.sock}"
        kill -0 "''${zsh_pid}" 2>/dev/null && continue
        kill "''${deno_pid}" 2>/dev/null
        rm -f "''${sock}"
      done
    } 2>/dev/null
  '';

  xdg.configFile."zeno/config.yml".source = ../config/zeno/config.yml;
}
