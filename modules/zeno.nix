{ pkgs, lib, config, ... }:

let
  zenoSrc = pkgs.fetchFromGitHub {
    owner = "yuki-yano";
    repo = "zeno.zsh";
    rev = "2e8fbecce0fc3692a5fcc9033ecca7ab35263e56";
    sha256 = "1mjhl82rr2jlgnz9rvnldpbhijyxrv5illxjyylp4j7zcgav17yk";
  };
  zenoDir = "${config.home.homeDirectory}/.local/share/zeno.zsh";

  # --- WezTerm tab-close confirmation background ---
  #
  # WezTerm prompts to close a pane unless every descendant process of the
  # pane's shell is in its allowlist (bash/zsh/fish/...). zsh's `&!` only
  # disowns a job from the shell's job table, it doesn't reparent it, so a
  # long-lived helper stays a descendant of the pane's shell for as long as
  # the shell lives. The fix is a double fork: reparent the helper to
  # launchd (pid 1) so it falls outside the pane's process tree.
  #
  # The double fork has to happen inside a separate, non-interactive zsh
  # process (invoked via `nohup ... &!`) rather than as a nested subshell in
  # the interactive shell itself — the interactive shell's job control
  # (MONITOR) doesn't guarantee the outer subshell exits before the inner
  # one keeps running independently of it.

  # zeno.zsh's own zeno-start-server does `nohup "$server_bin" ... &!`, which
  # only disowns the job — server_bin (and the deno process it execs into)
  # stays a direct child of zsh. ZENO_SERVER_BIN lets us swap in this
  # wrapper so the real `deno` process ends up reparented to launchd instead.
  zenoServerWrapper = pkgs.writeScript "zeno-server-wrapper" ''
    #!/usr/bin/env zsh
    (
      exec ${pkgs.deno}/bin/deno run --node-modules-dir=auto --no-check \
        --allow-env --allow-read --allow-run --allow-write --allow-ffi --allow-net \
        -- "${zenoDir}/src/server.ts" "$@" &
    )
  '';

  # Watchdog, as its own script for the same reason as zenoServerWrapper.
  # Ties the Deno socket server's lifetime to the owning shell's: polls the
  # shell PID ($1) every 5s, and once it's gone, resolves the live server
  # PID via `lsof` on the socket path ($2) and kills it (TERM, then KILL
  # after a grace period). This exists because zeno.zsh's own cleanup
  # (zshexit -> zeno-stop-server) only runs when zsh exits through its
  # normal shutdown path — force-kills (app quit, crash, `kill -9`) skip it
  # and orphan the server. Ignoring SIGHUP stops zsh's own HUP-to-jobs
  # forwarding (e.g. on tab/pane close) from killing this before it acts.
  zenoWatchdogScript = pkgs.writeScript "zeno-watchdog" ''
    #!/usr/bin/env zsh
    emulate -L zsh
    (
      trap ':' HUP
      local zsh_pid=$1 sock=$2 pid
      while kill -0 "$zsh_pid" 2>/dev/null; do
        sleep 5
      done
      for pid in $(lsof -t "$sock" 2>/dev/null); do
        kill -TERM "$pid" 2>/dev/null
      done
      sleep 1
      for pid in $(lsof -t "$sock" 2>/dev/null); do
        kill -KILL "$pid" 2>/dev/null
      done
      rm -f "$sock" 2>/dev/null
    ) &
  '';

  # Self-healing sweep, as its own script for the same reason. On every new
  # shell, kill any zeno server left behind by a past shell that died
  # without the watchdog above catching it. Each server's listening socket
  # is named zeno-<owner-shell-pid>.sock, so resolve the socket back to its
  # owner PID and check whether that shell is still alive.
  zenoCleanupScript = pkgs.writeScript "zeno-cleanup-orphans" ''
    #!/usr/bin/env zsh
    emulate -L zsh
    (
      trap ':' HUP
      local root=$1 pid sock_name owner
      for pid in ''${(f)"$(pgrep -f "$root/src/server.ts" 2>/dev/null)"}; do
        sock_name=$(lsof -p "$pid" 2>/dev/null | grep -o 'zeno-[0-9]*\.sock' | head -1)
        [[ -z $sock_name ]] && continue
        owner=''${sock_name#zeno-}
        owner=''${owner%.sock}
        [[ -z $owner ]] && continue
        if ! kill -0 "$owner" 2>/dev/null; then
          kill -TERM "$pid" 2>/dev/null
          sleep 1
          kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
        fi
      done
    ) &
  '';
in

{
  home.packages = [ pkgs.deno ];

  home.sessionVariables = {
    DENO_DIR = "${config.home.homeDirectory}/.cache/deno";
    ZENO_ROOT = zenoDir;
    ZENO_SERVER_BIN = zenoServerWrapper;
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

    # Arm the watchdog once ZENO_SOCK exists. It's only set once
    # zeno-enable-sock runs, lazily on first zeno use (space/Tab), not at
    # shell start, so a single call here would usually find it empty and
    # never retry. Poll via precmd until it's set, then arm and deregister.
    autoload -Uz add-zsh-hook
    _zeno_watchdog_arm() {
      emulate -L zsh
      local _sock=''${ZENO_SOCK}
      [[ -z ''${_sock} ]] && return
      add-zsh-hook -d precmd _zeno_watchdog_arm
      nohup ${zenoWatchdogScript} $$ "''${_sock}" >/dev/null 2>&1 &!
    }
    add-zsh-hook precmd _zeno_watchdog_arm

    # Self-healing sweep: kill any zeno server orphaned by a shell that died
    # before the watchdog could catch it. See zenoCleanupScript above.
    nohup ${zenoCleanupScript} "''${ZENO_ROOT}" >/dev/null 2>&1 &!
  '';

  xdg.configFile."zeno/config.yml".source = ../config/zeno/config.yml;
}
