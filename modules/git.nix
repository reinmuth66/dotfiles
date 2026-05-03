{ ... }:

{
  programs.git = {
    enable = true;
    userName = "reinmuth66";
    includes = [{ path = "~/.config/git/config.local"; }];
    delta = {
      enable = true;
      options = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
      };
    };
    extraConfig = {
      interactive.diffFilter = "delta --color-only";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
    ignores = [ "**/.claude/settings.local.json" ];
  };

  programs.lazygit.enable = true;
}
