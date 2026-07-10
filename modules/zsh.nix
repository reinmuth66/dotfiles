{ config, ... }:

{
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
  };

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  programs = {
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
      enable = true;

      loginExtra = ''
        eval "$(/opt/homebrew/bin/brew shellenv)"
      '';

      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      initContent = ''
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

        # marp: cosmiconfigの設定探索がホームディレクトリより下の階層で
        # 止まり ~/.marprc.yml を自動検出できないため、常に明示指定する
        function marp() {
          command marp --config "$HOME/.marprc.yml" "$@"
        }

      '';
    };
  };
}
