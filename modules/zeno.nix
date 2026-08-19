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

    # Watchdog: keep the Deno socket server tied to this shell's lifetime.
    #
    # zeno.zsh's own cleanup (zshexit -> zeno-stop-server) only runs when zsh
    # exits through its normal shutdown path. If the terminal force-kills the
    # shell (app quit, crash, `kill -9`), that path never runs and the server
    # is orphaned.
    #
    # This is armed immediately (not deferred to the first precmd), because
    # ZENO_SOCK is set synchronously by zeno-enable-sock while ZENO_PID is
    # only set lazily once the server actually starts — a watchdog gated on
    # ZENO_PID at the first precmd frequently found nothing to arm on (no
    # zeno usage yet that session) and permanently disabled itself for the
    # rest of the session. Resolving the live server PID via `lsof` on the
    # socket at kill-time sidesteps that. Ignoring SIGHUP stops zsh's own
    # HUP-to-jobs forwarding (e.g. on tab/pane close) from killing this
    # watchdog before it gets a chance to act.
    _zeno_watchdog_start() {
      emulate -L zsh
      local _zsh_pid=$$
      local _sock=''${ZENO_SOCK}
      [[ -z ''${_sock} ]] && return
      (
        trap ':' HUP
        while kill -0 ''${_zsh_pid} 2>/dev/null; do
          sleep 5
        done
        local _pid
        for _pid in $(lsof -t "''${_sock}" 2>/dev/null); do
          kill -TERM "''${_pid}" 2>/dev/null
        done
        sleep 1
        for _pid in $(lsof -t "''${_sock}" 2>/dev/null); do
          kill -KILL "''${_pid}" 2>/dev/null
        done
        rm -f "''${_sock}" 2>/dev/null
      ) 2>/dev/null &!
    }
    _zeno_watchdog_start

    # Self-healing sweep: on every new shell, kill any zeno server left
    # behind by a past shell that died without the watchdog above catching
    # it (e.g. a session predating this fix). Each server's listening socket
    # is named zeno-<owner-shell-pid>.sock, so resolve the socket back to
    # its owner PID and check whether that shell is still alive.
    _zeno_cleanup_orphans() {
      emulate -L zsh
      local pid sock_name owner
      for pid in ''${(f)"$(pgrep -f "''${ZENO_ROOT}/src/server.ts" 2>/dev/null)"}; do
        sock_name=$(lsof -p "''${pid}" 2>/dev/null | grep -o 'zeno-[0-9]*\.sock' | head -1)
        [[ -z ''${sock_name} ]] && continue
        owner=''${sock_name#zeno-}
        owner=''${owner%.sock}
        [[ -z ''${owner} ]] && continue
        if ! kill -0 "''${owner}" 2>/dev/null; then
          kill -TERM "''${pid}" 2>/dev/null
          sleep 1
          kill -0 "''${pid}" 2>/dev/null && kill -KILL "''${pid}" 2>/dev/null
        fi
      done
    }
    ( trap ':' HUP; _zeno_cleanup_orphans ) 2>/dev/null &!
  '';

  xdg.configFile."zeno/config.yml".source = ../config/zeno/config.yml;
}
