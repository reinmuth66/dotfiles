{ ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "reinmuth66";
      init.defaultBranch = "main";

      # ghq get の取得先 (~/ghq/github.com/<owner>/<repo>)
      ghq.root = "~/ghq";

      push = {
        # 初回の push で upstream を自動設定する
        autoSetupRemote = true;
        # --force-with-lease のとき、手元に取り込んでいないリモートの変更を上書きしない
        useForceIfIncludes = true;
      };
      fetch = {
        # リモートで消えたブランチの追跡ブランチを消す
        prune = true;
      };
      rebase = {
        autoStash = true;
        # fixup! / squash! コミットを自動で並べ替える
        autoSquash = true;
      };

      merge.conflictstyle = "zdiff3";
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
      };

      # 一度解決したコンフリクトを覚えて、同じものを自動で解決する
      rerere = {
        enabled = true;
        autoupdate = true;
      };

      branch.sort = "-committerdate";
      tag.sort = "version:refname";
    };
    includes = [ { path = "~/.config/git/config.local"; } ];
    ignores = [
      # macOS
      ".DS_Store"
      "._*"

      # direnv
      ".direnv"

      # Claude Code
      "**/.claude/settings.local.json"
      "**/.claude/worktrees"
      "**/CLAUDE.local.md"
    ];
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      customCommands = [
        {
          key = "A";
          command = "czg";
          context = "files";
          output = "terminal";
          description = "Conventional commit (czg)";
        }
      ];
    };
  };
}
