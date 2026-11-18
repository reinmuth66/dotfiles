{ pkgs, ... }:

let
  # Issue を herdr の新しいタブの Claude Code に渡す (gh-dash の C キーから呼ぶ)
  herdr-issue-task = pkgs.writeShellApplication {
    name = "herdr-issue-task";
    runtimeInputs = [
      pkgs.gh
      pkgs.jq
    ];
    text = builtins.readFile ../config/gh-dash/herdr-issue-task.sh;
  };
in
{
  programs.gh-dash = {
    enable = true;
    settings = {
      prSections = [
        {
          title = "自分の PR";
          filters = "is:open author:@me";
        }
        {
          title = "レビュー待ち";
          filters = "is:open review-requested:@me";
        }
      ];
      issuesSections = [
        {
          title = "自分の Issue";
          filters = "is:open author:@me";
        }
        {
          title = "担当";
          filters = "is:open assignee:@me";
        }
      ];
      # 起動したリポジトリに絞る
      smartFilteringAtLaunch = true;
      keybindings.issues = [
        # 組み込みの C (checkout) を上書きする
        {
          key = "C";
          command = "herdr-issue-task {{.RepoName}} {{.IssueNumber}}";
        }
        {
          key = "N";
          command = "herdr-app do tab.new '{\"argv\": [\"gh\", \"issue\", \"create\", \"-R\", \"{{.RepoName}}\"]}'";
        }
      ];
      # Catppuccin Macchiato の色。inverted (base) のほかは config/herdr-app/shared/ui.js の PALETTE と同じ値
      theme.colors = {
        text = {
          primary = "#cad3f5";
          secondary = "#a5adcb";
          inverted = "#24273a";
          faint = "#6e738d";
          warning = "#eed49f";
          success = "#a6da95";
          error = "#ed8796";
          actor = "#8aadf4";
        };
        background.selected = "#363a4f";
        border = {
          primary = "#b7bdf8";
          secondary = "#6e738d";
          faint = "#363a4f";
        };
      };
    };
  };

  home.packages = [ herdr-issue-task ];
}
