{ pkgs, config, ... }:

{
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    EDITOR = "nvim";
    LESSUTFCHARDEF = "e000-e09f:w,e0a0-e0bf:p,e0c0-f8ff:w,f0001-fffff:w";
  };

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;

    shellAliases = {
      ls = "eza --icons";
      ll = "eza -la --icons --git";
      cat = "bat";
    };

    loginExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
    ];

    initContent = ''
      [[ -f "$HOME/ssh-logs/.zshrc" ]] && source "$HOME/ssh-logs/.zshrc"

      eval "$(atuin init zsh --disable-up-arrow)"

      WORDCHARS=""

      # 履歴検索
      autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search
      bindkey "^[[3~" delete-char

      # zsh-autosuggestions
      ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(up-line-or-beginning-search down-line-or-beginning-search)
      ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(forward-char end-of-line vi-forward-char vi-end-of-line vi-add-eol)

      # yazi: 終了時にカレントディレクトリを引き継ぐ
      function y() {
        local tmp cwd
        tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        command yazi "$@" --cwd-file="$tmp"
        IFS= read -r -d "" cwd < "$tmp"
        [[ "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
        rm -f -- "$tmp"
      }

      # Claude Code
      function claude() {
        ~/life/scripts/boot_saver.sh "$@"
      }

      # 今日の日報を開く
      function today() {
        local date daily
        date="$(date +%Y-%m-%d)"
        daily="$HOME/life/!daily/$(date +%Y)/$(date +%m)/$date.md"
        mkdir -p "$(dirname "$daily")"
        touch "$daily"
        nvim "$daily"
      }
    '';
  };
}
