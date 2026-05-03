{ ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "reinmuth66";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
    includes = [{ path = "~/.config/git/config.local"; }];
    ignores = [ "**/.claude/settings.local.json" ];
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

  programs.lazygit.enable = true;
}
